package health.pulse.strength.widgets.extras

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.MaskImage
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.WidgetDimens
import health.pulse.strength.widgets.lock.Eyebrow
import health.pulse.strength.widgets.lock.PulseText
import health.pulse.strength.widgets.lock.TextFit
import health.pulse.strength.widgets.lock.WidgetCard

/**
 * WI-05 Loaded bar (2x2): the plates for today's heaviest barbell set, drawn on a half barbell in competition colours, with the weight
 * and "20 + 10 + 2.5 a side" in words. A tap opens the plate calculator (or the hub when no workout runs).
 */
class LoadedBarWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val model = ExtrasText.loadedBar(snapshot.loadedBar)
        val layout = model?.layout ?: Barbell.layout(emptyList())
        val size = LocalSize.current
        val compact = size.height < ExtrasText.COMPACT_BELOW_DP.dp
        val padding = if (compact) WidgetDimens.paddingCompact else WidgetDimens.padding
        val showEyebrow = !compact
        val totalSp = if (compact) 20f else 22f
        // What the text below the drawing needs: the eyebrow, the weight, the plates (two lines when compact) and a possible note.
        val textHeight = (if (showEyebrow) TextFit.height(12f) else 0f) +
            TextFit.height(totalSp) +
            TextFit.height(12f, if (compact) 2 else 1) +
            (if (model?.note != null) TextFit.height(11f) else 0f) + 4f
        val drawingHeight = (size.height - padding * 2 - textHeight.dp).coerceIn(24.dp, Barbell.HEIGHT.dp)
        WidgetCard(
            description = model?.description ?: "Loaded bar: no barbell lift is planned for today",
            link = DeepLinks.plates,
            padding = padding,
            contentAlignment = Alignment.TopStart,
        ) {
            Column(modifier = GlanceModifier.fillMaxSize()) {
                if (showEyebrow) Eyebrow("Top set today")
                Box(modifier = GlanceModifier.fillMaxWidth().defaultWeight(), contentAlignment = Alignment.Center) {
                    BarbellDrawing(layout, size.width - padding * 2, drawingHeight, model?.description)
                }
                if (model != null) {
                    PulseText(model.total, totalSp.sp, weight = FontWeight.Bold)
                    PulseText(model.perSide, 12.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = if (compact) 2 else 1)
                    model.note?.let { PulseText(it, 11.sp, color = GlanceTheme.colors.error) }
                } else {
                    PulseText("No barbell lift today", 13.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = 2)
                }
            }
        }
    }

    /** The half barbell scaled to fit [maxWidth] by [maxHeight]: the iron in one mask, the plates in one mask per colour. */
    @Composable
    private fun BarbellDrawing(layout: BarbellLayout, maxWidth: Dp, maxHeight: Dp, description: String?) {
        val unit = minOf(maxWidth.value / layout.width, maxHeight.value / Barbell.HEIGHT)
        val width = (layout.width * unit).dp
        val height = (Barbell.HEIGHT * unit).dp
        val pixelsPerUnit = (unit * LocalContext.current.resources.displayMetrics.density).coerceAtLeast(1f)
        val modifier = GlanceModifier.size(width, height)
        Box(modifier = modifier) {
            MaskImage(ExtrasCharts.barbellIron(layout, pixelsPerUnit), ExtrasPalette.iron, modifier, contentDescription = description)
            for (color in PlateColor.entries) {
                val plates = ExtrasCharts.barbellPlates(layout, color, pixelsPerUnit) ?: continue
                MaskImage(plates, ExtrasPalette.plate(color), modifier)
            }
        }
    }
}

class LoadedBarReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = LoadedBarWidget()
}
