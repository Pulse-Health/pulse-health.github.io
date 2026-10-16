package health.pulse.strength.ui.hub

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.ui.theme.PulsePrimaryButton

/** The Strength hub (OWNER: hub agent; this placeholder only exists so the app compiles until the screen is ported). */
@Composable
fun StrengthHubScreen(
    environment: StrengthAppEnvironment,
    onStart: (WorkoutTemplate?) -> Unit,
    onResume: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxSize().safeDrawingPadding().padding(16.dp)) {
        Text("Strength")
        PulsePrimaryButton(text = "Start empty workout", onClick = { onStart(null) })
    }
}
