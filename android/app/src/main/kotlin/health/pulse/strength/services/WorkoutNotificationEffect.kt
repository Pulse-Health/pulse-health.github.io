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
import health.pulse.strength.core.widgets.PRMoment
import health.pulse.strength.live.LiveUpdates
import java.time.Instant

/**
 * Keeps the ongoing notification in step with the workout: posts it when a workout starts or is restored, refreshes it after every
 * change, removes it (and the rest alert and alarms) when the workout ends.
 *
 * Two moments of the live surfaces (widgets/SPEC.md "Live moments") pass through here, because only this effect sees the old and the
 * new state of the workout: a set that made a personal record flashes on the notification for a few seconds (LA-01, [moments]), and a
 * finished workout leaves its summary behind (LA-05, [savedToHealth] says whether Health Connect has it).
 */
class WorkoutNotificationEffect(
    private val context: Context,
    private val restAlerts: RestAlerts,
    private val clock: () -> Instant = { Instant.now() },
    private val savedToHealth: () -> Boolean = { false },
    private val moments: (WorkoutState, WorkoutState, Instant) -> PRMoment? = { old, new, now -> SnapshotBuilder.prMoment(old, new, now) },
) : WorkoutSideEffect {
    /** The record that was just logged: every update of the notification carries it until it runs out, however many other changes come. */
    private var record: PRMoment? = null

    override fun workoutStarted(state: WorkoutState) {
        record = null
        NotificationChannels.ensureCreated(context)
        refresh(state, clock())
    }

    override fun workoutChanged(old: WorkoutState, new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
        val now = clock()
        moments(old, new, now)?.let { record = it }
        refresh(new, now)
    }

    override fun workoutEnded(state: WorkoutState, completed: CompletedWorkout?) {
        record = null
        restAlerts.cancel()
        val manager = NotificationManagerCompat.from(context)
        manager.cancel(WorkoutNotifications.ONGOING_ID)
        manager.cancel(WorkoutNotifications.REST_ALERT_ID)
        // A finished workout leaves its summary for two hours; a discarded one (nothing was saved) leaves nothing.
        if (completed != null) LiveUpdates.showFinish(context, SnapshotBuilder.finishBrief(completed, savedToHealth()))
    }

    private fun refresh(state: WorkoutState, now: Instant) {
        restAlerts.sync(state)
        if (!WorkoutNotifications.canNotify(context)) return
        val flash = record?.takeIf { it.expiresAt > now }
        if (flash == null) record = null
        val made = SnapshotBuilder.make(state, now)
        val snapshot = if (flash != null) made.copy(moment = flash) else made
        val manager = NotificationManagerCompat.from(context)
        @Suppress("MissingPermission") // canNotify() checked the runtime permission
        manager.notify(WorkoutNotifications.ONGOING_ID, WorkoutNotifications.ongoing(context, snapshot, now))
        // A rest alert that is still showing goes away as soon as the workout moves on (a set was logged, the rest was skipped).
        if (snapshot.phase != SnapshotPhase.REST_OVER) manager.cancel(WorkoutNotifications.REST_ALERT_ID)
    }
}
