package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.EngineBasicsTests.SvcRecorder.Event
import health.pulse.strength.core.EngineBasicsTests.SvcRig
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

// Port of IntegrationTests.swift. End-to-end checks across the areas (library, sample data, factory, reducer, presenter, snapshot,
// summary, engine). Every expected number below is derived by hand from the design and ARCHITECTURE.md section 3, not read back
// from the code under test.
//
// "Upper A · Push": bench W 50x8, W 70x5, 82.5x6, 82.5x6, 85x6 (rest 150); incline 3x28x10 (90); ohp 3x45x8 (120);
// lateral 3x8x15 and pushdown 3x30x12 (60, superset A); crossover 3x15x12 (60). 20 sets. Bench best estimated 1RM before: 99 kg.
//
// Adapted (the Kotlin port has no sync protocol):
//   testTheLiveActivityButtonsActOnTheSnapshotTarget: the notification buttons call `send(action, LIVE_ACTIVITY)` instead of
//     `receive(RemoteCommand)`; there is no command de-duplication, the repeated LogSet is a no-op of the reducer (idempotent).
//   testThePhoneAndTheWatchAgreeOverTheWire -> testAStateAndItsActionsSurviveTheJsonWire: the "wire" is the kotlinx.serialization
//     JSON (there is no SyncCodec / mirror); the state, the snapshot, the presentation and a Watch-style action round trip.

class IntegrationFlowTests {
    @get:Rule
    val folder = TemporaryFolder()

    private fun index(state: WorkoutState, exerciseID: String): Int = state.exercises.indexOfFirst { it.exercise.id == exerciseID }

    // region Opening state

    @Test
    fun testTheOpeningStateOfTheDesignWorkout() {
        val rig = SvcRig(folder)
        val state = rig.startUpperA()
        val presentation = requireNotNull(rig.engine.presentation(rig.clock.now))

        assertThat(state.exercises.map { it.exercise.id }).isEqualTo(listOf("bench", "incline", "ohp", "lateral", "pushdown", "crossover"))
        assertThat(state.exercises.map { it.supersetGroup }).isEqualTo(listOf(null, null, null, "A", "A", null))
        assertThat(state.exercises.map { it.restSeconds }).isEqualTo(listOf(150, 90, 120, 60, 60, 60))
        assertThat(state.exercises.map { it.sets.size }).isEqualTo(listOf(5, 3, 3, 3, 3, 3))
        assertThat(state.templateBaseline).hasSize(6)
        assertThat(state.currentIndex).isEqualTo(0)
        assertThat(state.revision).isEqualTo(0)

        assertThat(presentation.totals.totalSets).isEqualTo(20)
        assertThat(presentation.totals.loggedSets).isEqualTo(0)
        assertThat(presentation.header.title).isEqualTo("Upper A · Push")
        assertThat(presentation.header.clockText).isEqualTo("0:00")
        assertThat(presentation.header.setsText).isEqualTo("0 of 20")
        assertThat(presentation.header.volumeText).isEqualTo("0")
        assertThat(presentation.header.heartRateText).isEqualTo("–")
        assertThat(presentation.header.segments).hasSize(6)
        assertThat(presentation.navigator?.position).isEqualTo(1)
        assertThat(presentation.navigator?.total).isEqualTo(6)
        assertThat(presentation.dock).isNull()
        assertThat(presentation.undoText).isNull()

        val card = requireNotNull(presentation.card)
        assertThat(card.exercise.id).isEqualTo("bench")
        assertThat(card.recoveryPercent).isEqualTo(88)
        assertThat(card.recoveryLevel).isEqualTo(ActiveWorkoutPresentation.RecoveryLevel.GOOD)
        assertThat(card.restText).isEqualTo("2:30")
        assertThat(card.weightColumnTitle).isEqualTo("kg")
        assertThat(card.repsColumnTitle).isEqualTo("Reps")
        assertThat(card.supersetLabel).isNull()
        assertThat(card.rows.map { it.number }).isEqualTo(listOf("W", "W", "1", "2", "3"))
        assertThat(card.rows.map { it.weightText }).isEqualTo(listOf("50", "70", "82.5", "82.5", "85"))
        assertThat(card.rows.map { it.repsText }).isEqualTo(listOf("8", "5", "6", "6", "6"))
        // The last session of the demo history (5 days ago).
        assertThat(card.rows.map { it.previousText }).isEqualTo(listOf("50 × 8", "70 × 5", "80 × 6", "80 × 6", "80 × 5"))
        assertThat(card.rows.map { it.isNext }).isEqualTo(listOf(true, false, false, false, false))
        assertThat(card.rows.count { it.isPersonalRecord }).isEqualTo(0)
        assertThat(card.coachTip).isEqualTo("85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg.")

        assertThat(presentation.finishCheck.canFinish).isFalse()
        assertThat(presentation.finishCheck.title).isEqualTo("Nothing logged yet")
        assertThat(presentation.finishCheck.asksToUpdateTemplate).isFalse()
        assertThat(rig.engine.templateDiff().isEmpty).isTrue()

        val snapshot = requireNotNull(rig.engine.snapshot(rig.clock.now))
        assertThat(snapshot.phase).isEqualTo(SnapshotPhase.LOGGING)
        assertThat(snapshot.setLabel).isEqualTo("Warm-up · Set 1 of 5")
        assertThat(snapshot.weightText).isEqualTo("50")
        assertThat(snapshot.repsText).isEqualTo("8")
        assertThat(snapshot.repsUnit).isEqualTo("reps")
        assertThat(snapshot.showsWeight).isTrue()
        assertThat(snapshot.exerciseIndex).isEqualTo(0)
        assertThat(snapshot.exerciseCount).isEqualTo(6)
        assertThat(snapshot.targetExerciseID).isEqualTo(state.exercises[0].id)
        assertThat(snapshot.targetSetID).isEqualTo(state.exercises[0].sets[0].id)
        assertThat(snapshot.nextExerciseName).isEqualTo("Incline dumbbell press")
        assertThat(snapshot.loggedSets).isEqualTo(0)
        assertThat(snapshot.totalSets).isEqualTo(20)
        assertThat(snapshot.restEndsAt).isNull()
    }

    // endregion

    // region Logging, rest, personal record

    @Test
    fun testLoggingTheBenchSetsFollowsTheDesign() {
        val rig = SvcRig(folder)
        rig.startUpperA()

        // Warm-ups rest max(30, round(150 * 0.4 / 5) * 5) = 60 s, a working set rests the exercise's 150 s.
        rig.logSets(1)
        assertThat(rig.engine.state?.rest?.totalSeconds).isEqualTo(60)
        rig.logSets(1)
        assertThat(rig.engine.state?.rest?.totalSeconds).isEqualTo(60)
        rig.logSets(1)
        val afterThird = requireNotNull(rig.engine.state)
        assertThat(afterThird.rest?.totalSeconds).isEqualTo(150)
        assertThat(afterThird.rest?.endsAt).isEqualTo(rig.clock.now.addingTimeInterval(150.0))
        assertThat(afterThird.revision).isEqualTo(3)

        val presentation = requireNotNull(rig.engine.presentation(rig.clock.now))
        assertThat(presentation.totals.loggedSets).isEqualTo(3)
        assertThat(presentation.header.setsText).isEqualTo("3 of 20")
        assertThat(presentation.header.volumeText).isEqualTo("495")            // 82.5 x 6; warm-ups excluded
        assertThat(presentation.header.clockText).isEqualTo("3:00")
        val card = requireNotNull(presentation.card)
        assertThat(card.rows.map { it.isDone }).isEqualTo(listOf(true, true, true, false, false))
        assertThat(card.rows.map { it.isNext }).isEqualTo(listOf(false, false, false, true, false))
        assertWithMessage("no tip while a rest timer runs").that(card.coachTip).isNull()
        assertWithMessage("82.5 x 6 is 99.0, not above 99 + 0.05").that(card.rows[2].isPersonalRecord).isFalse()
        assertThat(card.rows[2].accessibilityLabel).isEqualTo("Set 3, working set, 82.5 kilograms, 6 reps, logged")

        val dock = requireNotNull(presentation.dock)
        assertThat(dock.phase).isEqualTo(ActiveWorkoutPresentation.DockPhase.RUNNING)
        assertThat(dock.totalSeconds).isEqualTo(150)
        assertThat(dock.remainingSeconds).isEqualTo(150)
        assertThat(dock.remainingText).isEqualTo("2:30")
        assertThat(dock.nextSetText).isEqualTo("Next · Set 2 · 82.5 kg × 6")
        assertThat(dock.showsRIR).isTrue()

        val snapshot = requireNotNull(rig.engine.snapshot(rig.clock.now))
        assertThat(snapshot.phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(snapshot.setLabel).isEqualTo("Set 4 of 5")
        assertThat(snapshot.nextSetText).isEqualTo("Set 4 · 82.5 kg × 6")
        assertThat(snapshot.restEndsAt).isEqualTo(rig.clock.now.addingTimeInterval(150.0))
        assertThat(snapshot.restStartedAt).isEqualTo(rig.clock.now)
        assertThat(snapshot.restTotalSeconds).isEqualTo(150)

        // 40 s later the dock counts down; 150 s later it is over.
        val later = rig.clock.now.addingTimeInterval(40.0)
        assertThat(rig.engine.presentation(later)?.dock?.remainingSeconds).isEqualTo(110)
        assertThat(rig.engine.snapshot(later)?.phase).isEqualTo(SnapshotPhase.RESTING)
        val over = rig.clock.now.addingTimeInterval(151.0)
        assertThat(rig.engine.presentation(over)?.dock?.phase).isEqualTo(ActiveWorkoutPresentation.DockPhase.FINISHED)
        assertThat(rig.engine.presentation(over)?.dock?.remainingText).isEqualTo("Go")
        assertThat(rig.engine.snapshot(over)?.phase).isEqualTo(SnapshotPhase.REST_OVER)
    }

    @Test
    fun testTheHeaviestBenchSetIsThePersonalRecord() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.logSets(5)

        val presentation = requireNotNull(rig.engine.presentation(rig.clock.now))
        val rows = requireNotNull(presentation.card).rows
        assertThat(rows.map { it.isPersonalRecord }).isEqualTo(listOf(false, false, false, false, true))
        assertThat(rows[4].estimated1RM).isEqualTo(102)                        // 85 x (1 + 6/30)
        assertThat(presentation.header.volumeText).isEqualTo("1,500")          // 495 + 495 + 510
        assertThat(presentation.totals.completedExercises).isEqualTo(1)

        // The bench is complete: the current exercise stays, the next target is the incline press.
        assertThat(rig.engine.state?.currentIndex).isEqualTo(0)
        val snapshot = requireNotNull(rig.engine.snapshot(rig.clock.now))
        assertThat(snapshot.exerciseName).isEqualTo("Incline dumbbell press")
        assertThat(snapshot.setLabel).isEqualTo("Set 1 of 3")
        assertThat(snapshot.weightText).isEqualTo("28")
        assertThat(snapshot.nextExerciseName).isEqualTo("Overhead press")
    }

    // endregion

    // region Superset

    @Test
    fun testTheSupersetAlternatesAndRestsAfterTheLastMember() {
        val rig = SvcRig(folder)
        val started = rig.startUpperA()
        val lateral = index(started, "lateral")
        val pushdown = index(started, "pushdown")
        assertThat(listOf(lateral, pushdown)).isEqualTo(listOf(3, 4))

        rig.logSets(5 + 3 + 3)                                           // bench, incline, ohp
        assertThat(rig.engine.state?.rest?.totalSeconds).isEqualTo(120)

        rig.logSets(1)                                                   // lateral set 1
        var state = requireNotNull(rig.engine.state)
        assertThat(state.exercises[lateral].sets[0].isDone).isTrue()
        assertWithMessage("moves on to the partner").that(state.currentIndex).isEqualTo(pushdown)
        assertWithMessage("no rest between the members").that(state.rest).isNull()
        var snapshot = requireNotNull(rig.engine.snapshot(rig.clock.now))
        assertThat(snapshot.phase).isEqualTo(SnapshotPhase.LOGGING)
        assertThat(snapshot.targetExerciseID).isEqualTo(state.exercises[pushdown].id)
        assertThat(snapshot.setLabel).isEqualTo("Set 1 of 3")
        assertThat(snapshot.weightText).isEqualTo("30")
        assertThat(snapshot.repsText).isEqualTo("12")

        rig.logSets(1)                                                   // pushdown set 1
        state = requireNotNull(rig.engine.state)
        assertWithMessage("back to the first member").that(state.currentIndex).isEqualTo(lateral)
        assertThat(state.rest?.totalSeconds).isEqualTo(60)
        snapshot = requireNotNull(rig.engine.snapshot(rig.clock.now))
        assertThat(snapshot.phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(snapshot.targetExerciseID).isEqualTo(state.exercises[lateral].id)
        assertThat(snapshot.setLabel).isEqualTo("Set 2 of 3")
        assertThat(rig.engine.presentation(rig.clock.now)?.card?.supersetLabel).isEqualTo("Superset A")
    }

    // endregion

    // region Finishing

    @Test
    fun testTheWholeWorkoutEndToEnd() {
        val rig = SvcRig(folder)
        val started = rig.startUpperA()
        val templateID = started.templateID
        val historyBefore = rig.model.data.history.size
        assertThat(historyBefore).isEqualTo(5)
        // The demo record is 85 kg x 5 from 10 days ago: 85 x (1 + 5/30) = 99.17 kg (the design shows it rounded, "99").
        val demoBest = 85.0 * (1 + 5.0 / 30)
        assertThat(rig.model.data.personalBests["bench"]?.estimated1RM ?: 0.0).isWithin(0.0001).of(demoBest)

        rig.logSets(20)
        val presentation = requireNotNull(rig.engine.presentation(rig.clock.now))
        assertThat(presentation.totals.loggedSets).isEqualTo(20)
        assertThat(presentation.totals.completedExercises).isEqualTo(6)
        assertThat(presentation.header.setsText).isEqualTo("20 of 20")
        // 1,500 bench + 840 incline + 1,080 ohp + 360 lateral + 1,080 pushdown + 540 crossover.
        assertThat(presentation.header.volumeText).isEqualTo("5,400")
        assertThat(presentation.finishCheck.canFinish).isTrue()
        assertThat(presentation.finishCheck.title).isEqualTo("Finish workout?")
        assertThat(presentation.finishCheck.message).isEqualTo("All sets are logged. Nice work.")
        assertThat(rig.engine.snapshot(rig.clock.now)?.phase).isEqualTo(SnapshotPhase.COMPLETE)
        assertThat(rig.engine.snapshot(rig.clock.now)?.setLabel).isEqualTo("All sets logged")
        assertThat(rig.engine.snapshot(rig.clock.now)?.targetSetID).isNull()

        rig.clock.advance(120.0)
        val completed = requireNotNull(rig.engine.finish(false))
        assertThat(completed.loggedSets).isEqualTo(20)
        assertThat(completed.volumeKg).isWithin(0.0001).of(5_400.0)
        assertThat(completed.durationSeconds).isEqualTo(20 * 60 + 120)
        assertThat(completed.exercises).hasSize(6)
        assertThat(completed.exercises.map { it.sets.size }).isEqualTo(listOf(5, 3, 3, 3, 3, 3))
        val bench = requireNotNull(completed.personalRecords.firstOrNull { it.exerciseID == "bench" })
        assertThat(bench.estimated1RM).isWithin(0.0001).of(102.0)
        assertThat(bench.weightKg).isEqualTo(85.0)
        assertThat(bench.reps).isEqualTo(6)
        assertThat(bench.previousBest).isWithin(0.0001).of(demoBest)
        assertThat(completed.exercises.filter { it.isPersonalRecord }.map { it.exerciseID }).isEqualTo(listOf("bench"))
        assertThat(completed.muscleSets.firstOrNull()?.muscle).isEqualTo(MuscleGroup.CHEST)

        // Everything recorded: history (newest first), personal best, template, nothing left active.
        assertThat(rig.model.data.history).hasSize(historyBefore + 1)
        assertThat(rig.model.data.history.first()).isEqualTo(completed)
        val best = requireNotNull(rig.model.data.personalBests["bench"])
        assertThat(best.estimated1RM).isWithin(0.0001).of(102.0)
        assertThat(best.weightKg).isEqualTo(85.0)
        assertThat(best.reps).isEqualTo(6)
        assertThat(rig.model.data.templates.firstOrNull { it.id == templateID }?.lastPerformed).isEqualTo(completed.finishedAt)
        assertThat(rig.engine.state).isNull()
        assertThat(rig.diskState).isNull()
        assertThat(rig.persistence.loadHistory().first()).isEqualTo(completed)
        assertThat(rig.persistence.loadPersonalBests()["bench"]?.estimated1RM ?: 0.0).isWithin(0.0001).of(102.0)

        // The next session starts from the new results: bench best 102, last sets = today's, no PR for the same 85 x 6.
        rig.clock.advance(3_600.0)
        assertThat(rig.engine.start(rig.upperA)).isTrue()
        val next = requireNotNull(rig.engine.state)
        assertThat(next.exercises[0].exercise.previousBestE1RM).isWithin(0.0001).of(102.0)
        assertThat(next.exercises[0].exercise.previousSets.map { it.weightKg }).isEqualTo(listOf(50.0, 70.0, 82.5, 82.5, 85.0))
        assertThat(next.exercises[0].exercise.previousSets.map { it.reps }).isEqualTo(listOf(8, 5, 6, 6, 6))
        rig.logSets(5)
        val rows = requireNotNull(rig.engine.presentation(rig.clock.now)?.card).rows
        assertThat(rows.map { it.isPersonalRecord }).isEqualTo(listOf(false, false, false, false, false))
        assertThat(rows.map { it.previousText }).isEqualTo(listOf("50 × 8", "70 × 5", "82.5 × 6", "82.5 × 6", "85 × 6"))
    }

    @Test
    fun testFinishingAnEditedWorkoutOffersAndAppliesTheTemplateUpdate() {
        val rig = SvcRig(folder)
        val started = rig.startUpperA()
        rig.logSets(5)
        val crossover = started.exercises[5].id
        rig.engine.send(WorkoutAction.RemoveExercise(crossover))
        rig.engine.send(WorkoutAction.AddExercises(listOf(ExerciseLibrary.exercise("pushup")!!)))

        val check = requireNotNull(rig.engine.presentation(rig.clock.now)).finishCheck
        assertThat(check.templateDiff).isEqualTo(TemplateDiff(added = 1, removed = 1, reordered = false))
        assertThat(check.diffMessage).isEqualTo("Changes: 1 added, 1 removed.")
        assertThat(check.asksToUpdateTemplate).isTrue()
        assertWithMessage("incline, ohp, lateral, pushdown and the push-up (3 sets each) are pending").that(check.unloggedSets).isEqualTo(15)

        val completed = requireNotNull(rig.engine.finish(true))
        assertThat(completed.loggedSets).isEqualTo(5)
        val template = requireNotNull(rig.model.data.templates.firstOrNull { it.id == started.templateID })
        assertThat(template.entries.map { it.exercise.id }).isEqualTo(listOf("bench", "incline", "ohp", "lateral", "pushdown", "pushup"))
        assertThat(template.lastPerformed).isEqualTo(completed.finishedAt)
        assertThat(template.entries[0].plannedSets.map { it.type })
            .isEqualTo(listOf(SetType.WARMUP, SetType.WARMUP, SetType.NORMAL, SetType.NORMAL, SetType.NORMAL))
    }

    // endregion

    // region Other surfaces (notification actions, wire format)

    @Test
    fun testTheLiveActivityButtonsActOnTheSnapshotTarget() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.logSets(2)                                                   // both warm-ups; the 82.5 kg set is next

        // "+" on the weight: nudge by one step of the barbell (2.5 kg).
        rig.engine.send(WorkoutAction.NudgeNextSet(weightSteps = 1, repsSteps = 0), ActionOrigin.LIVE_ACTIVITY)
        var snapshot = requireNotNull(rig.engine.snapshot(rig.clock.now))
        assertThat(snapshot.weightText).isEqualTo("85")
        assertThat(snapshot.repsText).isEqualTo("6")
        assertThat(rig.engine.state?.exercises?.get(0)?.sets?.get(2)?.weightKg).isEqualTo(85.0)

        // "Log set" logs exactly the set the snapshot named, once, even when the system delivers the action twice.
        val exerciseID = requireNotNull(snapshot.targetExerciseID)
        val setID = requireNotNull(snapshot.targetSetID)
        val log = WorkoutAction.LogSet(exerciseID, setID)
        rig.engine.send(log, ActionOrigin.LIVE_ACTIVITY)
        rig.engine.send(log, ActionOrigin.LIVE_ACTIVITY)
        assertThat(rig.engine.state?.exercises?.get(0)?.sets?.get(2)?.isDone).isEqualTo(true)
        assertThat(rig.engine.state?.exercises?.get(0)?.sets?.count { it.isDone }).isEqualTo(3)
        assertWithMessage("two warm-ups, the nudge, the log; the duplicate is a no-op").that(rig.recorder.changes).hasSize(2 + 1 + 1)
        val last = rig.recorder.changes.last()
        assertWithMessage("the log command was not reported").that(last).isInstanceOf(Event.Changed::class.java)
        last as Event.Changed
        assertThat(last.action).isEqualTo(WorkoutAction.LogSet(exerciseID, setID))
        assertThat(last.origin).isEqualTo(ActionOrigin.LIVE_ACTIVITY)

        // Rest buttons: +15 s then Skip.
        snapshot = requireNotNull(rig.engine.snapshot(rig.clock.now))
        assertThat(snapshot.phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(snapshot.restTotalSeconds).isEqualTo(150)
        rig.engine.send(WorkoutAction.AdjustRest(15), ActionOrigin.LIVE_ACTIVITY)
        snapshot = requireNotNull(rig.engine.snapshot(rig.clock.now))
        assertThat(snapshot.restTotalSeconds).isEqualTo(165)
        assertThat(snapshot.restEndsAt).isEqualTo(rig.clock.now.addingTimeInterval(165.0))
        rig.engine.send(WorkoutAction.SkipRest, ActionOrigin.LIVE_ACTIVITY)
        assertThat(rig.engine.snapshot(rig.clock.now)?.phase).isEqualTo(SnapshotPhase.LOGGING)
    }

    @Test
    fun testAStateAndItsActionsSurviveTheJsonWire() {
        val rig = SvcRig(folder)
        rig.startUpperA()
        rig.logSets(3)
        rig.engine.send(WorkoutAction.UpdateHeartRate(131), ActionOrigin.WATCH)

        // State -> wire -> state: what is shown does not change.
        val json = StrengthJson.format.encodeToString(WorkoutState.serializer(), rig.engine.state!!)
        val received = StrengthJson.format.decodeFromString(WorkoutState.serializer(), json)
        assertThat(received).isEqualTo(rig.engine.state)
        val now = rig.clock.now
        assertThat(SnapshotBuilder.make(received, now)).isEqualTo(rig.engine.snapshot(now))
        assertThat(WorkoutPresenter.present(received, now, rig.engine.recovery)).isEqualTo(rig.engine.presentation(now))

        // The snapshot itself survives the wire.
        val snapshot = requireNotNull(rig.engine.snapshot(now))
        val snapshotJson = StrengthJson.format.encodeToString(WorkoutSnapshot.serializer(), snapshot)
        assertThat(StrengthJson.format.decodeFromString(WorkoutSnapshot.serializer(), snapshotJson)).isEqualTo(snapshot)

        // Watch-style action -> wire -> engine: "Log set" from the snapshot's target.
        val action = WorkoutAction.LogSet(requireNotNull(snapshot.targetExerciseID), requireNotNull(snapshot.targetSetID))
        val actionJson = StrengthJson.format.encodeToString(WorkoutAction.serializer(), action)
        val arrived = StrengthJson.format.decodeFromString(WorkoutAction.serializer(), actionJson)
        assertThat(arrived).isEqualTo(action)
        rig.engine.send(arrived, ActionOrigin.WATCH)
        assertThat(rig.engine.state?.exercises?.get(0)?.sets?.get(3)?.isDone).isEqualTo(true)

        // The workout ends: nothing is left to show.
        rig.engine.discard()
        assertThat(rig.engine.state).isNull()
        assertThat(rig.engine.presentation(now)).isNull()
    }

    // endregion
}
