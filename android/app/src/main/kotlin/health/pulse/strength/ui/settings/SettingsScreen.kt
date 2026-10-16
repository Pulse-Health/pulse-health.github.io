package health.pulse.strength.ui.settings

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import health.pulse.strength.StrengthAppEnvironment

/**
 * Settings and About (OWNER: lead; placeholder until the platform services exist): Health Connect, notifications, the privacy policy
 * link, version and attributions. The hub opens it from a settings icon in its top bar.
 */
@Composable
fun SettingsScreen(environment: StrengthAppEnvironment, onBack: () -> Unit, modifier: Modifier = Modifier) {
    Text("Settings", modifier)
}
