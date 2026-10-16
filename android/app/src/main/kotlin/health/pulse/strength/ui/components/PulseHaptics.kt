package health.pulse.strength.ui.components

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalView

/**
 * The haptic vocabulary of the screens (the Android counterpart of the iOS feedback generators). Every call is a no-op when the
 * user turned touch feedback off in the system settings, because it goes through [View.performHapticFeedback].
 */
class PulseHaptics(private val view: View) {
    /** A light tap: stepping a value, toggling a chip, adding something. */
    fun light() = perform(HapticFeedbackConstants.CLOCK_TICK)

    /** A medium tap: starting a workout. */
    fun medium() = perform(HapticFeedbackConstants.CONTEXT_CLICK)

    /** A selection changed: picking a preset, a segment, a set type. */
    fun selection() = perform(
        if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.SEGMENT_FREQUENT_TICK else HapticFeedbackConstants.CLOCK_TICK,
    )

    /** A set was logged, a workout was saved, the rest is over. */
    fun success() = perform(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.LONG_PRESS)

    /** A destructive step (delete, discard, remove). */
    fun warning() = perform(if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS)

    private fun perform(constant: Int) {
        view.performHapticFeedback(constant)
    }
}

@Composable
fun rememberPulseHaptics(): PulseHaptics {
    val view = LocalView.current
    return remember(view) { PulseHaptics(view) }
}
