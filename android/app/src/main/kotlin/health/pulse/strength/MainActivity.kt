package health.pulse.strength

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import health.pulse.strength.core.widgets.StrengthDeepLink
import health.pulse.strength.ui.PulseStrengthRoot
import health.pulse.strength.ui.theme.PulseTheme
import kotlinx.coroutines.launch

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

    /**
     * Every `pulse-strength://` link of widgets/SPEC.md section 4 (`workout`, `hub`, `start-next`, `start`, `start-empty`, `exercise/<id>`,
     * `plates`, `weight`) and the ongoing notification's tap, which shows the running workout.
     */
    private fun handle(intent: Intent?) {
        val link = StrengthDeepLink.parse(intent?.dataString)
        when {
            link != null -> lifecycleScope.launch { DeepLinkRouter(environment).open(link) }
            intent?.getBooleanExtra(EXTRA_OPEN_WORKOUT, false) == true -> environment.hostRequests.post(HostRequest.OpenWorkout)
        }
    }

    companion object {
        /** Extra set by the ongoing notification's content intent. */
        const val EXTRA_OPEN_WORKOUT = "health.pulse.strength.OPEN_WORKOUT"
    }
}
