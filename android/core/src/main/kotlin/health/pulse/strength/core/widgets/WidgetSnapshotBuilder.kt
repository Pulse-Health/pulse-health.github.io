package health.pulse.strength.core.widgets

import health.pulse.strength.core.StrengthData
import health.pulse.strength.core.WorkoutTemplate
import java.time.Instant

/**
 * Builds the [WidgetSnapshot] from the strength data. The rules are widgets/SPEC.md section 2 and are the same in Swift; each one
 * lives in a small file next to this one (`WidgetPeriods`, `WidgetTemplates`, `WidgetSessions`, `WidgetMuscles`, `WidgetLifts`,
 * `WidgetBlock`, `WidgetSchedule`) and is a pure function of the data, the context and `now`.
 *
 * The Android store keeps no training plans and no body weights: the next workout is the rotation over the saved templates, the
 * goal is the context's weekly goal and the body weight is the context's.
 */
object WidgetSnapshotBuilder {
    /**
     * The snapshot of [data] at [now].
     *
     * Days and weeks are those of `context.zone` (Monday first). The weekly goal is `context.weeklyGoal` brought into 1...7. The
     * running workout, readiness and partners are copied from [context].
     */
    fun make(data: StrengthData, context: WidgetContext, now: Instant): WidgetSnapshot {
        val history = WidgetHistory(data.history, WidgetCalendar(context.zone), now)
        val goal = WidgetContext.clampedGoal(context.weeklyGoal)

        val next = WidgetTemplates.nextTemplate(data.templates)
        val lifts = WidgetLifts.lifts(history)
        val weekSets = WidgetMuscles.setsThisWeek(history)

        return WidgetSnapshot(
            generatedAt = now,
            timeZoneID = context.timeZoneID,
            week = WidgetPeriods.week(history, goal),
            nextUp = next?.let { WidgetTemplates.nextUp(it, history) },
            templates = WidgetTemplates.launcher(data.templates, next?.id, history),
            lastSession = WidgetSessions.lastSession(history),
            latestPR = WidgetSessions.latestPR(history),
            overload = next?.let { WidgetTemplates.overload(it, history) },
            freshness = WidgetMuscles.freshness(history),
            weeklySets = WidgetMuscles.weeklySets(weekSets),
            lifts = lifts.map { it.trend },
            month = WidgetPeriods.month(history),
            plateaus = WidgetLifts.plateaus(lifts),
            year = WidgetPeriods.year(history),
            block = WidgetBlock.block(history, data.templates, goal, lifts),
            formCue = next?.let { WidgetTemplates.formCue(it, history) },
            loadedBar = next?.let { WidgetTemplates.loadedBar(it) },
            strengthRatio = WidgetLifts.strengthRatio(lifts, context.bodyweightKg),
            restDay = WidgetSchedule.restDay(history, goal),
            tomorrow = next?.let { WidgetSchedule.tomorrow(history, it) },
            bodyMap = WidgetMuscles.bodyMap(weekSets, data.templates, next?.id),
            readiness = context.readiness,
            partners = context.partners,
            active = context.active,
        )
    }

    /**
     * The template that `startNext` starts and that [make] reports as `nextUp`: the rotation over [templates] (widgets/SPEC.md section 2),
     * null without templates.
     */
    fun nextTemplate(templates: List<WorkoutTemplate>): WorkoutTemplate? = WidgetTemplates.nextTemplate(templates)
}

/** What a widget shows when the app has never written a snapshot and there is no data: no templates, an empty week. */
fun WidgetSnapshot.Companion.empty(now: Instant, context: WidgetContext = WidgetContext()): WidgetSnapshot =
    WidgetSnapshotBuilder.make(StrengthData(), context, now)

/**
 * True when [other] shows the same as this snapshot: everything equal but the time stamp and the running workout's revision, which
 * grows with every edit of the workout even when the edit looks the same on screen.
 */
fun WidgetSnapshot.hasSameContentAs(other: WidgetSnapshot): Boolean =
    copy(generatedAt = other.generatedAt, active = active?.copy(revision = other.active?.revision ?: 0)) == other
