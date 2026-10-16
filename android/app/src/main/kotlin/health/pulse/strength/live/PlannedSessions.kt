package health.pulse.strength.live

import android.content.Context
import android.content.SharedPreferences
import android.text.format.DateFormat
import health.pulse.strength.runtime.StrengthRuntime
import java.util.Date

/**
 * LA-06 Pre-workout countdown. A planned session shows a notification with a countdown to its start from 30 minutes before, with the
 * actions "Start now" and "Snooze 10 min"; at the start an exact alarm posts "Time to train". The plan is kept in `SharedPreferences`,
 * armed again after a reboot, and cancelled as soon as a workout runs (`LiveUpdates.refresh` does that). The host UI (owner: host)
 * calls [schedule] from the "Plan a session" dialog of the hub.
 */
object PlannedSessions {
    /**
     * Plans [templateId] to start at [startsAtEpochMillis]; replaces an earlier plan. Shows the countdown from 30 minutes before. A start
     * that is not in the future cancels the plan instead.
     */
    fun schedule(context: Context, templateId: String, startsAtEpochMillis: Long) {
        val app = context.applicationContext
        if (startsAtEpochMillis <= System.currentTimeMillis()) {
            cancel(app)
            return
        }
        val plan = PlannedSession(templateId, startsAtEpochMillis)
        store(app).write(plan)
        arm(app, plan)
    }

    /** Moves the planned start by [minutes] (from now when the start has already passed) and shows the countdown again. */
    fun snooze(context: Context, minutes: Int = PlannedSessionModels.SNOOZE_MINUTES) {
        val app = context.applicationContext
        val plan = store(app).read() ?: return
        val from = maxOf(plan.startsAtMillis, System.currentTimeMillis())
        val moved = plan.copy(startsAtMillis = from + minutes * 60_000L)
        store(app).write(moved)
        LiveUpdateNotifier.cancel(app, LiveIds.PLANNED_DUE)
        arm(app, moved)
    }

    /** Forgets the plan and removes its alarms and notifications. Cheap when there is no plan. */
    fun cancel(context: Context) {
        val app = context.applicationContext
        val store = store(app)
        if (store.read() == null) return
        store.clear()
        LiveAlarms.cancel(app, AlarmSlot.PLANNED_COUNTDOWN)
        LiveAlarms.cancel(app, AlarmSlot.PLANNED_DUE)
        LiveUpdateNotifier.cancel(app, LiveIds.PLANNED)
        LiveUpdateNotifier.cancel(app, LiveIds.PLANNED_DUE)
    }

    /** Arms the stored plan again: after a reboot or an update, or when the exact-alarm grant changed. */
    internal fun restore(context: Context) {
        val app = context.applicationContext
        val plan = store(app).read() ?: return
        if (PlannedSessionModels.phaseAt(plan, System.currentTimeMillis()) == PlannedPhase.EXPIRED) cancel(app) else arm(app, plan)
    }

    /** The alarm 30 minutes before the start. */
    internal fun showCountdown(context: Context) {
        val app = context.applicationContext
        val plan = store(app).read() ?: return
        if (PlannedSessionModels.phaseAt(plan, System.currentTimeMillis()) != PlannedPhase.COUNTDOWN) return
        LiveUpdateNotifier.post(app, PlannedSessionModels.countdown(plan, StrengthRuntime.snapshots.current(), startsAtText(app, plan)))
    }

    /** The alarm at the start. */
    internal fun showDue(context: Context) {
        val app = context.applicationContext
        val plan = store(app).read() ?: return
        if (PlannedSessionModels.phaseAt(plan, System.currentTimeMillis()) != PlannedPhase.DUE) return
        LiveUpdateNotifier.cancel(app, LiveIds.PLANNED)
        LiveUpdateNotifier.post(app, PlannedSessionModels.due(plan, StrengthRuntime.snapshots.current(), startsAtText(app, plan)))
    }

    /** Sets the two alarms that the phase of [plan] still needs, and shows the countdown right away when it is already running. */
    private fun arm(context: Context, plan: PlannedSession) {
        LiveAlarms.cancel(context, AlarmSlot.PLANNED_COUNTDOWN)
        LiveAlarms.cancel(context, AlarmSlot.PLANNED_DUE)
        when (PlannedSessionModels.phaseAt(plan, System.currentTimeMillis())) {
            PlannedPhase.WAITING -> {
                LiveAlarms.schedule(context, AlarmSlot.PLANNED_COUNTDOWN, plan.startsAtMillis - PlannedSessionModels.COUNTDOWN_LEAD_MILLIS)
                LiveAlarms.schedule(context, AlarmSlot.PLANNED_DUE, plan.startsAtMillis)
                LiveUpdateNotifier.cancel(context, LiveIds.PLANNED)
            }
            PlannedPhase.COUNTDOWN -> {
                LiveAlarms.schedule(context, AlarmSlot.PLANNED_DUE, plan.startsAtMillis)
                showCountdown(context)
            }
            PlannedPhase.DUE, PlannedPhase.EXPIRED -> Unit
        }
    }

    /** "18:00" or "6:00 PM", as the phone is set. */
    private fun startsAtText(context: Context, plan: PlannedSession): String =
        DateFormat.getTimeFormat(context).format(Date(plan.startsAtMillis))

    private fun store(context: Context) = PlannedSessionStore(context.getSharedPreferences("pulse_planned_session", Context.MODE_PRIVATE))
}

/** The plan in `SharedPreferences`: it has to survive the process and (through the boot receiver) a reboot. */
internal class PlannedSessionStore(private val prefs: SharedPreferences) {
    fun read(): PlannedSession? {
        val templateId = prefs.getString(KEY_TEMPLATE, null) ?: return null
        val startsAt = prefs.getLong(KEY_STARTS_AT, 0L)
        return if (startsAt > 0L) PlannedSession(templateId, startsAt) else null
    }

    fun write(plan: PlannedSession) {
        prefs.edit().putString(KEY_TEMPLATE, plan.templateId).putLong(KEY_STARTS_AT, plan.startsAtMillis).apply()
    }

    fun clear() {
        prefs.edit().remove(KEY_TEMPLATE).remove(KEY_STARTS_AT).apply()
    }

    private companion object {
        const val KEY_TEMPLATE = "template_id"
        const val KEY_STARTS_AT = "starts_at"
    }
}
