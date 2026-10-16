package health.pulse.strength.widgets.lock

import android.util.Log
import androidx.annotation.DrawableRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import health.pulse.strength.widgets.common.ChartBitmaps
import health.pulse.strength.widgets.common.MaskImage
import health.pulse.strength.widgets.common.WidgetDimens
import health.pulse.strength.widgets.common.onLink
import health.pulse.strength.widgets.common.toPx
import kotlinx.coroutines.CancellationException

/**
 * Building blocks of the lock screen / glanceable hub widgets (LS-01 ... LS-11), which the extras widgets (WI-01 ... WI-11) reuse: the
 * rounded card, text, a tinted glyph, the 270 degree gauge and the meter bar. Charts are bitmap masks tinted with the theme's colours, so
 * they follow light and dark mode like the text does.
 */

/**
 * The card a widget sits on: the widget background with rounded corners, [padding] inside, and one tap target (the whole card) that opens
 * [link]. [description] is what a screen reader says for the whole card, in place of its pieces; pass null for a card that holds buttons
 * of its own, so they stay reachable one by one. The chart images inside carry their own descriptions as well.
 */
@Composable
internal fun WidgetCard(
    description: String?,
    link: String,
    cornerRadius: Dp = WidgetDimens.corner,
    padding: Dp = WidgetDimens.paddingCompact,
    background: ColorProvider = GlanceTheme.colors.surface,
    contentAlignment: Alignment = Alignment.Center,
    content: @Composable () -> Unit,
) {
    val described = if (description != null) GlanceModifier.semantics { contentDescription = description } else GlanceModifier
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .background(background)
            .cornerRadius(cornerRadius)
            .padding(padding)
            .then(described)
            .onLink(link),
        contentAlignment = contentAlignment,
        content = content,
    )
}

/** One style for every piece of widget text; [maxLines] defaults to a single line, which ellipsizes at the end. */
@Composable
internal fun PulseText(
    text: String,
    size: TextUnit,
    modifier: GlanceModifier = GlanceModifier,
    weight: FontWeight = FontWeight.Normal,
    color: ColorProvider = GlanceTheme.colors.onSurface,
    maxLines: Int = 1,
    align: TextAlign? = null,
) {
    Text(
        text = text,
        modifier = modifier,
        maxLines = maxLines,
        style = TextStyle(color = color, fontSize = size, fontWeight = weight, textAlign = align),
    )
}

/** The small upper-case label above a value ("NEXT UP"). */
@Composable
internal fun Eyebrow(
    text: String,
    size: TextUnit = 12.sp,
    color: ColorProvider = GlanceTheme.colors.onSurfaceVariant,
    modifier: GlanceModifier = GlanceModifier,
    maxLines: Int = 1,
    align: TextAlign? = null,
) {
    PulseText(text.uppercase(), size, modifier, FontWeight.Bold, color, maxLines, align)
}

/** A vector glyph from `res/drawable` drawn as a mask in [tint]. Pass a [description] only when the glyph says something the text does not. */
@Composable
internal fun Glyph(@DrawableRes icon: Int, size: Dp, tint: ColorProvider, description: String? = null) {
    Image(
        provider = ImageProvider(icon),
        contentDescription = description,
        modifier = GlanceModifier.size(size),
        colorFilter = ColorFilter.tint(tint),
    )
}

/** The shorter side of the widget: the 1x1 widgets are drawn as circles of this diameter. */
@Composable
internal fun squareSide(): Dp {
    val size = LocalSize.current
    return minOf(size.width, size.height)
}

/** A type size that grows with [side] ([ratio] of it) but never drops below [minimum] sp, so a small cell stays legible. */
internal fun scaledSp(side: Dp, ratio: Float, minimum: Float): TextUnit = maxOf(minimum, side.value * ratio).sp

/** The 270 degree gauge of the 1x1 widget (open at the bottom) with its label in the middle. */
@Composable
internal fun GaugeDial(model: GaugeModel, side: Dp) {
    val px = side.toPx()
    val stroke = px * 0.11f
    Box(modifier = GlanceModifier.size(side), contentAlignment = Alignment.Center) {
        MaskImage(ChartBitmaps.gaugeTrack(px, stroke), GlanceTheme.colors.outline, GlanceModifier.size(side))
        MaskImage(
            ChartBitmaps.gaugeArc(px, stroke, model.fraction),
            GlanceTheme.colors.secondary,
            GlanceModifier.size(side),
            contentDescription = model.description,
        )
        PulseText(model.label, scaledSp(side, 0.27f, 12f), weight = FontWeight.Bold, align = TextAlign.Center)
    }
}

/** A horizontal meter of [width] by [height] filled to [fraction]; pass [description] when the bar carries information the text next to it does not. */
@Composable
internal fun MeterBar(
    fraction: Float,
    width: Dp,
    height: Dp,
    fill: ColorProvider,
    track: ColorProvider,
    description: String?,
) {
    val barWidth = width.coerceAtLeast(1.dp)
    val widthPx = barWidth.toPx()
    val heightPx = height.toPx()
    Box(modifier = GlanceModifier.size(barWidth, height)) {
        MaskImage(ChartBitmaps.barTrack(widthPx, heightPx), track, GlanceModifier.size(barWidth, height))
        MaskImage(ChartBitmaps.barFill(widthPx, heightPx, fraction), fill, GlanceModifier.size(barWidth, height), contentDescription = description)
    }
}

/** Padding and type sizes of the 3x1 widgets; launchers whose single row is shorter than [TIGHT_BELOW] get the tighter set. */
internal data class CompactMetrics(val padding: Dp, val eyebrow: TextUnit, val title: TextUnit, val detail: TextUnit) {
    companion object {
        private val TIGHT_BELOW = 72.dp
        private val Regular = CompactMetrics(padding = 10.dp, eyebrow = 12.sp, title = 16.sp, detail = 13.sp)
        private val Tight = CompactMetrics(padding = 7.dp, eyebrow = 11.sp, title = 14.sp, detail = 11.sp)

        fun forHeight(height: Dp): CompactMetrics = if (height < TIGHT_BELOW) Tight else Regular
    }
}

/**
 * The eyebrow / headline / detail stack of a 3x1 widget, with an optional glyph on the left. The headline gives way to the card's
 * [CompactCard.titleSuffix]: a long exercise name is shortened, the figures after it are not.
 */
@Composable
internal fun ThreeLineCard(
    card: CompactCard,
    metrics: CompactMetrics,
    @DrawableRes icon: Int? = null,
    iconTint: ColorProvider = GlanceTheme.colors.primary,
) {
    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) {
            Glyph(icon, 26.dp, iconTint)
            Spacer(GlanceModifier.width(10.dp))
        }
        Column(modifier = GlanceModifier.defaultWeight()) {
            Eyebrow(card.eyebrow, metrics.eyebrow)
            Row(modifier = GlanceModifier.fillMaxWidth()) {
                PulseText(card.title, metrics.title, GlanceModifier.defaultWeight(), FontWeight.Bold)
                if (card.titleSuffix.isNotEmpty()) PulseText(" ${card.titleSuffix}", metrics.title, weight = FontWeight.Bold)
            }
            if (card.detail.isNotEmpty()) {
                PulseText(card.detail, metrics.detail, color = GlanceTheme.colors.onSurfaceVariant)
            }
        }
    }
}

/**
 * Runs one widget's refresh and logs a failure instead of throwing, so a widget that cannot be drawn (for example when its bitmaps exceed
 * the launcher's limit) does not stop the surfaces refreshed after it in `Surfaces.refreshAll`.
 */
internal suspend fun refreshQuietly(tag: String, block: suspend () -> Unit) {
    try {
        block()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (error: Exception) {
        Log.w(tag, "Updating a widget failed", error)
    }
}
