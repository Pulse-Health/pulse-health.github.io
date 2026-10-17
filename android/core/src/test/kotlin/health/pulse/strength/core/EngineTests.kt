package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.EngineBasicsTests.SvcClock
import health.pulse.strength.core.EngineBasicsTests.SvcRecorder
import health.pulse.strength.core.EngineBasicsTests.SvcRecorder.Event
import health.pulse.strength.core.EngineBasicsTests.SvcRig
import health.pulse.strength.core.StrengthDataTests.SvcDataFix
import health.pulse.strength.core.StrengthDataTests.SvcLCG
import health.pulse.strength.core.StrengthDataTests.SvcSyncFix
import java.io.File
import java.time.Instant
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

// Port of EngineTests.swift for the phone-only Kotlin WorkoutEngine.
//
// Not ported (the Kotlin engine has no role, mirror, receive(command), receive(envelope), pending commands or acknowledgements):
//   testTheMirrorThrottlesTooAndNeverPersists, testACommandRunsOnceAndKeepsItsOrigin, testTheMirrorIgnoresCommands,
//   testTheMirrorAdoptsTheFirstEnvelopeAndAnnouncesTheWorkout, testTheMirrorNeverEchoesAdoptedChanges, testOlderAndEqualEnvelopesAreIgnored, testAnEnvelopeForAnotherWorkoutWinsEvenWithALowerRevision,
//   testAnEnvelopeWithoutAStateEndsTheLocalWorkout, testAnEndWithoutAnIdEndsWhateverRuns, testAnEndNoticeForAnotherWorkoutIsIgnored,
//   testALateEnvelopeOfAnEndedWorkoutDoesNotRevive, testAnEndNoticeBeforeAnyStateStillBlocksThatWorkout,
//   testAnEmptyEnvelopeWithoutAWorkoutDoesNothing, testTheAuthorityIgnoresEnvelopes, testTheMirrorAppliesEditsOptimisticallyWithoutSaving,
//   testTheMirrorNeverRestores, testTheMirrorFinishesLocally.
// Adapted: testCommandsFromTheWatchAreHeartRateThrottledToo (send with origin WATCH instead of receive(command)),
//   testACommandThatArrivesWithoutAWorkoutIsConsumed -> testAnActionThatArrivesWithoutAWorkoutDoesNotHitTheNextWorkout (phone half) and
//   testPhoneDiskAndWatchStayInSyncUnderRandomPlay (the phone half: the disk follows the reported state).
// Extra (not in EngineTests.swift): testStartTrimsTheUnusualWhitespaceOfAName, testSVC1_… (RegressionTests.swift) and
//   testLastEndDiscardedTellsHowTheWorkoutEnded.
// The WorkoutControllerWrapperTests of EngineTests.swift are ported in WorkoutControllerTests.kt.

// region Start, send, derived values

class EngineBasicsTests {
    /** A clock the test moves by hand (usable as the engine's clock). */
    class SvcClock(start: Instant = SvcSyncFix.epoch) {
        var now: Instant = start
            private set

        fun advance(seconds: Double) {
            now = now.addingTimeInterval(seconds)
        }

        fun set(date: Instant) {
            now = date
        }

        val reader: () -> Instant = { now }
    }

    /** A side effect that remembers everything it is told. */
    class SvcRecorder : WorkoutSideEffect {
        sealed interface Event {
            data class Started(val state: WorkoutState) : Event
            data class Changed(val from: WorkoutState, val to: WorkoutState, val action: WorkoutAction, val origin: ActionOrigin) : Event
            data class Ended(val state: WorkoutState, val completed: CompletedWorkout?) : Event
        }

        private val recorded = mutableListOf<Event>()
        val events: List<Event> get() = recorded.toList()
        var onEvent: ((Event) -> Unit)? = null

        override fun workoutStarted(state: WorkoutState) = add(Event.Started(state))

        override fun workoutChanged(old: WorkoutState, new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) =
            add(Event.Changed(old, new, action, origin))

        override fun workoutEnded(state: WorkoutState, completed: CompletedWorkout?) = add(Event.Ended(state, completed))

        private fun add(event: Event) {
            recorded.add(event)
            onEvent?.invoke(event)
        }

        val changes: List<Event> get() = recorded.filterIsInstance<Event.Changed>()
    }

    /** An engine wired to a seeded data model, a temporary directory, a manual clock and a recorder. */
    class SvcRig(folder: TemporaryFolder, seed: Boolean = true, persistence: FileStrengthPersistence? = null) {
        val clock = SvcClock()
        val persistence: FileStrengthPersistence = persistence ?: FileStrengthPersistence(folder.newFolder())
        val model = StrengthDataModel(this.persistence, seed, SvcSyncFix.epoch)
        val engine = WorkoutEngine(this.persistence, model, clock = clock.reader)
        val recorder = SvcRecorder()

        var updates = 0
            private set

        init {
            engine.addEffect(recorder)
            engine.onUpdate = { updates += 1 }
        }

        val upperA: WorkoutTemplate get() = model.data.templates[0]

        fun startUpperA(): WorkoutState {
            engine.start(upperA)
            return engine.state!!
        }

        /** Logs the next [count] pending sets, one minute apart. */
        fun logSets(count: Int) {
            repeat(count) {
                clock.advance(60.0)
                engine.send(WorkoutAction.LogNextSet)
            }
        }

        val diskState: WorkoutState? get() = persistence.loadActiveWorkout()
    }

    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun testStartFromATemplateBuildsAndPersistsTheWorkout() {
        val rig = SvcRig(folder)
        assertThat(rig.engine.start(rig.upperA)).isTrue()
        val state = rig.engine.state
        assertThat(state?.name).isEqualTo("Upper A · Push")
        assertThat(state?.templateID).isEqualTo(rig.upperA.id)
        assertThat(state?.exercises?.size).isEqualTo(6)
        assertThat(state?.startedAt).isEqualTo(rig.clock.now)
        assertThat(state?.revision).isEqualTo(0)
        assertThat(state?.templateBaseline).isEqualTo(rig.upperA.entries.map { it.id })
        assertThat(rig.diskState).isEqualTo(state)
        assertThat(rig.engine.lastCompleted).isNull()
        assertThat(rig.recorder.events).isEqualTo(listOf(Event.Started(state!!)))
        assertThat(rig.updates).isEqualTo(1)
    }

    @Test
    fun testStartRefreshesThePreviousResultsFromTheStore() {
        val rig = SvcRig(folder)
        val squatBefore = rig.upperA.entries[0].exercise
        assertWithMessage("the template carries the library value").that(squatBefore.previousBestE1RM).isEqualTo(99.0)
        val workout = SvcDataFix.workout(80, SvcDataFix.daysAgo(0.1), SvcDataFix.entry("bench", listOf(SvcDataFix.work(100, 3)), n = 80))
        rig.model.record(workout, null)
        rig.engine.start(rig.upperA)
        val bench = rig.engine.state?.exercises?.get(0)?.exercise
        assertThat(bench?.previousBestE1RM ?: 0.0).isWithin(1e-9).of(110.0)
        assertThat(bench?.previousSets).isEqualTo(listOf(PreviousSet(100.0, 3)))
        assertThat(bench?.name).isEqualTo(squatBefore.name)
        assertThat(bench?.defaults).isEqualTo(squatBefore.defaults)
        assertWithMessage("the stored template is not rewritten")
            .that(rig.model.template(rig.upperA.id)?.entries?.get(0)?.exercise?.previousBestE1RM).isEqualTo(99.0)
    }

    @Test
    fun testStartKeepsAnExerciseTheStoreDoesNotKnow() {
        val rig = SvcRig(folder)
        val exotic = ExerciseLibrary.exercise("bench")!!.copy(id = "custom-gone", previousBestE1RM = 77.0)
        val template = WorkoutTemplate(
            name = "Exotic",
            entries = listOf(TemplateEntry(exercise = exotic, plannedSets = listOf(PlannedSet(weightKg = 50.0, reps = 5)), restSeconds = 60)),
        )
        rig.engine.start(template)
        assertThat(rig.engine.state?.exercises?.get(0)?.exercise).isEqualTo(exotic)
    }

    @Test
    fun testStartWithoutATemplateUsesTheNameOrTheDefault() {
        val cases: List<Pair<String?, String>> = listOf(null to "Workout", "   " to "Workout", "" to "Workout", "  Push day \n" to "Push day")
        for ((input, expected) in cases) {
            val rig = SvcRig(folder, seed = false)
            assertThat(rig.engine.start(null, input)).isTrue()
            assertThat(rig.engine.state?.name).isEqualTo(expected)
            assertThat(rig.engine.state?.exercises?.size).isEqualTo(0)
            assertThat(rig.engine.state?.templateID).isNull()
        }
    }

    /** Extra: Foundation's `.whitespacesAndNewlines` also trims the no-break space and the ideographic space. */
    @Test
    fun testStartTrimsTheUnusualWhitespaceOfAName() {
        val cases = listOf(" Push day " to "Push day", "　Pull day " to "Pull day", " 　" to "Workout")
        for ((input, expected) in cases) {
            val rig = SvcRig(folder, seed = false)
            rig.engine.start(null, input)
            assertThat(rig.engine.state?.name).isEqualTo(expected)
        }
    }

    @Test
    fun testStartIsIgnoredWhileAWorkoutRuns() {
        val rig = SvcRig(folder)
        val first = rig.startUpperA()
        assertThat(rig.engine.start(rig.model.data.templates[1])).isFalse()
        assertThat(rig.engine.start(null, "Other")).isFalse()
        assertThat(rig.engine.state).isEqualTo(first)
        assertThat(rig.recorder.events).hasSize(1)
        assertThat(rig.diskState).isEqualTo(first)
    }

    @Test
    fun testStartingTheNextWorkoutClearsTheLastCompleted() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.logSets(1)
        val completed = rig.engine.finish(false)
        assertThat(completed).isNotNull()
        assertThat(rig.engine.lastCompleted).isEqualTo(completed)
        rig.engine.start(null, null)
        assertThat(rig.engine.lastCompleted).isNull()
        assertThat(rig.engine.state).isNotNull()
    }

    @Test
    fun testSendReducesPersistsAndNotifies() {
        val rig = SvcRig(folder)
        val old = rig.startUpperA()
        rig.clock.advance(30.0)
        rig.engine.send(WorkoutAction.LogNextSet, ActionOrigin.WATCH)
        val new = rig.engine.state!!
        assertThat(new.revision).isEqualTo(1)
        assertThat(new.exercises[0].sets.count { it.isDone }).isEqualTo(1)
        assertWithMessage("logging a set starts the rest timer").that(new.rest).isNotNull()
        assertThat(rig.diskState).isEqualTo(new)
        assertThat(rig.recorder.events.last()).isEqualTo(Event.Changed(old, new, WorkoutAction.LogNextSet, ActionOrigin.WATCH))
        assertThat(rig.updates).isEqualTo(2)
    }

    @Test
    fun testTheDefaultOriginIsThePhone() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.engine.send(WorkoutAction.NextExercise)
        val last = rig.recorder.events.last()
        assertWithMessage("no change").that(last).isInstanceOf(Event.Changed::class.java)
        assertThat((last as Event.Changed).origin).isEqualTo(ActionOrigin.PHONE)
    }

    @Test
    fun testAnActionThatChangesNothingIsNotReported() {
        val rig = SvcRig(folder)
        val state = rig.startUpperA()
        val events = rig.recorder.events.size
        val updates = rig.updates
        rig.engine.send(WorkoutAction.SkipRest)                                                          // no rest running
        rig.engine.send(WorkoutAction.ToggleSet(SvcSyncFix.uuid(1), SvcSyncFix.uuid(2)))                 // unknown ids
        rig.engine.send(WorkoutAction.GoTo(0))                                                           // already there
        rig.engine.send(WorkoutAction.Undo)                                                              // nothing to undo
        assertThat(rig.engine.state).isEqualTo(state)
        assertThat(rig.recorder.events).hasSize(events)
        assertThat(rig.updates).isEqualTo(updates)
    }

    @Test
    fun testSendWithoutAWorkoutDoesNothing() {
        val rig = SvcRig(folder)
        rig.engine.send(WorkoutAction.LogNextSet)
        rig.engine.send(WorkoutAction.Pause)
        assertThat(rig.engine.state).isNull()
        assertThat(rig.recorder.events).isEmpty()
        assertThat(rig.updates).isEqualTo(0)
        assertThat(rig.diskState).isNull()
    }

    @Test
    fun testPublishingHappensBeforeTheEffectsAreTold() {
        val rig = SvcRig(folder)
        val log = mutableListOf<String>()
        rig.engine.onUpdate = { log.add("update") }
        rig.recorder.onEvent = { event ->
            if (event is Event.Changed) {
                log.add(if (rig.engine.state == event.to) "effect sees new state" else "effect sees stale state")
            } else {
                log.add("other")
            }
        }
        rig.startUpperA()
        log.clear()
        rig.engine.send(WorkoutAction.LogNextSet)
        assertThat(log).isEqualTo(listOf("update", "effect sees new state"))
    }

    @Test
    fun testEffectsAreRegisteredOnceAndToldInOrder() {
        val rig = SvcRig(folder)
        val second = SvcRecorder()
        val order = mutableListOf<String>()
        rig.recorder.onEvent = { order.add("first") }
        second.onEvent = { order.add("second") }
        rig.engine.addEffect(second)
        rig.engine.addEffect(second)
        rig.engine.addEffect(rig.recorder)
        rig.startUpperA()
        assertThat(order).isEqualTo(listOf("first", "second"))
        assertThat(second.events).hasSize(1)
    }

    @Test
    fun testAnEffectMayRegisterAnotherEffectWhileBeingTold() {
        val rig = SvcRig(folder)
        val late = SvcRecorder()
        rig.recorder.onEvent = { event ->
            if (event is Event.Started) rig.engine.addEffect(late)
        }
        rig.startUpperA()
        assertWithMessage("it missed the event that was already being delivered").that(late.events).isEmpty()
        rig.engine.send(WorkoutAction.NextExercise)
        assertThat(late.events).hasSize(1)
    }

    @Test
    fun testDerivedValuesAreNilWithoutAWorkout() {
        val rig = SvcRig(folder)
        assertThat(rig.engine.presentation(rig.clock.now)).isNull()
        assertThat(rig.engine.snapshot(rig.clock.now)).isNull()
        assertThat(rig.engine.templateDiff().isEmpty).isTrue()
    }

    @Test
    fun testDerivedValuesFollowTheState() {
        val rig = SvcRig(folder)
        val state = rig.startUpperA()
        var presentation = rig.engine.presentation(rig.clock.now)
        assertThat(presentation?.totals?.totalSets).isEqualTo(20)
        assertThat(presentation?.totals?.loggedSets).isEqualTo(0)
        assertThat(rig.engine.snapshot(rig.clock.now)?.workoutID).isEqualTo(state.id)

        rig.logSets(2)
        presentation = rig.engine.presentation(rig.clock.now)
        assertThat(presentation?.totals?.loggedSets).isEqualTo(2)
        val snapshot = rig.engine.snapshot(rig.clock.now)
        assertThat(snapshot?.targetExerciseID).isEqualTo(rig.engine.state?.exercises?.get(0)?.id)
        assertThat(snapshot?.targetSetID).isEqualTo(rig.engine.state?.exercises?.get(0)?.sets?.get(2)?.id)

        assertThat(rig.engine.templateDiff().isEmpty).isTrue()
        rig.engine.send(WorkoutAction.AddExercises(listOf(ExerciseLibrary.exercise("dips")!!)))
        assertThat(rig.engine.templateDiff().added).isEqualTo(1)
        rig.engine.send(WorkoutAction.MoveExercise(0, 2))
        assertThat(rig.engine.templateDiff().reordered).isTrue()
        assertThat(rig.engine.presentation(rig.clock.now)?.finishCheck?.templateDiff).isEqualTo(rig.engine.templateDiff())
    }

    @Test
    fun testTheRecoveryProviderCanBeReplaced() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.engine.recovery = { 41 }
        assertThat(rig.engine.presentation(rig.clock.now)?.card?.recoveryPercent).isEqualTo(41)
        rig.engine.recovery = { 93 }
        assertThat(rig.engine.presentation(rig.clock.now)?.card?.recoveryPercent).isEqualTo(93)
    }
}

// endregion

// region Heart-rate throttling

class EngineHeartRateTests {
    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun testHeartRateIsSavedAndReportedAtMostOncePerTenSeconds() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        val baseEvents = rig.recorder.events.size
        val baseUpdates = rig.updates

        rig.engine.send(WorkoutAction.UpdateHeartRate(100), ActionOrigin.WATCH)                         // t = 0: reported
        assertThat(rig.recorder.events).hasSize(baseEvents + 1)
        assertThat(rig.diskState?.heartRate).isEqualTo(100)

        rig.clock.advance(3.0)
        rig.engine.send(WorkoutAction.UpdateHeartRate(110), ActionOrigin.WATCH)                         // t = 3: kept in memory only
        assertThat(rig.engine.state?.heartRate).isEqualTo(110)
        assertThat(rig.engine.state?.heartRateCount).isEqualTo(2)
        assertThat(rig.recorder.events).hasSize(baseEvents + 1)
        assertThat(rig.diskState?.heartRate).isEqualTo(100)
        assertWithMessage("the published state still follows every sample").that(rig.updates).isEqualTo(baseUpdates + 2)

        rig.clock.advance(6.75)
        rig.engine.send(WorkoutAction.UpdateHeartRate(120), ActionOrigin.WATCH)                         // t = 9.75
        assertThat(rig.recorder.events).hasSize(baseEvents + 1)

        rig.clock.advance(0.25)
        rig.engine.send(WorkoutAction.UpdateHeartRate(130), ActionOrigin.WATCH)                         // t = 10: reported
        assertThat(rig.recorder.events).hasSize(baseEvents + 2)
        assertThat(rig.diskState?.heartRate).isEqualTo(130)
        assertThat(rig.engine.state?.heartRateSum).isEqualTo(460)
        assertThat(rig.engine.state?.heartRateCount).isEqualTo(4)
        assertWithMessage("heart-rate samples never bump the revision").that(rig.engine.state?.revision).isEqualTo(0)
        val last = rig.recorder.events.last()
        assertWithMessage("no change").that(last).isInstanceOf(Event.Changed::class.java)
        last as Event.Changed
        assertThat(last.action).isEqualTo(WorkoutAction.UpdateHeartRate(130))
        assertThat(last.origin).isEqualTo(ActionOrigin.WATCH)
        assertWithMessage("the effect sees every sample that happened since").that(last.from.heartRate).isEqualTo(120)
        assertThat(last.to.heartRate).isEqualTo(130)

        rig.clock.advance(9.99)
        rig.engine.send(WorkoutAction.UpdateHeartRate(131))
        assertThat(rig.recorder.events).hasSize(baseEvents + 2)
        rig.clock.advance(0.02)
        rig.engine.send(WorkoutAction.UpdateHeartRate(132))
        assertThat(rig.recorder.events).hasSize(baseEvents + 3)
    }

    @Test
    fun testOtherActionsAreNeverThrottledAndCarryTheLatestHeartRate() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.engine.send(WorkoutAction.UpdateHeartRate(100))
        rig.clock.advance(1.0)
        rig.engine.send(WorkoutAction.UpdateHeartRate(111))                                         // not reported
        rig.clock.advance(1.0)
        rig.engine.send(WorkoutAction.LogNextSet)
        assertThat(rig.recorder.changes).hasSize(2)
        assertThat(rig.diskState).isEqualTo(rig.engine.state)
        assertThat(rig.diskState?.heartRate).isEqualTo(111)
        rig.clock.advance(1.0)
        rig.engine.send(WorkoutAction.NextExercise)
        rig.clock.advance(1.0)
        rig.engine.send(WorkoutAction.PreviousExercise)
        assertThat(rig.recorder.changes).hasSize(4)
    }

    @Test
    fun testTheThrottleSurvivesAClockThatGoesBackwards() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.clock.advance(100.0)
        rig.engine.send(WorkoutAction.UpdateHeartRate(100))
        val count = rig.recorder.events.size
        rig.clock.advance(-60.0)                                                                    // the clock was set back
        rig.engine.send(WorkoutAction.UpdateHeartRate(101))
        assertThat(rig.recorder.events).hasSize(count + 1)
        rig.clock.advance(2.0)
        rig.engine.send(WorkoutAction.UpdateHeartRate(102))
        assertThat(rig.recorder.events).hasSize(count + 1)
    }

    @Test
    fun testANewWorkoutReportsItsFirstSampleImmediately() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.engine.send(WorkoutAction.UpdateHeartRate(90))
        rig.engine.discard()
        rig.clock.advance(1.0)
        rig.startUpperA()
        val count = rig.recorder.changes.size
        rig.engine.send(WorkoutAction.UpdateHeartRate(91))
        assertThat(rig.recorder.changes).hasSize(count + 1)
    }

    @Test
    fun testNilHeartRateIsReportedLikeAnySample() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.engine.send(WorkoutAction.UpdateHeartRate(100))
        rig.clock.advance(11.0)
        rig.engine.send(WorkoutAction.UpdateHeartRate(null))
        assertThat(rig.diskState?.heartRate).isNull()
        assertThat(rig.engine.state?.heartRateCount).isEqualTo(1)
    }

    @Test
    fun testTheIntervalIsTenSeconds() {
        assertThat(WorkoutEngine.heartRateInterval).isEqualTo(10.0)
    }
}

// endregion

// region Sync tests of the Swift suite, phone side only

class EngineSyncTests {
    @get:Rule
    val folder = TemporaryFolder()

    /**
     * Adapted from `testCommandsFromTheWatchAreHeartRateThrottledToo`: the Swift test delivered the samples as RemoteCommands;
     * the Kotlin engine has no commands, an action of origin WATCH goes through `send`.
     */
    @Test
    fun testCommandsFromTheWatchAreHeartRateThrottledToo() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        for (bpm in listOf(100, 101, 102)) {
            rig.engine.send(WorkoutAction.UpdateHeartRate(bpm), ActionOrigin.WATCH)
            rig.clock.advance(2.0)
        }
        assertThat(rig.recorder.changes).hasSize(1)
        assertThat(rig.engine.state?.heartRate).isEqualTo(102)
    }

    /**
     * Adapted from `testACommandThatArrivesWithoutAWorkoutIsConsumed`: without sync commands only the phone half remains. An action
     * that arrives while no workout runs is dropped and cannot hit the workout that starts afterwards.
     */
    @Test
    fun testAnActionThatArrivesWithoutAWorkoutDoesNotHitTheNextWorkout() {
        val rig = SvcRig(folder)
        rig.engine.send(WorkoutAction.LogNextSet, ActionOrigin.WATCH)
        assertThat(rig.engine.state).isNull()
        rig.startUpperA()
        assertThat(rig.engine.state?.revision).isEqualTo(0)
        assertThat(rig.engine.state?.exercises?.sumOf { it.doneCount }).isEqualTo(0)
        assertThat(rig.recorder.changes).isEmpty()
    }

    private fun randomAction(state: WorkoutState, random: SvcLCG): WorkoutAction {
        val exercises = state.exercises
        fun pickExercise(): WorkoutExercise? = if (exercises.isEmpty()) null else exercises[random.int(exercises.size)]
        fun pickSet(exercise: WorkoutExercise): LoggedSet? = if (exercise.sets.isEmpty()) null else exercise.sets[random.int(exercise.sets.size)]
        val unknown = SvcSyncFix.uuid(9_999)
        return when (random.int(34)) {
            0, 1, 2, 3 -> WorkoutAction.LogNextSet
            4, 5 -> {
                val e = pickExercise() ?: return WorkoutAction.LogNextSet
                val s = pickSet(e) ?: return WorkoutAction.LogNextSet
                WorkoutAction.ToggleSet(e.id, s.id)
            }
            6 -> {
                val e = pickExercise() ?: return WorkoutAction.LogNextSet
                val s = pickSet(e) ?: return WorkoutAction.LogNextSet
                WorkoutAction.LogSet(e.id, s.id)
            }
            7 -> {
                val e = pickExercise() ?: return WorkoutAction.SkipRest
                val s = pickSet(e) ?: return WorkoutAction.SkipRest
                WorkoutAction.SetWeight(e.id, s.id, random.int(400).toDouble() / 4)
            }
            8 -> {
                val e = pickExercise() ?: return WorkoutAction.SkipRest
                val s = pickSet(e) ?: return WorkoutAction.SkipRest
                WorkoutAction.SetReps(e.id, s.id, random.int(-2..30))
            }
            9 -> WorkoutAction.NudgeNextSet(random.int(-3..3), random.int(-3..3))
            10 -> {
                val e = pickExercise() ?: return WorkoutAction.SkipRest
                val s = pickSet(e) ?: return WorkoutAction.SkipRest
                WorkoutAction.SetSetType(e.id, s.id, SetType.entries[random.int(SetType.entries.size)])
            }
            11 -> {
                val e = pickExercise() ?: return WorkoutAction.SkipRest
                val s = pickSet(e) ?: return WorkoutAction.SkipRest
                WorkoutAction.SetRIR(e.id, s.id, if (random.int(2) == 0) null else random.int(0..5))
            }
            12 -> WorkoutAction.ToggleLastSetRIR(random.int(0..4))
            13 -> {
                val e = pickExercise() ?: return WorkoutAction.AddSet(unknown)
                WorkoutAction.AddSet(e.id)
            }
            14 -> {
                val e = pickExercise() ?: return WorkoutAction.Undo
                val s = pickSet(e) ?: return WorkoutAction.Undo
                WorkoutAction.DeleteSet(e.id, s.id)
            }
            15 -> {
                val e = pickExercise() ?: return WorkoutAction.Undo
                WorkoutAction.SetNote(e.id, "note ${random.int(100)}")
            }
            16 -> WorkoutAction.GoTo(random.int(-1..8))
            17 -> if (random.int(2) == 0) WorkoutAction.NextExercise else WorkoutAction.PreviousExercise
            18 -> {
                val library = ExerciseLibrary.builtIn
                WorkoutAction.AddExercises(listOf(library[random.int(library.size)]))
            }
            19 -> {
                val e = pickExercise() ?: return WorkoutAction.Undo
                WorkoutAction.RemoveExercise(e.id)
            }
            20 -> WorkoutAction.MoveExercise(random.int(0..7), random.int(0..7))
            21 -> {
                val e = pickExercise() ?: return WorkoutAction.Undo
                WorkoutAction.MoveExerciseBy(e.id, random.int(-2..2))
            }
            22 -> {
                val e = pickExercise() ?: return WorkoutAction.Undo
                WorkoutAction.ReplaceExercise(e.id, ExerciseLibrary.builtIn[random.int(ExerciseLibrary.builtIn.size)])
            }
            23 -> {
                val e = pickExercise() ?: return WorkoutAction.Undo
                WorkoutAction.ToggleSuperset(e.id)
            }
            24 -> {
                val e = pickExercise() ?: return WorkoutAction.Undo
                WorkoutAction.SetRest(e.id, random.int(0..4) * 30)
            }
            25 -> WorkoutAction.AdjustRest(random.int(-2..2) * 15)
            26 -> WorkoutAction.SkipRest
            27 -> if (random.int(2) == 0) WorkoutAction.Pause else WorkoutAction.Resume
            28 -> WorkoutAction.Undo
            29, 30 -> WorkoutAction.UpdateHeartRate(if (random.int(5) == 0) null else random.int(60..190))
            31 -> WorkoutAction.SetAutoStartRest(random.int(2) == 0)
            32 -> WorkoutAction.SetUsedWatch(random.int(2) == 0)
            else -> WorkoutAction.Rename("Workout ${random.int(50)}")
        }
    }

    /**
     * Adapted from `testPhoneDiskAndWatchStayInSyncUnderRandomPlay`: the phone half of the scenario (same seeds, same random
     * actions, same start / finish / discard choices). The saved workout follows every reported change and is gone after an
     * ending. The Watch half (an envelope of the state after every step) does not exist in the Kotlin port.
     */
    @Test
    fun testPhoneDiskAndWatchStayInSyncUnderRandomPlay() {
        for (seed in 1..14) {
            val random = SvcLCG(seed.toULong() * 7_919uL)
            val phone = SvcRig(folder)
            var started = 0
            for (step in 0 until 120) {
                phone.clock.advance(random.int(0..32).toDouble() / 4)
                val events = phone.recorder.events.size

                if (phone.engine.state == null) {
                    phone.engine.start(if (random.int(2) == 0) phone.upperA else null, "Free $step")
                    started += 1
                } else if (random.int(40) == 0) {
                    if (random.int(2) == 0) phone.engine.finish(random.int(2) == 0) else phone.engine.discard()
                    assertWithMessage("seed $seed step $step").that(phone.diskState).isNull()
                    assertWithMessage("seed $seed step $step").that(phone.engine.state).isNull()
                    continue
                } else {
                    val action = randomAction(phone.engine.state!!, random)
                    phone.engine.send(action, ActionOrigin.PHONE)
                }

                if (phone.recorder.events.size > events) {
                    assertWithMessage("seed $seed step $step: disk follows the reported state").that(phone.diskState).isEqualTo(phone.engine.state)
                }
                val current = phone.engine.state
                if (current != null) {
                    assertWithMessage("seed $seed step $step").that(current.currentIndex).isAtLeast(0)
                    assertWithMessage("seed $seed step $step").that(current.currentIndex).isAtMost(maxOf(0, current.exercises.size - 1))
                }
            }
            assertWithMessage("seed $seed started workouts").that(started).isAtLeast(1)
        }
    }
}

// endregion

// region Finish, discard, restore

class EngineLifecycleTests {
    @get:Rule
    val folder = TemporaryFolder()

    @Test
    fun testFinishRecordsTheWorkoutEverywhere() {
        val rig = SvcRig(folder)
        val started = rig.startUpperA()
        rig.logSets(5)
        rig.clock.advance(1_800.0)
        val previous = rig.engine.state!!
        val historyBefore = rig.model.data.history.size

        val completed = rig.engine.finish(false)
        assertWithMessage("nothing was recorded").that(completed).isNotNull()
        completed!!
        assertThat(rig.engine.state).isNull()
        assertThat(rig.engine.lastCompleted).isEqualTo(completed)
        assertThat(completed.name).isEqualTo("Upper A · Push")
        assertThat(completed.templateID).isEqualTo(started.templateID)
        assertThat(completed.finishedAt).isEqualTo(rig.clock.now)
        assertThat(completed.loggedSets).isEqualTo(5)
        assertThat(rig.model.data.history).hasSize(historyBefore + 1)
        assertThat(rig.model.data.history.first()).isEqualTo(completed)
        assertThat(rig.persistence.loadHistory().first()).isEqualTo(completed)
        assertWithMessage("the persisted active workout is deleted").that(rig.diskState).isNull()
        assertThat(rig.recorder.events.last()).isEqualTo(Event.Ended(previous, completed))
        assertThat(rig.recorder.events.count { it is Event.Ended }).isEqualTo(1)
        assertThat(rig.updates).isEqualTo(1 + 5 + 1)
    }

    @Test
    fun testFinishRaisesThePersonalBest() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.logSets(5)                                   // 2 warm-ups, 82.5 x 6, 82.5 x 6, 85 x 6
        val before = rig.model.data.personalBests["bench"]?.estimated1RM ?: 0.0
        assertThat(before).isWithin(1e-9).of(85 * (1 + 5.0 / 30))
        rig.engine.finish(false)
        val best = rig.model.data.personalBests["bench"]
        assertThat(best?.estimated1RM ?: 0.0).isWithin(1e-9).of(102.0)
        assertThat(best?.weightKg).isEqualTo(85.0)
        assertThat(best?.reps).isEqualTo(6)
        assertThat(best?.date).isEqualTo(rig.clock.now)
        assertThat(rig.persistence.loadPersonalBests()["bench"]).isEqualTo(best)
        assertThat(rig.model.exercise("bench")?.previousBestE1RM ?: 0.0).isWithin(1e-9).of(102.0)
    }

    @Test
    fun testFinishLeavesALowerPersonalBestAlone() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.logSets(3)                                   // best working set 82.5 x 6 = 99 < 99.17
        val before = rig.model.data.personalBests["bench"]
        rig.engine.finish(false)
        assertThat(rig.model.data.personalBests["bench"]).isEqualTo(before)
    }

    @Test
    fun testFinishStampsTheTemplateButLeavesItsExercisesAlone() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.engine.send(WorkoutAction.AddExercises(listOf(ExerciseLibrary.exercise("dips")!!)))
        rig.logSets(2)
        val templatesBefore = rig.model.data.templates
        rig.engine.finish(false)
        val templates = rig.model.data.templates
        assertThat(templates[0].lastPerformed).isEqualTo(rig.clock.now)
        assertThat(templates[0].entries).isEqualTo(templatesBefore[0].entries)
        assertThat(templates[1]).isEqualTo(templatesBefore[1])
        assertThat(templates[2]).isEqualTo(templatesBefore[2])
        assertThat(rig.persistence.loadTemplates()).isEqualTo(templates)
    }

    @Test
    fun testFinishCanUpdateTheTemplateFromTheWorkout() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.engine.send(WorkoutAction.AddExercises(listOf(ExerciseLibrary.exercise("dips")!!)))
        rig.engine.send(WorkoutAction.RemoveExercise(rig.engine.state!!.exercises[5].id))      // crossover goes
        rig.logSets(2)
        val before = rig.upperA
        rig.engine.finish(true)
        val updated = rig.model.data.templates[0]
        assertThat(updated.id).isEqualTo(before.id)
        assertThat(updated.name).isEqualTo(before.name)
        assertThat(updated.lastPerformed).isEqualTo(rig.clock.now)
        assertThat(updated.entries.map { it.exercise.id }).isEqualTo(listOf("bench", "incline", "ohp", "lateral", "pushdown", "dips"))
        assertWithMessage("kept entries keep their ids").that(updated.entries.take(5).map { it.id }).isEqualTo(before.entries.take(5).map { it.id })
        assertThat(rig.model.data.templates).hasSize(3)
        assertThat(rig.persistence.loadTemplates()[0]).isEqualTo(updated)
    }

    @Test
    fun testUpdatingATemplateOfAWorkoutWithoutOneDoesNothing() {
        val rig = SvcRig(folder)
        rig.engine.start(null, "Free")
        rig.engine.send(WorkoutAction.AddExercises(listOf(ExerciseLibrary.exercise("bench")!!)))
        rig.logSets(1)
        val templates = rig.model.data.templates
        val completed = rig.engine.finish(true)
        assertThat(completed).isNotNull()
        assertThat(completed?.templateID).isNull()
        assertThat(rig.model.data.templates).isEqualTo(templates)
    }

    @Test
    fun testUpdatingATemplateThatNoLongerExistsDoesNotBringItBack() {
        val rig = SvcRig(folder, seed = false)
        val orphan = SampleData.templates()[0]
        rig.engine.start(orphan)
        rig.logSets(1)
        rig.engine.finish(true)
        assertThat(rig.model.data.templates).isEmpty()
        assertThat(rig.model.data.history).hasSize(1)
    }

    @Test
    fun testFinishingWithNothingLoggedDiscardsInstead() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        val previous = rig.engine.state!!
        val historyBefore = rig.model.data.history
        assertThat(rig.engine.finish(true)).isNull()
        assertThat(rig.engine.state).isNull()
        assertThat(rig.engine.lastCompleted).isNull()
        assertThat(rig.model.data.history).isEqualTo(historyBefore)
        assertThat(rig.diskState).isNull()
        assertThat(rig.recorder.events.last()).isEqualTo(Event.Ended(previous, null))
    }

    @Test
    fun testFinishWithoutAWorkoutReturnsNil() {
        val rig = SvcRig(folder)
        assertThat(rig.engine.finish(false)).isNull()
        assertThat(rig.recorder.events).isEmpty()
        assertThat(rig.updates).isEqualTo(0)
    }

    @Test
    fun testNothingHappensAfterTheWorkoutEnded() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.logSets(1)
        rig.engine.finish(false)
        val events = rig.recorder.events.size
        rig.engine.send(WorkoutAction.LogNextSet)
        rig.engine.discard()
        assertThat(rig.engine.finish(false)).isNull()
        assertThat(rig.recorder.events).hasSize(events)
        assertThat(rig.diskState).isNull()
    }

    @Test
    fun testDiscardDropsTheWorkoutWithoutRecordingIt() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.logSets(3)
        val previous = rig.engine.state!!
        val history = rig.model.data
        rig.engine.discard()
        assertThat(rig.engine.state).isNull()
        assertThat(rig.diskState).isNull()
        assertThat(rig.model.data).isEqualTo(history)
        assertThat(rig.recorder.events.last()).isEqualTo(Event.Ended(previous, null))
    }

    @Test
    fun testDiscardKeepsTheLastFinishedWorkout() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.logSets(1)
        val completed = rig.engine.finish(false)
        rig.engine.start(null, "Second")
        assertThat(rig.engine.lastCompleted).isNull()
        rig.engine.discard()
        assertThat(rig.engine.lastCompleted).isNull()
        assertThat(rig.model.data.history.first()).isEqualTo(completed)
    }

    @Test
    fun testDiscardWithoutAWorkoutDoesNothing() {
        val rig = SvcRig(folder)
        rig.engine.discard()
        assertThat(rig.recorder.events).isEmpty()
    }

    @Test
    fun testRestoreBringsBackTheSavedWorkoutAndTellsTheEffects() {
        val persistence = FileStrengthPersistence(folder.newFolder())
        val saved = run {
            val rig = SvcRig(folder, persistence = persistence)
            rig.startUpperA()
            rig.logSets(3)
            rig.engine.send(WorkoutAction.Pause)
            rig.engine.state!!
        }
        val rig = SvcRig(folder, persistence = persistence)
        assertThat(rig.engine.state).isNull()
        rig.engine.restore()
        assertThat(rig.engine.state).isEqualTo(saved)
        assertThat(rig.recorder.events).isEqualTo(listOf(Event.Started(saved)))
        assertThat(rig.updates).isEqualTo(1)
        // The restored workout is fully alive.
        rig.engine.send(WorkoutAction.Resume)
        assertThat(rig.engine.state?.revision).isEqualTo(saved.revision + 1)
        assertThat(rig.diskState).isEqualTo(rig.engine.state)
        rig.logSets(1)
        assertThat(rig.engine.finish(false)).isNotNull()
    }

    @Test
    fun testRestoreLeavesARunningWorkoutAlone() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.logSets(2)
        rig.clock.advance(1.0)
        rig.engine.send(WorkoutAction.UpdateHeartRate(100))
        rig.clock.advance(1.0)
        rig.engine.send(WorkoutAction.UpdateHeartRate(101))                       // newer than the file
        val live = rig.engine.state
        val events = rig.recorder.events.size
        rig.engine.restore()
        assertThat(rig.engine.state).isEqualTo(live)
        assertThat(rig.recorder.events).hasSize(events)
    }

    @Test
    fun testRestoreWithoutASavedWorkoutDoesNothing() {
        val rig = SvcRig(folder)
        rig.engine.restore()
        assertThat(rig.engine.state).isNull()
        assertThat(rig.recorder.events).isEmpty()
        assertThat(rig.updates).isEqualTo(0)
    }

    @Test
    fun testRestoreSurvivesACorruptFile() {
        val directory = folder.newFolder()
        File(directory, "active-workout.json").writeText("{ broken")
        val rig = SvcRig(folder, persistence = FileStrengthPersistence(directory))
        rig.engine.restore()
        assertThat(rig.engine.state).isNull()
        rig.startUpperA()
        assertWithMessage("a fresh workout overwrites the damaged file").that(rig.diskState).isNotNull()
    }

    @Test
    fun testAnEngineWithoutPersistenceWorksInMemory() {
        val clock = SvcClock()
        val model = StrengthDataModel(persistence = null, seedDemoData = true, now = clock.now)
        val engine = WorkoutEngine(persistence = null, data = model, clock = clock.reader)
        engine.restore()
        assertThat(engine.state).isNull()
        engine.start(model.data.templates[0])
        engine.send(WorkoutAction.LogNextSet)
        assertThat(engine.state?.revision).isEqualTo(1)
        assertThat(engine.finish(false)).isNotNull()
        assertThat(engine.lastPersistenceError).isNull()
    }

    @Test
    fun testASaveFailureIsRecordedAndTheWorkoutKeepsRunning() {
        val blocker = folder.newFile("PulseStrength-engine-blocker")
        blocker.writeText("file")
        val broken = FileStrengthPersistence(File(blocker, "inner"))
        val rig = SvcRig(folder, seed = false, persistence = broken)
        rig.engine.start(SampleData.templates()[0])
        assertThat(rig.engine.lastPersistenceError).isNotNull()
        rig.engine.send(WorkoutAction.LogNextSet)
        assertWithMessage("the in-memory workout is unaffected").that(rig.engine.state?.revision).isEqualTo(1)
        assertThat(rig.recorder.changes).hasSize(1)
    }

    @Test
    fun testTheSavedWorkoutAlwaysMatchesTheLiveOne() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        val actions: List<WorkoutAction> = listOf(
            WorkoutAction.LogNextSet, WorkoutAction.NextExercise, WorkoutAction.AdjustRest(15), WorkoutAction.Pause, WorkoutAction.Resume,
            WorkoutAction.Rename("Renamed"), WorkoutAction.LogNextSet,
        )
        for (action in actions) {
            rig.clock.advance(5.0)
            rig.engine.send(action)
            assertWithMessage("$action").that(rig.diskState).isEqualTo(rig.engine.state)
        }
    }

    // region Extra tests (not in EngineTests.swift)

    /**
     * RegressionTests.swift `testSVC1_FinishKeepsTheActiveWorkoutFileWhenTheHistoryCouldNotBeSaved`: `finish` deleted
     * `active-workout.json` even when the history could not be written, so the logged sets were lost at the next launch.
     */
    @Test
    fun testSVC1_FinishKeepsTheActiveWorkoutFileWhenTheHistoryCouldNotBeSaved() {
        val persistence = FileStrengthPersistence(folder.newFolder())
        // history.json can no longer be replaced (stands in for a full disk / I/O error: the atomic write throws).
        val blocker = File(persistence.directory, "history.json")
        assertThat(blocker.mkdirs()).isTrue()
        File(blocker, "keep").writeText("x")

        val workoutID = run {
            val rig = SvcRig(folder, persistence = persistence)
            rig.startUpperA()
            rig.logSets(2)
            val loggedBefore = rig.engine.state?.exercises?.sumOf { it.doneCount }
            assertThat(loggedBefore).isEqualTo(2)
            val id = rig.engine.state!!.id

            val completed = rig.engine.finish(false)
            assertWithMessage("the user still gets the finished workout (summary screen)").that(completed?.loggedSets).isEqualTo(2)
            assertThat(rig.engine.state).isNull()
            assertWithMessage("the workout is in memory").that(rig.model.data.history.firstOrNull()?.id).isEqualTo(id)
            assertWithMessage("the failed save is reported, not swallowed").that(rig.engine.lastPersistenceError).isNotNull()

            // What a relaunch would find on disk.
            assertWithMessage("precondition: nothing could be written to history.json").that(persistence.loadHistory()).isEmpty()
            assertWithMessage("the two logged sets exist nowhere on disk any more").that(persistence.loadActiveWorkout()).isNotNull()
            id
        }

        // The relaunch: the unsaved workout comes back with every logged set, and finishing it again saves it once the disk works.
        assertThat(blocker.deleteRecursively()).isTrue()
        val rig = SvcRig(folder, seed = false, persistence = persistence)
        rig.engine.restore()
        assertThat(rig.engine.state?.id).isEqualTo(workoutID)
        assertThat(rig.engine.state?.exercises?.sumOf { it.doneCount }).isEqualTo(2)
        assertThat(rig.engine.finish(false)).isNotNull()
        assertThat(rig.engine.lastPersistenceError).isNull()
        assertWithMessage("saved exactly once").that(persistence.loadHistory().map { it.id }).isEqualTo(listOf(workoutID))
        assertWithMessage("now that the history is safe the active file is removed").that(persistence.loadActiveWorkout()).isNull()
    }

    @Test
    fun testLastEndDiscardedTellsHowTheWorkoutEnded() {
        val rig = SvcRig(folder)
        val seen = mutableListOf<Boolean>()
        rig.recorder.onEvent = { event -> if (event is Event.Ended) seen.add(rig.engine.lastEndDiscarded) }

        rig.startUpperA()
        rig.logSets(1)
        assertThat(rig.engine.finish(false)).isNotNull()
        assertThat(rig.engine.lastEndDiscarded).isFalse()

        rig.startUpperA()
        rig.logSets(1)
        rig.engine.discard()
        assertThat(rig.engine.lastEndDiscarded).isTrue()

        rig.startUpperA()
        assertWithMessage("a finish with no logged set is a discard").that(rig.engine.finish(false)).isNull()
        assertThat(rig.engine.lastEndDiscarded).isTrue()

        assertWithMessage("set before the effects' workoutEnded runs").that(seen).isEqualTo(listOf(false, true, true))
    }

    // endregion
}

// endregion
