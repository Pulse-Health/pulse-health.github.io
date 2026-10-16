package health.pulse.strength.core.widgets

import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.core.roundedAwayFromZero

/** What to do on a day without training and when tomorrow's session usually starts (widgets/SPEC.md section 2: restDay, tomorrow). */
internal object WidgetSchedule {
    private class Routine(val title: String, val focus: String, val minutes: Int)

    /** The four recovery routines, chosen by weekday (Monday is 0) modulo four. */
    private val routines = listOf(
        Routine("10-min mobility", "Hips and T-spine", 10),
        Routine("8-min shoulder reset", "Shoulders and upper back", 8),
        Routine("12-min hips and hamstrings", "Hips and hamstrings", 12),
        Routine("6-min wrist and ankle prep", "Wrists and ankles", 6),
    )

    /** How many of the latest workouts tell when the user usually starts. */
    const val startTimeSample = 10

    // region Rest day

    /**
     * A recovery routine when nothing was trained today and either yesterday had a workout or the weekly [goal] is met; else null.
     * A workout counts for the day of its `finishedAt`.
     */
    fun restDay(history: WidgetHistory, goal: Int): RestDaySuggestion? {
        if (history.entries.any { it.day == history.today }) return null
        val trainedYesterday = history.entries.any { it.day == history.today - 1 }
        val goalMet = history.thisWeek.size >= goal
        if (!trainedYesterday && !goalMet) return null
        val routine = routines[WidgetCalendar.weekdayIndex(history.today) % routines.size]
        return RestDaySuggestion(title = routine.title, focus = routine.focus, minutes = routine.minutes, reason = "Rest day")
    }

    // endregion

    // region Tomorrow

    /**
     * Tomorrow's session for night mode: the name of the next workout, tomorrow's weekday and, from the history, the time the user
     * usually starts.
     *
     * The start time is the median of the start times (`finishedAt - durationSeconds`, minutes after local midnight) of the latest 10
     * workouts, rounded to 5 minutes; null without history.
     */
    fun tomorrow(history: WidgetHistory, nextUp: WorkoutTemplate): TomorrowPlan = TomorrowPlan(
        templateName = nextUp.name,
        plannedMinuteOfDay = usualStartMinute(history),
        weekday = WidgetCalendar.weekdayNames[WidgetCalendar.weekdayIndex(history.today + 1)],
        isInferred = true,
    )

    private fun usualStartMinute(history: WidgetHistory): Int? {
        // Newest first; a tie keeps the order of the history.
        val latest = history.entries.sortedByDescending { it.workout.finishedAt }.take(startTimeSample)
        val minutes = latest.map { entry ->
            val workout = entry.workout
            history.calendar.minuteOfDay(workout.finishedAt.epochSecond - workout.durationSeconds)
        }.sorted()
        if (minutes.isEmpty()) return null
        val middle = minutes.size / 2
        val median = if (minutes.size % 2 == 1) minutes[middle].toDouble() else (minutes[middle - 1] + minutes[middle]) / 2.0
        return (median / 5).roundedAwayFromZero().toInt() * 5 % 1_440
    }

    // endregion
}
