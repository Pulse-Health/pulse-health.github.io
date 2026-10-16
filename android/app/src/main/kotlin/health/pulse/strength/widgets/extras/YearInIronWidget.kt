package health.pulse.strength.widgets.extras

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
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
import androidx.glance.text.FontWeight
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
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

/**
 * WI-08 Year in iron (2x2): the tonnes lifted this calendar year, the sessions behind them and twelve monthly bars with the current month
 * at full strength. A dark card in light mode too, as on the canvas.
 */
class YearInIronWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val model = ExtrasText.yearInIron(snapshot.year, ExtrasText.currentMonthIndex(snapshot))
        val size = LocalSize.current
        val roomy = size.width >= 140.dp
        val padding = if (roomy) WidgetDimens.padding else WidgetDimens.paddingCompact
        val caption = TextFit.firstFitting(model.captions, (size.width - padding * 2 - FitSafety).value, rememberTextMeter(13.sp, bold = false))
        WidgetCard(
            description = model.description,
            link = DeepLinks.hub,
            padding = padding,
            background = IronCard.background,
            contentAlignment = Alignment.TopStart,
        ) {
            Column(modifier = GlanceModifier.fillMaxSize()) {
                Eyebrow(model.eyebrow, color = IronCard.secondary)
                Spacer(GlanceModifier.defaultWeight())
                Row(verticalAlignment = Alignment.Bottom) {
                    PulseText(model.tonnes, if (roomy) 34.sp else 28.sp, weight = FontWeight.Bold, color = IronCard.text)
                    PulseText(" t", if (roomy) 18.sp else 15.sp, weight = FontWeight.Bold, color = IronCard.text)
                }
                PulseText(caption, 13.sp, color = IronCard.accent)
                Spacer(GlanceModifier.defaultWeight())
                MonthBars(model.bars, size.width - padding * 2)
            }
        }
    }

    @Composable
    private fun MonthBars(bars: List<ExtrasText.YearBar>, width: Dp) {
        val height = 28.dp
        val widthPx = width.toPx()
        val heightPx = height.toPx()
        val modifier = GlanceModifier.size(width, height)
        Box(modifier = modifier) {
            MaskImage(
                ExtrasCharts.yearMask(bars, current = false, widthPx = widthPx, heightPx = heightPx),
                IronCard.dimAccent,
                modifier,
                contentDescription = "Tonnes per month this year, the current month highlighted",
            )
            MaskImage(ExtrasCharts.yearMask(bars, current = true, widthPx = widthPx, heightPx = heightPx), IronCard.accent, modifier)
        }
    }
}

class YearInIronReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = YearInIronWidget()
}
