package health.pulse.strength.controls

import android.app.Activity
import android.os.Bundle
import health.pulse.strength.live.SystemScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

/**
 * CT-10 Action button analogue. A transparent activity without a window that runs the primary action (log set while logging, skip
 * rest while resting, start the next workout with none running) and finishes. Hardware buttons start it: Pixel Quick Tap and the
 * Samsung side key through the launcher shortcut "Primary action" (res/xml/shortcuts.xml), routines through the component. It is
 * exported for exactly that reason; the action is harmless to run by anyone (it never finishes a workout).
 */
class PrimaryActionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = applicationContext
        // The command runs on the app scope, so it completes even if the system tears this activity down first.
        SystemScope.launch {
            var message: String? = null
            try {
                message = PrimaryAction.press(app)
            } finally {
                // Whatever happened, the invisible activity must not stay on top of the screen.
                withContext(NonCancellable + Dispatchers.Main) {
                    message?.let { PrimaryAction.feedback(app, it) }
                    if (!isFinishing) finish()
                }
            }
        }
    }
}
