import Foundation

/// The week, month and year views of the history (widgets/SPEC.md section 2: week, month, year).
enum WidgetPeriods {
    /// The most weeks the streak counts.
    static let streakCap = 520

    // MARK: Week

    /// Progress toward `goal` in the current week (Monday to Sunday of the snapshot's time zone).
    ///
    /// `completed` counts the workouts that day-bucket into the week, a workout in the future included when its day is this week's. A
    /// day's `label` is the initials of the earliest workout (by `finishedAt`) of that day. `lastWorkoutAt` is the latest `finishedAt`
    /// of the whole history, so a workout dated in the future is the last one and is 0 days ago.
    static func week(_ history: WidgetHistory, goal: Int) -> WeekSummary {
        var sessions = [Int](repeating: 0, count: 7)
        var earliest = [CompletedWorkout?](repeating: nil, count: 7)
        for entry in history.thisWeek {
            let offset = entry.day - history.weekStart
            sessions[offset] += 1
            if let current = earliest[offset], current.finishedAt <= entry.workout.finishedAt { continue }
            earliest[offset] = entry.workout
        }
        let latest = history.latest?.workout.finishedAt
        let days = (0..<7).map { offset -> DayCell in
            let day = history.weekStart + offset
            return DayCell(
                date: history.calendar.startOfDay(day),
                letter: WidgetCalendar.weekdayLetters[offset],
                sessions: sessions[offset],
                label: earliest[offset].map { WidgetText.initials(of: $0.name) },
                isToday: day == history.today,
                isFuture: day > history.today
            )
        }
        return WeekSummary(
            weekStart: history.calendar.startOfDay(history.weekStart),
            goal: goal,
            completed: sessions.reduce(0, +),
            streakWeeks: streakWeeks(history, goal: goal),
            lastWorkoutAt: latest,
            daysSinceLastWorkout: latest.map { history.daysAgo($0) },
            days: days
        )
    }

    /// The weeks in a row that met `goal`, counted backwards from the current week. The current week counts when it already met the
    /// goal and is skipped, not a break, when it has not; the first earlier week below the goal ends the count. At most `streakCap`.
    static func streakWeeks(_ history: WidgetHistory, goal: Int) -> Int {
        var perWeek: [Int: Int] = [:]
        for entry in history.entries { perWeek[WidgetCalendar.monday(onOrBefore: entry.day), default: 0] += 1 }
        var streak = (perWeek[history.weekStart] ?? 0) >= goal ? 1 : 0
        var week = history.weekStart - 7
        while streak < streakCap, (perWeek[week] ?? 0) >= goal {
            streak += 1
            week -= 7
        }
        return streak
    }

    // MARK: Month

    /// The heatmap of the current month: per day the sessions and a level 1...3 by that day's volume against the month's heaviest day.
    ///
    /// A day without a session is level 0. With sessions, the level is 1 up to a third of the heaviest day's volume, 2 up to two
    /// thirds, else 3; when no day has any volume (reps-only workouts) every day with a session is level 1.
    static func month(_ history: WidgetHistory) -> MonthSummary {
        let civil = WidgetCalendar.civil(fromDay: history.today)
        let first = WidgetCalendar.dayNumber(year: civil.year, month: civil.month, day: 1)
        let length = WidgetCalendar.daysInMonth(year: civil.year, month: civil.month)
        var sessions = [Int](repeating: 0, count: length)
        var volume = [Double](repeating: 0, count: length)
        for entry in history.entries(inDays: first..<(first + length)) {
            sessions[entry.day - first] += 1
            volume[entry.day - first] += entry.workout.volumeKg
        }
        let heaviest = volume.max() ?? 0
        let days = (0..<length).map { offset -> MonthDay in
            let level: Int
            if sessions[offset] == 0 {
                level = 0
            } else if heaviest <= 0 || 3 * volume[offset] <= heaviest {
                level = 1
            } else if 3 * volume[offset] <= 2 * heaviest {
                level = 2
            } else {
                level = 3
            }
            return MonthDay(
                day: offset + 1,
                level: level,
                sessions: sessions[offset],
                isToday: first + offset == history.today,
                isFuture: first + offset > history.today
            )
        }
        return MonthSummary(
            monthStart: history.calendar.startOfDay(first),
            title: WidgetCalendar.monthNames[civil.month - 1],
            leadingBlankDays: WidgetCalendar.weekdayIndex(ofDay: first),
            sessionCount: sessions.reduce(0, +),
            days: days
        )
    }

    // MARK: Year

    /// The tonnage of the calendar year of `now`: the total, the sessions and the 12 months, in tonnes rounded to 0.1.
    static func year(_ history: WidgetHistory) -> YearSummary {
        let year = WidgetCalendar.civil(fromDay: history.today).year
        var monthly = [Double](repeating: 0, count: 12)
        var total = 0.0
        var sessions = 0
        for entry in history.entries {
            let civil = WidgetCalendar.civil(fromDay: entry.day)
            guard civil.year == year else { continue }
            monthly[civil.month - 1] += entry.workout.volumeKg
            total += entry.workout.volumeKg
            sessions += 1
        }
        return YearSummary(
            year: year,
            tonnes: WidgetText.tenth(total / 1000),
            sessionCount: sessions,
            monthlyTonnes: monthly.map { WidgetText.tenth($0 / 1000) }
        )
    }
}
