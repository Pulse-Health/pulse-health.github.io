package health.pulse.strength.live

import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.WorkoutSnapshot
import java.time.Instant

/**
 * Which alarms a snapshot needs: one when a rest counts down (the card turns into "Go" and the phone buzzes), one when a PR flash has
 * to be cleared. `LiveUpdates.refresh` schedules the ones that are set and cancels the others.
 */
internal data class LiveAlarmPlan(val restEndMillis: Long?, val momentEndMillis: Long?) {
    companion object {
        val NONE = LiveAlarmPlan(restEndMillis = null, momentEndMillis = null)

        fun of(snapshot: WorkoutSnapshot?, now: Instant): LiveAlarmPlan {
            if (snapshot == null || snapshot.finish != null || snapshot.isPaused) return NONE
            val restEnd = snapshot.restEndsAt?.takeIf { snapshot.phase == SnapshotPhase.RESTING && it.isAfter(now) }
            val momentEnd = snapshot.moment?.expiresAt?.takeIf { it.isAfter(now) }
            return LiveAlarmPlan(restEnd?.toEpochMilli(), momentEnd?.toEpochMilli())
        }
    }
}
