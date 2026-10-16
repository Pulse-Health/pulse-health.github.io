package health.pulse.strength.widgets.lock

import android.graphics.Paint
import android.graphics.Typeface
import android.util.Log
import android.util.TypedValue
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
import androidx.glance.LocalContext
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

/** The user's font scale, 1.0 at the default size (a smaller scale is treated as 1.0: the layouts are checked at the default size). */
@Composable
internal fun fontScale(): Float = LocalContext.current.resources.configuration.fontScale.coerceAtLeast(1f)

/**
 * [height] as the layout budgets of the widgets count it. They count lines of text at their default size, so at a larger font size the
 * same height counts as proportionally less, and a widget gives up its optional lines (a detail, a footer) sooner instead of clipping.
 */
@Composable
internal fun textHeight(height: Dp): Dp = height / fontScale()

/** The height of the widget as [textHeight] counts it. */
@Composable
internal fun textHeight(): Dp = textHeight(LocalSize.current.height)

/** A type size that grows with [side] ([ratio] of it) but never drops below [minimum] sp, so a small cell stays legible. */
internal fun scaledSp(side: Dp, ratio: Float, minimum: Float): TextUnit = maxOf(minimum, side.value * ratio).sp

/** The padding of a 1x1 card: the usual one, or less in the smallest cell (about 40 dp), where the circle would otherwise leave no room. */
internal fun squarePadding(side: Dp): Dp = if (side < SMALL_SQUARE) SMALL_SQUARE_PADDING else WidgetDimens.paddingCompact

private val SMALL_SQUARE = 50.dp
private val SMALL_SQUARE_PADDING = 6.dp

/** The type size the bold [text] is measured at to find the size at which it fills a width. */
private const val REFERENCE_SP = 20f

/**
 * The type size for the bold [text]: [maxSp], or smaller (down to [minSp]) when the text would be wider than [width] at that size, so
 * a streak of "104 wk" or "104d" in a small circle stays on its line instead of being cut.
 */
@Composable
internal fun fittingSp(text: String, width: Dp, maxSp: Float, minSp: Float): Float {
    val measured = rememberTextMeter(REFERENCE_SP.sp, bold = true).width(text)
    return TextFit.sizeForWidth(measured, REFERENCE_SP, width.value, minSp, maxSp)
}

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

/**
 * Padding and type sizes of the 3x1 widgets. A launcher decides how high a row is, so [forHeight] picks the largest set whose three lines
 * (the eyebrow, the headline, the detail) still fit; the last sets drop the eyebrow, which the headline can do without, and the very
 * last one the detail as well, for the smallest row a launcher can offer (40 dp) or large text in a short row.
 */
internal class CompactMetrics private constructor(
    val padding: Dp,
    val eyebrow: TextUnit,
    val title: TextUnit,
    val detail: TextUnit,
    val showsEyebrow: Boolean = true,
    val showsDetail: Boolean = true,
) {
    /** The height the lines of this set need, with a little air. */
    private val neededHeight: Dp = padding * 2 +
        TextFit.height((if (showsEyebrow) eyebrow.value else 0f) + title.value + (if (showsDetail) detail.value else 0f)).dp + 2.dp

    companion object {
        private val Tiers = listOf(
            CompactMetrics(padding = 10.dp, eyebrow = 12.sp, title = 16.sp, detail = 13.sp),
            CompactMetrics(padding = 8.dp, eyebrow = 11.sp, title = 15.sp, detail = 12.sp),
            CompactMetrics(padding = 7.dp, eyebrow = 11.sp, title = 14.sp, detail = 11.sp),
            CompactMetrics(padding = 6.dp, eyebrow = 11.sp, title = 14.sp, detail = 11.sp, showsEyebrow = false),
            CompactMetrics(padding = 4.dp, eyebrow = 10.sp, title = 13.sp, detail = 10.sp, showsEyebrow = false),
            CompactMetrics(padding = 4.dp, eyebrow = 10.sp, title = 13.sp, detail = 10.sp, showsEyebrow = false, showsDetail = false),
        )

        fun forHeight(height: Dp): CompactMetrics = Tiers.firstOrNull { height >= it.neededHeight } ?: Tiers.last()
    }
}

/**
 * A [TextMeter] for the system font at [size] ([bold] for the bold style): the widths the launcher's `TextView` will lay the text out in.
 * The widget is composed on the device that shows it, so the same font and display scale apply.
 */
@Composable
internal fun rememberTextMeter(size: TextUnit, bold: Boolean): TextMeter {
    val metrics = LocalContext.current.resources.displayMetrics
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, size.value, metrics)
    }
    return TextMeter { text -> paint.measureText(text) / metrics.density }
}

/** Width kept free when text is fitted, so a measurement that is a hair too small does not push the last character out. */
internal val FitSafety: Dp = 4.dp

/** An eyebrow wording (in capitals) and the lines it takes. */
internal class FittedEyebrow(val text: String, val lines: Int)

/**
 * The first of [variants] that wraps into at most [maxLines] lines of [width] (the last one when none does), and the lines it then takes.
 * Eyebrows are drawn in capitals, so the wordings are measured in capitals.
 */
@Composable
internal fun fitEyebrow(variants: List<String>, width: Dp, maxLines: Int, size: TextUnit = 12.sp): FittedEyebrow {
    val meter = rememberTextMeter(size, bold = true)
    val text = TextFit.firstWithin(variants.map { it.uppercase() }, width.value, maxLines, meter)
    return FittedEyebrow(text, TextFit.lineCount(text, width.value, meter).coerceAtMost(maxLines))
}

/**
 * The eyebrow / headline / detail stack of a 3x1 widget, with an optional glyph on the left. A headline that is too long is shortened
 * with an ellipsis, but the card's [CompactCard.titleSuffix] after it ("85 × 5") always stays whole.
 */
@Composable
internal fun ThreeLineCard(
    card: CompactCard,
    metrics: CompactMetrics,
    @DrawableRes icon: Int? = null,
    iconTint: ColorProvider = GlanceTheme.colors.primary,
) {
    val textWidth = LocalSize.current.width - metrics.padding * 2 - (if (icon != null) ICON_SLOT else 0.dp) - FitSafety
    val title = TextFit.fitLead(
        lead = card.title,
        trail = if (card.titleSuffix.isEmpty()) "" else " ${card.titleSuffix}",
        maxWidth = textWidth.value,
        meter = rememberTextMeter(metrics.title, bold = true),
    )
    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) {
            Glyph(icon, 26.dp, iconTint)
            Spacer(GlanceModifier.width(10.dp))
        }
        Column(modifier = GlanceModifier.defaultWeight()) {
            if (metrics.showsEyebrow) Eyebrow(card.eyebrow, metrics.eyebrow)
            PulseText(title, metrics.title, weight = FontWeight.Bold)
            if (metrics.showsDetail && card.detail.isNotEmpty()) {
                PulseText(card.detail, metrics.detail, color = GlanceTheme.colors.onSurfaceVariant)
            }
        }
    }
}

/** The glyph of a [ThreeLineCard] and the gap after it. */
private val ICON_SLOT = 36.dp

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
