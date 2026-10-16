import Foundation

/// What to do on a day without training and when tomorrow's session usually starts (widgets/SPEC.md section 2: restDay, tomorrow).
enum WidgetSchedule {
    /// The four recovery routines, chosen by weekday (Monday is 0) modulo four.
    private static let routines: [(title: String, focus: String, minutes: Int)] = [
        ("10-min mobility", "Hips and T-spine", 10),
        ("8-min shoulder reset", "Shoulders and upper back", 8),
        ("12-min hips and hamstrings", "Hips and hamstrings", 12),
        ("6-min wrist and ankle prep", "Wrists and ankles", 6),
    ]

    /// How many of the latest workouts tell when the user usually starts.
    static let startTimeSample = 10

    // MARK: Rest day

    /// A recovery routine when nothing was trained today and either yesterday had a workout or the weekly `goal` is met; else nil.
    /// A workout counts for the day of its `finishedAt`.
    static func restDay(_ history: WidgetHistory, goal: Int) -> RestDaySuggestion? {
        let trainedToday = history.entries.contains { $0.day == history.today }
        guard !trainedToday else { return nil }
        let trainedYesterday = history.entries.contains { $0.day == history.today - 1 }
        let goalMet = history.thisWeek.count >= goal
        guard trainedYesterday || goalMet else { return nil }
        let routine = routines[WidgetCalendar.weekdayIndex(ofDay: history.today) % routines.count]
        return RestDaySuggestion(title: routine.title, focus: routine.focus, minutes: routine.minutes, reason: "Rest day")
    }

    // MARK: Tomorrow

    /// Tomorrow's session for night mode: the name of the next workout, tomorrow's weekday and, from the history, the time the user
    /// usually starts.
    ///
    /// The start time is the median of the start times (`finishedAt - durationSeconds`, minutes after local midnight) of the latest 10
    /// workouts, rounded to 5 minutes; nil without history.
    static func tomorrow(_ history: WidgetHistory, nextUp: WorkoutTemplate) -> TomorrowPlan {
        let weekday = WidgetCalendar.weekdayIndex(ofDay: history.today + 1)
        return TomorrowPlan(
            templateName: nextUp.name,
            plannedMinuteOfDay: usualStartMinute(history),
            weekday: WidgetCalendar.weekdayNames[weekday],
            isInferred: true
        )
    }

    private static func usualStartMinute(_ history: WidgetHistory) -> Int? {
        let latest = history.entries.enumerated().sorted { lhs, rhs in
            lhs.element.workout.finishedAt != rhs.element.workout.finishedAt
                ? lhs.element.workout.finishedAt > rhs.element.workout.finishedAt
                : lhs.offset < rhs.offset
        }.prefix(startTimeSample)
        let minutes = latest.map { item -> Int in
            let workout = item.element.workout
            return history.calendar.minuteOfDay(workout.finishedAt.addingTimeInterval(-Double(workout.durationSeconds)))
        }.sorted()
        guard !minutes.isEmpty else { return nil }
        let middle = minutes.count / 2
        let median = minutes.count % 2 == 1 ? Double(minutes[middle]) : Double(minutes[middle - 1] + minutes[middle]) / 2
        return (Int((median / 5).rounded()) * 5) % 1_440
    }
}
