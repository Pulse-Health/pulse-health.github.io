package health.pulse.strength.core.widgets

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.PersonalRecord
import health.pulse.strength.core.addingTimeInterval
import java.time.Instant
import org.junit.Test

/**
 * widgets/SPEC.md section 2: week, streakWeeks, month and year. `WidFix.now` is Friday 2026-10-16 09:41 UTC; the current week runs from
 * Monday 12 October to Sunday 18 October.
 */
class WidgetWeekRuleTests {
    private fun week(history: List<CompletedWorkout>, goal: Int = 4, zone: String = "UTC", now: Instant = WidFix.now): WeekSummary =
        WidFix.snapshot(history = history, context = WidFix.context(zone, goal = goal), now = now).week

    @Test
    fun testWeekDaysAreMondayToSundayAtLocalMidnightWithTheirLetters() {
        val result = week(emptyList())
        assertThat(result.weekStart).isEqualTo(WidFix.date(2026, 10, 12))
        assertThat(result.days).hasSize(7)
        assertThat(result.days.map { it.letter }).containsExactly("M", "T", "W", "T", "F", "S", "S").inOrder()
        assertThat(result.days.map { it.date }).containsExactlyElementsIn((12..18).map { WidFix.date(2026, 10, it) }).inOrder()
        assertThat(result.goal).isEqualTo(4)
        assertThat(result.completed).isEqualTo(0)
        assertThat(result.streakWeeks).isEqualTo(0)
        assertThat(result.lastWorkoutAt).isNull()
        assertThat(result.daysSinceLastWorkout).isNull()
        assertThat(result.days.all { it.sessions == 0 && it.label == null }).isTrue()
    }

    @Test
    fun testWeekCompletedCountsTheWorkoutsThatDayBucketIntoThisWeek() {
        val history = listOf(
            WidFix.workout(1, at = WidFix.date(2026, 10, 15, 18, 0)),
            WidFix.workout(2, at = WidFix.date(2026, 10, 12, 0, 0, 0)), // Monday 00:00:00 is in
            WidFix.workout(3, at = WidFix.date(2026, 10, 11, 23, 59, 59)), // Sunday 23:59:59 of the week before is out
            WidFix.workout(4, at = WidFix.date(2026, 9, 1)),
        )
        assertThat(week(history).completed).isEqualTo(2)
    }

    @Test
    fun testWeekDaysHaveSessionsLabelIsTodayAndIsFuture() {
        val history = listOf(
            WidFix.workout(1, "Upper B · Pull", at = WidFix.date(2026, 10, 13, 9, 0)),
            WidFix.workout(2, "Legs", at = WidFix.date(2026, 10, 15, 18, 30)),
        )
        val days = week(history).days
        assertThat(days.map { it.sessions }).containsExactly(0, 1, 0, 1, 0, 0, 0).inOrder()
        assertThat(days.map { it.label }).containsExactly(null, "UB", null, "LE", null, null, null).inOrder()
        assertWithMessage("today is Friday").that(days.map { it.isToday }).containsExactly(false, false, false, false, true, false, false).inOrder()
        assertThat(days.map { it.isFuture }).containsExactly(false, false, false, false, false, true, true).inOrder()
    }

    @Test
    fun testWeekDayLabelIsTheInitialsOfTheEarliestWorkoutOfTheDay() {
        val history = listOf(
            WidFix.workout(1, "Upper A · Push", at = WidFix.date(2026, 10, 14, 18, 0)),
            WidFix.workout(2, "Lower A · Quads", at = WidFix.date(2026, 10, 14, 7, 0)),
        )
        val wednesday = week(history).days[2]
        assertThat(wednesday.sessions).isEqualTo(2)
        assertWithMessage("the 07:00 workout is the earliest, whatever the order of the history").that(wednesday.label).isEqualTo("LA")
    }

    @Test
    fun testWeekLastWorkoutAtIsTheLatestFinishedAt() {
        val history = listOf(
            WidFix.workout(1, at = WidFix.date(2026, 10, 10, 8, 0)),
            WidFix.workout(2, at = WidFix.date(2026, 10, 14, 18, 0)),
            WidFix.workout(3, at = WidFix.date(2026, 10, 12, 7, 0)),
        )
        assertThat(week(history).lastWorkoutAt).isEqualTo(WidFix.date(2026, 10, 14, 18, 0))
    }

    @Test
    fun testWeekDaysSinceLastWorkoutCountsCalendarDays() {
        assertWithMessage("23:50 yesterday is 1 day ago")
            .that(week(listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 15, 23, 50)))).daysSinceLastWorkout)
            .isEqualTo(1)
        assertThat(week(listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 16, 0, 5)))).daysSinceLastWorkout).isEqualTo(0)
        assertThat(week(listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 9, 9, 42)))).daysSinceLastWorkout).isEqualTo(7)
        assertWithMessage("null without history").that(week(emptyList()).daysSinceLastWorkout).isNull()
    }

    // region Time zones and the week boundary

    @Test
    fun testTheWeekChangesAtMondayMidnightNotOneSecondBefore() {
        val sunday = WidFix.workout(1, at = WidFix.date(2026, 10, 18, 23, 59, 58))
        val monday = WidFix.workout(2, at = WidFix.date(2026, 10, 19, 0, 0, 0))
        val history = listOf(monday, sunday)

        val lastSecondOfTheWeek = week(history, now = WidFix.date(2026, 10, 18, 23, 59, 59))
        assertThat(lastSecondOfTheWeek.weekStart).isEqualTo(WidFix.date(2026, 10, 12))
        assertWithMessage("the Monday workout is in the future: next week").that(lastSecondOfTheWeek.completed).isEqualTo(1)
        assertThat(lastSecondOfTheWeek.days[6].isToday).isTrue()
        assertThat(lastSecondOfTheWeek.days[6].sessions).isEqualTo(1)
        assertThat(lastSecondOfTheWeek.days.all { !it.isFuture }).isTrue()

        val firstSecondOfTheNext = week(history, now = WidFix.date(2026, 10, 19, 0, 0, 0))
        assertThat(firstSecondOfTheNext.weekStart).isEqualTo(WidFix.date(2026, 10, 19))
        assertWithMessage("only the workout of Monday 00:00:00 is in the new week").that(firstSecondOfTheNext.completed).isEqualTo(1)
        assertThat(firstSecondOfTheNext.days[0].isToday).isTrue()
        assertThat(firstSecondOfTheNext.days[0].sessions).isEqualTo(1)
        assertThat(firstSecondOfTheNext.daysSinceLastWorkout).isEqualTo(0)
    }

    @Test
    fun testSundayEveningInOneZoneIsMondayInAnother() {
        // 2026-10-18T22:30Z: Sunday evening in UTC, already Monday 11:30 in Auckland (UTC+13), Sunday 15:30 in Los Angeles.
        val now = WidFix.date(2026, 10, 18, 22, 30)
        val history = listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 18, 22, 0)))
        val utc = week(history, zone = "UTC", now = now)
        val auckland = week(history, zone = "Pacific/Auckland", now = now)
        val losAngeles = week(history, zone = "America/Los_Angeles", now = now)
        assertThat(utc.weekStart).isEqualTo(WidFix.date(2026, 10, 12))
        assertThat(utc.days[6].isToday).isTrue()
        assertThat(auckland.weekStart).isEqualTo(WidFix.date(2026, 10, 19, zone = "Pacific/Auckland"))
        assertWithMessage("Monday in New Zealand").that(auckland.days[0].isToday).isTrue()
        assertWithMessage("the workout is on Monday there").that(auckland.days[0].sessions).isEqualTo(1)
        assertThat(losAngeles.weekStart).isEqualTo(WidFix.date(2026, 10, 12, zone = "America/Los_Angeles"))
        assertThat(losAngeles.days[6].isToday).isTrue()
    }

    @Test
    fun testWeekDaysAcrossADaylightSavingChangeAreConsecutiveLocalMidnights() {
        // Clocks go back in Berlin on Sunday 25 October 2026: the week of 19 October has a 25 hour Sunday.
        val now = WidFix.date(2026, 10, 22, 12, 0, zone = "Europe/Berlin")
        val history = listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 25, 23, 30, zone = "Europe/Berlin")))
        val result = week(history, zone = "Europe/Berlin", now = now)
        assertThat(result.weekStart).isEqualTo(WidFix.date(2026, 10, 19, zone = "Europe/Berlin"))
        assertThat(result.days.map { it.date }).containsExactlyElementsIn((19..25).map { WidFix.date(2026, 10, it, zone = "Europe/Berlin") }).inOrder()
        assertWithMessage("23:30 on the long Sunday is still Sunday").that(result.days[6].sessions).isEqualTo(1)
        assertThat(result.days[6].isFuture).isTrue()
        assertThat(result.days[3].isToday).isTrue()
    }

    @Test
    fun testAWorkoutLateAtNightBelongsToItsLocalDayInEachZone() {
        val instant = WidFix.date(2026, 10, 14, 11, 30) // Wednesday 11:30Z
        val history = listOf(WidFix.workout(1, at = instant))
        assertThat(week(history, zone = "UTC").days.map { it.sessions }).containsExactly(0, 0, 1, 0, 0, 0, 0).inOrder()
        assertWithMessage("Thursday 00:30 in New Zealand")
            .that(week(history, zone = "Pacific/Auckland").days.map { it.sessions })
            .containsExactly(0, 0, 0, 1, 0, 0, 0)
            .inOrder()
        assertThat(week(history, zone = "America/Los_Angeles").days.map { it.sessions }).containsExactly(0, 0, 1, 0, 0, 0, 0).inOrder()
    }

    // endregion

    // region A workout in the future

    @Test
    fun testAWorkoutInTheFutureBelongsToItsDayAndCountsAsToday() {
        val future = WidFix.workout(1, "Upper A · Push", at = WidFix.date(2026, 10, 18, 9, 41)) // Sunday, two days ahead
        val snapshot = WidFix.snapshot(history = listOf(future, WidFix.workout(2, at = WidFix.date(2026, 10, 13, 9, 41))))
        assertWithMessage("its day is in this week").that(snapshot.week.completed).isEqualTo(2)
        assertThat(snapshot.week.days[6].sessions).isEqualTo(1)
        assertThat(snapshot.week.days[6].isFuture).isTrue()
        assertThat(snapshot.week.lastWorkoutAt).isEqualTo(future.finishedAt)
        assertWithMessage("a date in the future counts as 0 days").that(snapshot.week.daysSinceLastWorkout).isEqualTo(0)
        assertThat(snapshot.lastSession?.workoutID).isEqualTo(future.id.toString())
    }

    @Test
    fun testAWorkoutInAFutureWeekIsNotInThisWeekButIsStillTheLastWorkout() {
        val future = WidFix.workout(1, at = WidFix.date(2026, 10, 30, 9, 41))
        val snapshot = WidFix.snapshot(history = listOf(future))
        assertThat(snapshot.week.completed).isEqualTo(0)
        assertThat(snapshot.week.daysSinceLastWorkout).isEqualTo(0)
        assertThat(snapshot.week.lastWorkoutAt).isEqualTo(future.finishedAt)
    }

    @Test
    fun testAPersonalRecordInTheFutureIsNeverFresh() {
        val record = PersonalRecord(exerciseID = "bench", exerciseName = "Bench", weightKg = 85.0, reps = 5, estimated1RM = 99.0, previousBest = 95.0)
        val snapshot = WidFix.snapshot(history = listOf(WidFix.workout(1, at = WidFix.now.addingTimeInterval(3_600.0), records = listOf(record))))
        assertThat(snapshot.latestPR?.isFresh).isFalse()
    }

    // endregion
}

class WidgetStreakRuleTests {
    /** One workout in each of the weeks at [offsets] before the current one (0 = this week), [perWeek] workouts each. */
    private fun weeks(offsets: List<Int>, perWeek: Int = 1): List<CompletedWorkout> {
        val history = mutableListOf<CompletedWorkout>()
        for (offset in offsets) {
            for (index in 0 until perWeek) {
                history.add(WidFix.workout(history.size + 1, at = WidFix.date(2026, 10, 13, 9, index).addingTimeInterval(-offset * 7 * 86_400.0)))
            }
        }
        return history
    }

    private fun streak(history: List<CompletedWorkout>, goal: Int): Int =
        WidFix.snapshot(history = history, context = WidFix.context(goal = goal)).week.streakWeeks

    @Test
    fun testStreakWeeksCountsTheWeeksThatMetTheGoalGoingBackwardsAndTheCurrentWeekCountsWhenMet() {
        assertThat(streak(weeks(listOf(0, 1, 2), perWeek = 2), goal = 2)).isEqualTo(3)
        assertWithMessage("the current week has not met the goal yet").that(streak(weeks(listOf(1, 2), perWeek = 2), goal = 2)).isEqualTo(2)
    }

    @Test
    fun testTheCurrentWeekIsSkippedNotABreakWhenItHasNotMetTheGoal() {
        val history = weeks(listOf(1, 2, 3), perWeek = 2) + WidFix.workout(99, at = WidFix.date(2026, 10, 13, 12, 0)) // one workout this week, goal 2
        assertThat(streak(history, goal = 2)).isEqualTo(3)
    }

    @Test
    fun testTheStreakStopsAtTheFirstEarlierWeekBelowTheGoal() {
        // Weeks 0, 1 and 2 met the goal, week 3 did not, weeks 4 and 5 did.
        val history = weeks(listOf(0, 1, 2, 4, 5), perWeek = 2) +
            WidFix.workout(98, at = WidFix.date(2026, 10, 13, 12, 0).addingTimeInterval(-3 * 7 * 86_400.0))
        assertThat(streak(history, goal = 2)).isEqualTo(3)
    }

    @Test
    fun testAnEarlierWeekWithoutAnyWorkoutBreaksTheStreak() {
        assertThat(streak(weeks(listOf(0, 1, 3, 4), perWeek = 1), goal = 1)).isEqualTo(2)
    }

    @Test
    fun testTheGoalDecidesWhichWeeksCount() {
        val history = weeks(listOf(0, 1, 2, 3), perWeek = 3)
        assertThat(streak(history, goal = 3)).isEqualTo(4)
        assertThat(streak(history, goal = 4)).isEqualTo(0)
        assertThat(streak(history, goal = 1)).isEqualTo(4)
    }

    @Test
    fun testAWorkoutInAFutureWeekDoesNotCountForThePast() {
        val history = weeks(listOf(1, 2), perWeek = 1) + WidFix.workout(77, at = WidFix.date(2026, 10, 27, 9, 0))
        assertThat(streak(history, goal = 1)).isEqualTo(2)
    }

    @Test
    fun testStreakWeeksStopsAt520() {
        val history = (0 until 600).map { WidFix.workout(it + 1, at = WidFix.date(2026, 10, 13, 9, 0).addingTimeInterval(-it * 7 * 86_400.0)) }
        assertThat(streak(history, goal = 1)).isEqualTo(520)
        assertThat(WidgetPeriods.streakCap).isEqualTo(520)
    }

    @Test
    fun testStreakWeeksIsZeroWithoutHistory() {
        assertThat(streak(emptyList(), goal = 1)).isEqualTo(0)
    }
}

class WidgetMonthRuleTests {
    private fun month(history: List<CompletedWorkout>, now: Instant = WidFix.now, zone: String = "UTC"): MonthSummary =
        WidFix.snapshot(history = history, context = WidFix.context(zone), now = now).month

    @Test
    fun testMonthHasTheNameTheStartAndOneEntryPerDay() {
        val october = month(emptyList())
        assertThat(october.title).isEqualTo("October")
        assertThat(october.monthStart).isEqualTo(WidFix.date(2026, 10, 1))
        assertThat(october.days.map { it.day }).containsExactlyElementsIn((1..31).toList()).inOrder()
        assertThat(october.sessionCount).isEqualTo(0)
        assertThat(october.days.all { it.level == 0 && it.sessions == 0 }).isTrue()
        assertThat(month(emptyList(), now = WidFix.date(2026, 2, 10)).days).hasSize(28)
        assertThat(month(emptyList(), now = WidFix.date(2024, 2, 10)).days).hasSize(29)
        assertThat(month(emptyList(), now = WidFix.date(2026, 4, 10)).days).hasSize(30)
        assertThat(month(emptyList(), now = WidFix.date(2026, 4, 10)).title).isEqualTo("April")
    }

    @Test
    fun testMonthLeadingBlankDaysIsTheWeekdayOfThe1stWithMondayZero() {
        assertWithMessage("1 October 2026 is a Thursday").that(month(emptyList()).leadingBlankDays).isEqualTo(3)
        assertWithMessage("1 June 2026 is a Monday").that(month(emptyList(), now = WidFix.date(2026, 6, 15)).leadingBlankDays).isEqualTo(0)
        assertWithMessage("1 February 2026 is a Sunday").that(month(emptyList(), now = WidFix.date(2026, 2, 15)).leadingBlankDays).isEqualTo(6)
        assertWithMessage("1 March 2026 is a Sunday").that(month(emptyList(), now = WidFix.date(2026, 3, 15)).leadingBlankDays).isEqualTo(6)
    }

    @Test
    fun testMonthMarksTodayAndTheFuture() {
        val days = month(emptyList()).days
        assertThat(days.filter { it.isToday }.map { it.day }).containsExactly(16)
        assertThat(days.filter { it.isFuture }.map { it.day }).containsExactlyElementsIn((17..31).toList()).inOrder()
    }

    @Test
    fun testMonthCountsSessionsAndSumsTheVolumePerDay() {
        val history = listOf(
            WidFix.workout(1, at = WidFix.date(2026, 10, 3, 8, 0), volumeKg = 400.0),
            WidFix.workout(2, at = WidFix.date(2026, 10, 3, 18, 0), volumeKg = 500.0),
            WidFix.workout(3, at = WidFix.date(2026, 10, 9, 9, 0), volumeKg = 900.0),
            WidFix.workout(4, at = WidFix.date(2026, 9, 30, 23, 59), volumeKg = 5_000.0), // September
            WidFix.workout(5, at = WidFix.date(2026, 11, 1, 0, 0), volumeKg = 5_000.0), // November
        )
        val october = month(history)
        assertThat(october.sessionCount).isEqualTo(3)
        assertThat(october.days[2].sessions).isEqualTo(2)
        assertThat(october.days[8].sessions).isEqualTo(1)
        assertWithMessage("400 + 500 equals the heaviest day, 900").that(october.days[2].level).isEqualTo(3)
        assertThat(october.days[8].level).isEqualTo(3)
    }

    @Test
    fun testMonthLevelIsByVolumeAgainstTheHeaviestDay() {
        // The heaviest day has 900 kg: up to 300 kg is level 1, up to 600 level 2, above that level 3.
        val volumes = listOf(1 to 300.0, 2 to 301.0, 3 to 600.0, 4 to 601.0, 5 to 900.0, 6 to 0.0, 7 to 10.0)
        val history = volumes.mapIndexed { index, (day, kg) -> WidFix.workout(index + 1, at = WidFix.date(2026, 10, day, 9, 0), volumeKg = kg) }
        val levels = month(history).days.take(8).map { it.level }
        assertWithMessage("300 is a third: 1; 301: 2; 600 is two thirds: 2; 601: 3; 900: 3; 0 kg and 10 kg: 1")
            .that(levels)
            .containsExactly(1, 2, 2, 3, 3, 1, 1, 0)
            .inOrder()
    }

    @Test
    fun testMonthWhoseVolumesAreAllZeroGivesLevelOne() {
        val history = listOf(
            WidFix.workout(1, at = WidFix.date(2026, 10, 2, 9, 0), volumeKg = 0.0),
            WidFix.workout(2, at = WidFix.date(2026, 10, 5, 9, 0), volumeKg = 0.0),
        )
        assertThat(month(history).days.take(6).map { it.level }).containsExactly(0, 1, 0, 0, 1, 0).inOrder()
    }

    @Test
    fun testMonthFollowsTheLocalMonthOfTheZone() {
        // 2026-09-30T20:00Z is already 1 October 09:00 in Auckland (UTC+13).
        val now = WidFix.date(2026, 9, 30, 20, 0)
        val history = listOf(
            WidFix.workout(1, at = WidFix.date(2026, 9, 30, 10, 0), volumeKg = 100.0), // 30 September 23:00 in Auckland
            WidFix.workout(2, at = WidFix.date(2026, 9, 30, 19, 0), volumeKg = 100.0), // 1 October 08:00 in Auckland
        )
        val utc = month(history, now = now, zone = "UTC")
        val auckland = month(history, now = now, zone = "Pacific/Auckland")
        assertThat(utc.title).isEqualTo("September")
        assertThat(utc.days).hasSize(30)
        assertThat(utc.sessionCount).isEqualTo(2)
        assertThat(utc.days[29].sessions).isEqualTo(2)
        assertThat(auckland.title).isEqualTo("October")
        assertThat(auckland.days).hasSize(31)
        assertThat(auckland.monthStart).isEqualTo(WidFix.date(2026, 10, 1, zone = "Pacific/Auckland"))
        assertWithMessage("only the second workout is in October there").that(auckland.sessionCount).isEqualTo(1)
        assertThat(auckland.days[0].sessions).isEqualTo(1)
        assertThat(auckland.days[0].isToday).isTrue()
    }

    @Test
    fun testMonthWithADaylightSavingChangeInsideIt() {
        // Clocks go back in Berlin on 25 October 2026.
        val now = WidFix.date(2026, 10, 28, 9, 0, zone = "Europe/Berlin")
        val history = listOf(
            WidFix.workout(1, at = WidFix.date(2026, 10, 24, 23, 30, zone = "Europe/Berlin"), volumeKg = 100.0),
            WidFix.workout(2, at = WidFix.date(2026, 10, 25, 0, 15, zone = "Europe/Berlin"), volumeKg = 100.0),
            WidFix.workout(3, at = WidFix.date(2026, 10, 25, 23, 59, zone = "Europe/Berlin"), volumeKg = 100.0),
            WidFix.workout(4, at = WidFix.date(2026, 10, 26, 0, 0, zone = "Europe/Berlin"), volumeKg = 100.0),
        )
        val october = month(history, now = now, zone = "Europe/Berlin")
        assertThat(october.days).hasSize(31)
        assertThat(october.monthStart).isEqualTo(WidFix.date(2026, 10, 1, zone = "Europe/Berlin"))
        assertThat(october.days[23].sessions).isEqualTo(1)
        assertWithMessage("both workouts of the 25 hour day").that(october.days[24].sessions).isEqualTo(2)
        assertThat(october.days[25].sessions).isEqualTo(1)
        assertThat(october.days.filter { it.isToday }.map { it.day }).containsExactly(28)
        assertThat(october.leadingBlankDays).isEqualTo(3)
    }
}

class WidgetYearRuleTests {
    private fun year(history: List<CompletedWorkout>, now: Instant = WidFix.now, zone: String = "UTC"): YearSummary =
        WidFix.snapshot(history = history, context = WidFix.context(zone), now = now).year

    @Test
    fun testYearHasTwelveMonthsOfTonnesRoundedToATenth() {
        val history = listOf(
            WidFix.workout(1, at = WidFix.date(2026, 1, 5), volumeKg = 1_234.0),
            WidFix.workout(2, at = WidFix.date(2026, 1, 20), volumeKg = 2_000.0),
            WidFix.workout(3, at = WidFix.date(2026, 10, 2), volumeKg = 1_260.0),
        )
        val result = year(history)
        assertThat(result.year).isEqualTo(2026)
        assertThat(result.sessionCount).isEqualTo(3)
        assertWithMessage("4,494 kg is 4.494 t").that(result.tonnes).isEqualTo(4.5)
        assertThat(result.monthlyTonnes).hasSize(12)
        assertWithMessage("3,234 kg").that(result.monthlyTonnes[0]).isEqualTo(3.2)
        assertWithMessage("1,260 kg").that(result.monthlyTonnes[9]).isEqualTo(1.3)
        assertThat(result.monthlyTonnes.filterIndexed { index, _ -> index != 0 && index != 9 }).isEqualTo(List(10) { 0.0 })
    }

    @Test
    fun testYearIsTheCalendarYearOfNow() {
        val history = listOf(
            WidFix.workout(1, at = WidFix.date(2025, 12, 31, 23, 59), volumeKg = 9_000.0),
            WidFix.workout(2, at = WidFix.date(2026, 1, 1, 0, 0), volumeKg = 1_000.0),
            WidFix.workout(3, at = WidFix.date(2027, 1, 1, 0, 0), volumeKg = 8_000.0),
        )
        val result = year(history)
        assertThat(result.sessionCount).isEqualTo(1)
        assertThat(result.tonnes).isEqualTo(1.0)
        assertThat(year(history, now = WidFix.date(2025, 6, 1)).tonnes).isEqualTo(9.0)
    }

    @Test
    fun testYearFollowsTheLocalCalendarOfTheZone() {
        // 2025-12-31T23:30Z is already 1 January 2026 in Auckland.
        val history = listOf(WidFix.workout(1, at = WidFix.date(2025, 12, 31, 23, 30), volumeKg = 2_000.0))
        val now = WidFix.date(2026, 3, 1)
        assertThat(year(history, now = now, zone = "UTC").tonnes).isEqualTo(0.0)
        assertThat(year(history, now = now, zone = "Pacific/Auckland").tonnes).isEqualTo(2.0)
        assertThat(year(history, now = now, zone = "Pacific/Auckland").monthlyTonnes[0]).isEqualTo(2.0)
    }

    @Test
    fun testYearWithoutHistoryIsAllZeros() {
        assertThat(year(emptyList())).isEqualTo(YearSummary(year = 2026, tonnes = 0.0, sessionCount = 0, monthlyTonnes = List(12) { 0.0 }))
    }
}
