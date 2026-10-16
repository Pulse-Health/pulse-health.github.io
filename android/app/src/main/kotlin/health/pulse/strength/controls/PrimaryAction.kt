package health.pulse.strength.controls

import android.content.Context
import android.os.VibrationEffect
import android.os.Vibrator
import android.widget.Toast
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.live.LiveText
import health.pulse.strength.runtime.StrengthRuntime
import health.pulse.strength.surfaces.Surfaces

/** The three meanings of the one button (CT-10). */
internal enum class PrimaryKind {
    /** A workout waits for its next set. */
    LOG_SET,

    /** A rest counts down. */
    SKIP_REST,

    /** Nothing runs. */
    START_NEXT,
}

/**
 * CT-10 Action button analogue: one intent, three meanings. The routing itself is `WorkoutCommands.primaryAction` (log set while
 * logging, skip rest while resting, start the next workout with none running, never finish); this object runs it and tells the person
 * what it did, because the activity that gets the hardware button has no window.
 */
internal object PrimaryAction {
    /** What `WorkoutCommands.primaryAction` will do for [snapshot]; it decides on the stored phase, and so does this. */
    fun kindFor(snapshot: WidgetSnapshot): PrimaryKind {
        val active = snapshot.active
        return when {
            active == null -> PrimaryKind.START_NEXT
            active.phase == SnapshotPhase.RESTING -> PrimaryKind.SKIP_REST
            else -> PrimaryKind.LOG_SET
        }
    }

    /** The line shown after the press, from the snapshot as it was when the button was pressed ("Set logged · 80 kg × 6"). */
    fun confirmation(snapshot: WidgetSnapshot): String {
        val active = snapshot.active
        return when (kindFor(snapshot)) {
            PrimaryKind.START_NEXT -> snapshot.nextUp?.let { "Starting ${it.name}" } ?: "No workout to start"
            PrimaryKind.SKIP_REST -> "Rest skipped"
            PrimaryKind.LOG_SET -> when {
                active == null || active.targetSetID == null -> "All sets logged"
                else -> "Set logged · ${LiveText.work(active)}"
            }
        }
    }

    /** Presses the button: runs the command and refreshes every surface. Returns the confirmation to show ([feedback]). */
    suspend fun press(context: Context): String {
        val app = context.applicationContext
        val message = confirmation(StrengthRuntime.snapshots.current())
        StrengthRuntime.commands.primaryAction()
        Surfaces.refreshAll(app)
        return message
    }

    /** The confirmation for a press that the person cannot see happen: a short buzz and a toast. */
    fun feedback(context: Context, message: String) {
        val vibrator = context.getSystemService(Vibrator::class.java)
        if (vibrator != null && vibrator.hasVibrator()) vibrator.vibrate(VibrationEffect.createOneShot(TICK_MS, VibrationEffect.DEFAULT_AMPLITUDE))
        Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
    }

    private const val TICK_MS = 40L
}
