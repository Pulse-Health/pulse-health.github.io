import Foundation

/// Builds the `WidgetSnapshot` from the strength data. The rules are widgets/SPEC.md section 2 and are the same in Kotlin; each one
/// lives in a small file next to this one (`WidgetPeriods`, `WidgetTemplates`, `WidgetSessions`, `WidgetMuscles`, `WidgetLifts`,
/// `WidgetBlock`, `WidgetSchedule`) and is a pure function of the data, the context and `now`.
public enum WidgetSnapshotBuilder {
    /// The snapshot of `data` at `now`.
    ///
    /// Days and weeks are those of `context.timeZone` (Monday first). The weekly goal is the active training plan's `daysPerWeek` when it
    /// has one, else `context.weeklyGoal`, brought into 1...7. The body weight is `context.bodyweightKg`, else the newest weigh-in of
    /// `data`. The running workout, readiness and partners are copied from the context.
    public static func build(data: StrengthData, context: WidgetContext = WidgetContext(), now: Date) -> WidgetSnapshot {
        let calendar = WidgetCalendar(context: context)
        let history = WidgetHistory(workouts: data.history, calendar: calendar, now: now)
        let goal = StrengthSettings.clamped(data.activePlan?.daysPerWeek ?? context.weeklyGoal)
        let bodyweight = context.bodyweightKg ?? data.latestBodyWeight?.kg

        let next = data.nextTemplate()
        let lifts = WidgetLifts.lifts(history)
        let weekSets = WidgetMuscles.setsThisWeek(history)

        return WidgetSnapshot(
            generatedAt: now,
            timeZoneID: TimeZone(identifier: context.timeZoneID) == nil ? "UTC" : context.timeZoneID,
            week: WidgetPeriods.week(history, goal: goal),
            nextUp: next.map { WidgetTemplates.nextUp($0, in: data, history: history) },
            templates: WidgetTemplates.launcher(data.templates, suggested: next?.id, history: history),
            lastSession: WidgetSessions.lastSession(history),
            latestPR: WidgetSessions.latestPR(history),
            overload: next.flatMap { WidgetTemplates.overload(for: $0, history: history) },
            freshness: WidgetMuscles.freshness(history),
            weeklySets: WidgetMuscles.weeklySets(weekSets),
            lifts: lifts.map { $0.trend },
            month: WidgetPeriods.month(history),
            plateaus: WidgetLifts.plateaus(lifts),
            year: WidgetPeriods.year(history),
            block: WidgetBlock.block(history, templates: data.templates, goal: goal, lifts: lifts),
            formCue: next.flatMap { WidgetTemplates.formCue(for: $0, history: history) },
            loadedBar: next.flatMap { WidgetTemplates.loadedBar(for: $0) },
            strengthRatio: WidgetLifts.strengthRatio(lifts, bodyweightKg: bodyweight),
            restDay: WidgetSchedule.restDay(history, goal: goal),
            tomorrow: next.map { WidgetSchedule.tomorrow(history, nextUp: $0) },
            bodyMap: WidgetMuscles.bodyMap(weekSets, templates: data.templates, nextUp: next?.id),
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
