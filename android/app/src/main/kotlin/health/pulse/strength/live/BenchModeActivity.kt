package health.pulse.strength.live

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.text.format.DateFormat
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.runtime.StrengthRuntime
import health.pulse.strength.surfaces.Surfaces
import health.pulse.strength.widgets.common.PulseActions

/**
 * SB-02 / SB-04 Bench mode: a full-screen screen for the phone that leans against the bench. It shows over the lock screen, keeps the
 * display on, draws edge to edge without system bars, and renders `StrengthRuntime.snapshots` live ([BenchModeScreen]). Opened with
 * [BenchMode.intent] from the host UI, the widgets, the Rest tile and the notification of a running rest; not exported.
 */
class BenchModeActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
        showOverLockScreen()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        hideSystemBars()

        val forcedNight = if (intent.hasExtra(BenchMode.EXTRA_NIGHT)) intent.getBooleanExtra(BenchMode.EXTRA_NIGHT, false) else null
        val is24Hour = DateFormat.is24HourFormat(this)
        val actions = BenchActions(
            adjustRest = { seconds -> launchCommand { StrengthRuntime.commands.adjustRest(seconds) } },
            skipRest = { launchCommand { StrengthRuntime.commands.skipRest() } },
            logSet = { launchCommand { StrengthRuntime.commands.logNextSet() } },
            resume = { launchCommand { StrengthRuntime.commands.resume() } },
            openWorkout = { startActivity(PulseActions.linkIntent(DeepLinks.workout)) },
            close = { finish() },
        )
        setContent {
            val snapshot by StrengthRuntime.snapshots.snapshot.collectAsStateWithLifecycle()
            BenchModeScreen(snapshot, forcedNight, is24Hour, actions)
        }
    }

    /** Runs a command on the app scope, so it completes even if this screen is closed at once, then refreshes every surface. */
    private fun launchCommand(command: suspend () -> Unit) {
        val app = applicationContext
        SystemScope.launch {
            command()
            Surfaces.refreshAll(app)
        }
    }

    /** Show-when-locked and turn-screen-on: attributes of the activity from Android 8.1, window flags before. */
    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        }
    }

    /** Immersive: the bars come back with a swipe from the edge. */
    private fun hideSystemBars() {
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.systemBars())
    }
}
