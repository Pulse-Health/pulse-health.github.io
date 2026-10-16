import Foundation

/// Builds the `WidgetSnapshot` from the strength data. The rules are widgets/SPEC.md section 2 and are the same in Kotlin.
public enum WidgetSnapshotBuilder {
    /// The snapshot of `data` at `now`.
    public static func build(data: StrengthData, context: WidgetContext = WidgetContext(), now: Date) -> WidgetSnapshot {
        // Filled in by the core work (see the rules in widgets/SPEC.md section 2); this minimal version keeps the API stable.
        let calendar = context.calendar
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        return WidgetSnapshot(
            generatedAt: now,
            timeZoneID: context.timeZoneID,
            week: WeekSummary(weekStart: weekStart, goal: context.weeklyGoal),
            weeklySets: WeeklySetsSummary(),
            month: MonthSummary(monthStart: monthStart, title: ""),
            year: YearSummary(year: calendar.component(.year, from: now)),
            bodyMap: BodyMap(),
            readiness: context.readiness,
            partners: context.partners,
            active: context.active
        )
    }
}

public extension WidgetSnapshot {
    /// What a widget shows when the app has never written a snapshot and there is no data: no templates, an empty week.
    static func empty(now: Date = Date(), context: WidgetContext = WidgetContext()) -> WidgetSnapshot {
        WidgetSnapshotBuilder.build(data: StrengthData(), context: context, now: now)
    }
}
