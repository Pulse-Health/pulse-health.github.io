package health.pulse.strength.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * A clickable surface that fades while pressed (the design's plain button style: rows, cells), without the ripple.
 * Its [role] and [onClickLabel] are what TalkBack announces. A faint wash over the whole surface shows the press on a button whose
 * fill sits outside this modifier, and a ring shows keyboard / D-pad focus (the ripple would have drawn it).
 */
@Composable
fun Modifier.pulseClickable(
    enabled: Boolean = true,
    onClickLabel: String? = null,
    role: Role? = Role.Button,
    pressedAlpha: Float = 0.6f,
    onClick: () -> Unit,
): Modifier {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val focused by source.collectIsFocusedAsState()
    val colors = PulseTheme.colors
    return this
        .graphicsLayer { alpha = if (pressed && enabled) pressedAlpha else 1f }
        .drawWithContent {
            drawContent()
            val radius = CornerRadius(10.dp.toPx())
            if (pressed && enabled) drawRoundRect(colors.ink.copy(alpha = 0.08f), cornerRadius = radius)
            if (focused && enabled) {
                val width = 2.dp.toPx()
                drawRoundRect(
                    colors.green,
                    topLeft = Offset(width / 2, width / 2),
                    size = Size(size.width - width, size.height - width),
                    cornerRadius = radius,
                    style = Stroke(width),
                )
            }
        }
        .clickable(
            interactionSource = source,
            indication = null,
            enabled = enabled,
            onClickLabel = onClickLabel,
            role = role,
            onClick = onClick,
        )
}

/** A design height (a control that contains text) that grows with the user's font size but never drops below the design value. */
@Composable
fun Modifier.pulseMinHeight(design: Dp, maxScale: Float = 1.6f): Modifier {
    val scale = LocalDensity.current.fontScale.coerceIn(1f, maxScale)
    return this.heightIn(min = design * scale)
}

/** White card with the design's soft shadow. */
@Composable
fun Modifier.pulseCard(radius: Dp = PulseMetrics.cardRadius, shadow: Boolean = true): Modifier {
    val shape = RoundedCornerShape(radius)
    val shadowColor = Color.Black.copy(alpha = 0.07f)
    return this
        .shadow(if (shadow) 4.dp else 0.dp, shape, clip = false, ambientColor = shadowColor, spotColor = shadowColor)
        .background(PulseTheme.colors.card, shape)
}

/** Full-width green call to action (52 dp, radius 14). */
@Composable
fun PulsePrimaryButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    val colors = PulseTheme.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .pulseMinHeight(52.dp)
            .background(colors.green.copy(alpha = if (enabled) 1f else 0.4f), RoundedCornerShape(14.dp))
            .pulseClickable(enabled = enabled, pressedAlpha = 0.8f, onClick = onClick)
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) { content() }
}

@Composable
fun PulsePrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    PulsePrimaryButton(onClick = onClick, modifier = modifier, enabled = enabled) {
        Text(text, style = PulseFont.headline, color = PulseTheme.colors.onGreen)
    }
}

/** Grey tinted button with green text ("Add Set", stepper buttons). */
@Composable
fun PulseTintButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    radius: Dp = PulseMetrics.rowRadius,
    enabled: Boolean = true,
    content: @Composable RowScope.() -> Unit,
) {
    Row(
        modifier = modifier
            .pulseMinHeight(48.dp)
            .background(PulseTheme.colors.cellFill, RoundedCornerShape(radius))
            .pulseClickable(enabled = enabled, pressedAlpha = 0.7f, onClick = onClick)
            .padding(horizontal = 12.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) { content() }
}

@Composable
fun PulseTintButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    PulseTintButton(onClick = onClick, modifier = modifier, enabled = enabled) {
        Text(text, style = PulseFont.text(15.sp, FontWeight.SemiBold), color = PulseTheme.colors.greenText)
    }
}

/** The blue "Finish" pill. */
@Composable
fun PulsePillButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    Row(
        modifier = modifier
            .pulseMinHeight(48.dp)
            .background(PulseTheme.colors.pillFill.copy(alpha = if (enabled) 1f else 0.4f), CircleShape)
            .pulseClickable(enabled = enabled, pressedAlpha = 0.8f, onClick = onClick)
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text, style = PulseFont.text(15.sp, FontWeight.SemiBold), color = Color.White)
    }
}

/** Filter chip (picker, create form): blue tint when selected. */
@Composable
fun PulseChip(title: String, isSelected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Box(
        modifier = modifier
            .pulseMinHeight(40.dp)
            .background(if (isSelected) colors.blueTint else colors.chipFill, CircleShape)
            .semantics { selected = isSelected }
            .pulseClickable(role = Role.Tab, onClick = onClick)
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            style = PulseFont.text(15.sp, if (isSelected) FontWeight.SemiBold else FontWeight.Medium),
            color = if (isSelected) colors.blueText else colors.ink.copy(alpha = 0.75f),
        )
    }
}

/** iOS-style segmented control (RIR selector, tracking kind). */
@Composable
fun <T> PulseSegmented(
    options: List<Pair<T, String>>,
    selection: T,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = PulseTheme.colors
    Row(
        modifier = modifier
            .background(colors.chipFill, RoundedCornerShape(9.dp))
            .padding(2.dp),
    ) {
        for ((value, title) in options) {
            val isSelected = value == selection
            Box(
                modifier = Modifier
                    .weight(1f)
                    .pulseMinHeight(40.dp)
                    .then(
                        if (isSelected) {
                            Modifier.shadow(2.dp, RoundedCornerShape(7.dp), clip = false).background(colors.segmentThumb, RoundedCornerShape(7.dp))
                        } else {
                            Modifier
                        },
                    )
                    .semantics { selected = isSelected }
                    .pulseClickable(role = Role.RadioButton, onClick = { onSelect(value) }),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    title,
                    style = PulseFont.number(15.sp, if (isSelected) FontWeight.Bold else FontWeight.Medium),
                    color = colors.ink,
                )
            }
        }
    }
}
