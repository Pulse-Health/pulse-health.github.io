package health.pulse.strength.live

import android.content.Context
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.FinishBrief
import health.pulse.strength.runtime.StrengthRuntime
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * LA-01 ... LA-05, LA-07 ... LA-10: the workout notification, the Android "Live Activity". It follows `StrengthRuntime.snapshots`:
 *
 * * a running workout is one ongoing notification with a fixed id that every phase replaces in place ([LiveUpdateModels] decides what it
 *   says, [LiveUpdateNotifier] draws it);
 * * the alarm that ends the rest and the one that clears a PR flash are scheduled from the snapshot here, so no other component has to;
 * * a planned session ([PlannedSessions]) is cancelled as soon as a workout runs;
 * * without a workout the card is removed, and the finish card (LA-05) takes its place when the app handed in the [FinishBrief].
 *
 * `Surfaces.refreshAll` calls [refresh] after every new snapshot.
 */
object LiveUpdates {
    private val lock = Any()

    /** Brings the notification in line with the current snapshot. */
    suspend fun refresh(context: Context) {
        withContext(Dispatchers.Default) {
            sync(context.applicationContext, StrengthRuntime.snapshots.current().active, Instant.now())
        }
    }

    /**
     * LA-05: the app calls this when a workout was finished and saved. The finish card replaces the workout card (immediately when the
     * snapshot has no workout any more, otherwise as soon as it drops it) and leaves after two hours.
     */
    fun showFinish(context: Context, brief: FinishBrief) {
        val app = context.applicationContext
        LiveState.of(app).handInFinish(brief, System.currentTimeMillis())
        sync(app, StrengthRuntime.snapshots.current().active, Instant.now())
    }

    internal fun sync(context: Context, active: WorkoutSnapshot?, now: Instant) {
        synchronized(lock) {
            val state = LiveState.of(context)
            val finish = active?.finish
            when {
                active != null && finish != null -> showFinishCard(context, state, finish, key = active.workoutID)
                active != null -> showWorkout(context, state, active, now)
                else -> showNothing(context, state)
            }
        }
    }

    private fun showWorkout(context: Context, state: LiveState, active: WorkoutSnapshot, now: Instant) {
        // The planned session is over, an older finish card has been replaced.
        PlannedSessions.cancel(context)
        LiveUpdateNotifier.cancel(context, LiveIds.FINISH)
        state.finishPostedFor = null
        LiveUpdateNotifier.post(context, LiveUpdateModels.workout(active, now, state.dismissedCoachTip))
        applyAlarms(context, LiveAlarmPlan.of(active, now))
    }

    private fun showNothing(context: Context, state: LiveState) {
        state.takePendingFinish(System.currentTimeMillis())?.let {
            showFinishCard(context, state, it, key = null)
            return
        }
        LiveUpdateNotifier.cancel(context, LiveIds.LIVE)
        applyAlarms(context, LiveAlarmPlan.NONE)
        state.forgetCoachTip()
    }

    /** [key] identifies a finish that comes with the snapshot, so a card the user dismissed does not return with the next refresh. */
    private fun showFinishCard(context: Context, state: LiveState, brief: FinishBrief, key: String?) {
        LiveUpdateNotifier.cancel(context, LiveIds.LIVE)
        applyAlarms(context, LiveAlarmPlan.NONE)
        state.forgetCoachTip()
        if (key != null && state.finishPostedFor == key) return
        LiveUpdateNotifier.post(context, LiveUpdateModels.finish(brief))
        state.finishPostedFor = key
    }

    private fun applyAlarms(context: Context, plan: LiveAlarmPlan) {
        val restEnd = plan.restEndMillis
        if (restEnd != null) RestAlarms.scheduleRestEnd(context, restEnd) else RestAlarms.cancel(context)
        val momentEnd = plan.momentEndMillis
        if (momentEnd != null) LiveAlarms.schedule(context, AlarmSlot.MOMENT_END, momentEnd) else LiveAlarms.cancel(context, AlarmSlot.MOMENT_END)
    }
}
