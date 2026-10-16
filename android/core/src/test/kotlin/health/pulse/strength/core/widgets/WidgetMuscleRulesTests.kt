package health.pulse.strength.core.widgets

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.MuscleSets
import health.pulse.strength.core.PlannedSet
import health.pulse.strength.core.SetType
import health.pulse.strength.core.StrengthData
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.core.addingTimeInterval
import org.junit.Test

/** widgets/SPEC.md section 2: freshness, weeklySets and bodyMap. `WidFix.now` is Friday 2026-10-16 09:41 UTC. */
class WidgetFreshnessRuleTests {
    private fun freshness(history: List<CompletedWorkout>): List<MuscleFreshness> = WidFix.snapshot(history = history).freshness

    private fun chest(sets: Int = 3): List<MuscleSets> = listOf(MuscleSets(MuscleGroup.CHEST, sets))

    @Test
    fun testFreshnessHasAllSixGroupsInMuscleGroupOrder() {
        val result = freshness(emptyList())
        assertThat(result.map { it.muscle })
            .containsExactly(MuscleGroup.CHEST, MuscleGroup.BACK, MuscleGroup.SHOULDERS, MuscleGroup.ARMS, MuscleGroup.LEGS, MuscleGroup.CORE)
            .inOrder()
        assertWithMessage("never trained: ready").that(result.all { it.daysSince == null && it.status == FreshnessStatus.READY }).isTrue()
    }

    @Test
    fun testFreshnessDaysSinceComesFromTheLatestWorkoutThatTrainedTheGroup() {
        val history = listOf(
            WidFix.workout(3, "Upper B · Pull", daysAgo = 3.0).withMuscles(listOf(MuscleSets(MuscleGroup.BACK, 12), MuscleSets(MuscleGroup.ARMS, 3))),
            WidFix.workout(2, "Upper A · Push", daysAgo = 5.0).withMuscles(listOf(MuscleSets(MuscleGroup.CHEST, 9), MuscleSets(MuscleGroup.SHOULDERS, 6))),
            WidFix.workout(1, "Lower A · Quads", daysAgo = 7.0).withMuscles(listOf(MuscleSets(MuscleGroup.LEGS, 12))),
        )
        assertThat(freshness(history).map { it.daysSince }).containsExactly(5, 3, 5, 3, 7, null).inOrder()
        assertWithMessage("whatever the order of the history").that(freshness(history.reversed()).map { it.daysSince }).containsExactly(5, 3, 5, 3, 7, null).inOrder()
    }

    @Test
    fun testFreshnessUsesTheNewestWorkoutOfTheGroup() {
        val history = listOf(
            WidFix.workout(1, daysAgo = 9.0).withMuscles(chest()),
            WidFix.workout(2, daysAgo = 2.0).withMuscles(chest()),
            WidFix.workout(3, daysAgo = 6.0).withMuscles(chest()),
        )
        assertThat(freshness(history)[0].daysSince).isEqualTo(2)
    }

    @Test
    fun testFreshnessStatusIsReadyFromFourDaysRecoveringForTwoOrThreeAndWorkedForTodayAndYesterday() {
        val expected = listOf(
            0.0 to FreshnessStatus.WORKED, 1.0 to FreshnessStatus.WORKED, 2.0 to FreshnessStatus.RECOVERING, 3.0 to FreshnessStatus.RECOVERING,
            4.0 to FreshnessStatus.READY, 5.0 to FreshnessStatus.READY, 30.0 to FreshnessStatus.READY,
        )
        for ((days, status) in expected) {
            val result = freshness(listOf(WidFix.workout(1, daysAgo = days).withMuscles(chest())))[0]
            assertWithMessage("$days days ago").that(result.daysSince).isEqualTo(days.toInt())
            assertWithMessage("$days days ago").that(result.status).isEqualTo(status)
        }
    }

    @Test
    fun testFreshnessCountsCalendarDays() {
        val late = freshness(listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 15, 23, 50)).withMuscles(chest())))[0]
        assertWithMessage("23:50 yesterday is 1 day ago").that(late.daysSince).isEqualTo(1)
        assertThat(late.status).isEqualTo(FreshnessStatus.WORKED)
    }

    @Test
    fun testFreshnessIgnoresAGroupEntryWithoutSets() {
        val history = listOf(
            WidFix.workout(2, daysAgo = 0.0).withMuscles(listOf(MuscleSets(MuscleGroup.CHEST, 0))),
            WidFix.workout(1, daysAgo = 6.0).withMuscles(chest()),
        )
        assertThat(freshness(history)[0].daysSince).isEqualTo(6)
    }
}

class WidgetWeeklySetsRuleTests {
    private fun weekly(history: List<CompletedWorkout>): WeeklySetsSummary = WidFix.snapshot(history = history).weeklySets

    private fun sets(chest: Int = 0, back: Int = 0, shoulders: Int = 0, arms: Int = 0, legs: Int = 0, core: Int = 0): List<MuscleSets> =
        listOf(
            MuscleGroup.CHEST to chest, MuscleGroup.BACK to back, MuscleGroup.SHOULDERS to shoulders, MuscleGroup.ARMS to arms,
            MuscleGroup.LEGS to legs, MuscleGroup.CORE to core,
        ).filter { it.second > 0 }.map { MuscleSets(it.first, it.second) }

    private fun thisWeek(muscles: List<MuscleSets>): List<CompletedWorkout> =
        listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 14, 9, 0)).withMuscles(muscles))

    @Test
    fun testWeeklySetsSumsTheMuscleSetsOfThisWeeksWorkouts() {
        val history = listOf(
            WidFix.workout(1, at = WidFix.date(2026, 10, 12, 0, 0, 0)).withMuscles(sets(chest = 9, back = 3)), // Monday 00:00:00: in
            WidFix.workout(2, at = WidFix.date(2026, 10, 15, 9, 0)).withMuscles(sets(chest = 4, legs = 5)),
            WidFix.workout(3, at = WidFix.date(2026, 10, 11, 23, 59, 59)).withMuscles(sets(chest = 20)), // last Sunday: out
            WidFix.workout(4, at = WidFix.date(2026, 10, 20, 9, 0)).withMuscles(sets(chest = 20)), // next week: out
        )
        val result = weekly(history)
        assertThat(result.muscles.map { it.muscle }).isEqualTo(MuscleGroup.entries.toList())
        assertThat(result.muscles.map { it.sets }).containsExactly(13, 3, 0, 0, 5, 0).inOrder()
    }

    @Test
    fun testWeeklySetsTargetsAreTenToFourteenForTheMajorsAndSixToTenForArmsAndCore() {
        val result = weekly(emptyList())
        assertThat(result.muscles.map { it.targetLow }).containsExactly(10, 10, 10, 6, 10, 6).inOrder()
        assertThat(result.muscles.map { it.targetHigh }).containsExactly(14, 14, 14, 10, 14, 10).inOrder()
    }

    @Test
    fun testWeeklySetsStatusIsUnderBelowTheLowBoundOverAboveTheHighBoundElseOnTarget() {
        val below = weekly(thisWeek(sets(chest = 9, arms = 5))).muscles
        assertThat(below[0].status).isEqualTo(SetsStatus.UNDER)
        assertThat(below[3].status).isEqualTo(SetsStatus.UNDER)
        val low = weekly(thisWeek(sets(chest = 10, arms = 6))).muscles
        assertWithMessage("the low bound is on target").that(low[0].status).isEqualTo(SetsStatus.ON_TARGET)
        assertThat(low[3].status).isEqualTo(SetsStatus.ON_TARGET)
        val high = weekly(thisWeek(sets(chest = 14, arms = 10))).muscles
        assertWithMessage("so is the high bound").that(high[0].status).isEqualTo(SetsStatus.ON_TARGET)
        assertThat(high[3].status).isEqualTo(SetsStatus.ON_TARGET)
        val above = weekly(thisWeek(sets(chest = 15, arms = 11))).muscles
        assertThat(above[0].status).isEqualTo(SetsStatus.OVER)
        assertThat(above[3].status).isEqualTo(SetsStatus.OVER)
        assertWithMessage("no sets is under").that(weekly(emptyList()).muscles.map { it.status }).isEqualTo(List(6) { SetsStatus.UNDER })
    }

    @Test
    fun testWeeklySetsTotalIsTheFourMajorsAgainst48() {
        val result = weekly(thisWeek(sets(chest = 12, back = 10, shoulders = 9, arms = 8, legs = 6, core = 4)))
        assertWithMessage("arms and core are not part of the total").that(result.totalSets).isEqualTo(37)
        assertThat(result.totalTarget).isEqualTo(48)
        assertThat(result.setsToGo).isEqualTo(11)
        val over = weekly(thisWeek(sets(chest = 20, back = 20, shoulders = 20, legs = 20)))
        assertThat(over.totalSets).isEqualTo(80)
        assertWithMessage("never negative").that(over.setsToGo).isEqualTo(0)
        val none = weekly(emptyList())
        assertThat(none.totalSets).isEqualTo(0)
        assertThat(none.setsToGo).isEqualTo(48)
    }

    @Test
    fun testWeeklySetsLaggingMuscleIsTheMajorWithTheFewestSetsFirstOnATie() {
        assertThat(weekly(thisWeek(sets(chest = 12, back = 10, shoulders = 9, legs = 6))).laggingMuscle).isEqualTo(MuscleGroup.LEGS)
        assertWithMessage("back and legs tie: the first in MuscleGroup order")
            .that(weekly(thisWeek(sets(chest = 12, back = 11, shoulders = 15, legs = 11))).laggingMuscle).isEqualTo(MuscleGroup.BACK)
        assertThat(weekly(thisWeek(sets(chest = 3, back = 3, shoulders = 3, legs = 3))).laggingMuscle).isEqualTo(MuscleGroup.CHEST)
        assertThat(weekly(emptyList()).laggingMuscle).isEqualTo(MuscleGroup.CHEST)
        assertWithMessage("arms and core are never lagging")
            .that(weekly(thisWeek(sets(chest = 12, back = 12, shoulders = 12, legs = 11))).laggingMuscle).isEqualTo(MuscleGroup.LEGS)
    }

    @Test
    fun testWeeklySetsLaggingMuscleIsNullOnceEveryMajorReachedTwelve() {
        assertThat(weekly(thisWeek(sets(chest = 12, back = 12, shoulders = 12, legs = 12))).laggingMuscle).isNull()
        assertThat(weekly(thisWeek(sets(chest = 20, back = 13, shoulders = 12, legs = 14))).laggingMuscle).isNull()
    }
}

class WidgetBodyMapRuleTests {
    private fun bodyMap(muscles: List<MuscleSets>, templates: List<WorkoutTemplate> = emptyList(), extra: List<CompletedWorkout> = emptyList()): BodyMap {
        val week = WidFix.workout(1, at = WidFix.date(2026, 10, 14, 9, 0)).withMuscles(muscles)
        return WidFix.snapshot(StrengthData(templates = templates, history = listOf(week) + extra)).bodyMap
    }

    private fun sets(vararg pairs: Pair<MuscleGroup, Int>): List<MuscleSets> = pairs.map { MuscleSets(it.first, it.second) }

    @Test
    fun testBodyMapLevelIsZeroForNoSetsOneUpToFourTwoUpToNineThreeFromTen() {
        val counts = listOf(0, 1, 4, 5, 9, 10, 25)
        val expected = listOf(0, 1, 1, 2, 2, 3, 3)
        for ((count, level) in counts.zip(expected)) {
            val result = bodyMap(sets(MuscleGroup.CHEST to count)).levels.first { it.muscle == MuscleGroup.CHEST }
            assertWithMessage("$count sets").that(result.level).isEqualTo(level)
        }
        assertThat(bodyMap(emptyList()).levels.map { it.muscle }).isEqualTo(MuscleGroup.entries.toList())
    }

    @Test
    fun testBodyMapUntouchedAreTheGroupsWithNoSetsThisWeek() {
        val result = bodyMap(sets(MuscleGroup.CHEST to 6, MuscleGroup.BACK to 3, MuscleGroup.ARMS to 2))
        assertThat(result.untouched).containsExactly(MuscleGroup.SHOULDERS, MuscleGroup.LEGS, MuscleGroup.CORE).inOrder()
        assertThat(bodyMap(emptyList()).untouched).isEqualTo(MuscleGroup.entries.toList())
    }

    @Test
    fun testBodyMapOnlyCountsThisWeek() {
        val lastWeek = WidFix.workout(2, at = WidFix.date(2026, 10, 11, 23, 0)).withMuscles(sets(MuscleGroup.LEGS to 12))
        assertThat(bodyMap(emptyList(), extra = listOf(lastWeek)).untouched).isEqualTo(MuscleGroup.entries.toList())
    }

    private fun pushPull(): List<WorkoutTemplate> = listOf(
        WidFix.template(1, "Upper A · Push", listOf(WidFix.entry("bench", WidFix.planned(3, 80.0, 6)), WidFix.entry("ohp", WidFix.planned(3, 45.0, 8)))),
        WidFix.template(
            2, "Lower A · Quads",
            listOf(
                WidFix.entry("squat", listOf(PlannedSet(type = SetType.WARMUP, weightKg = 40.0, reps = 8)) + WidFix.planned(3, 80.0, 6)),
                WidFix.entry("legext", WidFix.planned(3, 45.0, 12)),
            ),
        ),
    )

    private val majorsWithoutLegs = sets(MuscleGroup.CHEST to 12, MuscleGroup.BACK to 9, MuscleGroup.SHOULDERS to 6)

    @Test
    fun testBodyMapMessageNamesTheFirstUntouchedMajorAndSaysItsTemplateIsNextInLine() {
        // Upper A was last: Lower A is next.
        val templates = pushPull().let { listOf(it[0].copy(lastPerformed = WidFix.now.addingTimeInterval(-86_400.0)), it[1]) }
        assertThat(bodyMap(majorsWithoutLegs, templates).message).isEqualTo("Legs untouched. Lower A is next in line.")
    }

    @Test
    fun testBodyMapMessageSuggestsTheTemplateWhenItIsNotTheNextUp() {
        // Lower A was last: Upper A is next.
        val templates = pushPull().let { listOf(it[0], it[1].copy(lastPerformed = WidFix.now.addingTimeInterval(-86_400.0))) }
        assertThat(bodyMap(majorsWithoutLegs, templates).message).isEqualTo("Legs untouched. Try Lower A.")
    }

    @Test
    fun testBodyMapMessageUsesTheFirstUntouchedMajorInMuscleGroupOrder() {
        val message = bodyMap(sets(MuscleGroup.BACK to 6), pushPull()).message
        assertThat(message).startsWith("Chest untouched.")
        assertWithMessage("nothing was performed: the first template is next").that(message).isEqualTo("Chest untouched. Upper A is next in line.")
    }

    @Test
    fun testBodyMapMessagePicksTheTemplateWithTheMostNonWarmUpSetsOfTheGroup() {
        // Lower B has 2 sets of squats, Lower A has 3 working sets (plus a warm-up that does not count).
        val templates = pushPull() + WidFix.template(
            3, "Lower B · Hamstrings",
            listOf(WidFix.entry("rdl", WidFix.planned(2, 70.0, 8)), WidFix.entry("legcurl", WidFix.planned(2, 35.0, 12))),
        )
        assertWithMessage("Lower A has 6 working leg sets, Lower B has 4").that(bodyMap(majorsWithoutLegs, templates).message).isEqualTo("Legs untouched. Try Lower A.")
        // The first template wins a tie: Lower B and Lower C both have 4 working leg sets.
        val glutes = WidFix.template(
            4, "Lower C · Glutes",
            listOf(WidFix.entry("hipthrust", WidFix.planned(2, 70.0, 8)), WidFix.entry("lunge", WidFix.planned(2, 12.0, 10))),
        )
        val tie = listOf(templates[0], templates[2], glutes)
        assertThat(bodyMap(majorsWithoutLegs, tie).message).isEqualTo("Legs untouched. Try Lower B.")
    }

    @Test
    fun testBodyMapMessageWithoutATemplateForTheGroupIsJustTheGroup() {
        assertThat(bodyMap(majorsWithoutLegs, listOf(pushPull()[0])).message).isEqualTo("Legs untouched.")
        assertWithMessage("no templates at all").that(bodyMap(majorsWithoutLegs).message).isEqualTo("Legs untouched.")
    }

    @Test
    fun testBodyMapMessageUsesTheWholeNameWhenItHasNoDot() {
        val templates = listOf(
            WidFix.template(1, "Upper", listOf(WidFix.entry("bench", WidFix.planned(3, 80.0, 6)))),
            WidFix.template(2, "Legs", listOf(WidFix.entry("squat", WidFix.planned(3, 80.0, 6)))),
        )
        assertWithMessage("Upper is next after nothing was performed").that(bodyMap(majorsWithoutLegs, templates).message).isEqualTo("Legs untouched. Try Legs.")
    }

    @Test
    fun testBodyMapMessageWhenEveryMajorGroupWasTrained() {
        val result = bodyMap(sets(MuscleGroup.CHEST to 1, MuscleGroup.BACK to 1, MuscleGroup.SHOULDERS to 1, MuscleGroup.LEGS to 1))
        assertThat(result.message).isEqualTo("Every major group has been trained this week.")
        assertWithMessage("arms and core do not count for the message").that(result.untouched).containsExactly(MuscleGroup.ARMS, MuscleGroup.CORE).inOrder()
    }
}
