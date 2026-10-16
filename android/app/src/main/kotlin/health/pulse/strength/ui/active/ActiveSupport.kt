package health.pulse.strength.ui.active

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.ui.theme.LocalReduceMotion
import health.pulse.strength.ui.theme.pulseClickable
import kotlin.math.max

// Small helpers shared by the active-workout components.

/** Largest font scale that still grows the "design size" lengths (control heights, ring, button widths); text itself is not capped. */
internal const val MaxLayoutFontScale = 1.6f

/** A design length that grows with the user's font size (never below the design value): the Dynamic Type `@PulseScaled` counterpart. */
@Composable
@ReadOnlyComposable
internal fun Dp.fontScaled(maxScale: Float = MaxLayoutFontScale): Dp = this * LocalDensity.current.fontScale.coerceIn(1f, maxScale)

/** True when the user chose a clearly bigger text size than the default (the "whenLarger" rules of the design). */
@Composable
@ReadOnlyComposable
internal fun isLargeText(): Boolean = LocalDensity.current.fontScale > 1.12f

/**
 * A text size of [size] sp that follows the user's font size only up to [maxScale] (decorative captions such as the column titles
 * of the set table: every row announces its own values, and a big caption would take the room of the figures).
 */
@Composable
@ReadOnlyComposable
internal fun cappedSp(size: Float, maxScale: Float = 1.3f): TextUnit {
    val fontScale = LocalDensity.current.fontScale
    return (size * minOf(1f, maxScale / fontScale)).sp
}

private class EqualHolder<T>(var value: T)

/**
 * Returns [value], but keeps handing out the previous instance while the new one is `==` to it. The presentation is rebuilt every
 * second; its parts (card, rows, dock) usually are equal, so the composables that take them can skip recomposition.
 */
@Composable
internal fun <T> rememberEqual(value: T): T {
    val holder = remember { EqualHolder(value) }
    if (holder.value != value) holder.value = value
    return holder.value
}

/** A 48 dp tap target announced as a button named [label]; [content] draws the glyph. */
@Composable
internal fun ActiveTapTarget(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    tag: String? = null,
    content: @Composable BoxScope.() -> Unit,
) {
    Box(
        modifier = modifier
            .size(48.dp)
            .then(if (tag != null) Modifier.testTag(tag) else Modifier)
            .alpha(if (enabled) 1f else 0.3f)
            .pulseClickable(enabled = enabled, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
        content = content,
    )
}

/** [ActiveTapTarget] around a Material glyph. */
@Composable
internal fun ActiveIconButton(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    tint: Color,
    iconSize: Dp = 24.dp,
    enabled: Boolean = true,
    tag: String? = null,
) {
    ActiveTapTarget(label = label, onClick = onClick, modifier = modifier, enabled = enabled, tag = tag) {
        Icon(imageVector = icon, contentDescription = null, tint = tint, modifier = Modifier.size(iconSize))
    }
}

/** The "ellipsis in a circle" glyph of the More and exercise-options buttons. */
@Composable
internal fun EllipsisCircleIcon(tint: Color, modifier: Modifier = Modifier, size: Dp = 24.dp) {
    Canvas(modifier.size(size)) {
        val stroke = size.toPx() * 0.075f
        val radius = size.toPx() / 2 - stroke / 2
        drawCircle(tint, radius = radius, style = Stroke(width = stroke))
        val dot = size.toPx() * 0.058f
        val gap = size.toPx() * 0.215f
        for (i in -1..1) drawCircle(tint, radius = dot, center = Offset(center.x + i * gap, center.y))
    }
}

/**
 * Shows [content] for a value that comes and goes (the rest dock, the undo toast) with a slide + fade, or just a fade when the user
 * turned animations off. The last non-null value stays on screen while the exit animation runs.
 */
@Composable
internal fun <T : Any> AnimatedAppearance(
    value: T?,
    modifier: Modifier = Modifier,
    content: @Composable (T) -> Unit,
) {
    val last = remember { EqualHolder<T?>(null) }
    if (value != null) last.value = value
    val reduceMotion = LocalReduceMotion.current
    val enter: EnterTransition = if (reduceMotion) {
        fadeIn()
    } else {
        fadeIn() + slideInVertically { it / 2 } + expandVertically(expandFrom = Alignment.Bottom)
    }
    val exit: ExitTransition = if (reduceMotion) {
        fadeOut()
    } else {
        fadeOut() + slideOutVertically { it / 2 } + shrinkVertically(shrinkTowards = Alignment.Bottom)
    }
    AnimatedVisibility(visible = value != null, modifier = modifier, enter = enter, exit = exit) {
        last.value?.let { content(it) }
    }
}

/**
 * One-line text that shrinks (down to [minScale] of its size) when it does not fit its width, the `minimumScaleFactor` of the
 * design for the figures in fixed-width columns. Text that still does not fit is clipped.
 */
@Composable
internal fun ShrinkToFitText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    minScale: Float = 0.7f,
    textAlign: TextAlign? = null,
) {
    val fontScale = LocalDensity.current.fontScale
    var scale by remember(text, style.fontSize, fontScale) { mutableFloatStateOf(1f) }
    Text(
        text = text,
        modifier = modifier,
        color = color,
        style = style.copy(fontSize = style.fontSize * scale),
        textAlign = textAlign,
        maxLines = 1,
        softWrap = false,
        overflow = TextOverflow.Clip,
        onTextLayout = { result ->
            if (result.didOverflowWidth && scale > minScale) {
                val available = result.layoutInput.constraints.maxWidth.toFloat()
                val needed = result.multiParagraph.maxIntrinsicWidth
                if (needed > 0f && available.isFinite()) scale = max(minScale, scale * (available / needed) * 0.98f)
            }
        },
    )
}
