package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import org.junit.Test

// The live moments of widgets/SPEC.md section 2: what `SnapshotBuilder.make` adds to the snapshot (set dots, superset, plates, coach tip)
// and the two helpers the app calls (`prMoment`, `finishBrief`).

private fun snapshotAt(state: WorkoutState, seconds: Number = 1): WorkoutSnapshot = SnapshotBuilder.make(state, RedFix.at(seconds))

/** `state` after logging the next [count] sets, one second apart from `t0 + start`. */
private fun logged(state: WorkoutState, count: Int, start: Number = 10): WorkoutState =
    RedFix.reduced(state, List(count) { WorkoutAction.LogNextSet }, start)

// region exerciseDoneSets / exerciseSetCount

class SetDotsTests {
    @Test
    fun testTheDotsCountTheSetsOfTheShownExercise() {
        var state = RedFix.designState()
        assertThat(snapshotAt(state).exerciseDoneSets).isEqualTo(0)
        assertThat(snapshotAt(state).exerciseSetCount).isEqualTo(5)

        state = logged(state, 3)
        assertThat(snapshotAt(state, 20).exerciseDoneSets).isEqualTo(3)
        assertThat(snapshotAt(state, 20).exerciseSetCount).isEqualTo(5)
    }

    @Test
    fun testTheDotsMoveOnWithTheTargetToTheNextExercise() {
        val state = logged(RedFix.designState(), 5)
        val snapshot = snapshotAt(state, 20)
        assertThat(snapshot.exerciseName).isEqualTo("Incline dumbbell press")
        assertThat(snapshot.exerciseDoneSets).isEqualTo(0)
        assertThat(snapshot.exerciseSetCount).isEqualTo(3)
    }

    @Test
    fun testAFinishedWorkoutShowsTheCurrentExercisesDots() {
        val snapshot = snapshotAt(RedFix.allDone(RedFix.designState()))
        assertThat(snapshot.phase).isEqualTo(SnapshotPhase.COMPLETE)
        assertThat(snapshot.exerciseDoneSets).isEqualTo(5)
        assertThat(snapshot.exerciseSetCount).isEqualTo(5)
    }

    @Test
    fun testAWorkoutWithoutExercisesHasNoDots() {
        val snapshot = snapshotAt(WorkoutFactory.makeEmpty("Workout", RedFix.t0))
        assertThat(snapshot.exerciseDoneSets).isNull()
        assertThat(snapshot.exerciseSetCount).isNull()
    }
}

// endregion

// region superset

class SupersetBriefTests {
    /** The design's workout positioned on the lateral raise, the first member of superset A. */
    private fun onTheSuperset(): WorkoutState = RedFix.reduced(RedFix.designState(), WorkoutAction.GoTo(3))

    @Test
    fun testAnExerciseOutsideASupersetHasNone() {
        assertThat(snapshotAt(RedFix.designState()).superset).isNull()
    }

    @Test
    fun testTheMembersAreTaggedInWorkoutOrderWithTheirNextSet() {
        val brief = snapshotAt(onTheSuperset()).superset!!
        assertThat(brief.label).isEqualTo("A")
        assertThat(brief.round).isEqualTo(1)
        assertThat(brief.rounds).isEqualTo(3)
        assertThat(brief.members.map { it.tag }).containsExactly("A1", "A2").inOrder()
        assertThat(brief.members.map { it.name }).containsExactly("Dumbbell lateral raise", "Triceps pushdown").inOrder()
        assertThat(brief.members.map { it.detail }).containsExactly("8 × 15", "30 × 12").inOrder()
        assertThat(brief.members.map { it.isDone }).containsExactly(false, false).inOrder()
        assertThat(brief.members.map { it.isCurrent }).containsExactly(true, false).inOrder()
    }

    @Test
    fun testLoggingTheFirstMemberMakesTheSecondOneCurrentInTheSameRound() {
        val brief = snapshotAt(logged(onTheSuperset(), 1), 20).superset!!
        assertThat(brief.round).isEqualTo(1)
        assertThat(brief.members.map { it.isDone }).containsExactly(true, false).inOrder()
        assertThat(brief.members.map { it.isCurrent }).containsExactly(false, true).inOrder()
    }

    @Test
    fun testTheRoundMovesOnWhenEveryMemberLoggedItsSet() {
        val brief = snapshotAt(logged(onTheSuperset(), 2), 20).superset!!
        assertThat(brief.round).isEqualTo(2)
        assertThat(brief.members.map { it.isDone }).containsExactly(false, false).inOrder()
        assertThat(brief.members.map { it.isCurrent }).containsExactly(true, false).inOrder()
    }

    @Test
    fun testAFinishedMemberShowsItsLastSetAndTheRoundStopsAtTheSetCount() {
        val state = RedFix.reduced(RedFix.allDone(RedFix.designState()), WorkoutAction.GoTo(3))
        val brief = snapshotAt(state).superset!!
        assertThat(brief.round).isEqualTo(3)
        assertThat(brief.rounds).isEqualTo(3)
        assertThat(brief.members.map { it.detail }).containsExactly("8 × 15", "30 × 12").inOrder()
        assertThat(brief.members.map { it.isDone }).containsExactly(true, true).inOrder()
    }

    @Test
    fun testTheDetailFollowsTheNextPendingSetOfEachMember() {
        var state = onTheSuperset()
        state = RedFix.reduced(state, WorkoutAction.SetWeight(RedFix.ex(state, 3), RedFix.setID(state, 3, 1), 9.0))
        state = logged(state, 2)
        val brief = snapshotAt(state, 20).superset!!
        assertThat(brief.members[0].detail).isEqualTo("9 × 15")
    }
}

// endregion

// region plates

class PlatesBriefTests {
    @Test
    fun testTheTargetOfABarbellExerciseGetsItsPlates() {
        val first = snapshotAt(RedFix.designState()).plates!!
        assertThat(first.totalKg).isEqualTo(50.0)
        assertThat(first.barKg).isEqualTo(20.0)
        assertThat(first.perSide).containsExactly(15.0)
        assertThat(first.leftoverKg).isEqualTo(0.0)
        assertThat(first.summary).isEqualTo("15")

        val working = snapshotAt(logged(RedFix.designState(), 2), 20).plates!!
        assertThat(working.totalKg).isEqualTo(82.5)
        assertThat(working.perSide).containsExactly(25.0, 5.0, 1.25).inOrder()
        assertThat(working.summary).isEqualTo("25 + 5 + 1.25")
    }

    @Test
    fun testTheLeftoverIsCarried() {
        val state = RedFix.editSet(RedFix.designState(), 0, 0) { it.copy(weightKg = 21.0) }
        val plates = snapshotAt(state).plates!!
        assertThat(plates.perSide).isEmpty()
        assertThat(plates.leftoverKg).isEqualTo(0.5)
        assertThat(plates.summary).isEqualTo("")
    }

    @Test
    fun testNoPlatesForOtherEquipmentOrTrackingOrAWeightBelowTheBar() {
        val dumbbell = RedFix.reduced(RedFix.designState(), WorkoutAction.GoTo(1))
        assertWithMessage("dumbbell").that(snapshotAt(dumbbell).plates).isNull()

        val pushup = RedFix.state(listOf(RedFix.entry(1, RedFix.pushup, RedFix.normal(3, 0.0, 12), rest = 60)))
        assertWithMessage("body weight").that(snapshotAt(pushup).plates).isNull()

        val light = RedFix.editSet(RedFix.designState(), 0, 0) { it.copy(weightKg = 10.0) }
        assertWithMessage("lighter than the bar").that(snapshotAt(light).plates).isNull()
    }

    @Test
    fun testNoPlatesOnceEverySetIsLogged() {
        assertThat(snapshotAt(RedFix.allDone(RedFix.designState())).plates).isNull()
    }
}

// endregion

// region coach tip

class CoachTipBriefTests {
    /** The bench after its two warm-ups and first working set, the working set recorded with [rir], mid-rest. */
    private fun afterTheFirstWorkingSet(rir: Int?): WorkoutState {
        var state = logged(RedFix.designState(), 3)
        if (rir != null) state = RedFix.reduced(state, WorkoutAction.ToggleLastSetRIR(rir), 14)
        return state
    }

    @Test
    fun testAnEasySetWhileRestingSuggestsOneStepMoreForTheNextSet() {
        val state = afterTheFirstWorkingSet(rir = 3)
        val snapshot = snapshotAt(state, 20)
        assertThat(snapshot.phase).isEqualTo(SnapshotPhase.RESTING)
        val tip = snapshot.coachTip!!
        assertThat(tip.title).isEqualTo("Felt easy?")
        assertThat(tip.subtitle).isEqualTo("3 reps in reserve on set 3")
        assertThat(tip.text).isEqualTo("Add 2.5 kg for set 4 to stay at 1–2 RIR.")
        assertThat(tip.suggestedWeightKg).isEqualTo(85.0)
        assertThat(tip.suggestedWeightText).isEqualTo("85 kg")
        assertThat(tip.keepWeightText).isEqualTo("Keep 82.5")
        assertThat(tip.targetSetID).isEqualTo(state.exercises[0].sets[3].id.toString())
        assertThat(tip.targetExerciseID).isEqualTo(state.exercises[0].id.toString())
    }

    @Test
    fun testFourOrMoreRepsInReserveCountToo() {
        assertThat(snapshotAt(afterTheFirstWorkingSet(rir = 4), 20).coachTip).isNotNull()
    }

    @Test
    fun testTwoRepsInReserveOrNoneRecordedGiveNoTip() {
        assertThat(snapshotAt(afterTheFirstWorkingSet(rir = 2), 20).coachTip).isNull()
        assertThat(snapshotAt(afterTheFirstWorkingSet(rir = null), 20).coachTip).isNull()
    }

    @Test
    fun testAWarmUpSetGivesNoTip() {
        var state = logged(RedFix.designState(), 1)
        state = RedFix.reduced(state, WorkoutAction.ToggleLastSetRIR(4), 14)
        val snapshot = snapshotAt(state, 20)
        assertThat(snapshot.phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(snapshot.coachTip).isNull()
    }

    @Test
    fun testNoTipOutsideTheRestingPhase() {
        val state = afterTheFirstWorkingSet(rir = 3)
        val over = SnapshotBuilder.make(state, state.rest!!.endsAt.plusSeconds(1))
        assertThat(over.phase).isEqualTo(SnapshotPhase.REST_OVER)
        assertThat(over.coachTip).isNull()

        val skipped = snapshotAt(RedFix.reduced(state, WorkoutAction.SkipRest, 21), 22)
        assertThat(skipped.phase).isEqualTo(SnapshotPhase.LOGGING)
        assertThat(skipped.coachTip).isNull()
    }

    @Test
    fun testNoTipWithoutAPendingSetOfTheSameExercise() {
        var state = RedFix.withDone(RedFix.designState(), 0, 0..3)
        state = RedFix.reduced(state, RedFix.log(state, 0, 4), 10)
        state = RedFix.reduced(state, WorkoutAction.ToggleLastSetRIR(4), 11)
        assertThat(snapshotAt(state, 12).phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(snapshotAt(state, 12).coachTip).isNull()
    }

    @Test
    fun testNoTipForAnExerciseWithoutAWeight() {
        var state = RedFix.state(listOf(RedFix.entry(1, RedFix.pushup, RedFix.normal(3, 0.0, 12), rest = 60)))
        state = RedFix.reduced(state, WorkoutAction.LogNextSet, 10)
        state = RedFix.reduced(state, WorkoutAction.ToggleLastSetRIR(4), 11)
        assertThat(snapshotAt(state, 12).coachTip).isNull()
    }

    @Test
    fun testTheStepIsTheExercisesOwn() {
        var state = RedFix.state(listOf(RedFix.entry(1, RedFix.incline, RedFix.normal(3, 24.0, 10), rest = 90)))
        state = RedFix.reduced(state, WorkoutAction.LogNextSet, 10)
        state = RedFix.reduced(state, WorkoutAction.ToggleLastSetRIR(3), 11)
        val tip = snapshotAt(state, 12).coachTip!!
        assertThat(tip.suggestedWeightKg).isEqualTo(26.0)
        assertThat(tip.suggestedWeightText).isEqualTo("26 kg")
        assertThat(tip.keepWeightText).isEqualTo("Keep 24")
        assertThat(tip.subtitle).isEqualTo("3 reps in reserve on set 1")
    }
}

// endregion

// region prMoment

class PRMomentTests {
    /** The design's bench: previous best 99 kg; 82.5 x 6 estimates 99.0 and 85 x 6 estimates 102. */
    private fun beforeTheLastBenchSet(): WorkoutState = logged(RedFix.designState(), 4)

    @Test
    fun testALoggedRecordSetGivesAMomentThatExpiresAfterFourSeconds() {
        val old = beforeTheLastBenchSet()
        val new = RedFix.reduced(old, WorkoutAction.LogNextSet, 20)
        val now = RedFix.at(20)
        val moment = SnapshotBuilder.prMoment(old, new, now)!!
        assertThat(moment.exerciseName).isEqualTo("Barbell bench press")
        assertThat(moment.weightText).isEqualTo("85")
        assertThat(moment.repsText).isEqualTo("6")
        assertThat(moment.estimated1RM).isEqualTo(102)
        assertThat(moment.deltaKg).isEqualTo(3)
        assertThat(moment.expiresAt).isEqualTo(now.plusSeconds(4))
        assertThat(SnapshotBuilder.momentLifetime).isEqualTo(4.0)
    }

    @Test
    fun testTheLifetimeCanBeChosen() {
        val old = beforeTheLastBenchSet()
        val new = RedFix.reduced(old, WorkoutAction.LogNextSet, 20)
        assertThat(SnapshotBuilder.prMoment(old, new, RedFix.at(20), lifetime = 10.0)!!.expiresAt).isEqualTo(RedFix.at(30))
    }

    @Test
    fun testASetThatDoesNotBeatTheBestByMoreThanTheMarginIsNoMoment() {
        // 82.5 x 6 estimates exactly the previous best of 99.
        val old = logged(RedFix.designState(), 2)
        val new = RedFix.reduced(old, WorkoutAction.LogNextSet, 20)
        assertThat(SnapshotBuilder.prMoment(old, new, RedFix.at(20))).isNull()
    }

    @Test
    fun testAWarmUpIsNeverARecord() {
        val heavyWarmUp = RedFix.editSet(RedFix.designState(), 0, 0) { it.copy(weightKg = 100.0, reps = 10) }
        val new = RedFix.reduced(heavyWarmUp, WorkoutAction.LogNextSet, 20)
        assertThat(SnapshotBuilder.prMoment(heavyWarmUp, new, RedFix.at(20))).isNull()
    }

    @Test
    fun testNothingIsLoggedByAChangeThatLogsNoSet() {
        val old = beforeTheLastBenchSet()
        assertThat(SnapshotBuilder.prMoment(old, old, RedFix.at(20))).isNull()
        val edited = RedFix.reduced(old, WorkoutAction.SetWeight(RedFix.ex(old, 0), RedFix.setID(old, 0, 4), 90.0), 20)
        assertThat(SnapshotBuilder.prMoment(old, edited, RedFix.at(20))).isNull()
    }

    @Test
    fun testARecordThatWasAlreadyLoggedIsNotAMomentAgain() {
        val old = beforeTheLastBenchSet()
        val recordLogged = RedFix.reduced(old, WorkoutAction.LogNextSet, 20)
        val later = RedFix.reduced(recordLogged, WorkoutAction.SetRIR(RedFix.ex(old, 0), RedFix.setID(old, 0, 4), 1), 21)
        assertThat(SnapshotBuilder.prMoment(recordLogged, later, RedFix.at(21))).isNull()
    }

    @Test
    fun testNoMomentWithoutAPreviousBest() {
        val noHistory = RedFix.exercise("bench2", "Bench", MuscleGroup.CHEST, Equipment.BARBELL, best = 0.0, kg = 60.0, reps = 8, rest = 90)
        val old = RedFix.state(listOf(RedFix.entry(1, noHistory, RedFix.normal(2, 60.0, 8), rest = 90)))
        val new = RedFix.reduced(old, WorkoutAction.LogNextSet, 20)
        assertThat(SnapshotBuilder.prMoment(old, new, RedFix.at(20))).isNull()
    }

    @Test
    fun testAnExerciseWithoutAWeightIsNeverARecord() {
        val pushup = RedFix.exercise(
            "pushup2", "Push-up", MuscleGroup.CHEST, Equipment.BODYWEIGHT, tracking = TrackingKind.REPS_ONLY, best = 10.0, kg = 0.0, reps = 12, rest = 60,
        )
        val old = RedFix.state(listOf(RedFix.entry(1, pushup, RedFix.normal(2, 0.0, 30), rest = 60)))
        val new = RedFix.reduced(old, WorkoutAction.LogNextSet, 20)
        assertThat(SnapshotBuilder.prMoment(old, new, RedFix.at(20))).isNull()
    }

    @Test
    fun testTheDeltaIsMeasuredAgainstTheBestBeforeTheSet() {
        // The first working set beats 99 (90 x 6 = 108); the second beats that one (95 x 6 = 114).
        var start = RedFix.designState()
        start = RedFix.editSet(start, 0, 2) { it.copy(weightKg = 90.0) }
        start = RedFix.editSet(start, 0, 3) { it.copy(weightKg = 95.0) }
        val afterWarmUps = logged(start, 2)
        val first = RedFix.reduced(afterWarmUps, WorkoutAction.LogNextSet, 20)
        val firstMoment = SnapshotBuilder.prMoment(afterWarmUps, first, RedFix.at(20))!!
        assertThat(firstMoment.estimated1RM).isEqualTo(108)
        assertThat(firstMoment.deltaKg).isEqualTo(9)
        val second = RedFix.reduced(first, WorkoutAction.LogNextSet, 30)
        val secondMoment = SnapshotBuilder.prMoment(first, second, RedFix.at(30))!!
        assertThat(secondMoment.estimated1RM).isEqualTo(114)
        assertThat(secondMoment.deltaKg).isEqualTo(6)
    }

    @Test
    fun testTheMomentFollowsAToggleThatLogsTheSet() {
        val old = beforeTheLastBenchSet()
        val new = RedFix.reduced(old, RedFix.toggle(old, 0, 4), 20)
        assertThat(SnapshotBuilder.prMoment(old, new, RedFix.at(20))?.estimated1RM).isEqualTo(102)
    }
}

// endregion

// region finishBrief

class FinishBriefTests {
    private fun completed(durationSeconds: Int, volumeKg: Double, records: Int = 0, sets: Int = 12): CompletedWorkout {
        val record = PersonalRecord("bench", "Barbell bench press", 85.0, 6, 102.0, 99.0)
        return CompletedWorkout(
            id = RedFix.uuid(9, 9), name = "Upper A · Push", templateID = null, startedAt = RedFix.t0, finishedAt = RedFix.at(durationSeconds),
            durationSeconds = durationSeconds, volumeKg = volumeKg, loggedSets = sets, averageHeartRate = null, averageRIR = null,
            exercises = emptyList(), personalRecords = List(records) { record }, muscleSets = emptyList(),
        )
    }

    @Test
    fun testTheBriefCarriesTheNumbersOfTheWorkout() {
        val brief = SnapshotBuilder.finishBrief(completed(3_090, 9_144.0, records = 2, sets = 18), savedToHealth = true)
        assertThat(brief.workoutName).isEqualTo("Upper A · Push")
        assertThat(brief.durationMinutes).isEqualTo(52)
        assertThat(brief.sets).isEqualTo(18)
        assertThat(brief.volumeText).isEqualTo("9.1")
        assertThat(brief.personalRecordCount).isEqualTo(2)
        assertThat(brief.savedToHealth).isTrue()
        assertThat(SnapshotBuilder.finishBrief(completed(60, 0.0), savedToHealth = false).savedToHealth).isFalse()
    }

    @Test
    fun testMinutesRoundHalfUp() {
        assertThat(SnapshotBuilder.finishBrief(completed(29, 0.0), false).durationMinutes).isEqualTo(0)
        assertThat(SnapshotBuilder.finishBrief(completed(30, 0.0), false).durationMinutes).isEqualTo(1)
        assertThat(SnapshotBuilder.finishBrief(completed(3_029, 0.0), false).durationMinutes).isEqualTo(50)
        assertThat(SnapshotBuilder.finishBrief(completed(3_030, 0.0), false).durationMinutes).isEqualTo(51)
    }

    @Test
    fun testVolumeIsTonnesWithOneDecimalAndNoTrailingZero() {
        assertThat(SnapshotBuilder.finishBrief(completed(60, 9_000.0), false).volumeText).isEqualTo("9")
        assertThat(SnapshotBuilder.finishBrief(completed(60, 9_049.0), false).volumeText).isEqualTo("9")
        assertThat(SnapshotBuilder.finishBrief(completed(60, 9_050.0), false).volumeText).isEqualTo("9.1")
        assertThat(SnapshotBuilder.finishBrief(completed(60, 12_345.0), false).volumeText).isEqualTo("12.3")
        assertThat(SnapshotBuilder.finishBrief(completed(60, 40.0), false).volumeText).isEqualTo("0")
    }
}

// endregion
