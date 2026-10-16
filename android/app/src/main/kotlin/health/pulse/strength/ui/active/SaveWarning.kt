package health.pulse.strength.ui.active

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulseTheme

/**
 * Tells the user that the workout in progress could not be written to the phone (usually: the storage is full), so it is not safe
 * if the app is closed now. It stays until a save works again. It is a live region, so a screen reader announces it.
 */
@Composable
internal fun SaveWarning(modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Row(
        modifier = modifier
            .widthIn(max = PulseMetrics.maxContentWidth)
            .fillMaxWidth()
            .padding(horizontal = PulseMetrics.screenInset, vertical = 4.dp)
            .background(colors.destructive.copy(alpha = 0.12f), RoundedCornerShape(12.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp)
            .testTag("save-warning")
            .semantics { liveRegion = LiveRegionMode.Assertive },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "Can't save your workout. The phone may be out of storage; free up some space. Your sets stay on screen.",
            style = PulseFont.subhead,
            color = colors.ink,
        )
    }
}
