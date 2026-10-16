package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import org.junit.Test

// Port of SnapshotTests.swift (Swift: 29 tests in 2 classes).

class SnapshotBuilderTests {
    private fun snapshot(state: WorkoutState, seconds: Double = 0.0): WorkoutSnapshot = SnapshotBuilder.make(state, PresFix.at(seconds))

    private fun snapshot(state: WorkoutState, seconds: Int): WorkoutSnapshot = snapshot(state, seconds.toDouble())

    // region Phases

    @Test
    fun testLoggingPhaseOfAFreshWorkout() {
        val state = PresFix.freshUpperA()
        val snap = snapshot(state, 5)
        assertThat(snap.phase).isEqualTo(SnapshotPhase.LOGGING)
        assertThat(snap.workoutID).isEqualTo(state.id)
        assertThat(snap.workoutName).isEqualTo("Upper A · Push")
        assertThat(snap.revision).isEqualTo(0)
        assertThat(snap.exerciseName).isEqualTo("Barbell bench press")
        assertThat(snap.exerciseIndex).isEqualTo(0)
        assertThat(snap.exerciseCount).isEqualTo(6)
        assertThat(snap.targetExerciseID).isEqualTo(state.exercises[0].id)
        assertThat(snap.targetSetID).isEqualTo(state.exercises[0].sets[0].id)
        assertThat(snap.setLabel).isEqualTo("Warm-up · Set 1 of 5")
        assertThat(snap.tracking).isEqualTo(TrackingKind.WEIGHT_REPS)
        assertThat(snap.weightText).isEqualTo("50")
        assertThat(snap.repsText).isEqualTo("8")
        assertThat(snap.repsUnit).isEqualTo("reps")
        assertThat(snap.showsWeight).isTrue()
        assertThat(snap.nextSetText).isEqualTo("Warm-up · 50 kg × 8")
        assertThat(snap.restStartedAt).isNull()
        assertThat(snap.restEndsAt).isNull()
        assertThat(snap.restTotalSeconds).isEqualTo(0)
        assertThat(snap.restFrozenRemaining).isNull()
        assertThat(snap.heartRate).isNull()
        assertThat(snap.volumeText).isEqualTo("0")
        assertThat(snap.loggedSets).isEqualTo(0)
        assertThat(snap.totalSets).isEqualTo(20)
        assertThat(snap.nextExerciseName).isEqualTo("Incline dumbbell press")
        assertThat(snap.isPaused).isFalse()
        assertThat(snap.elapsedWhenPaused).isEqualTo(0)
        assertThat(snap.activeStart).isEqualTo(PresFix.t0)
    }

    @Test
    fun testRestingPhaseOfTheOpeningState() {
        val state = PresFix.goldenState()
        val snap = snapshot(state, 1458)
        assertThat(snap.phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(snap.revision).isEqualTo(state.revision)
        // The target is the 4th set of the bench: "Set 4 of 5".
        assertThat(snap.targetExerciseID).isEqualTo(state.exercises[0].id)
        assertThat(snap.targetSetID).isEqualTo(state.exercises[0].sets[3].id)
        assertThat(snap.setLabel).isEqualTo("Set 4 of 5")
        assertThat(snap.weightText).isEqualTo("82.5")
        assertThat(snap.repsText).isEqualTo("6")
        assertThat(snap.nextSetText).isEqualTo("Set 4 · 82.5 kg × 6")
        assertThat(snap.restStartedAt).isEqualTo(PresFix.at(1403))
        assertThat(snap.restEndsAt).isEqualTo(PresFix.at(1553))
        assertThat(snap.restTotalSeconds).isEqualTo(150)
        assertThat(snap.restFrozenRemaining).isNull()
        assertThat(snap.volumeText).isEqualTo("495")
        assertThat(snap.loggedSets).isEqualTo(3)
        assertThat(snap.totalSets).isEqualTo(20)
        assertThat(snap.exerciseName).isEqualTo("Barbell bench press")
        assertThat(snap.nextExerciseName).isEqualTo("Incline dumbbell press")
    }

    @Test
    fun testRestOverPhaseOnceTheCountdownReachedZero() {
        val state = PresFix.goldenState()
        assertThat(snapshot(state, 1552).phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(snapshot(state, 1552.5).phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(snapshot(state, 1553).phase).isEqualTo(SnapshotPhase.REST_OVER)
        assertThat(snapshot(state, 4000).phase).isEqualTo(SnapshotPhase.REST_OVER)
        // The rest dates stay available for the "Go" state.
        val over = snapshot(state, 4000)
        assertThat(over.restEndsAt).isEqualTo(PresFix.at(1553))
        assertThat(over.setLabel).isEqualTo("Set 4 of 5")
    }

    @Test
    fun testRestingBecomesLoggingAfterSkipRest() {
        val state = PresFix.reduced(PresFix.goldenState(), WorkoutAction.SkipRest, 1459)
        val snap = snapshot(state, 1460)
        assertThat(snap.phase).isEqualTo(SnapshotPhase.LOGGING)
        assertThat(snap.restEndsAt).isNull()
        assertThat(snap.restStartedAt).isNull()
        assertThat(snap.restTotalSeconds).isEqualTo(0)
    }

    @Test
    fun testCompletePhase() {
        val state = PresFix.loggedEverything(PresFix.freshUpperA())
        val snap = snapshot(state, 600)
        assertThat(snap.phase).isEqualTo(SnapshotPhase.COMPLETE)
        assertThat(snap.targetExerciseID).isNull()
        assertThat(snap.targetSetID).isNull()
        assertThat(snap.setLabel).isEqualTo("All sets logged")
        assertThat(snap.nextSetText).isEqualTo("All sets logged")
        assertThat(snap.nextExerciseName).isNull()
        assertThat(snap.loggedSets).isEqualTo(20)
        assertThat(snap.totalSets).isEqualTo(20)
        assertThat(snap.exerciseName.isEmpty()).isFalse()
    }

    @Test
    fun testCompleteWinsOverARunningRest() {
        var state = PresFix.loggedEverything(PresFix.freshUpperA(), 0.0)
        assertThat(state.rest).isNotNull()
        state = state.copy(rest = RestState(endsAt = PresFix.at(1000), totalSeconds = 60))
        val snap = snapshot(state, 10)
        assertThat(snap.phase).isEqualTo(SnapshotPhase.COMPLETE)
        assertThat(snap.restEndsAt).isEqualTo(PresFix.at(1000))
    }

    @Test
    fun testEmptyWorkoutIsCompleteWithoutTargets() {
        val state = WorkoutFactory.makeEmpty("Workout", PresFix.t0)
        val snap = snapshot(state, 30)
        assertThat(snap.phase).isEqualTo(SnapshotPhase.COMPLETE)
        assertThat(snap.targetExerciseID).isNull()
        assertThat(snap.targetSetID).isNull()
        assertThat(snap.exerciseName).isEqualTo("")
        assertThat(snap.exerciseCount).isEqualTo(0)
        assertThat(snap.totalSets).isEqualTo(0)
        assertThat(snap.nextExerciseName).isNull()
    }

    // endregion

    // region Set label and next set text

    @Test
    fun testSetLabelCountsPositionAmongAllSetsOfTheExercise() {
        var state = PresFix.freshUpperA()
        val expected = listOf("Warm-up · Set 1 of 5", "Warm-up · Set 2 of 5", "Set 3 of 5", "Set 4 of 5", "Set 5 of 5")
        for (label in expected) {
            assertThat(snapshot(state).setLabel).isEqualTo(label)
            state = PresFix.reduced(state, WorkoutAction.LogNextSet, 1)
        }
        // Then the incline press starts.
        assertThat(snapshot(state).setLabel).isEqualTo("Set 1 of 3")
    }

    @Test
    fun testSetLabelForDropAndFailureSets() {
        val sets = listOf(Triple(SetType.DROP, 60.0, 8), Triple(SetType.FAILURE, 70.0, 4))
        var state = PresFix.single(PresFix.lib("bench"), sets)
        assertThat(snapshot(state).setLabel).isEqualTo("Set 1 of 2")
        assertThat(snapshot(state).nextSetText).isEqualTo("Set 1 · 60 kg × 8")
        state = PresFix.marking(state, 0, listOf(0))
        assertThat(snapshot(state).setLabel).isEqualTo("Set 2 of 2")
    }

    @Test
    fun testSetLabelCountsSetsAddedDuringTheWorkout() {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(2, 80.0, 5))
        state = PresFix.reduced(state, WorkoutAction.AddSet(state.exercises[0].id))
        state = PresFix.marking(state, 0, listOf(0, 1))
        assertThat(snapshot(state).setLabel).isEqualTo("Set 3 of 3")
    }

    @Test
    fun testNextSetTextOfRepsOnlyAndDurationExercises() {
        val pushup = PresFix.single(PresFix.lib("pushup"), listOf(Triple(SetType.NORMAL, 0.0, 12), Triple(SetType.NORMAL, 0.0, 10)))
        var snap = snapshot(pushup)
        assertThat(snap.nextSetText).isEqualTo("Set 1 · 12 reps")
        assertThat(snap.weightText).isEqualTo("BW")
        assertThat(snap.repsText).isEqualTo("12")
        assertThat(snap.repsUnit).isEqualTo("reps")
        assertThat(snap.showsWeight).isFalse()
        assertThat(snap.tracking).isEqualTo(TrackingKind.REPS_ONLY)

        val plank = PresFix.single(PresFix.lib("plank"), listOf(Triple(SetType.NORMAL, 0.0, 45)))
        snap = snapshot(plank)
        assertThat(snap.nextSetText).isEqualTo("Set 1 · 45 s")
        assertThat(snap.weightText).isEqualTo("–")
        assertThat(snap.repsText).isEqualTo("45")
        assertThat(snap.repsUnit).isEqualTo("sec")
        assertThat(snap.showsWeight).isFalse()
        assertThat(snap.tracking).isEqualTo(TrackingKind.DURATION)
    }

    @Test
    fun testWeightTextHasNoTrailingZeros() {
        val state = PresFix.single(
            PresFix.lib("bench"),
            listOf(Triple(SetType.NORMAL, 82.5, 6), Triple(SetType.NORMAL, 80.0, 6), Triple(SetType.NORMAL, 80.25, 6)),
        )
        assertThat(snapshot(state).weightText).isEqualTo("82.5")
        assertThat(snapshot(PresFix.marking(state, 0, listOf(0))).weightText).isEqualTo("80")
        assertThat(snapshot(PresFix.marking(state, 0, listOf(0, 1))).weightText).isEqualTo("80.25")
    }

    @Test
    fun testTargetFollowsNudgesOfTheNextSet() {
        var state = PresFix.goldenState()
        state = PresFix.reduced(state, WorkoutAction.NudgeNextSet(weightSteps = 1, repsSteps = -1), 1460)
        val snap = snapshot(state, 1461)
        assertThat(snap.weightText).isEqualTo("85")
        assertThat(snap.repsText).isEqualTo("5")
        assertThat(snap.nextSetText).isEqualTo("Set 4 · 85 kg × 5")
    }

    // endregion

    // region Target and next exercise

    @Test
    fun testTargetMovesToTheNextExerciseWhenTheCurrentOneIsDone() {
        var state = PresFix.freshUpperA()
        repeat(5) { state = PresFix.reduced(state, WorkoutAction.LogNextSet, 1) }
        assertThat(state.currentIndex).isEqualTo(0) // not a superset: the current exercise stays
        val snap = snapshot(state, 2)
        assertThat(snap.targetExerciseID).isEqualTo(state.exercises[1].id)
        assertThat(snap.exerciseName).isEqualTo("Incline dumbbell press")
        assertThat(snap.exerciseIndex).isEqualTo(1)
        assertThat(snap.setLabel).isEqualTo("Set 1 of 3")
        assertThat(snap.nextSetText).isEqualTo("Set 1 · 28 kg × 10")
        assertThat(snap.nextExerciseName).isEqualTo("Overhead press")
    }

    @Test
    fun testTargetStartsAtTheCurrentExercise() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.GoTo(2))
        val snap = snapshot(state)
        assertThat(snap.exerciseName).isEqualTo("Overhead press")
        assertThat(snap.exerciseIndex).isEqualTo(2)
        assertThat(snap.targetExerciseID).isEqualTo(state.exercises[2].id)
        assertThat(snap.setLabel).isEqualTo("Set 1 of 3")
        assertThat(snap.nextExerciseName).isEqualTo("Dumbbell lateral raise")
    }

    @Test
    fun testSupersetAlternatesTheTarget() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.GoTo(3))
        var snap = snapshot(state)
        assertThat(snap.exerciseName).isEqualTo("Dumbbell lateral raise")
        assertThat(snap.nextExerciseName).isEqualTo("Triceps pushdown")
        state = PresFix.reduced(state, WorkoutAction.LogNextSet, 10)
        snap = snapshot(state, 11)
        assertThat(snap.exerciseName).isEqualTo("Triceps pushdown")
        assertThat(snap.exerciseIndex).isEqualTo(4)
        assertThat(snap.phase).isEqualTo(SnapshotPhase.LOGGING) // no rest between the members of a superset
        assertThat(snap.nextExerciseName).isEqualTo("Cable crossover")
        state = PresFix.reduced(state, WorkoutAction.LogNextSet, 20)
        snap = snapshot(state, 21)
        assertThat(snap.exerciseName).isEqualTo("Dumbbell lateral raise")
        assertThat(snap.setLabel).isEqualTo("Set 2 of 3")
        assertThat(snap.phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(snap.restTotalSeconds).isEqualTo(60)
    }

    @Test
    fun testNextExerciseNameSkipsFinishedExercisesAndHasNoWrapAround() {
        var state = PresFix.freshUpperA()
        // Finish the overhead press and go there: the next exercise with pending sets is the lateral raise.
        state = PresFix.marking(state, 2, listOf(0, 1, 2))
        state = PresFix.marking(state, 3, listOf(0, 1, 2))
        state = PresFix.reduced(state, WorkoutAction.GoTo(1))
        assertThat(snapshot(state).exerciseName).isEqualTo("Incline dumbbell press")
        assertThat(snapshot(state).nextExerciseName).isEqualTo("Triceps pushdown")
        // On the last exercise nothing follows, even though earlier exercises are pending.
        state = PresFix.reduced(state, WorkoutAction.GoTo(5))
        assertThat(snapshot(state).exerciseName).isEqualTo("Cable crossover")
        assertThat(snapshot(state).nextExerciseName).isNull()
    }

    @Test
    fun testNextExerciseNameIsNilWhenOnlyTheShownExerciseIsPending() {
        var state = PresFix.freshUpperA()
        for (k in 1 until 6) state = PresFix.marking(state, k, (0 until state.exercises[k].sets.size).toList())
        assertThat(snapshot(state).nextExerciseName).isNull()
        assertThat(snapshot(state).exerciseName).isEqualTo("Barbell bench press")
    }

    // endregion

    // region Time and pause

    @Test
    fun testActiveStartMovesWithPausedTime() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.Pause, 100)
        state = PresFix.reduced(state, WorkoutAction.Resume, 160)
        val snap = snapshot(state, 200)
        assertThat(snap.activeStart).isEqualTo(PresFix.at(60))
        assertThat(snap.isPaused).isFalse()
        assertThat(snap.elapsedWhenPaused).isEqualTo(0)
    }

    @Test
    fun testPausedSnapshotFreezesTheClockAndTheRest() {
        var state = PresFix.goldenState() // rest ends at t0 + 1553
        state = PresFix.reduced(state, WorkoutAction.Pause, 1423) // 130 s of rest left
        for (seconds in listOf(1424.0, 1500.0, 9000.0)) {
            val snap = snapshot(state, seconds)
            assertThat(snap.isPaused).isTrue()
            assertThat(snap.elapsedWhenPaused).isEqualTo(1423)
            assertThat(snap.restFrozenRemaining).isEqualTo(130)
            assertWithMessage("at $seconds").that(snap.phase).isEqualTo(SnapshotPhase.RESTING)
            assertThat(snap.restTotalSeconds).isEqualTo(150)
        }
        state = PresFix.reduced(state, WorkoutAction.Resume, 1523)
        val resumed = snapshot(state, 1524)
        assertThat(resumed.isPaused).isFalse()
        assertThat(resumed.restFrozenRemaining).isNull()
        assertThat(resumed.restEndsAt).isEqualTo(PresFix.at(1653))
        assertThat(resumed.restStartedAt).isEqualTo(PresFix.at(1503))
        assertThat(resumed.activeStart).isEqualTo(PresFix.at(100))
    }

    @Test
    fun testPausedWithoutRestHasNoFrozenRemaining() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.Pause, 77.9)
        val snap = snapshot(state, 500)
        assertThat(snap.isPaused).isTrue()
        assertThat(snap.elapsedWhenPaused).isEqualTo(77)
        assertThat(snap.restFrozenRemaining).isNull()
        assertThat(snap.phase).isEqualTo(SnapshotPhase.LOGGING)
    }

    @Test
    fun testPausedWithAnEmptyFrozenRestIsRestOver() {
        var state = PresFix.goldenState()
        state = PresFix.reduced(state, WorkoutAction.Pause, 1560) // the rest ended at 1553 while the clock still ran
        val snap = snapshot(state, 1600)
        assertThat(snap.phase).isEqualTo(SnapshotPhase.REST_OVER)
        assertThat(snap.restFrozenRemaining).isEqualTo(0)
    }

    @Test
    fun testFrozenRestSecondsRoundUp() {
        var state = PresFix.goldenState()
        state = PresFix.reduced(state, WorkoutAction.Pause, 1500.5) // 52.5 s left
        assertThat(snapshot(state, 1600).restFrozenRemaining).isEqualTo(53)
    }

    // endregion

    // region Pass-through values

    @Test
    fun testHeartRateAndVolumeAreCopied() {
        var state = PresFix.loggedEverything(PresFix.freshUpperA())
        state = PresFix.reduced(state, WorkoutAction.UpdateHeartRate(131), 700)
        val snap = snapshot(state, 701)
        assertThat(snap.heartRate).isEqualTo(131)
        // Working sets: bench 495 + 495 + 510, incline 840, ohp 1080, lateral 360, pushdown 1080, crossover 540.
        assertThat(snap.volumeText).isEqualTo("5,400")
        assertThat(snap.revision).isEqualTo(state.revision)
    }

    @Test
    fun testRevisionTracksTheState() {
        var state = PresFix.freshUpperA()
        assertThat(snapshot(state).revision).isEqualTo(0)
        state = PresFix.reduced(state, WorkoutAction.LogNextSet, 1)
        assertThat(snapshot(state).revision).isEqualTo(1)
        state = PresFix.reduced(state, WorkoutAction.UpdateHeartRate(100), 2)
        assertThat(snapshot(state).revision).isEqualTo(1) // heart-rate samples do not bump the revision
    }

    // endregion

    // region Stability (notification de-duplication; Swift: Live Activity de-duplication)

    @Test
    fun testSnapshotIsStableWhileNothingChanges() {
        val logging = PresFix.freshUpperA()
        assertThat(snapshot(logging, 10)).isEqualTo(snapshot(logging, 500))
        val resting = PresFix.goldenState()
        assertThat(snapshot(resting, 1460)).isEqualTo(snapshot(resting, 1500))
        var paused = PresFix.goldenState()
        paused = PresFix.reduced(paused, WorkoutAction.Pause, 1423)
        assertThat(snapshot(paused, 1430)).isEqualTo(snapshot(paused, 3000))
    }

    // endregion

    // region Size and serialization

    /** UTF-8 size of the JSON of [snap] in the Kotlin persistence format (the Swift test measured JSONEncoder output). */
    private fun jsonSize(snap: WorkoutSnapshot): Int =
        StrengthJson.format.encodeToString(WorkoutSnapshot.serializer(), snap).toByteArray(Charsets.UTF_8).size

    /**
     * Swift: `testLiveActivitySizeSanity` (ActivityKit's 4 KB payload limit). Adapted: the Kotlin format has a single date encoding
     * (ISO 8601), so the Swift "plain" and "iso8601" measurements collapse into one; both Swift limits are kept.
     */
    @Test
    fun testLiveActivitySizeSanity() {
        val states = mutableListOf(
            PresFix.freshUpperA(),
            PresFix.goldenState(),
            PresFix.reduced(PresFix.goldenState(), WorkoutAction.Pause, 1423),
            PresFix.loggedEverything(PresFix.freshUpperA()),
        )
        // Worst case: long names everywhere, a heart rate and a long weight text.
        val longExercise = PresFix.lib("incline").copy(name = "Incline dumbbell press ".repeat(3))
        var long = PresFix.single(longExercise, listOf(Triple(SetType.WARMUP, 1234.56, 999)))
        long = long.copy(
            name = "Upper A · Push ".repeat(4),
            heartRate = 187,
            rest = RestState(endsAt = PresFix.at(100), totalSeconds = 600),
        )
        states.add(long)
        for ((index, state) in states.withIndex()) {
            val snap = snapshot(state, 1458)
            assertWithMessage("state $index").that(jsonSize(snap)).isLessThan(1500)
        }
        assertThat(jsonSize(snapshot(PresFix.goldenState(), 1458))).isLessThan(1000)
    }

    @Test
    fun testSnapshotRoundTripsThroughJSON() {
        val snap = snapshot(PresFix.goldenState(), 1458)
        val text = StrengthJson.format.encodeToString(WorkoutSnapshot.serializer(), snap)
        assertThat(StrengthJson.format.decodeFromString(WorkoutSnapshot.serializer(), text)).isEqualTo(snap)
    }

    // endregion
}

// region Fuzz: snapshot invariants

class SnapshotFuzzTests {
    @Test
    fun testInvariantsHoldUnderRandomPlay() {
        for (seed in 1..12) {
            val rng = PresLCG(seed.toLong() + 900)
            var state = if (seed % 4 == 0) {
                WorkoutFactory.makeEmpty("Fuzz", PresFix.t0)
            } else {
                WorkoutFactory.makeWorkout(PresFix.upperA(), PresFix.t0)
            }
            var clock = 0.0
            for (step in 0 until 150) {
                clock += rng.below(30).toDouble() / 2
                val exercise = if (state.exercises.isEmpty()) null else state.exercises[rng.below(state.exercises.size)]
                val set = exercise?.let { if (it.sets.isEmpty()) null else it.sets[rng.below(it.sets.size)] }
                val action: WorkoutAction = when (rng.below(11)) {
                    0, 1, 2 -> WorkoutAction.LogNextSet
                    3 -> if (exercise != null && set != null) WorkoutAction.ToggleSet(exercise.id, set.id) else WorkoutAction.SkipRest
                    4 -> WorkoutAction.Pause
                    5 -> WorkoutAction.Resume
                    6 -> WorkoutAction.AdjustRest(if (rng.below(2) == 0) 15 else -15)
                    7 -> WorkoutAction.GoTo(rng.below(6))
                    8 -> WorkoutAction.NudgeNextSet(weightSteps = rng.below(5) - 2, repsSteps = rng.below(5) - 2)
                    9 -> WorkoutAction.SkipRest
                    else -> WorkoutAction.AddExercises(listOf(PresFix.lib(listOf("pushup", "plank", "squat")[rng.below(3)])))
                }
                state = WorkoutReducer.reduce(state, action, PresFix.at(clock))

                val now = PresFix.at(clock + rng.below(300).toDouble() / 2)
                val snap = SnapshotBuilder.make(state, now)
                val context = "seed $seed step $step $action"
                val target = WorkoutTargets.nextPending(state)

                assertWithMessage(context).that(snap.phase == SnapshotPhase.COMPLETE).isEqualTo(target == null)
                assertWithMessage(context).that(snap.targetSetID == null).isEqualTo(target == null)
                assertWithMessage(context).that(snap.targetExerciseID == null).isEqualTo(target == null)
                assertWithMessage(context).that(snap.workoutID).isEqualTo(state.id)
                assertWithMessage(context).that(snap.revision).isEqualTo(state.revision)
                assertWithMessage(context).that(snap.exerciseCount).isEqualTo(state.exercises.size)
                assertWithMessage(context).that(snap.isPaused).isEqualTo(state.isPaused)
                assertWithMessage(context).that(snap.restFrozenRemaining != null).isEqualTo(state.isPaused && state.rest != null)
                assertWithMessage(context).that(snap.restEndsAt != null).isEqualTo(state.rest != null)
                assertWithMessage(context).that(snap.restTotalSeconds >= 0).isTrue()
                if (snap.phase == SnapshotPhase.RESTING || snap.phase == SnapshotPhase.REST_OVER) {
                    assertWithMessage(context).that(snap.restEndsAt).isNotNull()
                }
                if (target != null) {
                    val entry = state.exercises[target.exerciseIndex]
                    assertWithMessage(context).that(snap.targetExerciseID).isEqualTo(entry.id)
                    assertWithMessage(context).that(snap.targetSetID).isEqualTo(entry.sets[target.setIndex].id)
                    assertWithMessage(context).that(snap.exerciseName).isEqualTo(entry.exercise.name)
                    assertWithMessage(context).that(snap.exerciseIndex).isEqualTo(target.exerciseIndex)
                    assertWithMessage(context).that(snap.setLabel.endsWith("of ${entry.sets.size}")).isTrue()
                    assertWithMessage(context).that(snap.showsWeight).isEqualTo(entry.exercise.tracksWeight)
                }
                val totals = PresFix.present(state, clock).totals
                assertWithMessage(context).that(snap.loggedSets).isEqualTo(totals.loggedSets)
                assertWithMessage(context).that(snap.totalSets).isEqualTo(totals.totalSets)
                val size = StrengthJson.format.encodeToString(WorkoutSnapshot.serializer(), snap).toByteArray(Charsets.UTF_8).size
                assertWithMessage(context).that(size).isLessThan(1500)
            }
        }
    }
}

// endregion
