package health.pulse.strength.core.widgets

import health.pulse.strength.core.WorkoutSnapshot
import java.time.ZoneId
import java.time.ZoneOffset

/** What the host adds to the strength data when it builds a [WidgetSnapshot] (widgets/SPEC.md section 2). */
data class WidgetContext(
    /** Workouts per week the user aims for; the builder brings it into [weeklyGoalRange]. */
    val weeklyGoal: Int = defaultWeeklyGoal,
    /** Latest body mass from Health, null when unknown. */
    val bodyweightKg: Double? = null,
    /** Readiness from the wider Pulse app; null in the standalone build. */
    val readiness: ReadinessSummary? = null,
    /** Training partners from the wider Pulse app; empty in the standalone build. */
    val partners: List<PartnerWeek> = emptyList(),
    /** The running workout (the live notification's content), null when none. */
    val active: WorkoutSnapshot? = null,
    /** The time zone that defines the day and week buckets. */
    val zone: ZoneId = ZoneId.systemDefault(),
) {
    /** The snapshot's `timeZoneID`: the zone's id, "UTC" for the zone offset Z. */
    val timeZoneID: String get() = if (zone == ZoneOffset.UTC) "UTC" else zone.id

    companion object {
        /** The weekly goal until the user chooses another one. */
        const val defaultWeeklyGoal: Int = 4

        /** Smallest and largest weekly goal. */
        val weeklyGoalRange: IntRange = 1..7

        /** [goal] brought into [weeklyGoalRange]. */
        fun clampedGoal(goal: Int): Int = goal.coerceIn(weeklyGoalRange)
    }
}
