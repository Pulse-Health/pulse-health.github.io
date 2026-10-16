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
        val padding = WidgetDimens.padding
        val showEyebrow = size.height >= 130.dp
        // What the text lines below the drawing need: the weight, the plates, a possible note, and the gaps between them.
        val textHeight = (if (showEyebrow) 18.dp else 0.dp) + 24.dp + 16.dp + (if (model?.note != null) 14.dp else 0.dp) + 12.dp
        val drawingHeight = (size.height - padding * 2 - textHeight).coerceIn(28.dp, Barbell.HEIGHT.dp)
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
                    PulseText(model.total, 22.sp, weight = FontWeight.Bold)
                    PulseText(model.perSide, 12.sp, color = GlanceTheme.colors.onSurfaceVariant)
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
