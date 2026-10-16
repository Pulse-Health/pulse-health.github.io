package health.pulse.strength.core.widgets

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.StrengthData
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.core.addingTimeInterval
import java.time.Instant
import org.junit.Test

/** widgets/SPEC.md section 2: restDay and tomorrow. */
class WidgetRestDayRuleTests {
    private fun restDay(history: List<CompletedWorkout>, now: Instant, goal: Int = 4, zone: String = "UTC"): RestDaySuggestion? =
        WidFix.snapshot(history = history, context = WidFix.context(zone, goal = goal), now = now).restDay

    /** 12 October 2026 is a Monday; [weekday] 0 is that Monday. */
    private fun day(weekday: Int, hour: Int = 9, minute: Int = 41): Instant = WidFix.date(2026, 10, 12 + weekday, hour, minute)

    @Test
    fun testRestDayAfterAWorkoutYesterdayIsOneOfFourRoutinesByWeekday() {
        val routines = listOf(
            Triple("10-min mobility", "Hips and T-spine", 10),
            Triple("8-min shoulder reset", "Shoulders and upper back", 8),
            Triple("12-min hips and hamstrings", "Hips and hamstrings", 12),
            Triple("6-min wrist and ankle prep", "Wrists and ankles", 6),
        )
        // Tuesday to Sunday have a workout the day before; the Monday one follows a workout on Sunday 11 October.
        val yesterdays = listOf(WidFix.date(2026, 10, 11, 18, 0)) + (0 until 6).map { day(it, hour = 18, minute = 0) }
        for (weekday in 0 until 7) {
            val history = listOf(WidFix.workout(1, at = yesterdays[weekday]))
            val result = restDay(history, now = day(weekday))
            val expected = routines[weekday % 4]
            assertWithMessage("weekday $weekday").that(result?.title).isEqualTo(expected.first)
            assertWithMessage("weekday $weekday").that(result?.focus).isEqualTo(expected.second)
            assertWithMessage("weekday $weekday").that(result?.minutes).isEqualTo(expected.third)
            assertThat(result?.reason).isEqualTo("Rest day")
        }
    }

    @Test
    fun testRestDayIsNullWhenAWorkoutWasDoneToday() {
        val history = listOf(WidFix.workout(1, at = day(3, hour = 7, minute = 0)), WidFix.workout(2, at = day(4, hour = 8, minute = 0)))
        assertWithMessage("a workout yesterday, but one this morning too").that(restDay(history, now = day(4))).isNull()
        val laterToday = listOf(WidFix.workout(1, at = day(3, hour = 18, minute = 0)), WidFix.workout(2, at = day(4, hour = 20, minute = 0)))
        assertWithMessage("a workout dated later today is today's").that(restDay(laterToday, now = day(4))).isNull()
    }

    @Test
    fun testRestDayIsNullWithoutAWorkoutYesterdayWhenTheGoalIsNotMet() {
        val history = listOf(WidFix.workout(1, at = day(0, hour = 18, minute = 0))) // Monday evening, now is Thursday
        assertThat(restDay(history, now = day(3), goal = 4)).isNull()
        assertWithMessage("no history, nothing to recover from").that(restDay(emptyList(), now = day(3))).isNull()
    }

    @Test
    fun testRestDayWhenTheGoalIsMetEvenWithoutAWorkoutYesterday() {
        val history = listOf(WidFix.workout(1, at = day(0, hour = 18, minute = 0)), WidFix.workout(2, at = day(1, hour = 18, minute = 0)))
        assertWithMessage("2 of 2 workouts this week: a rest day").that(restDay(history, now = day(4), goal = 2)).isNotNull()
        assertThat(restDay(history, now = day(4), goal = 3)).isNull()
    }

    @Test
    fun testRestDayCountsYesterdayAsALocalCalendarDay() {
        assertWithMessage("20 minutes ago, but yesterday")
            .that(restDay(listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 15, 23, 50))), now = WidFix.date(2026, 10, 16, 0, 10)))
            .isNotNull()
        assertWithMessage("two days ago")
            .that(restDay(listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 14, 23, 50))), now = WidFix.date(2026, 10, 16, 9, 0)))
            .isNull()
        // 2026-10-15T22:00Z is 11:00 on the 16th in Auckland: a workout "today" there.
        val history = listOf(WidFix.workout(1, at = WidFix.date(2026, 10, 15, 22, 0)))
        val now = WidFix.date(2026, 10, 16, 1, 0)
        assertWithMessage("UTC: yesterday").that(restDay(history, now = now, zone = "UTC")).isNotNull()
        assertWithMessage("Auckland: both are the 16th").that(restDay(history, now = now, zone = "Pacific/Auckland")).isNull()
    }
}

class WidgetTomorrowRuleTests {
    private val upper = WidFix.template(1, "Upper A · Push", listOf(WidFix.entry("bench", WidFix.planned(3, 80.0, 6))))

    private fun tomorrow(
        history: List<CompletedWorkout>,
        now: Instant = WidFix.now,
        zone: String = "UTC",
        templates: List<WorkoutTemplate> = listOf(upper),
    ): TomorrowPlan? = WidFix.snapshot(StrengthData(templates = templates, history = history), WidFix.context(zone), now).tomorrow

    /** A workout that started at [hour]:[minute] on [day] of October 2026 and lasted 50 minutes. */
    private fun started(n: Int, day: Int, hour: Int, minute: Int, zone: String = "UTC"): CompletedWorkout {
        val start = WidFix.date(2026, 10, day, hour, minute, zone = zone)
        return WidFix.workout(n, at = start.addingTimeInterval(3_000.0), durationSeconds = 3_000)
    }

    @Test
    fun testTomorrowNeedsANextUp() {
        assertThat(tomorrow(listOf(started(1, day = 12, hour = 7, minute = 0)), templates = emptyList())).isNull()
    }

    @Test
    fun testTomorrowNamesTheNextWorkoutAndTomorrowsWeekday() {
        val plan = tomorrow(emptyList())!!
        assertThat(plan.templateName).isEqualTo("Upper A · Push")
        assertWithMessage("16 October 2026 is a Friday").that(plan.weekday).isEqualTo("Saturday")
        assertThat(plan.isInferred).isTrue()
        assertThat(plan.note).isEqualTo("Gym bag ready?")
        assertWithMessage("no history, no usual time").that(plan.plannedMinuteOfDay).isNull()
        val weekdays = (0 until 7).map { tomorrow(emptyList(), now = WidFix.date(2026, 10, 12 + it, 9, 0))?.weekday }
        assertThat(weekdays).containsExactly("Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday", "Monday").inOrder()
    }

    @Test
    fun testTomorrowTheStartTimeIsTheMedianOfTheStartsRoundedToFiveMinutes() {
        // Starts 07:02, 07:08 and 06:58: the median is 07:02 = 422 minutes, which rounds to 420.
        val history = listOf(started(1, 14, 7, 2), started(2, 13, 7, 8), started(3, 12, 6, 58))
        assertThat(tomorrow(history)?.plannedMinuteOfDay).isEqualTo(420)
        val late = listOf(started(1, 14, 18, 3), started(2, 13, 18, 30), started(3, 12, 18, 0))
        assertWithMessage("18:03 rounds to 18:05").that(tomorrow(late)?.plannedMinuteOfDay).isEqualTo(18 * 60 + 5)
    }

    @Test
    fun testTomorrowWithAnEvenNumberOfWorkoutsAveragesTheTwoMiddleStartsAndRoundsHalvesUp() {
        // 07:05 (425) and 07:10 (430): 427.5 minutes is 85.5 steps of five, which rounds up to 86 = 430.
        val history = listOf(started(1, 14, 7, 5), started(2, 13, 7, 10))
        assertThat(tomorrow(history)?.plannedMinuteOfDay).isEqualTo(430)
        // 07:00 (420) and 07:04 (424): 422 minutes rounds to 420.
        assertThat(tomorrow(listOf(started(1, 14, 7, 0), started(2, 13, 7, 4)))?.plannedMinuteOfDay).isEqualTo(420)
    }

    @Test
    fun testTomorrowUsesTheStartNotTheFinishOfTheWorkout() {
        // Finished at 08:00 after 50 minutes: it started at 07:10.
        val workout = WidFix.workout(1, at = WidFix.date(2026, 10, 14, 8, 0), durationSeconds = 3_000)
        assertThat(tomorrow(listOf(workout))?.plannedMinuteOfDay).isEqualTo(7 * 60 + 10)
    }

    @Test
    fun testTomorrowLooksAtTheLatestTenWorkoutsOnly() {
        val history = (1..10).map { started(it, 14, 7, 0).movedBack(it.toDouble()) } +
            listOf(started(20, 14, 20, 0).movedBack(40.0), started(21, 14, 20, 0).movedBack(41.0))
        assertWithMessage("the two evening workouts are older than the latest ten").that(tomorrow(history)?.plannedMinuteOfDay).isEqualTo(420)
        assertWithMessage("whatever the order of the history").that(tomorrow(history.reversed())?.plannedMinuteOfDay).isEqualTo(420)
    }

    @Test
    fun testTomorrowTheStartTimeIsInTheLocalTimeZone() {
        // 07:00 UTC is 20:00 in Auckland (UTC+13).
        val history = listOf(started(1, 14, 7, 0), started(2, 13, 7, 0))
        assertThat(tomorrow(history, zone = "UTC")?.plannedMinuteOfDay).isEqualTo(420)
        assertThat(tomorrow(history, zone = "Pacific/Auckland")?.plannedMinuteOfDay).isEqualTo(20 * 60)
    }

    @Test
    fun testTomorrowTheStartTimeWrapsAtMidnight() {
        // 23:58 rounds to 24:00, which is 0.
        val history = listOf(started(1, 14, 23, 58), started(2, 13, 23, 58))
        assertThat(tomorrow(history)?.plannedMinuteOfDay).isEqualTo(0)
    }
}
