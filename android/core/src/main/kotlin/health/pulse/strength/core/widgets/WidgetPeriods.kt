package health.pulse.strength.core.widgets

import health.pulse.strength.core.CompletedWorkout

/** The week, month and year views of the history (widgets/SPEC.md section 2: week, month, year). */
internal object WidgetPeriods {
    /** The most weeks the streak counts. */
    const val streakCap = 520

    // region Week

    /**
     * Progress toward [goal] in the current week (Monday to Sunday of the snapshot's time zone).
     *
     * `completed` counts the workouts that day-bucket into the week, a workout in the future included when its day is this week's. A
     * day's `label` is the initials of the earliest workout (by `finishedAt`) of that day. `lastWorkoutAt` is the latest `finishedAt`
     * of the whole history, so a workout dated in the future is the last one and is 0 days ago.
     */
    fun week(history: WidgetHistory, goal: Int): WeekSummary {
        val sessions = IntArray(7)
        val earliest = arrayOfNulls<CompletedWorkout>(7)
        for (entry in history.thisWeek) {
            val offset = (entry.day - history.weekStart).toInt()
            sessions[offset] += 1
            val current = earliest[offset]
            if (current != null && !current.finishedAt.isAfter(entry.workout.finishedAt)) continue
            earliest[offset] = entry.workout
        }
        val latest = history.latest?.workout?.finishedAt
        val days = (0 until 7).map { offset ->
            val day = history.weekStart + offset
            DayCell(
                date = history.calendar.startOfDay(day),
                letter = WidgetCalendar.weekdayLetters[offset],
                sessions = sessions[offset],
                label = earliest[offset]?.let { WidgetText.initials(it.name) },
                isToday = day == history.today,
                isFuture = day > history.today,
            )
        }
        return WeekSummary(
            weekStart = history.calendar.startOfDay(history.weekStart),
            goal = goal,
            completed = sessions.sum(),
            streakWeeks = streakWeeks(history, goal),
            lastWorkoutAt = latest,
            daysSinceLastWorkout = latest?.let { history.daysAgo(it) },
            days = days,
        )
    }

    /**
     * The weeks in a row that met [goal], counted backwards from the current week. The current week counts when it already met the
     * goal and is skipped, not a break, when it has not; the first earlier week below the goal ends the count. At most [streakCap].
     */
    fun streakWeeks(history: WidgetHistory, goal: Int): Int {
        val perWeek = HashMap<Long, Int>()
        for (entry in history.entries) {
            val monday = WidgetCalendar.mondayOnOrBefore(entry.day)
            perWeek[monday] = (perWeek[monday] ?: 0) + 1
        }
        var streak = if ((perWeek[history.weekStart] ?: 0) >= goal) 1 else 0
        var week = history.weekStart - 7
        while (streak < streakCap && (perWeek[week] ?: 0) >= goal) {
            streak += 1
            week -= 7
        }
        return streak
    }

    // endregion

    // region Month

    /**
     * The heatmap of the current month: per day the sessions and a level 1...3 by that day's volume against the month's heaviest day.
     *
     * A day without a session is level 0. With sessions, the level is 1 up to a third of the heaviest day's volume, 2 up to two
     * thirds, else 3; when no day has any volume (reps-only workouts) every day with a session is level 1.
     */
    fun month(history: WidgetHistory): MonthSummary {
        val civil = WidgetCalendar.civil(history.today)
        val first = WidgetCalendar.dayNumber(civil.year, civil.monthValue, 1)
        val length = WidgetCalendar.daysInMonth(civil.year, civil.monthValue)
        val sessions = IntArray(length)
        val volume = DoubleArray(length)
        for (entry in history.inDays(first until first + length)) {
            val offset = (entry.day - first).toInt()
            sessions[offset] += 1
            volume[offset] += entry.workout.volumeKg
        }
        val heaviest = volume.maxOrNull() ?: 0.0
        val days = (0 until length).map { offset ->
            val level = when {
                sessions[offset] == 0 -> 0
                heaviest <= 0 || 3 * volume[offset] <= heaviest -> 1
                3 * volume[offset] <= 2 * heaviest -> 2
                else -> 3
            }
            MonthDay(
                day = offset + 1,
                level = level,
                sessions = sessions[offset],
                isToday = first + offset == history.today,
                isFuture = first + offset > history.today,
            )
        }
        return MonthSummary(
            monthStart = history.calendar.startOfDay(first),
            title = WidgetCalendar.monthNames[civil.monthValue - 1],
            leadingBlankDays = WidgetCalendar.weekdayIndex(first),
            sessionCount = sessions.sum(),
            days = days,
        )
    }

    // endregion

    // region Year

    /** The tonnage of the calendar year of `now`: the total, the sessions and the 12 months, in tonnes rounded to 0.1. */
    fun year(history: WidgetHistory): YearSummary {
        val year = WidgetCalendar.civil(history.today).year
        val monthly = DoubleArray(12)
        var total = 0.0
        var sessions = 0
        for (entry in history.entries) {
            val civil = WidgetCalendar.civil(entry.day)
            if (civil.year != year) continue
            monthly[civil.monthValue - 1] += entry.workout.volumeKg
            total += entry.workout.volumeKg
            sessions += 1
        }
        return YearSummary(
            year = year,
            tonnes = WidgetText.tenth(total / 1000),
            sessionCount = sessions,
            monthlyTonnes = monthly.map { WidgetText.tenth(it / 1000) },
        )
    }

    // endregion
}
