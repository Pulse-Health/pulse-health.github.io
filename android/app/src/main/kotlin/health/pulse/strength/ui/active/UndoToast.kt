package health.pulse.strength.ui.active

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight

/**
 * The dark toast that offers "Undo" after an exercise was removed or a set was deleted ("Removed Cable crossover", "Set deleted").
 * The caller shows it while `ActiveWorkoutPresentation.undoText` is non-null and dispatches `WorkoutAction.Undo` from [onUndo].
 * The text is a live region, so a screen reader announces it when the toast appears, and it has an "Undo" action of its own (the
 * TalkBack actions menu and Switch Access list it): the user does not have to find the Undo button among everything else on the
 * screen. The undo window (6 s) is the reducer's, so the toast cannot stay longer than the undo is valid.
 */
@Composable
internal fun UndoToast(text: String, onUndo: () -> Unit, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    val shape = RoundedCornerShape(14.dp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .shadow(12.dp, shape, clip = false, ambientColor = Color.Black.copy(alpha = 0.2f), spotColor = Color.Black.copy(alpha = 0.3f))
            .background(colors.toastFill.copy(alpha = 0.96f), shape)
            .pulseMinHeight(48.dp)
            .padding(start = 16.dp, end = 6.dp)
            .testTag("undo-toast"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = text,
            style = PulseFont.subhead,
            color = Color.White,
            maxLines = if (isLargeText()) 2 else 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .weight(1f)
                .padding(vertical = 8.dp)
                .semantics {
                    liveRegion = LiveRegionMode.Polite
                    customActions = listOf(CustomAccessibilityAction("Undo") { onUndo(); true })
                },
        )
        Box(
            modifier = Modifier
                .pulseMinHeight(48.dp)
                .testTag("undo-button")
                .pulseClickable(onClickLabel = "Restore what was just removed", onClick = onUndo)
                .padding(horizontal = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text("Undo", style = PulseFont.text(15.sp, FontWeight.SemiBold), color = colors.toastAction, maxLines = 1)
        }
    }
}
