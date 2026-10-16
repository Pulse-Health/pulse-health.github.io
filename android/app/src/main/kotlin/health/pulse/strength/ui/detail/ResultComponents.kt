package health.pulse.strength.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseTheme

// Small pieces shared by the exercise detail and the workout summary.

/**
 * A design length that holds text (a badge around a number, a chart height) grown with the user's font size, but never below the
 * design value and never beyond [maxScale]: the Android counterpart of `@PulseScaled`.
 */
@Composable
internal fun scaledDp(design: Dp, maxScale: Float = 1.6f): Dp {
    val scale = LocalDensity.current.fontScale.coerceIn(1f, maxScale)
    return design * scale
}

/** True at the biggest system font sizes (the counterpart of the iOS accessibility sizes): the layouts then stack. */
@Composable
internal fun isLargeFontScale(): Boolean = LocalDensity.current.fontScale >= LargeFontScale

/** Font scale from which rows stack their parts (iOS: the accessibility text sizes start near 1.6). */
internal const val LargeFontScale = 1.5f

/** A 0.5 dp separator line (rgba(60,60,67,0.18) in the design). */
@Composable
internal fun StrengthHairline(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .height(0.5.dp)
            .background(PulseTheme.colors.separator),
    )
}

/** The yellow "PR" tag of the session rows and the exercise results. */
@Composable
internal fun StrengthPRChip(horizontal: Dp, vertical: Dp, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Text(
        text = "PR",
        style = PulseFont.text(11.sp, FontWeight.Bold),
        color = colors.prText,
        modifier = modifier
            .background(colors.prFill, CircleShape)
            .padding(horizontal = horizontal, vertical = vertical)
            .semantics { contentDescription = "Personal record" },
    )
}

/**
 * One line of text that shrinks (down to [minScale] of its size) before it would not fit, then truncates: the counterpart of
 * SwiftUI's `lineLimit(1)` + `minimumScaleFactor`. The line height of [style] is kept, so neighbours stay level when one text
 * shrinks; give [style] an explicit `lineHeight` for that.
 *
 * With [singleLine] false the text simply wraps (the layouts for very large fonts, where nothing shrinks).
 */
@Composable
internal fun FitText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    minScale: Float = 0.7f,
    singleLine: Boolean = true,
    textAlign: TextAlign? = null,
) {
    if (!singleLine) {
        Text(text, style = style, color = color, modifier = modifier, textAlign = textAlign)
        return
    }
    val measurer = rememberTextMeasurer()
    BoxWithConstraints(modifier) {
        val available = constraints.maxWidth
        val fitted = remember(text, style, available, measurer) {
            if (constraints.hasBoundedWidth && available > 0 && style.fontSize.isSp) {
                val width = measurer.measure(text, style, softWrap = false, maxLines = 1).size.width
                if (width > available) {
                    val scale = (available.toFloat() / width).coerceIn(minScale, 1f)
                    style.copy(fontSize = style.fontSize * scale, lineHeight = style.lineHeight)
                } else {
                    style
                }
            } else {
                style
            }
        }
        Text(
            text,
            style = fitted,
            color = color,
            maxLines = 1,
            softWrap = false,
            overflow = TextOverflow.Ellipsis,
            textAlign = textAlign,
        )
    }
}
