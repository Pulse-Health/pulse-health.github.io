package health.pulse.strength.core.widgets

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.CompletedSet
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.HeartRateSample
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.MuscleSets
import health.pulse.strength.core.SampleData
import health.pulse.strength.core.SetType
import health.pulse.strength.core.SnapshotBuilder
import health.pulse.strength.core.StrengthData
import health.pulse.strength.core.WorkoutFactory
import health.pulse.strength.core.WorkoutState
import java.time.Instant
import org.junit.Test

/**
 * The builder as a whole (widgets/SPEC.md section 2): the demo data, an empty store, the goal and body weight inputs, what is copied from
 * the context, and the JSON the snapshot makes.
 */
class WidgetSnapshotBuilderTests {
    private val utc = WidFix.context()

    private fun demo(context: WidgetContext = utc): WidgetSnapshot = WidFix.snapshot(StrengthData.demo(WidFix.now), context)

    // region The demo data

    @Test
    fun testTheDemoDataGivesTheNumbersOfTheRules() {
        val snapshot = demo()
        assertThat(snapshot.schemaVersion).isEqualTo(WidgetSnapshot.CURRENT_SCHEMA_VERSION)
        assertThat(snapshot.generatedAt).isEqualTo(WidFix.now)
        assertThat(snapshot.timeZoneID).isEqualTo("UTC")

        // Friday 16 October: one workout this week (Upper B on Tuesday), three days since it, the week before had three workouts.
        assertThat(snapshot.week.completed).isEqualTo(1)
        assertThat(snapshot.week.goal).isEqualTo(4)
        assertThat(snapshot.week.days.map { it.label }).containsExactly(null, "UB", null, null, null, null, null).inOrder()
        assertThat(snapshot.week.daysSinceLastWorkout).isEqualTo(3)
        assertWithMessage("last week had 3 of 4").that(snapshot.week.streakWeeks).isEqualTo(0)

        // After Upper B (3 days ago) comes Upper A.
        assertThat(snapshot.nextUp?.name).isEqualTo("Upper A · Push")
        assertThat(snapshot.nextUp?.daysSince).isEqualTo(5)
        assertThat(snapshot.templates.map { it.isSuggested }).containsExactly(true, false, false).inOrder()
        assertThat(snapshot.lastSession?.name).isEqualTo("Upper B · Pull")
        assertThat(snapshot.lastSession?.durationMinutes).isEqualTo(52)

        // The one record of the demo: bench, 85 x 5 ten days ago.
        val pr = snapshot.latestPR!!
        assertThat(pr.exerciseID).isEqualTo("bench")
        assertThat(pr.estimated1RM).isWithin(1e-9).of(85 * (1 + 5.0 / 30))
        assertThat(pr.deltaKg).isWithin(1e-9).of(85 * (1 + 5.0 / 30) - 95)
        assertThat(pr.isFresh).isFalse()

        // Bench last time: 80 x 6, so 82.5 x 6 today.
        assertThat(snapshot.overload?.lastWeightKg).isEqualTo(80.0)
        assertThat(snapshot.overload?.targetWeightKg).isEqualTo(82.5)
        assertThat(snapshot.overload?.targetSets).isEqualTo(3)

        assertThat(snapshot.freshness.map { it.daysSince }).containsExactly(5, 3, 3, 3, 7, null).inOrder()
        assertThat(snapshot.freshness.map { it.status })
            .containsExactly(
                FreshnessStatus.READY, FreshnessStatus.RECOVERING, FreshnessStatus.RECOVERING, FreshnessStatus.RECOVERING,
                FreshnessStatus.READY, FreshnessStatus.READY,
            ).inOrder()
        assertThat(snapshot.weeklySets.totalSets).isEqualTo(15)
        assertThat(snapshot.weeklySets.laggingMuscle).isEqualTo(MuscleGroup.CHEST)
        assertThat(snapshot.month.title).isEqualTo("October")
        assertThat(snapshot.month.leadingBlankDays).isEqualTo(3)
        assertThat(snapshot.month.sessionCount).isEqualTo(5)
        assertThat(snapshot.year.sessionCount).isEqualTo(5)
        assertThat(snapshot.year.tonnes).isEqualTo(31.9)
        assertThat(snapshot.block?.name).isEqualTo("Block 1")
        assertThat(snapshot.block?.weekIndex).isEqualTo(3)
        assertThat(snapshot.formCue?.exerciseID).isEqualTo("bench")
        assertThat(snapshot.loadedBar?.summary).isEqualTo("25 + 5 + 2.5")
        assertWithMessage("one workout this week and none yesterday").that(snapshot.restDay).isNull()
        assertThat(snapshot.tomorrow?.plannedMinuteOfDay).isEqualTo(530)
        assertThat(snapshot.tomorrow?.weekday).isEqualTo("Saturday")
        assertThat(snapshot.bodyMap.message).isEqualTo("Chest untouched. Upper A is next in line.")
    }

    @Test
    fun testTheDemoLiftsAndPlateausFollowTheRules() {
        val snapshot = demo()
        assertThat(snapshot.lifts.map { it.exerciseID })
            .containsExactly("bench", "crossover", "incline", "lateral", "ohp", "pushdown", "brow", "crow").inOrder()
        val bench = snapshot.lifts[0]
        assertThat(bench.points.map { it.value }).containsExactly(93.0, 99.2, 96.0).inOrder()
        assertThat(bench.prIndex).isEqualTo(1)
        assertThat(bench.deltaKg).isEqualTo(-3.2)
        assertThat(bench.sessionCount).isEqualTo(3)
        assertThat(snapshot.lifts[6].sessionCount).isEqualTo(1)
        assertThat(snapshot.lifts[6].prIndex).isNull()
        assertThat(snapshot.plateaus.map { it.exerciseID }).containsExactly("bench", "crossover", "incline", "lateral").inOrder()
        assertThat(snapshot.plateaus.map { it.status }).isEqualTo(List(4) { TrendStatus.FALLING })
        assertThat(snapshot.strengthRatio?.exerciseID).isEqualTo("bench")
        assertWithMessage("the demo data has no body weight").that(snapshot.strengthRatio?.ratio).isNull()
    }

    @Test
    fun testTheDemoSnapshotSurvivesTheJSONEncoding() {
        val snapshot = demo()
        assertThat(WidgetJson.decodeSnapshot(WidgetJson.encodeSnapshot(snapshot))).isEqualTo(snapshot)
    }

    @Test
    fun testTheSnapshotIsAPureFunctionOfItsInput() {
        val data = StrengthData.demo(WidFix.now)
        assertThat(WidFix.snapshot(data)).isEqualTo(WidFix.snapshot(data))
    }

    @Test
    fun testTheOrderOfTheHistoryDoesNotMatterWhenAllFinishTimesDiffer() {
        // The history is newest first by contract; a shuffled list gives the same snapshot because every rule orders by finishedAt.
        val data = StrengthData.demo(WidFix.now)
        val shuffled = data.copy(history = listOf(data.history[2], data.history[0], data.history[4], data.history[1], data.history[3]))
        assertThat(WidFix.snapshot(shuffled)).isEqualTo(WidFix.snapshot(data))
    }

    // endregion

    // region An empty store

    @Test
    fun testAnEmptyStoreGivesAnEmptyButCompleteSnapshot() {
        val snapshot = WidFix.snapshot(StrengthData())
        assertThat(snapshot.week.days).hasSize(7)
        assertThat(snapshot.week.completed).isEqualTo(0)
        assertThat(snapshot.week.streakWeeks).isEqualTo(0)
        assertThat(snapshot.week.lastWorkoutAt).isNull()
        assertThat(snapshot.week.daysSinceLastWorkout).isNull()
        assertThat(snapshot.nextUp).isNull()
        assertThat(snapshot.templates).isEmpty()
        assertThat(snapshot.lastSession).isNull()
        assertThat(snapshot.latestPR).isNull()
        assertThat(snapshot.overload).isNull()
        assertThat(snapshot.freshness.map { it.muscle }).isEqualTo(MuscleGroup.entries.toList())
        assertThat(snapshot.freshness.all { it.daysSince == null && it.status == FreshnessStatus.READY }).isTrue()
        assertThat(snapshot.weeklySets.muscles).hasSize(6)
        assertThat(snapshot.weeklySets.totalSets).isEqualTo(0)
        assertThat(snapshot.weeklySets.setsToGo).isEqualTo(48)
        assertThat(snapshot.lifts).isEmpty()
        assertThat(snapshot.month.days).hasSize(31)
        assertThat(snapshot.plateaus).isEmpty()
        assertThat(snapshot.year.monthlyTonnes).isEqualTo(List(12) { 0.0 })
        assertThat(snapshot.block).isNull()
        assertThat(snapshot.formCue).isNull()
        assertThat(snapshot.loadedBar).isNull()
        assertThat(snapshot.strengthRatio).isNull()
        assertThat(snapshot.restDay).isNull()
        assertThat(snapshot.tomorrow).isNull()
        assertThat(snapshot.bodyMap.levels).hasSize(6)
        assertThat(snapshot.bodyMap.untouched).isEqualTo(MuscleGroup.entries.toList())
        assertThat(snapshot.bodyMap.message).isEqualTo("Chest untouched.")
        assertThat(snapshot.readiness).isNull()
        assertThat(snapshot.partners).isEmpty()
        assertThat(snapshot.active).isNull()
    }

    @Test
    fun testTheEmptySnapshotHelperIsTheBuilderOnNoData() {
        val context = WidFix.context("Europe/Berlin", goal = 5)
        assertThat(WidgetSnapshot.empty(WidFix.now, context)).isEqualTo(WidFix.snapshot(StrengthData(), context))
        assertThat(WidgetSnapshot.empty(WidFix.now, context).week.goal).isEqualTo(5)
        assertThat(WidgetSnapshot.empty(WidFix.now).week.goal).isEqualTo(4)
    }

    @Test
    fun testTheEmptySnapshotSurvivesTheJSONEncoding() {
        val snapshot = WidgetSnapshot.empty(WidFix.now, utc)
        assertThat(WidgetJson.decodeSnapshot(WidgetJson.encodeSnapshot(snapshot))).isEqualTo(snapshot)
    }

    @Test
    fun testAStoreOfTemplatesOnlyHasANextUpButNoHistoryCards() {
        val template = WidFix.template(1, "Upper A · Push", listOf(WidFix.entry("bench", WidFix.planned(3, 80.0, 6))))
        val snapshot = WidFix.snapshot(StrengthData(templates = listOf(template)))
        assertThat(snapshot.nextUp?.name).isEqualTo("Upper A · Push")
        assertThat(snapshot.nextUp?.daysSince).isNull()
        assertThat(snapshot.lastSession).isNull()
        assertWithMessage("no history").that(snapshot.overload).isNull()
        assertThat(snapshot.block).isNull()
        assertThat(snapshot.formCue).isNotNull()
        assertThat(snapshot.loadedBar?.totalKg).isEqualTo(80.0)
        assertThat(snapshot.tomorrow?.templateName).isEqualTo("Upper A · Push")
        assertThat(snapshot.tomorrow?.plannedMinuteOfDay).isNull()
    }

    @Test
    fun testAStoreWithoutWeightExercisesHasNoLiftCards() {
        val bodyweight = WidFix.template(
            1, "Calisthenics",
            listOf(WidFix.entry("pushup", WidFix.planned(3, 0.0, 12)), WidFix.entry("plank", WidFix.planned(3, 0.0, 45))),
        )
        val history = listOf(
            WidFix.workout(1, "Calisthenics", daysAgo = 2.0)
                .withExercises(listOf(WidFix.lift("pushup", listOf(WidFix.set(0.0, 12)), n = 1), WidFix.lift("plank", listOf(WidFix.set(0.0, 45)), n = 2))),
        )
        val snapshot = WidFix.snapshot(StrengthData(templates = listOf(bodyweight), history = history))
        assertThat(snapshot.lifts).isEmpty()
        assertThat(snapshot.plateaus).isEmpty()
        assertThat(snapshot.overload).isNull()
        assertThat(snapshot.loadedBar).isNull()
        assertThat(snapshot.strengthRatio).isNull()
        assertThat(snapshot.block?.liftName).isNull()
        assertWithMessage("cues still work").that(snapshot.formCue?.exerciseID).isEqualTo("pushup")
        assertThat(snapshot.nextUp).isNotNull()
        assertThat(snapshot.nextUp?.exercises?.map { it.summary }).containsExactly("3 × 12", "3 × 45 s").inOrder()
    }

    // endregion

    // region The weekly goal

    @Test
    fun testTheGoalIsTheContextsWeeklyGoalBroughtIntoOneToSeven() {
        assertThat(WidFix.snapshot(StrengthData(), WidFix.context(goal = 5)).week.goal).isEqualTo(5)
        assertThat(WidFix.snapshot(StrengthData(), WidFix.context(goal = 0)).week.goal).isEqualTo(1)
        assertThat(WidFix.snapshot(StrengthData(), WidFix.context(goal = 12)).week.goal).isEqualTo(7)
        assertThat(WidFix.snapshot(StrengthData(), WidFix.context(goal = Int.MIN_VALUE)).week.goal).isEqualTo(1)
        assertWithMessage("the default").that(WidFix.snapshot(StrengthData()).week.goal).isEqualTo(4)
        assertThat(WidgetContext().weeklyGoal).isEqualTo(WidgetContext.defaultWeeklyGoal)
    }

    @Test
    fun testTheGoalDecidesTheStreakAndTheRestDay() {
        // Two workouts in each of the last three weeks (Tuesday and Wednesday); nothing yesterday (Thursday), now Friday.
        val history = mutableListOf<CompletedWorkout>()
        for (week in 0 until 3) {
            for (day in listOf(13, 14)) {
                history.add(WidFix.workout(history.size + 1, at = WidFix.date(2026, 10, day, 9, 0).minusSeconds(week * 7 * 86_400L)))
            }
        }
        val data = StrengthData(history = history)
        assertThat(WidFix.snapshot(data, WidFix.context(goal = 2)).week.streakWeeks).isEqualTo(3)
        assertWithMessage("2 of 2: a rest day").that(WidFix.snapshot(data, WidFix.context(goal = 2)).restDay).isNotNull()
        assertThat(WidFix.snapshot(data, WidFix.context(goal = 3)).week.streakWeeks).isEqualTo(0)
        assertThat(WidFix.snapshot(data, WidFix.context(goal = 3)).restDay).isNull()
    }

    // endregion

    // region Copied from the context

    @Test
    fun testReadinessPartnersAndTheRunningWorkoutAreCopiedFromTheContext() {
        val readiness = ReadinessSummary(score = 82, label = "Ready", message = "Good sleep.", source = "Pulse")
        val partners = listOf(PartnerWeek(name = "Sam", initials = "S", completed = 4, goal = 4, closedWeek = true))
        val state = WorkoutFactory.makeWorkout(SampleData.templates(WidFix.now)[0], WidFix.now)
        val active = SnapshotBuilder.make(state, WidFix.now)
        val context = WidFix.context().copy(readiness = readiness, partners = partners, active = active)
        val snapshot = WidFix.snapshot(StrengthData(), context)
        assertThat(snapshot.readiness).isEqualTo(readiness)
        assertThat(snapshot.partners).isEqualTo(partners)
        assertThat(snapshot.active).isEqualTo(active)
    }

    @Test
    fun testTheBodyWeightComesFromTheContextOnly() {
        val history = listOf(1 to 96.0, 2 to 99.2, 3 to 93.0).map { (offset, value) ->
            WidFix.workout(offset, daysAgo = offset * 4.0).withExercises(listOf(WidFix.lift("bench", listOf(WidFix.set(50.0, 5)), best = value, n = offset)))
        }
        val data = StrengthData(history = history)
        assertThat(WidFix.snapshot(data, WidFix.context(bodyweightKg = 80.0)).strengthRatio?.bodyweightKg).isEqualTo(80.0)
        assertThat(WidFix.snapshot(data, WidFix.context(bodyweightKg = 80.0)).strengthRatio?.ratio).isEqualTo(1.24)
        assertThat(WidFix.snapshot(data, WidFix.context(bodyweightKg = 90.0)).strengthRatio?.bodyweightKg).isEqualTo(90.0)
        assertWithMessage("the Android store keeps no weigh-ins").that(WidFix.snapshot(data).strengthRatio?.bodyweightKg).isNull()
    }

    // endregion

    // region What a host asks of the builder

    @Test
    fun testNextTemplateIsTheTemplateOfNextUp() {
        val data = StrengthData.demo(WidFix.now)
        assertThat(WidgetSnapshotBuilder.nextTemplate(data.templates)?.id?.toString()).isEqualTo(demo().nextUp?.templateID)
        assertThat(WidgetSnapshotBuilder.nextTemplate(emptyList())).isNull()

        // The rotation wraps around: after the last template comes the first.
        val templates = listOf(1, 2, 3).map { WidFix.template(it, "Day $it", last = if (it == 3) WidFix.now else null) }
        assertThat(WidgetSnapshotBuilder.nextTemplate(templates)).isEqualTo(templates[0])
        assertThat(WidFix.snapshot(StrengthData(templates = templates)).nextUp?.templateID).isEqualTo(templates[0].id.toString())
    }

    @Test
    fun testTwoSnapshotsOfTheSameDataHaveTheSameContentWhateverTheTimeStamp() {
        val data = StrengthData.demo(WidFix.now)
        val earlier = WidFix.snapshot(data)
        val later = WidFix.snapshot(data, now = WidFix.now.plusSeconds(3_600))
        assertThat(later.generatedAt).isNotEqualTo(earlier.generatedAt)
        assertThat(earlier.hasSameContentAs(later)).isTrue()
        assertThat(later.hasSameContentAs(earlier)).isTrue()
        assertThat(earlier.hasSameContentAs(earlier)).isTrue()
    }

    @Test
    fun testAnotherDayOrAnotherGoalIsAnotherContent() {
        val data = StrengthData.demo(WidFix.now)
        val snapshot = WidFix.snapshot(data)
        assertThat(snapshot.hasSameContentAs(WidFix.snapshot(data, now = WidFix.now.plusSeconds(86_400)))).isFalse()
        assertThat(snapshot.hasSameContentAs(WidFix.snapshot(data, WidFix.context(goal = 5)))).isFalse()
        assertThat(snapshot.hasSameContentAs(WidFix.snapshot(data, WidFix.context("Pacific/Auckland")))).isFalse()
        assertThat(snapshot.hasSameContentAs(WidFix.snapshot(StrengthData()))).isFalse()
    }

    @Test
    fun testTheRunningWorkoutsRevisionIsNotContentButItsStateIs() {
        val state = WorkoutFactory.makeWorkout(SampleData.templates(WidFix.now)[0], WidFix.now)
        fun snapshot(workout: WorkoutState?): WidgetSnapshot =
            WidFix.snapshot(StrengthData(), WidFix.context().copy(active = workout?.let { SnapshotBuilder.make(it, WidFix.now) }))

        val running = snapshot(state)
        assertThat(running.hasSameContentAs(snapshot(state.copy(revision = state.revision + 7)))).isTrue()
        assertThat(running.hasSameContentAs(snapshot(state.copy(name = "Renamed")))).isFalse()
        assertThat(running.hasSameContentAs(snapshot(null))).isFalse()
        assertThat(snapshot(null).hasSameContentAs(running)).isFalse()
    }

    // endregion

    // region Damaged files

    @Test
    fun testValuesFromADamagedFileNeverCrashTheBuilder() {
        val broken = CompletedSet(SetType.NORMAL, Double.POSITIVE_INFINITY, Int.MAX_VALUE, Int.MIN_VALUE, Instant.MAX)
        val samples = (0 until 20).map { HeartRateSample(if (it % 2 == 0) Int.MAX_VALUE else Int.MIN_VALUE, WidFix.now) }
        val workouts = listOf(
            WidFix.workout(1, at = Instant.MIN, durationSeconds = Int.MAX_VALUE, volumeKg = Double.NaN, startedAt = Instant.MIN).withExercises(
                listOf(WidFix.lift("bench", listOf(broken, WidFix.set(Double.NaN, 5), WidFix.set(80.0, 6, at = Instant.MAX)), best = Double.POSITIVE_INFINITY, n = 1)),
            ),
            WidFix.workout(2, at = Instant.MAX, durationSeconds = Int.MIN_VALUE, volumeKg = Double.POSITIVE_INFINITY, heartRate = samples, startedAt = Instant.MAX),
            WidFix.workout(3, at = Instant.EPOCH, durationSeconds = 0, volumeKg = -5.0),
            WidFix.workout(4, at = Instant.ofEpochSecond(-999_999_999_999_999L)),
            WidFix.workout(5, at = Instant.ofEpochSecond(1_000_000_000_000_000L)),
        )
        val template = WidFix.template(1, "Upper A · Push", listOf(WidFix.entry("bench", WidFix.planned(3, 80.0, 6))), last = Instant.MIN)
        val snapshot = WidFix.snapshot(StrengthData(templates = listOf(template), history = workouts))
        assertThat(snapshot.week.days).hasSize(7)
        assertThat(snapshot.month.days).hasSize(31)
        assertThat(snapshot.year.monthlyTonnes).hasSize(12)
        assertThat(snapshot.freshness).hasSize(6)
    }

    // endregion

    // region A big history

    @Test
    fun testAHistoryOfThousandsOfWorkoutsIsBuiltQuickly() {
        // A workout every day and a half for twelve years: every week has four or five, so with a goal of 2 the streak hits its cap.
        val history = (0 until 3_000).map { index ->
            WidFix.workout(index + 1, "Upper A · Push", daysAgo = index * 1.5, volumeKg = 5_000.0)
                .withExercises(
                    listOf(
                        WidFix.lift("bench", listOf(WidFix.set(60.0 + index % 20, 5), WidFix.set(70.0, 5, SetType.WARMUP)), n = 1),
                        WidFix.lift("squat", listOf(WidFix.set(80.0 + index % 10, 5)), n = 2),
                    ),
                )
                .withMuscles(listOf(MuscleSets(MuscleGroup.CHEST, 3), MuscleSets(MuscleGroup.LEGS, 3)))
        }
        val templates = listOf(
            WidFix.template(1, "Upper A · Push", listOf(WidFix.entry("bench", WidFix.planned(3, 82.5, 5)))),
            WidFix.template(2, "Lower", listOf(WidFix.entry("squat", WidFix.planned(3, 100.0, 5)))),
        )
        val started = System.nanoTime()
        val snapshot = WidFix.snapshot(StrengthData(templates = templates, history = history), WidFix.context(goal = 2))
        assertThat((System.nanoTime() - started) / 1e9).isLessThan(20.0)
        assertThat(snapshot.week.streakWeeks).isEqualTo(520)
        assertThat(snapshot.lifts.map { it.exerciseID }).containsExactly("bench", "squat").inOrder()
        assertThat(snapshot.year.sessionCount).isEqualTo(history.count { !it.finishedAt.isBefore(WidFix.date(2026, 1, 1)) })
        assertThat(snapshot.lastSession?.workoutID).isEqualTo(history[0].id.toString())
    }

    // endregion
}
