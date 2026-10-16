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
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.TextAlign
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.ChartBitmaps
import health.pulse.strength.widgets.common.MaskImage
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.WidgetDimens
import health.pulse.strength.widgets.common.toPx
import health.pulse.strength.widgets.lock.Eyebrow
import health.pulse.strength.widgets.lock.FitSafety
import health.pulse.strength.widgets.lock.PulseText
import health.pulse.strength.widgets.lock.TextFit
import health.pulse.strength.widgets.lock.WidgetCard
import health.pulse.strength.widgets.lock.rememberTextMeter
import health.pulse.strength.widgets.lock.scaledSp

/**
 * WI-09 Readiness to load (4x2): the readiness score from the wider Pulse app on a ring that is green, yellow or red by thirds, and the
 * advice for today's session. Without Pulse data it invites the user to connect Pulse.
 */
class ReadinessWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val model = ExtrasText.readiness(snapshot.readiness)
        val size = LocalSize.current
        val padding = WidgetDimens.padding
        val ring = minOf(104.dp, size.height - padding * 2)
        // The advice is set as large as it can be while all of it, the eyebrow and the line under it still fit (counted by wrapping it with
        // the real font); in a short widget the advice shrinks first and the line under it ("From Pulse") goes before the advice is cut.
        val textWidth = (size.width - padding * 2 - ring - RING_GAP - FitSafety).value
        val adviceMeters = ExtrasText.adviceStyles.associate { it.adviceSp to rememberTextMeter(it.adviceSp.sp, bold = true) }
        val detailMeters = ExtrasText.adviceStyles.mapNotNull { it.detailSp }.associateWith { rememberTextMeter(it.sp, bold = false) }
        val layout = ExtrasText.adviceLayout(
            room = (size.height - padding * 2).value,
            adviceLines = { TextFit.lineCount(model.headline, textWidth, adviceMeters.getValue(it)) },
            detailLines = { TextFit.lineCount(model.detail, textWidth, detailMeters.getValue(it)) },
        )
        val detailSp = layout.style.detailSp
        WidgetCard(description = model.description, link = DeepLinks.hub, padding = padding) {
            Row(modifier = GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                ReadinessRing(model, ring)
                Spacer(GlanceModifier.width(RING_GAP))
                Column(modifier = GlanceModifier.defaultWeight()) {
                    Eyebrow(model.eyebrow, size = ExtrasText.READINESS_EYEBROW_SP.sp, color = GlanceTheme.colors.onPrimaryContainer)
                    Spacer(GlanceModifier.height(ExtrasText.READINESS_GAP_DP.dp))
                    PulseText(model.headline, layout.style.adviceSp.sp, weight = FontWeight.Bold, maxLines = layout.maxLines)
                    if (detailSp != null) {
                        Spacer(GlanceModifier.height(ExtrasText.READINESS_GAP_DP.dp))
                        PulseText(model.detail, detailSp.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = 2)
                    }
                }
            }
        }
    }

    @Composable
    private fun ReadinessRing(model: ExtrasText.ReadinessModel, side: Dp) {
        val px = side.toPx()
        val stroke = px * 0.096f
        Box(modifier = GlanceModifier.size(side), contentAlignment = Alignment.Center) {
            MaskImage(ChartBitmaps.ringTrack(px, stroke), ExtrasPalette.track, GlanceModifier.size(side))
            MaskImage(
                ChartBitmaps.ringArc(px, stroke, model.fraction),
                ExtrasPalette.tier(model.tier),
                GlanceModifier.size(side),
                contentDescription = model.description,
            )
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                PulseText(model.score, scaledSp(side, 0.2f, 16f), weight = FontWeight.Bold, align = TextAlign.Center)
                if (model.caption.isNotEmpty()) {
                    PulseText(model.caption, scaledSp(side, 0.11f, 10f), color = GlanceTheme.colors.onSurfaceVariant, align = TextAlign.Center)
                }
            }
        }
    }

    private companion object {
        val RING_GAP = 16.dp
    }
}

class ReadinessReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = ReadinessWidget()
}
