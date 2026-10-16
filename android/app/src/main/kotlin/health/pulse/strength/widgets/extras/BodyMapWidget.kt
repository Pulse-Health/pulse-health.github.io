package health.pulse.strength.widgets.extras

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import health.pulse.strength.core.widgets.BodyMap
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.MaskImage
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.WidgetDimens
import health.pulse.strength.widgets.common.toPx
import health.pulse.strength.widgets.lock.FitSafety
import health.pulse.strength.widgets.lock.PulseText
import health.pulse.strength.widgets.lock.TextFit
import health.pulse.strength.widgets.lock.WidgetCard
import health.pulse.strength.widgets.lock.fontScale
import health.pulse.strength.widgets.lock.rememberTextMeter
import health.pulse.strength.widgets.lock.textHeight

/**
 * WI-01 Body map (4x2): a front and a back silhouette shaded by this week's sets per muscle group, so gaps jump out, and the sentence
 * that names the first untouched group. One mask per heat level keeps every shade a day/night colour.
 */
class BodyMapWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val bodyMap = snapshot.bodyMap
        val size = LocalSize.current
        // Below 130 dp the text column cannot hold the subtitle as well as the sentence, so the picture speaks for "front and back".
        val compact = textHeight() < ExtrasText.COMPACT_BELOW_DP.dp
        val padding = if (compact) WidgetDimens.paddingCompact else WidgetDimens.padding
        val message = ExtrasText.bodyMessage(bodyMap)
        val description = ExtrasText.bodyDescription(bodyMap)
        val aspect = BodyMapShapes.WIDTH / BodyMapShapes.HEIGHT
        val figureHeight = minOf(size.height - padding * 2, (size.width / 2 - padding) / aspect)
        // The lines of 13 sp text that fit under the title (and the subtitle) at the size the user reads them; the sentence is set whole
        // (counted by wrapping it with the real font) and the detail under it only when all of it still fits.
        val scale = fontScale()
        val titleBlock = (TextFit.height(15f) + if (compact) 0f else TextFit.height(13f)) * scale
        val lines = (((size.height - padding * 2).value - titleBlock) / (TextFit.height(13f) * scale)).toInt().coerceAtLeast(1)
        val columnWidth = (size.width - padding * 2 - figureHeight * aspect - GAP - FitSafety).value
        val headlineNeeds = TextFit.lineCount(message.headline, columnWidth, rememberTextMeter(13.sp, bold = true))
        val detailNeeds = if (message.detail.isEmpty()) 0 else TextFit.lineCount(message.detail, columnWidth, rememberTextMeter(13.sp, bold = false))
        val headlineLines = minOf(headlineNeeds, lines)
        val detailLines = if (detailNeeds > 0 && headlineLines + detailNeeds <= lines) detailNeeds else 0
        WidgetCard(
            description = "$description ${message.headline} ${message.detail}".trim(),
            link = DeepLinks.hub,
            padding = padding,
        ) {
            Row(modifier = GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                Silhouettes(bodyMap, figureHeight * aspect, figureHeight, description)
                Spacer(GlanceModifier.width(GAP))
                Column(modifier = GlanceModifier.defaultWeight().fillMaxHeight()) {
                    PulseText("This week", 15.sp, weight = FontWeight.Medium)
                    if (!compact) PulseText("Front and back", 13.sp, color = GlanceTheme.colors.onSurfaceVariant)
                    Spacer(GlanceModifier.defaultWeight())
                    PulseText(message.headline, 13.sp, weight = FontWeight.Bold, maxLines = headlineLines)
                    if (detailLines > 0) {
                        PulseText(message.detail, 13.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = detailLines)
                    }
                }
            }
        }
    }

    private companion object {
        const val MAX_MASK_PX = 360
        val GAP = 12.dp
    }

    @Composable
    private fun Silhouettes(bodyMap: BodyMap, width: Dp, height: Dp, description: String) {
        val widthPx = width.toPx().coerceAtMost(MAX_MASK_PX)
        Box(modifier = GlanceModifier.size(width, height)) {
            for (level in 0..BodyMapShapes.MAX_LEVEL) {
                val mask = ExtrasCharts.bodyMask(bodyMap, level, widthPx) ?: continue
                MaskImage(
                    bitmap = mask,
                    tint = ExtrasPalette.heat(level),
                    modifier = GlanceModifier.size(width, height),
                    contentDescription = if (level == 0) description else null,
                )
            }
        }
    }
}

class BodyMapReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = BodyMapWidget()
}
