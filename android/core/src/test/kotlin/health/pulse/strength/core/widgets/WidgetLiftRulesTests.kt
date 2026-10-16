package health.pulse.strength.core.widgets

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.CompletedExercise
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.SetType
import health.pulse.strength.core.StrengthData
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.core.addingTimeInterval
import java.time.Instant
import java.util.UUID
import org.junit.Test

/** widgets/SPEC.md section 2: lifts, plateaus, strengthRatio and block. `WidFix.now` is Friday 2026-10-16 09:41 UTC. */
private object LiftFix {
    /** A workout [daysAgo] days before `now` in which [exerciseID] has the recorded estimate [e1RM]. */
    fun session(n: Int, exerciseID: String, daysAgo: Double, e1RM: Double): CompletedWorkout =
        WidFix.workout(n, daysAgo = daysAgo).withExercises(listOf(WidFix.lift(exerciseID, listOf(WidFix.set(50.0, 5)), best = e1RM, n = n)))

    /** The lifts of the snapshot of [history]. */
    fun lifts(history: List<CompletedWorkout>, now: Instant = WidFix.now): List<LiftTrend> = WidFix.snapshot(history = history, now = now).lifts

    /** Sessions of [exerciseID] with the given estimates, oldest first, [spacing] days apart, the newest [newest] days ago. */
    fun series(exerciseID: String, values: List<Double>, newest: Double = 1.0, spacing: Double = 4.0, firstNumber: Int = 1): List<CompletedWorkout> =
        values.mapIndexed { offset, value -> session(firstNumber + offset, exerciseID, daysAgo = newest + (values.size - 1 - offset) * spacing, e1RM = value) }
}

class WidgetLiftsRuleTests {
    @Test
    fun testLiftsAreTheWeightTrackingExercisesOfTheLast90Days() {
        val history = listOf(
            WidFix.workout(1, daysAgo = 2.0).withExercises(
                listOf(
                    WidFix.lift("bench", listOf(WidFix.set(80.0, 6)), n = 1),
                    WidFix.lift("pullup", listOf(WidFix.set(0.0, 8)), n = 2), // reps only
                    WidFix.lift("plank", listOf(WidFix.set(0.0, 45)), n = 3), // duration
                ),
            ),
        )
        assertThat(LiftFix.lifts(history).map { it.exerciseID }).containsExactly("bench")
        assertThat(LiftFix.lifts(emptyList())).isEmpty()
    }

    @Test
    fun testLiftsNeedASessionWithinTheLast90Days() {
        val day = 86_400.0
        val old = WidFix.workout(1, at = WidFix.now.addingTimeInterval(-90 * day - 1)).withExercises(listOf(WidFix.lift("squat", listOf(WidFix.set(100.0, 5)), n = 1)))
        val edge = WidFix.workout(2, at = WidFix.now.addingTimeInterval(-90 * day)).withExercises(listOf(WidFix.lift("bench", listOf(WidFix.set(80.0, 5)), n = 2)))
        assertWithMessage("exactly 90 days ago is in, a second more is out").that(LiftFix.lifts(listOf(old, edge)).map { it.exerciseID }).containsExactly("bench")
    }

    @Test
    fun testAnOldSessionStillFeedsThePointsOfALiftThatWasTrainedRecently() {
        val history = listOf(LiftFix.session(2, "bench", daysAgo = 3.0, e1RM = 100.0), LiftFix.session(1, "bench", daysAgo = 200.0, e1RM = 90.0))
        val bench = LiftFix.lifts(history)[0]
        assertWithMessage("the points come from all of the history").that(bench.points.map { it.value }).containsExactly(90.0, 100.0).inOrder()
        assertWithMessage("but only the sessions of the last 90 days are counted").that(bench.sessionCount).isEqualTo(1)
    }

    @Test
    fun testLiftsAreRankedByTheNumberOfDistinctWorkoutsThenTheMostRecentThenTheID() {
        val history = mutableListOf<CompletedWorkout>()
        var n = 0
        fun add(id: String, daysAgo: Double) {
            n += 1
            history.add(LiftFix.session(n, id, daysAgo = daysAgo, e1RM = 100.0))
        }
        // squat 3 sessions; ohp 2 (latest 1 day ago); bench 2 (latest 1 day ago); curl 2 (latest 5 days ago); deadlift 1 (latest 1 day ago)
        add("squat", 20.0); add("squat", 10.0); add("squat", 6.0)
        add("ohp", 8.0); add("ohp", 1.0)
        add("bench", 9.0); add("bench", 1.0)
        add("curl", 12.0); add("curl", 5.0)
        add("deadlift", 1.0)
        assertWithMessage("bench and ohp tie on count and recency: the smaller id first")
            .that(LiftFix.lifts(history).map { it.exerciseID })
            .containsExactly("squat", "bench", "ohp", "curl", "deadlift")
            .inOrder()
    }

    @Test
    fun testLiftsAreLimitedToTheTopEightMostTrainedFirst() {
        val ids = listOf("bench", "incline", "crossover", "cpress", "ohp", "dbpress", "lateral", "rdelt", "curl", "dbcurl")
        val history = mutableListOf<CompletedWorkout>()
        for ((offset, id) in ids.withIndex()) {
            // The earlier ids are trained more often.
            for (repeatCount in 0 until ids.size - offset) {
                history.add(LiftFix.session(offset * 100 + repeatCount + 1, id, daysAgo = 1 + repeatCount * 3.0, e1RM = 50.0))
            }
        }
        val lifts = LiftFix.lifts(history)
        assertThat(lifts).hasSize(8)
        assertThat(lifts.map { it.exerciseID }).isEqualTo(ids.take(8))
    }

    @Test
    fun testASessionValueIsTheGreatestRecordedEstimateOfTheExerciseInThatWorkout() {
        val workout = WidFix.workout(1, daysAgo = 2.0).withExercises(
            listOf(
                WidFix.lift("bench", listOf(WidFix.set(50.0, 5)), best = 90.0, n = 1),
                WidFix.lift("bench", listOf(WidFix.set(50.0, 5)), best = 104.44, n = 2), // the same exercise twice in one workout
                WidFix.lift("squat", listOf(WidFix.set(100.0, 5)), best = 130.0, n = 3),
            ),
        )
        val bench = LiftFix.lifts(listOf(workout)).first { it.exerciseID == "bench" }
        assertThat(bench.currentE1RM).isEqualTo(104.4)
        assertWithMessage("one workout is one session").that(bench.points).hasSize(1)
        assertThat(bench.sessionCount).isEqualTo(1)
    }

    @Test
    fun testASessionValueFallsBackToTheBestEpleyEstimateOfTheNonWarmUpSetsWhenNoneWasRecorded() {
        val sets = listOf(WidFix.set(120.0, 10, SetType.WARMUP), WidFix.set(60.0, 10), WidFix.set(75.0, 6)) // 80.0 and 90.0; the warm-up would be 160
        val workout = WidFix.workout(1, daysAgo = 2.0).withExercises(listOf(WidFix.lift("bench", sets, best = 0.0, n = 1)))
        assertThat(LiftFix.lifts(listOf(workout))[0].currentE1RM).isEqualTo(90.0)
    }

    @Test
    fun testAnExerciseWithoutAnyEstimateIsNotASession() {
        val warmUpsOnly = WidFix.workout(1, daysAgo = 2.0).withExercises(listOf(WidFix.lift("bench", listOf(WidFix.set(40.0, 8, SetType.WARMUP)), best = 0.0, n = 1)))
        val noWeight = WidFix.workout(2, daysAgo = 3.0).withExercises(listOf(WidFix.lift("squat", listOf(WidFix.set(0.0, 8)), best = 0.0, n = 2)))
        assertThat(LiftFix.lifts(listOf(warmUpsOnly, noWeight))).isEmpty()
    }

    @Test
    fun testPointsAreTheLastSixSessionsOldestFirstRoundedToATenth() {
        val values = listOf(80.04, 81.26, 82.5, 83.74, 84.01, 85.96, 86.0)
        val bench = LiftFix.lifts(LiftFix.series("bench", values))[0]
        assertThat(bench.points).hasSize(6)
        assertThat(bench.points.map { it.value }).containsExactly(81.3, 82.5, 83.7, 84.0, 86.0, 86.0).inOrder()
        assertWithMessage("oldest first").that(bench.points.map { it.date }).isInOrder()
        assertThat(bench.currentE1RM).isEqualTo(86.0)
        assertThat(bench.bestE1RM).isEqualTo(86.0)
        assertWithMessage("all seven sessions are within 90 days").that(bench.sessionCount).isEqualTo(7)
    }

    @Test
    fun testDeltaIsTheLatestMinusTheOneBeforeAndZeroForOnePoint() {
        val two = LiftFix.lifts(LiftFix.series("bench", listOf(96.0, 99.2)))[0]
        assertWithMessage("rounded to a tenth: 99.2 - 96 has floating point noise").that(two.deltaKg).isEqualTo(3.2)
        val down = LiftFix.lifts(LiftFix.series("bench", listOf(99.2, 96.0)))[0]
        assertThat(down.deltaKg).isEqualTo(-3.2)
        assertThat(LiftFix.lifts(LiftFix.series("bench", listOf(90.0)))[0].deltaKg).isEqualTo(0.0)
    }

    @Test
    fun testPRIndexMarksTheBestPointWhenItBeatEveryEarlierOne() {
        assertThat(LiftFix.lifts(LiftFix.series("bench", listOf(93.0, 99.0, 96.0)))[0].prIndex).isEqualTo(1)
        assertThat(LiftFix.lifts(LiftFix.series("bench", listOf(90.0, 95.0, 100.0)))[0].prIndex).isEqualTo(2)
        assertWithMessage("the best is the first point: it beat nothing").that(LiftFix.lifts(LiftFix.series("bench", listOf(100.0, 95.0, 90.0)))[0].prIndex).isNull()
        assertWithMessage("a flat lift has no record").that(LiftFix.lifts(LiftFix.series("bench", listOf(58.4, 58.4, 58.4)))[0].prIndex).isNull()
        assertWithMessage("a single session beat nothing").that(LiftFix.lifts(LiftFix.series("bench", listOf(90.0)))[0].prIndex).isNull()
    }

    @Test
    fun testPRIndexIsTheFirstPointOfATiedBest() {
        assertWithMessage("the record was set at index 1 and matched afterwards")
            .that(LiftFix.lifts(LiftFix.series("bench", listOf(90.0, 100.0, 100.0)))[0].prIndex).isEqualTo(1)
        assertThat(LiftFix.lifts(LiftFix.series("bench", listOf(100.0, 100.0, 90.0)))[0].prIndex).isNull()
    }

    @Test
    fun testLiftNameIsTheNameFromTheNewestWorkout() {
        fun bench(name: String) = CompletedExercise(
            exerciseID = "bench", name = name, muscle = MuscleGroup.CHEST, mediaKey = null, tracking = TrackingKind.WEIGHT_REPS,
            sets = listOf(WidFix.set(80.0, 5)), isPersonalRecord = false, bestE1RM = 93.0,
        )
        val older = WidFix.workout(1, daysAgo = 9.0).withExercises(listOf(bench("Bench (old name)")))
        val newer = WidFix.workout(2, daysAgo = 2.0).withExercises(listOf(bench("Barbell bench press")))
        assertThat(LiftFix.lifts(listOf(newer, older))[0].name).isEqualTo("Barbell bench press")
        assertWithMessage("whatever the order of the history").that(LiftFix.lifts(listOf(older, newer))[0].name).isEqualTo("Barbell bench press")
    }

    @Test
    fun testSessionsOfTheSameInstantKeepTheOlderPositionOfTheHistoryFirst() {
        // Two workouts finished at the same moment; the history lists the newer one first, so the other one is the older session.
        val at = WidFix.now.addingTimeInterval(-86_400.0)
        val first = WidFix.workout(1, at = at).withExercises(listOf(WidFix.lift("bench", listOf(WidFix.set(50.0, 5)), best = 90.0, n = 1)))
        val second = WidFix.workout(2, at = at).withExercises(listOf(WidFix.lift("bench", listOf(WidFix.set(50.0, 5)), best = 100.0, n = 2)))
        assertThat(LiftFix.lifts(listOf(second, first))[0].points.map { it.value }).containsExactly(90.0, 100.0).inOrder()
    }
}

class WidgetPlateauRuleTests {
    private fun plateaus(history: List<CompletedWorkout>): List<PlateauFlag> = WidFix.snapshot(history = history).plateaus

    private fun status(values: List<Double>): PlateauFlag? = plateaus(LiftFix.series("bench", values)).firstOrNull()

    @Test
    fun testPlateausNeedAtLeastThreePoints() {
        assertThat(plateaus(LiftFix.series("bench", listOf(90.0, 95.0)))).isEmpty()
        assertThat(plateaus(emptyList())).isEmpty()
        assertThat(status(listOf(90.0, 95.0, 100.0))?.exerciseID).isEqualTo("bench")
    }

    @Test
    fun testALiftWhoseLatestPointIsANewBestIsRising() {
        val flag = status(listOf(90.0, 95.0, 100.0))
        assertThat(flag?.status).isEqualTo(TrendStatus.RISING)
        assertWithMessage("count - p: the best was set by the last point").that(flag?.flatSessions).isEqualTo(1)
        assertThat(flag?.tip).isNull()
        assertThat(flag?.name).isEqualTo("Barbell bench press")
    }

    @Test
    fun testAFirstPointThatStaysTheBestCountsAsTheNewBestOfThatPosition() {
        val flag = status(listOf(100.0, 99.0, 98.0))
        assertWithMessage("p = 0: the first point counts").that(flag?.flatSessions).isEqualTo(3)
        assertWithMessage("3 sessions and the last point within 3 % of the best").that(flag?.status).isEqualTo(TrendStatus.FLAT)
    }

    @Test
    fun testFlatNeedsThreeSessionsWithoutANewBestAndTheLastPointWithinThreePercent() {
        assertThat(status(listOf(100.0, 100.0, 100.0))?.status).isEqualTo(TrendStatus.FLAT)
        assertThat(status(listOf(100.0, 99.0, 98.0))?.status).isEqualTo(TrendStatus.FLAT)
        assertWithMessage("exactly 97 % is still flat").that(status(listOf(100.0, 100.0, 97.0))?.status).isEqualTo(TrendStatus.FLAT)
        assertWithMessage("only 2 sessions since the best and within 3 %").that(status(listOf(90.0, 100.0, 98.0))?.status).isEqualTo(TrendStatus.RISING)
    }

    @Test
    fun testFallingNeedsTwoSessionsWithoutANewBestAndTheLastPointMoreThanThreePercentBelow() {
        assertThat(status(listOf(100.0, 99.0, 96.0))?.status).isEqualTo(TrendStatus.FALLING)
        assertWithMessage("2 sessions since the best, 4 % down").that(status(listOf(90.0, 100.0, 96.0))?.status).isEqualTo(TrendStatus.FALLING)
        assertWithMessage("just under 97 %").that(status(listOf(100.0, 100.0, 96.9))?.status).isEqualTo(TrendStatus.FALLING)
        assertThat(status(listOf(90.0, 95.0, 100.0, 99.0, 95.0))?.flatSessions).isEqualTo(3)
        assertThat(status(listOf(90.0, 95.0, 100.0, 99.0, 95.0))?.status).isEqualTo(TrendStatus.FALLING)
    }

    @Test
    fun testPlateauFlatSessionsAreTheNumberOfPointsFromTheLatestNewBestToTheEnd() {
        assertThat(status(listOf(90.0, 100.0, 95.0, 96.0, 97.0, 98.0))?.flatSessions).isEqualTo(5)
        assertWithMessage("equal values are no new best, 101 is").that(status(listOf(100.0, 100.0, 100.0, 101.0))?.flatSessions).isEqualTo(1)
        assertWithMessage("p = 1: matching the best is not a new best").that(status(listOf(90.0, 100.0, 100.0, 100.0))?.flatSessions).isEqualTo(3)
    }

    @Test
    fun testOnlyTheFirstFlatLiftCarriesTheTip() {
        val history = LiftFix.series("bench", listOf(100.0, 100.0, 100.0), firstNumber = 1) +
            LiftFix.series("squat", listOf(150.0, 150.0, 150.0), firstNumber = 10) +
            LiftFix.series("ohp", listOf(60.0, 60.0, 60.0), firstNumber = 20)
        val flags = plateaus(history)
        assertThat(flags).hasSize(3)
        assertThat(flags.all { it.status == TrendStatus.FLAT }).isTrue()
        assertThat(flags.map { it.tip }).containsExactly("Try 3 × 8 at about 90% for two weeks.", null, null).inOrder()
    }

    @Test
    fun testTheTipGoesToTheFirstFlatLiftEvenWhenARisingLiftComesFirst() {
        val history = LiftFix.series("bench", listOf(90.0, 95.0, 100.0), spacing = 3.0, firstNumber = 1) +
            LiftFix.series("squat", listOf(150.0, 150.0, 150.0), firstNumber = 10) +
            LiftFix.series("ohp", listOf(60.0, 60.0, 60.0), firstNumber = 20)
        val flags = plateaus(history)
        assertThat(flags.map { it.status }).containsExactly(TrendStatus.RISING, TrendStatus.FLAT, TrendStatus.FLAT).inOrder()
        assertThat(flags.map { it.tip }).containsExactly(null, "Try 3 × 8 at about 90% for two weeks.", null).inOrder()
    }

    @Test
    fun testPlateausAreTheFirstFourLiftsWithEnoughPoints() {
        val ids = listOf("bench", "incline", "crossover", "cpress", "ohp", "dbpress")
        var history = emptyList<CompletedWorkout>()
        for ((offset, id) in ids.withIndex()) {
            history = history + LiftFix.series(id, listOf(100.0, 100.0, 100.0), spacing = 3.0, firstNumber = offset * 10 + 1)
        }
        history = history + LiftFix.series("curl", listOf(50.0, 50.0), spacing = 3.0, firstNumber = 100) // two points: skipped
        val flags = plateaus(history)
        assertThat(flags).hasSize(4)
        assertThat(flags.map { it.exerciseID }).isEqualTo(WidFix.snapshot(history = history).lifts.filter { it.points.size >= 3 }.take(4).map { it.exerciseID })
    }
}

class WidgetStrengthRatioRuleTests {
    private fun ratio(history: List<CompletedWorkout>, context: WidgetContext = WidFix.context()): StrengthRatio? =
        WidFix.snapshot(history = history, context = context).strengthRatio

    @Test
    fun testStrengthRatioIsTheFirstListedMainLift() {
        // curl is trained most, then squat, then bench: the first main lift of `lifts` is the squat.
        val history = LiftFix.series("curl", listOf(40.0, 41.0, 42.0, 43.0), firstNumber = 1) +
            LiftFix.series("squat", listOf(120.0, 125.0, 130.0), firstNumber = 10) +
            LiftFix.series("bench", listOf(90.0), firstNumber = 20)
        val result = ratio(history)
        assertThat(result?.exerciseID).isEqualTo("squat")
        assertThat(result?.exerciseName).isEqualTo("Back squat")
        assertWithMessage("its best e1RM").that(result?.estimated1RM).isEqualTo(130.0)
        assertThat(result?.goalRatio).isEqualTo(2.0)
    }

    @Test
    fun testStrengthRatioGoalsAre15For2For25And1() {
        for ((id, goal) in listOf("bench" to 1.5, "squat" to 2.0, "deadlift" to 2.5, "ohp" to 1.0)) {
            assertWithMessage(id).that(ratio(LiftFix.series(id, listOf(100.0)))?.goalRatio).isEqualTo(goal)
        }
        assertWithMessage("not a main lift").that(ratio(LiftFix.series("curl", listOf(40.0)))).isNull()
        assertThat(ratio(emptyList())).isNull()
    }

    @Test
    fun testStrengthRatioUsesTheBestEstimateOfThePoints() {
        assertThat(ratio(LiftFix.series("bench", listOf(93.0, 99.2, 96.0)))?.estimated1RM).isEqualTo(99.2)
    }

    @Test
    fun testStrengthRatioWithoutBodyweightHasNoRatio() {
        val result = ratio(LiftFix.series("bench", listOf(99.2)))
        assertThat(result?.bodyweightKg).isNull()
        assertThat(result?.ratio).isNull()
    }

    @Test
    fun testStrengthRatioIsTheEstimateOverTheBodyweightRoundedToHundredths() {
        val result = ratio(LiftFix.series("bench", listOf(99.2)), WidFix.context(bodyweightKg = 80.0))
        assertThat(result?.bodyweightKg).isEqualTo(80.0)
        assertThat(result?.ratio).isEqualTo(1.24)
        assertWithMessage("100 / 83 = 1.2048 rounds to 1.2").that(ratio(LiftFix.series("bench", listOf(100.0)), WidFix.context(bodyweightKg = 83.0))?.ratio).isEqualTo(1.2)
        assertWithMessage("100 / 70 = 1.4286").that(ratio(LiftFix.series("bench", listOf(100.0)), WidFix.context(bodyweightKg = 70.0))?.ratio).isEqualTo(1.43)
    }

    @Test
    fun testABodyweightThatIsNotAboveZeroCountsAsUnknown() {
        for (bad in listOf(0.0, -5.0, Double.NaN, Double.POSITIVE_INFINITY)) {
            val result = ratio(LiftFix.series("bench", listOf(99.2)), WidFix.context(bodyweightKg = bad))
            assertWithMessage("$bad").that(result?.ratio).isNull()
            assertWithMessage("$bad").that(result?.bodyweightKg).isNull()
        }
    }
}

class WidgetBlockRuleTests {
    private val push = WidFix.template(1, "Upper A · Push")
    private val pull = WidFix.template(2, "Upper B · Pull")

    private fun block(history: List<CompletedWorkout>, templates: List<WorkoutTemplate>? = null, context: WidgetContext = WidFix.context()): TrainingBlock? =
        WidFix.snapshot(StrengthData(templates = templates ?: listOf(push, pull), history = history), context).block

    private fun done(n: Int, name: String, templateID: UUID?, date: Instant): CompletedWorkout = WidFix.workout(n, name, at = date, templateID = templateID)

    @Test
    fun testBlockIsNullWithoutHistory() {
        assertThat(block(emptyList())).isNull()
    }

    @Test
    fun testBlockIsCountedInFourWeeksFromTheWeekOfTheFirstWorkout() {
        // The first workout was on Monday 21 September: 3 whole weeks before this week's Monday (12 October).
        val result = block(listOf(done(1, "Upper A · Push", push.id, WidFix.date(2026, 9, 21, 9, 0))))
        assertThat(result?.name).isEqualTo("Block 1")
        assertThat(result?.weekIndex).isEqualTo(4)
        assertThat(result?.weekCount).isEqualTo(4)
    }

    @Test
    fun testBlockNumberAndWeekIndexAdvanceEveryFourWeeks() {
        val expectations = listOf(
            Triple(WidFix.date(2026, 10, 14, 9, 0), "Block 1", 1), // n = 0: this very week
            Triple(WidFix.date(2026, 10, 6, 9, 0), "Block 1", 2), // n = 1
            Triple(WidFix.date(2026, 9, 30, 9, 0), "Block 1", 3), // n = 2
            Triple(WidFix.date(2026, 9, 21, 9, 0), "Block 1", 4), // n = 3
            Triple(WidFix.date(2026, 9, 14, 9, 0), "Block 2", 1), // n = 4
            Triple(WidFix.date(2026, 8, 24, 9, 0), "Block 2", 4), // n = 7
            Triple(WidFix.date(2026, 8, 17, 9, 0), "Block 3", 1), // n = 8
        )
        for ((first, name, week) in expectations) {
            val result = block(listOf(done(1, "Upper A · Push", push.id, first)))
            assertWithMessage("$first").that(result?.name).isEqualTo(name)
            assertWithMessage("$first").that(result?.weekIndex).isEqualTo(week)
        }
    }

    @Test
    fun testBlockRowsAreTheFirstFourTemplatesLabelledWithTheTextAfterTheDot() {
        val templates = listOf(push, pull, WidFix.template(3, "Lower A · Quads"), WidFix.template(4, "Cardio"), WidFix.template(5, "Fifth · Ignored"))
        val result = block(listOf(done(1, "Upper A · Push", push.id, WidFix.date(2026, 10, 14, 9, 0))), templates)
        assertThat(result?.rows?.map { it.label }).containsExactly("Push", "Pull", "Quads", "Cardio").inOrder()
        assertThat(result?.rows?.map { it.cells.size }).containsExactly(4, 4, 4, 4).inOrder()
    }

    @Test
    fun testBlockCellsAreDoneMissedPlannedOrUpcoming() {
        // Block 1, week 4 (first workout Monday 21 September). Weeks: 21-27 Sep, 28 Sep - 4 Oct, 5-11 Oct, 12-18 Oct (now).
        val history = listOf(
            done(5, "Upper B · Pull", pull.id, WidFix.date(2026, 10, 13, 9, 0)), // week 4: Pull done
            done(4, "Upper A · Push", null, WidFix.date(2026, 10, 1, 9, 0)), // week 2: no template id: matched by name
            done(3, "Upper B · Pull", pull.id, WidFix.date(2026, 9, 24, 9, 0)), // week 1: Pull done
            done(2, "Upper A · Push", push.id, WidFix.date(2026, 9, 22, 9, 0)), // week 1: Push done
        )
        val result = block(history)!!
        fun states(row: Int): List<BlockCellState> = result.rows[row].cells.map { it.state }
        assertWithMessage("Push: weeks 1 and 2 done, week 3 missed, the current week planned")
            .that(states(0))
            .containsExactly(BlockCellState.DONE, BlockCellState.DONE, BlockCellState.MISSED, BlockCellState.PLANNED)
            .inOrder()
        assertWithMessage("Pull")
            .that(states(1))
            .containsExactly(BlockCellState.DONE, BlockCellState.MISSED, BlockCellState.MISSED, BlockCellState.DONE)
            .inOrder()
        assertThat(result.sessionsDone).isEqualTo(4)
        assertWithMessage("goal 4 x 4 weeks so far").that(result.sessionsPlanned).isEqualTo(16)
        assertThat(result.sessionsMissed).isEqualTo(3)
    }

    @Test
    fun testBlockCellsAfterTheCurrentWeekAreUpcoming() {
        val result = block(listOf(done(1, "Upper A · Push", push.id, WidFix.date(2026, 10, 14, 9, 0))))!!
        assertThat(result.weekIndex).isEqualTo(1)
        assertThat(result.rows[0].cells.map { it.state })
            .containsExactly(BlockCellState.DONE, BlockCellState.UPCOMING, BlockCellState.UPCOMING, BlockCellState.UPCOMING).inOrder()
        assertThat(result.rows[1].cells.map { it.state })
            .containsExactly(BlockCellState.PLANNED, BlockCellState.UPCOMING, BlockCellState.UPCOMING, BlockCellState.UPCOMING).inOrder()
        assertThat(result.sessionsPlanned).isEqualTo(4)
        assertThat(result.sessionsMissed).isEqualTo(0)
    }

    @Test
    fun testAWorkoutWithATemplateIDOnlyCountsForThatTemplateEvenWhenTheNameMatches() {
        val result = block(listOf(done(1, "Upper A · Push", WidFix.uuid(9_999), WidFix.date(2026, 10, 14, 9, 0))))
        assertWithMessage("the id names another template").that(result?.rows?.get(0)?.cells?.first()?.state).isEqualTo(BlockCellState.PLANNED)
        assertWithMessage("the workout still counts toward the block").that(result?.sessionsDone).isEqualTo(1)
    }

    @Test
    fun testBlockSessionsDoneCountTheWorkoutsFromTheMondayTheBlockBegan() {
        // The first workout was on Monday 14 September: n = 4, so block 2 begins on Monday 12 October, this very week.
        val history = listOf(
            done(4, "Upper A · Push", push.id, WidFix.date(2026, 10, 13, 9, 0)),
            done(3, "Upper A · Push", push.id, WidFix.date(2026, 10, 12, 0, 0, 0)), // Monday 00:00:00: in the block
            done(2, "Upper A · Push", push.id, WidFix.date(2026, 10, 11, 23, 59, 59)), // the Sunday before: not in it
            done(1, "Upper A · Push", push.id, WidFix.date(2026, 9, 14, 9, 0)),
        )
        val result = block(history)
        assertThat(result?.name).isEqualTo("Block 2")
        assertThat(result?.weekIndex).isEqualTo(1)
        assertThat(result?.sessionsDone).isEqualTo(2)
        assertThat(result?.sessionsPlanned).isEqualTo(4)
    }

    @Test
    fun testBlockSessionsPlannedUseTheWeeklyGoalOfTheContext() {
        val result = block(listOf(done(1, "Upper A · Push", push.id, WidFix.date(2026, 9, 21, 9, 0))), context = WidFix.context(goal = 3))
        assertWithMessage("3 per week x 4 weeks").that(result?.sessionsPlanned).isEqualTo(12)
    }

    @Test
    fun testBlockWithoutTemplatesHasNoRowsButStillCountsSessions() {
        val result = block(listOf(done(1, "Upper A · Push", null, WidFix.date(2026, 10, 14, 9, 0))), templates = emptyList())
        assertThat(result?.rows).isEmpty()
        assertThat(result?.sessionsDone).isEqualTo(1)
        assertThat(result?.sessionsMissed).isEqualTo(0)
    }

    @Test
    fun testBlockOfAHistoryInTheFutureStartsAtWeekOne() {
        val result = block(listOf(done(1, "Upper A · Push", push.id, WidFix.date(2026, 12, 1, 9, 0))))
        assertThat(result?.name).isEqualTo("Block 1")
        assertThat(result?.weekIndex).isEqualTo(1)
    }

    // region The lift of the block

    private fun bench(n: Int, date: Instant, value: Double): CompletedWorkout =
        WidFix.workout(n, at = date).withExercises(listOf(WidFix.lift("bench", listOf(WidFix.set(50.0, 5)), best = value, n = n)))

    @Test
    fun testBlockLiftChangeRunsFromTheLastSessionBeforeTheBlockToTheLatest() {
        // First workout Monday 24 August: block 2 began on Monday 21 September, this is its week 4.
        val history = listOf(
            done(1, "Upper A · Push", push.id, WidFix.date(2026, 8, 24, 9, 0)),
            bench(10, WidFix.date(2026, 9, 3, 9, 0), 88.0),
            bench(11, WidFix.date(2026, 9, 17, 9, 0), 90.0), // the last session before the block
            bench(12, WidFix.date(2026, 9, 23, 9, 0), 92.0),
            bench(13, WidFix.date(2026, 10, 14, 9, 0), 96.2),
        )
        val result = block(history)
        assertThat(result?.name).isEqualTo("Block 2")
        assertThat(result?.liftName).isEqualTo("Barbell bench press")
        assertThat(result?.liftDeltaKg).isEqualTo(6.2)
    }

    @Test
    fun testBlockLiftChangeStartsAtTheFirstSessionInsideTheBlockWhenNoneCameBefore() {
        val history = listOf(
            done(1, "Upper A · Push", push.id, WidFix.date(2026, 8, 24, 9, 0)),
            bench(12, WidFix.date(2026, 9, 23, 9, 0), 92.0),
            bench(13, WidFix.date(2026, 10, 14, 9, 0), 96.2),
        )
        assertThat(block(history)?.liftDeltaKg).isEqualTo(4.2)
    }

    @Test
    fun testBlockLiftIsNullForALiftWithFewerThanTwoSessionsOrWithoutLifts() {
        val first = done(1, "Upper A · Push", push.id, WidFix.date(2026, 8, 24, 9, 0))
        assertWithMessage("no lift at all").that(block(listOf(first))?.liftName).isNull()
        assertThat(block(listOf(first))?.liftDeltaKg).isNull()
        val withOne = listOf(first, WidFix.workout(2, at = WidFix.date(2026, 10, 14, 9, 0)).withExercises(listOf(WidFix.lift("bench", listOf(WidFix.set(80.0, 5)), n = 2))))
        assertWithMessage("one session").that(block(withOne)?.liftName).isNull()
        assertThat(block(withOne)?.liftDeltaKg).isNull()
    }

    @Test
    fun testBlockLiftIsTheFirstOfTheListedLifts() {
        val history = listOf(done(1, "Upper A · Push", push.id, WidFix.date(2026, 9, 21, 9, 0))) +
            LiftFix.series("squat", listOf(100.0, 110.0), newest = 2.0, spacing = 4.0, firstNumber = 20) +
            LiftFix.series("bench", listOf(90.0, 95.0, 99.0), newest = 1.0, spacing = 3.0, firstNumber = 30)
        assertWithMessage("bench was trained in more workouts").that(block(history)?.liftName).isEqualTo("Barbell bench press")
    }

    // endregion
}
