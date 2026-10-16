package health.pulse.strength.ui.active

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Menu
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.ActiveWorkoutPresentation
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight

/**
 * The exercise navigator capsule ("<  1 / 6  >") and the Edit pill next to it. On a narrow window with big text the pill wraps
 * under the capsule.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun NavigatorBar(
    navigator: ActiveWorkoutPresentation.Navigator,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
    onEdit: () -> Unit,
    modifier: Modifier = Modifier,
) {
    FlowRow(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalArrangement = Arrangement.spacedBy(8.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        Capsule(navigator, onPrevious, onNext)
        EditPill(onEdit)
    }
}

@Composable
private fun Capsule(navigator: ActiveWorkoutPresentation.Navigator, onPrevious: () -> Unit, onNext: () -> Unit) {
    val colors = PulseTheme.colors
    Row(
        modifier = Modifier
            .pulseMinHeight(48.dp)
            .background(colors.chipFill, CircleShape),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ActiveIconButton(
            icon = Icons.Rounded.ChevronLeft,
            label = "Previous exercise",
            onClick = onPrevious,
            tint = colors.green,
            iconSize = 28.dp,
            enabled = navigator.canGoPrevious,
            tag = "active-previous",
        )
        Text(
            text = positionText(navigator),
            style = PulseFont.number(17.sp, FontWeight.SemiBold),
            textAlign = TextAlign.Center,
            maxLines = 1,
            modifier = Modifier
                .widthIn(min = 62.dp)
                .testTag("active-position")
                .semantics { contentDescription = "Exercise ${navigator.position} of ${navigator.total}" },
        )
        ActiveIconButton(
            icon = Icons.Rounded.ChevronRight,
            label = "Next exercise",
            onClick = onNext,
            tint = colors.green,
            iconSize = 28.dp,
            enabled = navigator.canGoNext,
            tag = "active-next",
        )
    }
}

/** "1" in ink, " / 6" in secondary ink. */
@Composable
private fun positionText(navigator: ActiveWorkoutPresentation.Navigator): AnnotatedString {
    val colors = PulseTheme.colors
    return buildAnnotatedString {
        withStyle(SpanStyle(color = colors.ink)) { append(navigator.position.toString()) }
        withStyle(SpanStyle(color = colors.inkSecondary, fontWeight = FontWeight.Medium)) { append(" / ${navigator.total}") }
    }
}

@Composable
private fun EditPill(onEdit: () -> Unit) {
    val colors = PulseTheme.colors
    Row(
        modifier = Modifier
            .pulseMinHeight(48.dp)
            .background(colors.chipFill, CircleShape)
            .pulseClickable(onClickLabel = "Reorder, add or remove exercises", onClick = onEdit)
            .padding(horizontal = 16.dp)
            .testTag("active-edit"),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.Menu, contentDescription = null, tint = colors.greenText, modifier = Modifier.size(20.dp))
        Text("Edit", style = PulseFont.headline, color = colors.greenText, maxLines = 1)
    }
}
