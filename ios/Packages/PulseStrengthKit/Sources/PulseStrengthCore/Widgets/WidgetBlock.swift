import Foundation

/// The derived 4-week training block of the iPad and tablet widgets (widgets/SPEC.md section 2: block). The app has no block concept:
/// blocks are counted in four-week steps from the week of the first workout ever finished.
enum WidgetBlock {
    /// Weeks in a block.
    static let weeks = 4

    /// The block that contains the current week; nil without history.
    ///
    /// The anchor is the Monday of the week of the earliest workout and `n` the whole weeks from it to this week's Monday (never below
    /// 0). The block is number `n / 4 + 1` and this is its week `n % 4 + 1`. Its rows are the first four templates in store order, one
    /// cell per week of the block: a week after the current one is `upcoming`; an earlier or current week is `done` when a workout of
    /// that template finished in it (matched by `templateID`, or by name for a workout that has none), else `planned` for the current
    /// week and `missed` for an earlier one. `sessionsDone` counts the workouts since the block began, `sessionsPlanned` is the goal
    /// times the weeks so far. The lift is the first of `lifts`: how its value changed from the last session before the block (its first
    /// session inside it when it had none before) to its latest, nil for a lift with fewer than two sessions.
    static func block(
        _ history: WidgetHistory,
        templates: [WorkoutTemplate],
        goal: Int,
        lifts: [WidgetLifts.Series]
    ) -> TrainingBlock? {
        guard let earliest = history.entries.map({ $0.day }).min() else { return nil }
        let anchor = WidgetCalendar.monday(onOrBefore: earliest)
        let elapsed = max(0, (history.weekStart - anchor) / 7)
        let weekIndex = elapsed % weeks + 1
        let blockStart = anchor + (elapsed / weeks) * weeks * 7

        let rows = templates.prefix(4).map { template -> BlockRow in
            let cells = (1...weeks).map { week -> BlockCell in
                if week > weekIndex { return BlockCell(state: .upcoming) }
                let start = blockStart + (week - 1) * 7
                let done = history.entries(inDays: start..<(start + 7)).contains { belongs($0.workout, to: template) }
                if done { return BlockCell(state: .done) }
                return BlockCell(state: week == weekIndex ? .planned : .missed)
            }
            return BlockRow(label: WidgetText.rowLabel(of: template.name), cells: cells)
        }
        let missed = rows.reduce(0) { $0 + $1.cells.filter { $0.state == .missed }.count }
        let change = liftChange(lifts.first, blockStart: blockStart)
        return TrainingBlock(
            name: "Block \(elapsed / weeks + 1)",
            weekIndex: weekIndex,
            weekCount: weeks,
            rows: rows,
            sessionsDone: history.entries.filter { $0.day >= blockStart }.count,
            sessionsPlanned: goal * weekIndex,
            sessionsMissed: missed,
            liftName: change == nil ? nil : lifts.first?.trend.name,
            liftDeltaKg: change
        )
    }

    /// True when `workout` is a workout of `template`: the same `templateID`, or the same name for a workout without one.
    private static func belongs(_ workout: CompletedWorkout, to template: WorkoutTemplate) -> Bool {
        workout.templateID.map { $0 == template.id } ?? (workout.name == template.name)
    }

    /// The change of the lift's value from the baseline to its latest session, rounded to 0.1; nil with fewer than two sessions.
    private static func liftChange(_ lift: WidgetLifts.Series?, blockStart: Int) -> Double? {
        guard let lift, lift.sessions.count >= 2, let latest = lift.sessions.last else { return nil }
        let baseline = lift.sessions.last(where: { $0.day < blockStart }) ?? lift.sessions.first(where: { $0.day >= blockStart })
        guard let baseline else { return nil }
        return WidgetText.tenth(latest.value - baseline.value)
    }
}
