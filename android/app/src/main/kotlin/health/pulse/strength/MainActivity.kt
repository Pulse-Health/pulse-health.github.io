package health.pulse.strength

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import health.pulse.strength.core.StrengthConfig
import health.pulse.strength.ui.PulseStrengthRoot
import health.pulse.strength.ui.theme.PulseTheme

class MainActivity : ComponentActivity() {
    private val environment: StrengthAppEnvironment
        get() = (application as PulseStrengthApplication).environment

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) handle(intent)
        setContent {
            PulseTheme {
                PulseStrengthRoot(environment)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    /** `pulse-strength://workout` (and the ongoing notification's tap) shows the running workout. */
    private fun handle(intent: Intent?) {
        val data = intent?.data
        val isDeepLink = data != null &&
            data.scheme.equals(StrengthConfig.urlScheme, ignoreCase = true) &&
            data.host.equals("workout", ignoreCase = true)
        if (isDeepLink || intent?.getBooleanExtra(EXTRA_OPEN_WORKOUT, false) == true) environment.requestOpenWorkout()
    }

    companion object {
        /** Extra set by the ongoing notification's content intent. */
        const val EXTRA_OPEN_WORKOUT = "health.pulse.strength.OPEN_WORKOUT"
    }
}
