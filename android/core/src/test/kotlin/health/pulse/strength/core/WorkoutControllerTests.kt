package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.EngineBasicsTests.SvcClock
import health.pulse.strength.core.EngineBasicsTests.SvcRecorder
import health.pulse.strength.core.EngineBasicsTests.SvcRecorder.Event
import java.io.File
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

// The Kotlin WorkoutController / StrengthStore flows. Ports WorkoutControllerWrapperTests of EngineTests.swift (minus the role,
// mirror and RemoteCommand parts) and adds the scenarios of the controller contract: the `state` / `lastCompleted` flows, the
// relaunch (`restoreFromDisk` on a new controller over the same directory), the effects' arguments, and the history write that
// fails on `finish` (RegressionTests.swift SVC-1: the active-workout file is kept, `lastPersistenceError` is set, finishing the
// restored workout again records it once).

class WorkoutControllerTests {
    @get:Rule
    val folder = TemporaryFolder()

    private fun makePersistence(): FileStrengthPersistence = FileStrengthPersistence(folder.newFolder())

    /** A store holding the three sample templates (no history), like the Swift `makeStore`. */
    private fun makeStore(persistence: FileStrengthPersistence?): StrengthStore {
        val store = StrengthStore(persistence)
        for (template in SampleData.templates()) store.saveTemplate(template)
        return store
    }

    /** Makes `history.json` impossible to replace (a non-empty directory stands in for a full disk / I/O error). */
    private fun breakHistoryFile(persistence: FileStrengthPersistence): File {
        val blocker = File(persistence.directory, "history.json")
        assertThat(blocker.mkdirs()).isTrue()
        File(blocker, "keep").writeText("x")
        return blocker
    }

    private fun doneSets(state: WorkoutState?): Int = state?.exercises?.sumOf { it.doneCount } ?: 0

    // region Ported from WorkoutControllerWrapperTests

    @Test
    fun testThePublishedStateFollowsTheWorkout() {
        val persistence = makePersistence()
        val store = makeStore(persistence)
        val clock = SvcClock()
        val controller = WorkoutController(store, persistence, clock = clock.reader)
        assertThat(controller.state.value).isNull()
        assertThat(controller.presentation(clock.now)).isNull()
        assertThat(controller.store).isSameInstanceAs(store)

        assertThat(controller.startWorkout(store.templates[0])).isTrue()
        assertThat(controller.state.value?.name).isEqualTo("Upper A · Push")
        assertThat(persistence.loadActiveWorkout()).isEqualTo(controller.state.value)

        clock.advance(30.0)
        controller.send(WorkoutAction.LogNextSet)
        assertThat(controller.state.value?.revision).isEqualTo(1)
        assertThat(controller.presentation(clock.now)?.totals?.loggedSets).isEqualTo(1)
        assertThat(controller.snapshot(clock.now)?.workoutID).isEqualTo(controller.state.value?.id)
        assertThat(controller.templateDiff().isEmpty).isTrue()

        val completed = controller.finish(false)
        assertThat(completed).isNotNull()
        assertThat(controller.state.value).isNull()
        assertThat(controller.lastCompleted.value).isEqualTo(completed)
        assertWithMessage("the store publishes the recorded workout").that(store.history.first()).isEqualTo(completed)
        assertThat(store.data.value.history.first()).isEqualTo(completed)
        assertThat(store.templates[0].lastPerformed).isEqualTo(completed?.finishedAt)
        assertThat(persistence.loadActiveWorkout()).isNull()
    }

    @Test
    fun testStartingWithoutATemplateAndDiscarding() {
        val controller = WorkoutController(makeStore(null), null)
        assertThat(controller.startWorkout(null)).isTrue()
        assertThat(controller.state.value?.name).isEqualTo("Workout")
        assertWithMessage("ignored while one runs").that(controller.startWorkout(null, "Second")).isFalse()
        assertThat(controller.state.value?.name).isEqualTo("Workout")
        controller.discard()
        assertThat(controller.state.value).isNull()
        assertThat(controller.lastCompleted.value).isNull()
        controller.startWorkout(null, "Second")
        assertThat(controller.state.value?.name).isEqualTo("Second")
    }

    /**
     * Adapted from `testEffectsRestoreAndCommands`: the Swift test fed the workout a RemoteCommand twice (the second was
     * dropped as a duplicate); the Kotlin controller has no commands, the action goes through `send`.
     */
    @Test
    fun testEffectsRestoreAndRelaunch() {
        val persistence = makePersistence()
        val store = makeStore(persistence)
        val clock = SvcClock()
        val first = WorkoutController(store, persistence, clock = clock.reader)
        val recorder = SvcRecorder()
        first.addEffect(recorder)
        first.startWorkout(store.templates[1])
        first.send(WorkoutAction.LogNextSet, ActionOrigin.WATCH)
        assertThat(first.state.value?.revision).isEqualTo(1)
        assertThat(recorder.changes).hasSize(1)

        // A relaunch picks the workout up again.
        val second = WorkoutController(store, persistence, clock = clock.reader)
        val relaunched = SvcRecorder()
        second.addEffect(relaunched)
        assertThat(second.state.value).isNull()
        second.restoreFromDisk()
        assertThat(second.state.value).isEqualTo(first.state.value)
        assertThat(relaunched.events).isEqualTo(listOf(Event.Started(first.state.value!!)))
    }

    /** Adapted from `testTheMirrorFollowsEnvelopesAndKeepsTheRecoveryProvider` (the recovery provider part). */
    @Test
    fun testTheRecoveryProviderIsKeptAndCanBeReplaced() {
        val store = makeStore(null)
        val controller = WorkoutController(store, null, recovery = { 12 })
        assertThat(controller.recovery(MuscleGroup.CHEST)).isEqualTo(12)
        controller.recovery = { 77 }
        assertThat(controller.recovery(MuscleGroup.LEGS)).isEqualTo(77)

        controller.startWorkout(store.templates[0])                         // the first card is the bench press (chest)
        assertThat(controller.presentation(SvcClock().now)?.card?.recoveryPercent).isEqualTo(77)
    }

    /** Adapted from `testObjectWillChangeFiresForEveryPublishedChange` (Combine only): the `state` StateFlow emits per change. */
    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun testTheStateFlowEmitsForEveryPublishedChange() = runTest {
        val store = makeStore(null)
        val controller = WorkoutController(store, null)
        val states = mutableListOf<WorkoutState?>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { controller.state.collect { states.add(it) } }
        assertThat(states).isEqualTo(listOf<WorkoutState?>(null))

        controller.startWorkout(store.templates[0])
        assertThat(states).hasSize(2)
        val afterStart = states.size
        controller.send(WorkoutAction.SkipRest)                              // no change
        assertThat(states).hasSize(afterStart)
        controller.send(WorkoutAction.NextExercise)
        assertThat(states).hasSize(afterStart + 1)
        assertThat(states.last()?.currentIndex).isEqualTo(1)
        controller.discard()
        assertThat(states).hasSize(afterStart + 2)
        assertThat(states.last()).isNull()
    }

    // endregion

    // region State and lastCompleted follow start / send / finish / discard

    @Test
    fun testStateAndLastCompletedFollowStartSendFinishAndDiscard() {
        val persistence = makePersistence()
        val store = makeStore(persistence)
        val clock = SvcClock()
        val controller = WorkoutController(store, persistence, clock = clock.reader)
        assertThat(controller.state.value).isNull()
        assertThat(controller.lastCompleted.value).isNull()

        // start
        assertThat(controller.startWorkout(store.templates[0])).isTrue()
        val started = controller.state.value!!
        assertThat(started.startedAt).isEqualTo(clock.now)
        assertThat(started.revision).isEqualTo(0)
        assertThat(controller.lastCompleted.value).isNull()

        // send: every change replaces the published state, a no-op does not
        clock.advance(60.0)
        controller.send(WorkoutAction.LogNextSet)
        val logged = controller.state.value!!
        assertThat(logged.revision).isEqualTo(1)
        assertThat(doneSets(logged)).isEqualTo(1)
        controller.send(WorkoutAction.GoTo(logged.currentIndex))   // already there
        assertThat(controller.state.value).isEqualTo(logged)

        // finish: the state goes, lastCompleted arrives
        clock.advance(60.0)
        controller.send(WorkoutAction.LogNextSet)
        val completed = controller.finish(false)
        assertThat(completed).isNotNull()
        assertThat(completed?.loggedSets).isEqualTo(2)
        assertThat(controller.state.value).isNull()
        assertThat(controller.lastCompleted.value).isEqualTo(completed)

        // the next workout clears lastCompleted
        clock.advance(60.0)
        assertThat(controller.startWorkout(null, "Free")).isTrue()
        assertThat(controller.state.value?.name).isEqualTo("Free")
        assertThat(controller.lastCompleted.value).isNull()

        // discard: the state goes, nothing is recorded, lastCompleted stays empty
        val historyBefore = store.history
        controller.discard()
        assertThat(controller.state.value).isNull()
        assertThat(controller.lastCompleted.value).isNull()
        assertThat(store.history).isEqualTo(historyBefore)

        // finishing a workout with nothing logged is a discard too
        controller.startWorkout(store.templates[1])
        assertThat(controller.finish(true)).isNull()
        assertThat(controller.state.value).isNull()
        assertThat(controller.lastCompleted.value).isNull()
        assertThat(persistence.loadActiveWorkout()).isNull()
    }

    @Test
    fun testHeartRateSamplesAreAllPublishedButReportedAtMostOncePerTenSeconds() {
        val persistence = makePersistence()
        val store = makeStore(persistence)
        val clock = SvcClock()
        val controller = WorkoutController(store, persistence, clock = clock.reader)
        val recorder = SvcRecorder()
        controller.addEffect(recorder)
        controller.startWorkout(store.templates[0])

        controller.send(WorkoutAction.UpdateHeartRate(100), ActionOrigin.WATCH)
        clock.advance(4.0)
        controller.send(WorkoutAction.UpdateHeartRate(110), ActionOrigin.WATCH)
        assertWithMessage("the published state follows every sample").that(controller.state.value?.heartRate).isEqualTo(110)
        assertThat(recorder.changes).hasSize(1)
        assertThat(persistence.loadActiveWorkout()?.heartRate).isEqualTo(100)
        clock.advance(6.0)
        controller.send(WorkoutAction.UpdateHeartRate(120), ActionOrigin.WATCH)
        assertThat(recorder.changes).hasSize(2)
        assertThat(persistence.loadActiveWorkout()?.heartRate).isEqualTo(120)
        assertThat(controller.state.value?.revision).isEqualTo(0)
    }

    // endregion

    // region Effects

    @Test
    fun testEffectsAreCalledWithTheRightArguments() {
        val store = makeStore(null)
        val clock = SvcClock()
        val controller = WorkoutController(store, null, clock = clock.reader)
        val recorder = SvcRecorder()
        controller.addEffect(recorder)
        controller.addEffect(recorder)                                       // registered once

        // workoutStarted(state)
        controller.startWorkout(store.templates[0])
        val started = controller.state.value!!
        assertThat(recorder.events).isEqualTo(listOf(Event.Started(started)))

        // workoutChanged(old, new, action, origin)
        clock.advance(30.0)
        controller.send(WorkoutAction.LogNextSet, ActionOrigin.LIVE_ACTIVITY)
        val afterLog = controller.state.value!!
        assertThat(recorder.events.last()).isEqualTo(Event.Changed(started, afterLog, WorkoutAction.LogNextSet, ActionOrigin.LIVE_ACTIVITY))
        controller.send(WorkoutAction.NextExercise)
        assertThat(recorder.events.last())
            .isEqualTo(Event.Changed(afterLog, controller.state.value!!, WorkoutAction.NextExercise, ActionOrigin.PHONE))
        assertWithMessage("a change-free action tells nobody").that(recorder.events).hasSize(3)
        controller.send(WorkoutAction.Undo)
        assertThat(recorder.events).hasSize(3)

        // workoutEnded(previous, completed)
        val previous = controller.state.value!!
        clock.advance(30.0)
        val seenDiscarded = mutableListOf<Boolean>()
        recorder.onEvent = { event -> if (event is Event.Ended) seenDiscarded.add(controller.lastEndDiscarded) }
        val completed = controller.finish(false)
        assertThat(recorder.events.last()).isEqualTo(Event.Ended(previous, completed))
        assertThat(completed?.finishedAt).isEqualTo(clock.now)

        // workoutEnded(previous, null) for a discard
        controller.startWorkout(null, "Free")
        val free = controller.state.value!!
        controller.discard()
        assertThat(recorder.events.last()).isEqualTo(Event.Ended(free, null))
        assertWithMessage("lastEndDiscarded is set before workoutEnded runs").that(seenDiscarded).isEqualTo(listOf(false, true))
    }

    @Test
    fun testEffectsSeeTheNewStateAlreadyPublishedOnTheFlow() {
        val store = makeStore(null)
        val controller = WorkoutController(store, null)
        val recorder = SvcRecorder()
        val seen = mutableListOf<String>()
        recorder.onEvent = { event ->
            when (event) {
                is Event.Started -> seen.add(if (controller.state.value == event.state) "started: flow has the state" else "started: stale flow")
                is Event.Changed -> seen.add(if (controller.state.value == event.to) "changed: flow has the new state" else "changed: stale flow")
                is Event.Ended -> seen.add(
                    if (controller.state.value == null && controller.lastCompleted.value == event.completed) "ended: flow is cleared" else "ended: stale flow",
                )
            }
        }
        controller.addEffect(recorder)
        controller.startWorkout(store.templates[0])
        controller.send(WorkoutAction.LogNextSet)
        controller.finish(false)
        assertThat(seen).isEqualTo(listOf("started: flow has the state", "changed: flow has the new state", "ended: flow is cleared"))
    }

    // endregion

    // region Relaunch

    @Test
    fun testRestoreFromDiskAfterARelaunchRestoresTheWorkout() {
        val persistence = makePersistence()
        val clock = SvcClock()
        val saved = run {
            val store = makeStore(persistence)
            val controller = WorkoutController(store, persistence, clock = clock.reader)
            controller.startWorkout(store.templates[0])
            repeat(3) {
                clock.advance(60.0)
                controller.send(WorkoutAction.LogNextSet)
            }
            controller.send(WorkoutAction.Pause)
            controller.state.value!!
        }

        // "Relaunch": everything is new, only the directory is the same.
        val store = StrengthStore(FileStrengthPersistence(persistence.directory))
        assertThat(store.templates).hasSize(3)
        val controller = WorkoutController(store, FileStrengthPersistence(persistence.directory), clock = clock.reader)
        val recorder = SvcRecorder()
        controller.addEffect(recorder)
        assertThat(controller.state.value).isNull()
        controller.restoreFromDisk()
        assertThat(controller.state.value).isEqualTo(saved)
        assertThat(controller.lastCompleted.value).isNull()
        assertThat(recorder.events).isEqualTo(listOf(Event.Started(saved)))

        // The restored workout is fully alive, and a second restore while it runs changes nothing.
        controller.restoreFromDisk()
        assertThat(recorder.events).hasSize(1)
        clock.advance(10.0)
        controller.send(WorkoutAction.Resume)
        assertThat(controller.state.value?.revision).isEqualTo(saved.revision + 1)
        assertThat(controller.state.value?.isPaused).isFalse()
        controller.send(WorkoutAction.LogNextSet)
        assertThat(doneSets(controller.state.value)).isEqualTo(4)
        val completed = controller.finish(false)
        assertThat(completed?.loggedSets).isEqualTo(4)
        assertThat(store.history.map { it.id }).isEqualTo(listOf(saved.id))
    }

    @Test
    fun testRestoreFromDiskWithoutASavedWorkoutOrWithACorruptFileDoesNothing() {
        val persistence = makePersistence()
        val store = makeStore(persistence)
        val controller = WorkoutController(store, persistence)
        val recorder = SvcRecorder()
        controller.addEffect(recorder)
        controller.restoreFromDisk()
        assertThat(controller.state.value).isNull()
        assertThat(recorder.events).isEmpty()

        File(persistence.directory, "active-workout.json").writeText("{ broken")
        controller.restoreFromDisk()
        assertThat(controller.state.value).isNull()
        assertThat(recorder.events).isEmpty()
        controller.startWorkout(store.templates[0])
        assertWithMessage("a fresh workout overwrites the damaged file").that(persistence.loadActiveWorkout()).isNotNull()
    }

    // endregion

    // region A finish whose history write fails

    @Test
    fun testFinishKeepsTheActiveWorkoutFileAndReportsTheErrorWhenTheHistoryCouldNotBeSaved() {
        val persistence = makePersistence()
        val store = makeStore(persistence)
        val clock = SvcClock()
        val controller = WorkoutController(store, persistence, clock = clock.reader)
        val recorder = SvcRecorder()
        controller.addEffect(recorder)
        breakHistoryFile(persistence)

        controller.startWorkout(store.templates[0])
        clock.advance(60.0)
        controller.send(WorkoutAction.LogNextSet)
        clock.advance(60.0)
        controller.send(WorkoutAction.LogNextSet)
        assertThat(doneSets(controller.state.value)).isEqualTo(2)
        assertThat(controller.lastPersistenceError).isNull()
        val previous = controller.state.value!!

        val completed = controller.finish(false)
        assertWithMessage("the user still gets the finished workout (summary screen)").that(completed?.loggedSets).isEqualTo(2)
        assertThat(controller.state.value).isNull()
        assertThat(controller.lastCompleted.value).isEqualTo(completed)
        assertWithMessage("the workout is in memory").that(store.history.firstOrNull()?.id).isEqualTo(previous.id)
        assertThat(recorder.events.last()).isEqualTo(Event.Ended(previous, completed))
        assertWithMessage("the failed save is reported, not swallowed").that(controller.lastPersistenceError).isNotNull()
        assertWithMessage("the store reports it too").that(store.lastPersistenceError).isNotNull()

        // What a relaunch would find on disk.
        assertWithMessage("precondition: nothing could be written to history.json").that(persistence.loadHistory()).isEmpty()
        assertWithMessage("the active-workout file is kept").that(File(persistence.directory, "active-workout.json").isFile).isTrue()
        val kept = persistence.loadActiveWorkout()
        assertWithMessage("the two logged sets are still on disk").that(doneSets(kept)).isEqualTo(2)
        assertThat(kept?.id).isEqualTo(previous.id)
    }

    @Test
    fun testRestoringAndFinishingAgainAfterARelaunchRecordsTheWorkoutOnce() {
        val persistence = makePersistence()
        val clock = SvcClock()
        val blocker = breakHistoryFile(persistence)
        val workoutID = run {
            val store = makeStore(persistence)
            val controller = WorkoutController(store, persistence, clock = clock.reader)
            controller.startWorkout(store.templates[0])
            repeat(3) {                                                                    // two warm-ups and the first 82.5 x 6
                clock.advance(60.0)
                controller.send(WorkoutAction.LogNextSet)
            }
            val id = controller.state.value!!.id
            assertThat(controller.finish(false)).isNotNull()
            assertThat(controller.lastPersistenceError).isNotNull()
            id
        }

        // The relaunch: the disk works again; the unsaved workout comes back with every logged set.
        assertThat(blocker.deleteRecursively()).isTrue()
        val store = StrengthStore(FileStrengthPersistence(persistence.directory))
        assertThat(store.history).isEmpty()
        val controller = WorkoutController(store, FileStrengthPersistence(persistence.directory), clock = clock.reader)
        val recorder = SvcRecorder()
        controller.addEffect(recorder)
        controller.restoreFromDisk()
        assertThat(controller.state.value?.id).isEqualTo(workoutID)
        assertThat(doneSets(controller.state.value)).isEqualTo(3)
        assertThat(recorder.events.firstOrNull()).isInstanceOf(Event.Started::class.java)

        clock.advance(30.0)
        val completed = controller.finish(false)
        assertThat(completed?.id).isEqualTo(workoutID)
        assertThat(controller.lastPersistenceError).isNull()
        assertThat(controller.state.value).isNull()
        assertWithMessage("saved exactly once").that(persistence.loadHistory().map { it.id }).isEqualTo(listOf(workoutID))
        assertThat(store.history.map { it.id }).isEqualTo(listOf(workoutID))
        assertWithMessage("now that the history is safe the active file is removed").that(persistence.loadActiveWorkout()).isNull()
        assertThat(persistence.loadPersonalBests()["bench"]).isNotNull()
    }

    @Test
    fun testRestoringAndFinishingAgainInTheSameProcessAlsoRecordsTheWorkoutOnce() {
        val persistence = makePersistence()
        val store = makeStore(persistence)
        val clock = SvcClock()
        val controller = WorkoutController(store, persistence, clock = clock.reader)
        val blocker = breakHistoryFile(persistence)

        controller.startWorkout(store.templates[0])
        clock.advance(60.0)
        controller.send(WorkoutAction.LogNextSet)
        val id = controller.state.value!!.id
        val first = controller.finish(false)
        assertThat(first).isNotNull()
        assertThat(controller.lastPersistenceError).isNotNull()
        assertThat(store.history.map { it.id }).isEqualTo(listOf(id))                    // in memory already

        assertThat(blocker.deleteRecursively()).isTrue()
        controller.restoreFromDisk()
        assertThat(controller.state.value?.id).isEqualTo(id)
        clock.advance(60.0)
        controller.send(WorkoutAction.LogNextSet)                                          // a set more than the first attempt
        val second = controller.finish(false)
        assertThat(second?.id).isEqualTo(id)
        assertThat(second?.loggedSets).isEqualTo(2)
        assertThat(controller.lastPersistenceError).isNull()
        assertWithMessage("recorded by its id: one entry, the newer copy").that(store.history.map { it.id }).isEqualTo(listOf(id))
        assertThat(store.history.first().loggedSets).isEqualTo(2)
        assertThat(persistence.loadHistory().map { it.id }).isEqualTo(listOf(id))
        assertThat(persistence.loadHistory().first().loggedSets).isEqualTo(2)
        assertThat(persistence.loadActiveWorkout()).isNull()
    }

    @Test
    fun testASaveFailureOfTheActiveWorkoutIsReportedAndTheWorkoutKeepsRunning() {
        val blocker = folder.newFile("PulseStrength-controller-blocker")
        blocker.writeText("file")
        val broken = FileStrengthPersistence(File(blocker, "inner"))
        val store = makeStore(null)
        val controller = WorkoutController(store, broken)
        val recorder = SvcRecorder()
        controller.addEffect(recorder)

        controller.startWorkout(store.templates[0])
        assertThat(controller.lastPersistenceError).isNotNull()
        controller.send(WorkoutAction.LogNextSet)
        assertWithMessage("the in-memory workout is unaffected").that(controller.state.value?.revision).isEqualTo(1)
        assertThat(recorder.changes).hasSize(1)
        assertThat(controller.lastPersistenceError).isNotNull()
    }

    @Test
    fun testThePersistenceErrorIsObservableAndClearsWithTheNextSuccessfulSave() {
        val persistence = makePersistence()
        val store = makeStore(persistence)
        val controller = WorkoutController(store, persistence)
        val seen = mutableListOf<Boolean>()
        assertThat(controller.persistenceError.value).isNull()

        val blocker = breakHistoryFile(persistence)
        controller.startWorkout(store.templates[0])
        controller.send(WorkoutAction.LogNextSet)
        assertWithMessage("saving the running workout works, so nothing is reported").that(controller.persistenceError.value).isNull()

        assertThat(controller.finish(false)).isNotNull()
        seen.add(controller.persistenceError.value != null)
        assertWithMessage("the finished workout could not be written").that(controller.persistenceError.value).isNotNull()
        assertThat(controller.persistenceError.value).isSameInstanceAs(controller.lastPersistenceError)

        assertThat(blocker.deleteRecursively()).isTrue()
        controller.startWorkout(null, "Next")
        seen.add(controller.persistenceError.value != null)
        assertThat(controller.persistenceError.value).isNull()
        assertThat(seen).containsExactly(true, false).inOrder()
    }

    @Test
    fun testALaterSuccessfulSaveClearsTheError() {
        val persistence = makePersistence()
        val store = makeStore(persistence)
        val controller = WorkoutController(store, persistence)
        val blocker = breakHistoryFile(persistence)
        controller.startWorkout(store.templates[0])
        controller.send(WorkoutAction.LogNextSet)
        assertThat(controller.finish(false)).isNotNull()
        assertThat(controller.lastPersistenceError).isNotNull()

        assertThat(blocker.deleteRecursively()).isTrue()
        controller.startWorkout(null, "Next")                                              // replaces the kept file
        assertThat(controller.lastPersistenceError).isNull()
        assertThat(persistence.loadActiveWorkout()?.name).isEqualTo("Next")
    }

    // endregion
}
