package health.pulse.strength.services

import android.content.Context
import androidx.core.app.NotificationManagerCompat
import health.pulse.strength.core.ActionOrigin
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.SnapshotBuilder
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutSideEffect
import health.pulse.strength.core.WorkoutState
import java.time.Instant

/**
 * Keeps the ongoing notification in step with the workout: posts it when a workout starts or is restored, refreshes it after every
 * change, removes it (and the rest alert and alarms) when the workout ends.
 */
class WorkoutNotificationEffect(
    private val context: Context,
    private val restAlerts: RestAlerts,
    private val clock: () -> Instant = { Instant.now() },
) : WorkoutSideEffect {
    override fun workoutStarted(state: WorkoutState) {
        NotificationChannels.ensureCreated(context)
        refresh(state)
    }

    override fun workoutChanged(old: WorkoutState, new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
        refresh(new)
    }

    override fun workoutEnded(state: WorkoutState, completed: CompletedWorkout?) {
        restAlerts.cancel()
        val manager = NotificationManagerCompat.from(context)
        manager.cancel(WorkoutNotifications.ONGOING_ID)
        manager.cancel(WorkoutNotifications.REST_ALERT_ID)
    }

    private fun refresh(state: WorkoutState) {
        restAlerts.sync(state)
        if (!WorkoutNotifications.canNotify(context)) return
        val now = clock()
        val snapshot = SnapshotBuilder.make(state, now)
        val manager = NotificationManagerCompat.from(context)
        @Suppress("MissingPermission") // canNotify() checked the runtime permission
        manager.notify(WorkoutNotifications.ONGOING_ID, WorkoutNotifications.ongoing(context, snapshot, now))
        // A rest alert that is still showing goes away as soon as the workout moves on (a set was logged, the rest was skipped).
        if (snapshot.phase != SnapshotPhase.REST_OVER) manager.cancel(WorkoutNotifications.REST_ALERT_ID)
    }
}
