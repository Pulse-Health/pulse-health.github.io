package health.pulse.strength.wear

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.wear.ui.PulseWearTheme
import health.pulse.strength.wear.ui.WearRoot
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

/**
 * The watch app: the week, the next workout, and the controls of a running one (see `WearScreen`). Tiles, complications and the Ongoing
 * Activity open it; a tile or complication that starts the next workout does so with [EXTRA_COMMAND].
 */
class WearMainActivity : ComponentActivity() {
    private val startRequests = MutableStateFlow(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A recreated activity (a changed font size, a process restore) must not start a workout a second time.
        if (savedInstanceState == null) takeCommand(intent)
        setContent { PulseWearTheme { WearRoot(startRequests) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        takeCommand(intent)
    }

    /** Reads, and removes, the command a tile or complication asked for. Only `startNext` is honoured: the activity is exported. */
    private fun takeCommand(intent: Intent?) {
        val command = intent?.getStringExtra(EXTRA_COMMAND) ?: return
        intent.removeExtra(EXTRA_COMMAND)
        if (command == WidgetCommands.START_NEXT) startRequests.update { it + 1 }
    }

    companion object {
        /** Intent extra naming a command the activity runs when it opens (only `startNext` is honoured). */
        const val EXTRA_COMMAND = "health.pulse.strength.wear.extra.COMMAND"
    }
}
