package health.pulse.strength.health

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import health.pulse.strength.R
import health.pulse.strength.ui.PrivacyLinks
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulsePrimaryButton
import health.pulse.strength.ui.theme.PulseTheme
import androidx.compose.foundation.background

/**
 * Health Connect asks every app that writes health data for a screen that explains why: this is it. It is opened from Health
 * Connect's permission dialog and settings ("Privacy policy" / "How this app uses your data").
 */
class PermissionsRationaleActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            PulseTheme {
                val colors = PulseTheme.colors
                Column(
                    Modifier.fillMaxSize().background(colors.ground).safeDrawingPadding().verticalScroll(rememberScrollState()).padding(20.dp),
                    verticalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(14.dp),
                ) {
                    Text(getString(R.string.hc_rationale_title), style = PulseFont.title, color = colors.ink)
                    Text(getString(R.string.hc_rationale_body), style = PulseFont.body, color = colors.ink)
                    Text(getString(R.string.hc_rationale_offline), style = PulseFont.subhead, color = colors.inkSecondary)
                    PulsePrimaryButton(
                        text = getString(R.string.privacy_policy),
                        onClick = { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PrivacyLinks.policyUrl))) },
                    )
                    PulsePrimaryButton(text = getString(R.string.close), onClick = { finish() })
                }
            }
        }
    }
}
