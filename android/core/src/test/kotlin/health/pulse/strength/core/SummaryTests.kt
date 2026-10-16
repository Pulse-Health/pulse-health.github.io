package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import org.junit.Test

// Port of SummaryTests.swift (Swift: 36 tests in 2 classes).

class SummaryBuilderTests {
    /**
     * A finished session of the design's workout:
     * bench W 50x8, W 70x5, 82.5x6 (RIR 3), 82.5x6 (RIR 2), 85x6 (RIR 1) = a personal record (102 > 99);
     * incline 28x10 (RIR 4) and 28x10 (third set pending); lateral 8x15 and pushdown 30x12 (one set each, superset).
     * Heart rate samples 120, 130, 140 and one out-of-range sample (20).
     */
    private fun session(): WorkoutState {
        var state = PresFix.freshUpperA()
        var clock = 100.0
        fun apply(action: WorkoutAction) {
            state = WorkoutReducer.reduce(state, action, PresFix.at(clock))
            clock += 10
        }
        // Bench: five sets in order, with RIR on the working sets.
        repeat(2) { apply(WorkoutAction.LogNextSet) }
        apply(WorkoutAction.LogNextSet); apply(WorkoutAction.ToggleLastSetRIR(3))
        apply(WorkoutAction.LogNextSet); apply(WorkoutAction.ToggleLastSetRIR(2))
        apply(WorkoutAction.LogNextSet); apply(WorkoutAction.ToggleLastSetRIR(1))
        // Incline: two of three sets.
        apply(WorkoutAction.LogNextSet); apply(WorkoutAction.ToggleLastSetRIR(4))
        apply(WorkoutAction.LogNextSet)
        // Skip overhead press; superset lateral + pushdown, one round.
        apply(WorkoutAction.GoTo(3))
        apply(WorkoutAction.LogNextSet)
        apply(WorkoutAction.LogNextSet)
        for (bpm in listOf(120, 130, 140, 20)) apply(WorkoutAction.UpdateHeartRate(bpm))
        return state
    }

    private fun build(state: WorkoutState, finishedAt: Double = 3725.0): CompletedWorkout =
        SummaryBuilder.build(state, PresFix.at(finishedAt))

    // region Totals

    @Test
    fun testIdentityAndTiming() {
        val state = session()
        val summary = build(state)
        assertThat(summary.id).isEqualTo(state.id)
        assertThat(summary.name).isEqualTo("Upper A · Push")
        assertThat(summary.templateID).isEqualTo(PresFix.upperA().id)
        assertThat(summary.startedAt).isEqualTo(PresFix.t0)
        assertThat(summary.finishedAt).isEqualTo(PresFix.at(3725))
        assertThat(summary.durationSeconds).isEqualTo(3725)
    }

    @Test
    fun testVolumeAndSetCounts() {
        val summary = build(session())
        // 82.5x6 + 82.5x6 + 85x6 + 28x10 + 28x10 + 8x15 + 30x12 = 495 + 495 + 510 + 280 + 280 + 120 + 360
        assertThat(summary.volumeKg).isWithin(0.0001).of(2540.0)
        assertThat(summary.loggedSets).isEqualTo(9) // warm-ups included
    }

    @Test
    fun testVolumeMatchesThePresenterTotals() {
        val state = session()
        assertThat(build(state).volumeKg).isWithin(0.0001).of(PresFix.present(state, 3725).totals.volumeKg)
        assertThat(build(state).loggedSets).isEqualTo(PresFix.present(state, 3725).totals.loggedSets)
    }

    @Test
    fun testOnlyLoggedSetsAreKeptAndExercisesWithoutLoggedSetsAreLeftOut() {
        val summary = build(session())
        assertThat(summary.exercises.map { it.exerciseID }).isEqualTo(listOf("bench", "incline", "lateral", "pushdown"))
        assertThat(summary.exercises.map { it.sets.size }).isEqualTo(listOf(5, 2, 1, 1))
        val bench = summary.exercises[0]
        assertThat(bench.sets.map { it.type }).isEqualTo(listOf(SetType.WARMUP, SetType.WARMUP, SetType.NORMAL, SetType.NORMAL, SetType.NORMAL))
        assertThat(bench.sets.map { it.weightKg }).isEqualTo(listOf(50.0, 70.0, 82.5, 82.5, 85.0))
        assertThat(bench.sets.map { it.reps }).isEqualTo(listOf(8, 5, 6, 6, 6))
        assertThat(bench.sets.map { it.rir }).isEqualTo(listOf<Int?>(null, null, 3, 2, 1))
    }

    @Test
    fun testCompletedExerciseFieldsComeFromTheWorkoutEntry() {
        val state = session()
        val summary = build(state)
        val bench = summary.exercises[0]
        assertThat(bench.id).isEqualTo(state.exercises[0].id)
        assertThat(bench.name).isEqualTo("Barbell bench press")
        assertThat(bench.muscle).isEqualTo(MuscleGroup.CHEST)
        assertThat(bench.mediaKey).isEqualTo("bench")
        assertThat(bench.tracking).isEqualTo(TrackingKind.WEIGHT_REPS)
    }

    @Test
    fun testNoPendingSetIsKept() {
        // The third incline set was never logged.
        val incline = build(session()).exercises[1]
        assertThat(incline.sets.size).isEqualTo(2)
    }

    @Test
    fun testLoggingAPendingSetIsNeededToAppear() {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(3, 80.0, 5))
        assertThat(build(state).exercises).isEmpty()
        state = PresFix.marking(state, 0, listOf(1))
        val summary = build(state)
        assertThat(summary.exercises.size).isEqualTo(1)
        assertThat(summary.loggedSets).isEqualTo(1)
    }

    // endregion

    // region Personal records

    @Test
    fun testPersonalRecordList() {
        val summary = build(session())
        assertThat(summary.personalRecords.size).isEqualTo(1)
        val record = PresFix.unwrap(summary.personalRecords.firstOrNull())
        assertThat(record.exerciseID).isEqualTo("bench")
        assertThat(record.exerciseName).isEqualTo("Barbell bench press")
        assertThat(record.weightKg).isEqualTo(85.0)
        assertThat(record.reps).isEqualTo(6)
        assertThat(record.estimated1RM).isWithin(0.0001).of(102.0)
        assertThat(record.previousBest).isEqualTo(99.0)
        assertThat(summary.exercises.map { it.isPersonalRecord }).isEqualTo(listOf(true, false, false, false))
    }

    @Test
    fun testBestE1RMOfEachExercise() {
        val summary = build(session())
        assertThat(summary.exercises[0].bestE1RM).isWithin(0.0001).of(102.0)
        assertThat(summary.exercises[1].bestE1RM).isWithin(0.0001).of(28.0 * (1 + 10.0 / 30))
        assertThat(summary.exercises[2].bestE1RM).isWithin(0.0001).of(12.0) // 8 x 15
    }

    @Test
    fun testWarmUpsNeverSetTheBestE1RM() {
        val state = PresFix.marking(
            PresFix.single(PresFix.lib("bench", 0.0), listOf(Triple(SetType.WARMUP, 200.0, 5), Triple(SetType.NORMAL, 80.0, 5))), 0, listOf(0, 1),
        )
        assertThat(build(state).exercises[0].bestE1RM).isWithin(0.0001).of(80.0 * (1 + 5.0 / 30))
    }

    @Test
    fun testNoPersonalRecordWithoutHistoryButTheBestIsStillReported() {
        val state = PresFix.marking(
            PresFix.single(PresFix.lib("bench", 0.0), listOf(Triple(SetType.NORMAL, 100.0, 5), Triple(SetType.NORMAL, 110.0, 5))), 0, listOf(0, 1),
        )
        val summary = build(state)
        assertThat(summary.personalRecords).isEmpty()
        assertThat(summary.exercises[0].isPersonalRecord).isFalse()
        assertThat(summary.exercises[0].bestE1RM).isWithin(0.0001).of(110.0 * (1 + 5.0 / 30))
    }

    @Test
    fun testNoPersonalRecordWhenTheBestOnlyMatchesTheBaseline() {
        val state = PresFix.marking(PresFix.single(PresFix.lib("bench"), listOf(Triple(SetType.NORMAL, 82.5, 6))), 0, listOf(0))
        val summary = build(state)
        assertThat(summary.personalRecords).isEmpty()
        assertThat(summary.exercises[0].isPersonalRecord).isFalse()
    }

    @Test
    fun testPersonalRecordUsesTheRunningBaselineLikeThePresenter() {
        // 85 x 5 (99.17) then 85 x 6 (102) against 80: both are records, the best set is the second.
        val state = PresFix.marking(
            PresFix.single(PresFix.lib("bench", 80.0), listOf(Triple(SetType.NORMAL, 85.0, 5), Triple(SetType.NORMAL, 85.0, 6))), 0, listOf(0, 1),
        )
        val record = PresFix.unwrap(build(state).personalRecords.firstOrNull())
        assertThat(record.reps).isEqualTo(6)
        assertThat(record.estimated1RM).isWithin(0.0001).of(102.0)
        assertThat(record.previousBest).isEqualTo(80.0)
        val view = PresFix.present(state, 10)
        assertThat(PresFix.unwrap(view.card).rows.map { it.isPersonalRecord }).isEqualTo(listOf(true, true))
    }

    @Test
    fun testRecordBestSetIsTheHighestEstimateNotTheLastSet() {
        val state = PresFix.marking(
            PresFix.single(PresFix.lib("bench", 80.0), listOf(Triple(SetType.NORMAL, 85.0, 6), Triple(SetType.NORMAL, 85.0, 3))), 0, listOf(0, 1),
        )
        val record = PresFix.unwrap(build(state).personalRecords.firstOrNull())
        assertThat(record.reps).isEqualTo(6)
        assertThat(record.weightKg).isEqualTo(85.0)
    }

    @Test
    fun testRecordsListFollowsTheWorkoutOrder() {
        val a = PresFix.entry(1, PresFix.lib("incline", 20.0), PresFix.normal(1, 28.0, 10))
        val b = PresFix.entry(2, PresFix.lib("bench", 50.0), PresFix.normal(1, 80.0, 5))
        var state = PresFix.workout(listOf(a, b))
        state = PresFix.marking(state, 0, listOf(0))
        state = PresFix.marking(state, 1, listOf(0))
        assertThat(build(state).personalRecords.map { it.exerciseID }).isEqualTo(listOf("incline", "bench"))
    }

    @Test
    fun testTheSameExerciseTwiceYieldsOneRecordWithTheBestEstimate() {
        val a = PresFix.entry(1, PresFix.lib("bench", 80.0), PresFix.normal(1, 85.0, 5))
        val b = PresFix.entry(2, PresFix.lib("bench", 80.0), PresFix.normal(1, 90.0, 5))
        var state = PresFix.workout(listOf(a, b))
        state = PresFix.marking(state, 0, listOf(0))
        state = PresFix.marking(state, 1, listOf(0))
        val summary = build(state)
        assertThat(summary.exercises.size).isEqualTo(2)
        assertThat(summary.personalRecords.size).isEqualTo(1)
        assertThat(summary.personalRecords[0].weightKg).isEqualTo(90.0)
    }

    @Test
    fun testBodyweightAndDurationExercisesHaveNoEstimate() {
        val pushup = PresFix.entry(1, PresFix.lib("pushup"), PresFix.normal(2, 0.0, 12))
        val plank = PresFix.entry(2, PresFix.lib("plank"), PresFix.normal(1, 0.0, 60))
        var state = PresFix.workout(listOf(pushup, plank))
        state = PresFix.marking(state, 0, listOf(0, 1))
        state = PresFix.marking(state, 1, listOf(0))
        val summary = build(state)
        assertThat(summary.exercises.map { it.bestE1RM }).isEqualTo(listOf(0.0, 0.0))
        assertThat(summary.exercises.map { it.isPersonalRecord }).isEqualTo(listOf(false, false))
        assertThat(summary.exercises.map { it.tracking }).isEqualTo(listOf(TrackingKind.REPS_ONLY, TrackingKind.DURATION))
        assertThat(summary.volumeKg).isEqualTo(0.0)
        assertThat(summary.loggedSets).isEqualTo(3)
        assertThat(summary.exercises[1].sets.map { it.reps }).isEqualTo(listOf(60))
    }

    // endregion

    // region Muscle sets

    @Test
    fun testMuscleSetsAreSortedBySetsThenName() {
        val summary = build(session())
        // Non-warm-up logged sets: chest 3 + 2, shoulders (lateral) 1, arms (pushdown) 1.
        assertThat(summary.muscleSets.map { it.muscle }).isEqualTo(listOf(MuscleGroup.CHEST, MuscleGroup.ARMS, MuscleGroup.SHOULDERS))
        assertThat(summary.muscleSets.map { it.sets }).isEqualTo(listOf(5, 1, 1))
    }

    @Test
    fun testMuscleSetsOmitZerosAndWarmUps() {
        val warmUpOnly = PresFix.marking(
            PresFix.single(PresFix.lib("squat"), listOf(Triple(SetType.WARMUP, 40.0, 10), Triple(SetType.NORMAL, 80.0, 5))), 0, listOf(0),
        )
        assertThat(build(warmUpOnly).muscleSets).isEmpty()
        assertThat(build(warmUpOnly).loggedSets).isEqualTo(1)
    }

    @Test
    fun testMuscleSetsCountEveryTrackingKind() {
        val plank = PresFix.entry(1, PresFix.lib("plank"), PresFix.normal(2, 0.0, 45))
        val pushup = PresFix.entry(2, PresFix.lib("pushup"), PresFix.normal(2, 0.0, 12))
        val squat = PresFix.entry(3, PresFix.lib("squat"), PresFix.normal(3, 80.0, 5))
        var state = PresFix.workout(listOf(plank, pushup, squat))
        state = PresFix.marking(state, 0, listOf(0, 1))
        state = PresFix.marking(state, 1, listOf(0, 1))
        state = PresFix.marking(state, 2, listOf(0, 1, 2))
        val sets = build(state).muscleSets
        // Legs 3, then chest and core with 2 each (alphabetical).
        assertThat(sets.map { it.muscle }).isEqualTo(listOf(MuscleGroup.LEGS, MuscleGroup.CHEST, MuscleGroup.CORE))
        assertThat(sets.map { it.sets }).isEqualTo(listOf(3, 2, 2))
    }

    @Test
    fun testMuscleSetsAllSixGroupsTieBreakByName() {
        val entries = mutableListOf<WorkoutExercise>()
        val ids = listOf("bench", "pullup", "ohp", "curl", "squat", "plank")
        for ((n, id) in ids.withIndex()) entries.add(PresFix.entry(n + 1, PresFix.lib(id), PresFix.normal(1, 20.0, 5)))
        var state = PresFix.workout(entries)
        for (k in entries.indices) state = PresFix.marking(state, k, listOf(0))
        assertThat(build(state).muscleSets.map { it.muscle.rawValue }).isEqualTo(listOf("Arms", "Back", "Chest", "Core", "Legs", "Shoulders"))
    }

    // endregion

    // region RIR and heart rate

    @Test
    fun testAverageRIR() {
        // Recorded on logged sets: 3, 2, 1 (bench) and 4 (incline).
        assertThat(PresFix.unwrap(build(session()).averageRIR)).isWithin(0.0001).of(2.5)
    }

    @Test
    fun testAverageRIRIgnoresUnrecordedAndUnloggedSets() {
        var state = PresFix.single(PresFix.lib("bench"), PresFix.normal(4, 80.0, 5))
        state = PresFix.marking(state, 0, listOf(0, 1, 2))
        state = PresFix.editSet(state, 0, 0) { it.copy(rir = 1) }
        state = PresFix.editSet(state, 0, 1) { it.copy(rir = 2) }
        state = PresFix.editSet(state, 0, 3) { it.copy(rir = 4) } // pending: ignored
        assertThat(PresFix.unwrap(build(state).averageRIR)).isWithin(0.0001).of(1.5)
    }

    @Test
    fun testAverageRIRIsNilWithoutRecordedValues() {
        val state = PresFix.marking(PresFix.single(PresFix.lib("bench"), PresFix.normal(2, 80.0, 5)), 0, listOf(0, 1))
        assertThat(build(state).averageRIR).isNull()
    }

    @Test
    fun testAverageHeartRate() {
        // 120, 130, 140 count; 20 is out of range for the reducer.
        assertThat(build(session()).averageHeartRate).isEqualTo(130)
    }

    @Test
    fun testAverageHeartRateIsNilWithoutSamples() {
        assertThat(build(PresFix.goldenState()).averageHeartRate).isNull()
    }

    // endregion

    // region Duration

    @Test
    fun testDurationOfAWorkoutWithoutPauses() {
        assertThat(build(session(), 600.0).durationSeconds).isEqualTo(600)
        assertThat(build(session(), 0.0).durationSeconds).isEqualTo(0)
        assertThat(build(session(), -10.0).durationSeconds).isEqualTo(0)
    }

    @Test
    fun testDurationExcludesPausedTime() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.Pause, 1000)
        state = PresFix.reduced(state, WorkoutAction.Resume, 1400) // 400 s paused
        assertThat(build(state, 2000.0).durationSeconds).isEqualTo(1600)
    }

    @Test
    fun testDurationOfAWorkoutFinishedWhilePausedStopsAtThePause() {
        var state = PresFix.freshUpperA()
        state = PresFix.reduced(state, WorkoutAction.Pause, 1000)
        assertThat(build(state, 5000.0).durationSeconds).isEqualTo(1000)
    }

    @Test
    fun testDurationIgnoresAnEarlierFinishedAtOfTheState() {
        val state = PresFix.freshUpperA().copy(finishedAt = PresFix.at(50))
        assertThat(build(state, 700.0).durationSeconds).isEqualTo(700)
    }

    // endregion

    // region Empty and degenerate workouts

    @Test
    fun testEmptyWorkoutSummary() {
        val state = WorkoutFactory.makeEmpty("Workout", PresFix.t0)
        val summary = build(state, 90.0)
        assertThat(summary.name).isEqualTo("Workout")
        assertThat(summary.templateID).isNull()
        assertThat(summary.durationSeconds).isEqualTo(90)
        assertThat(summary.volumeKg).isEqualTo(0.0)
        assertThat(summary.loggedSets).isEqualTo(0)
        assertThat(summary.averageHeartRate).isNull()
        assertThat(summary.averageRIR).isNull()
        assertThat(summary.exercises).isEmpty()
        assertThat(summary.personalRecords).isEmpty()
        assertThat(summary.muscleSets).isEmpty()
    }

    @Test
    fun testNothingLoggedSummary() {
        val summary = build(PresFix.freshUpperA(), 30.0)
        assertThat(summary.loggedSets).isEqualTo(0)
        assertThat(summary.exercises).isEmpty()
        assertThat(summary.volumeKg).isEqualTo(0.0)
    }

    @Test
    fun testEverythingLogged() {
        val state = PresFix.loggedEverything(PresFix.freshUpperA())
        val summary = build(state, 600.0)
        assertThat(summary.exercises.size).isEqualTo(6)
        assertThat(summary.loggedSets).isEqualTo(20)
        assertThat(summary.exercises.map { it.sets.size }).isEqualTo(listOf(5, 3, 3, 3, 3, 3))
        // bench 85 x 6 = 102 beats 99; incline 28 x 10 = 37.3 < 38; ohp 45 x 8 = 57 < 58; lateral 8 x 15 = 12 < 12.5;
        // pushdown 30 x 12 = 42 < 43; crossover 15 x 12 = 21 < 22.
        assertThat(summary.personalRecords.map { it.exerciseID }).isEqualTo(listOf("bench"))
    }

    /** Swift: `testSummaryIsCodableAndStable` (JSONEncoder/JSONDecoder); adapted to the Kotlin JSON format of the persistence files. */
    @Test
    fun testSummaryIsCodableAndStable() {
        val state = session()
        val summary = build(state)
        val json = StrengthJson.format
        val text = json.encodeToString(CompletedWorkout.serializer(), summary)
        assertThat(json.decodeFromString(CompletedWorkout.serializer(), text)).isEqualTo(summary)
        // Building twice from the same state gives the same summary.
        assertThat(build(state)).isEqualTo(summary)
    }

    @Test
    fun testSummaryHasUniqueIdentifiersForLists() {
        val summary = build(PresFix.loggedEverything(PresFix.freshUpperA()))
        assertThat(summary.exercises.map { it.id }.toSet().size).isEqualTo(summary.exercises.size)
        assertThat(summary.personalRecords.map { it.id }.toSet().size).isEqualTo(summary.personalRecords.size)
        assertThat(summary.muscleSets.map { it.id }.toSet().size).isEqualTo(summary.muscleSets.size)
    }

    // endregion
}

// region Fuzz: summary invariants

class SummaryFuzzTests {
    @Test
    fun testSummaryAgreesWithThePresenterUnderRandomPlay() {
        for (seed in 1..10) {
            val rng = PresLCG(seed.toLong() + 500)
            var state = WorkoutFactory.makeWorkout(PresFix.upperA(), PresFix.t0)
            var clock = 0.0
            for (step in 0 until 120) {
                clock += rng.below(30).toDouble()
                val exercise = if (state.exercises.isEmpty()) null else state.exercises[rng.below(state.exercises.size)]
                val set = exercise?.let { if (it.sets.isEmpty()) null else it.sets[rng.below(it.sets.size)] }
                val action: WorkoutAction = when (rng.below(8)) {
                    0, 1, 2 -> WorkoutAction.LogNextSet
                    3 -> if (exercise != null && set != null) WorkoutAction.ToggleSet(exercise.id, set.id) else WorkoutAction.SkipRest
                    4 -> WorkoutAction.ToggleLastSetRIR(rng.below(5))
                    5 -> WorkoutAction.UpdateHeartRate(60 + rng.below(100))
                    6 -> if (exercise != null && set != null) {
                        WorkoutAction.SetWeight(exercise.id, set.id, rng.below(240).toDouble() / 2)
                    } else {
                        WorkoutAction.SkipRest
                    }
                    else -> WorkoutAction.GoTo(rng.below(6))
                }
                state = WorkoutReducer.reduce(state, action, PresFix.at(clock))

                val summary = SummaryBuilder.build(state, PresFix.at(clock + 1))
                val view = PresFix.present(state, clock + 1)
                val context = "seed $seed step $step"
                assertWithMessage(context).that(summary.loggedSets).isEqualTo(view.totals.loggedSets)
                assertWithMessage(context).that(summary.volumeKg).isWithin(0.0001).of(view.totals.volumeKg)
                assertWithMessage(context).that(summary.exercises.map { it.sets.size }.sum()).isEqualTo(summary.loggedSets)
                assertWithMessage(context).that(summary.muscleSets.map { it.sets }).isEqualTo(summary.muscleSets.map { it.sets }.sortedDescending())
                assertWithMessage(context).that(summary.muscleSets.all { it.sets > 0 }).isTrue()
                assertWithMessage(context).that(summary.exercises.count { it.isPersonalRecord }).isEqualTo(summary.personalRecords.size)
                assertWithMessage(context).that(summary.averageHeartRate).isEqualTo(state.averageHeartRate)
                for (entry in summary.exercises) {
                    assertWithMessage(context).that(entry.sets.isEmpty()).isFalse()
                    if (entry.isPersonalRecord) assertWithMessage(context).that(entry.bestE1RM).isGreaterThan(0.0)
                }
                for (record in summary.personalRecords) {
                    assertWithMessage(context).that(record.estimated1RM).isGreaterThan(record.previousBest)
                }
            }
        }
    }
}

// endregion
