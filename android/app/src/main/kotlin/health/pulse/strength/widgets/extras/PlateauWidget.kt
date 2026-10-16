package health.pulse.strength.widgets.extras

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.lock.PulseText
import health.pulse.strength.widgets.lock.WidgetCard

/**
 * WI-10 Plateau watch (4x2): the lifts with a dot, the trend in words ("rising", "flat 3×", "falling") and, when a lift has stalled, the
 * one tip the snapshot carries. As many lifts as fit are shown, always including the one the tip is about.
 */
class PlateauWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val size = LocalSize.current
        val padding = if (size.height < 130.dp) 12.dp else 14.dp
        // Height left for the lifts under the title row, in rows of 24 dp; at least two lifts are shown.
        val rowsFit = ((size.height - padding * 2 - TITLE_DP.dp - 8.dp).value / ROW_DP).toInt().coerceIn(2, 4)
        val model = ExtrasText.plateau(snapshot.plateaus, rowsFit)
        val tipFits = size.height - padding * 2 - TITLE_DP.dp - 8.dp - ROW_DP.dp * model.rows.size >= TIP_DP.dp
        WidgetCard(description = model.description, link = DeepLinks.hub, padding = padding, contentAlignment = Alignment.TopStart) {
            Column(modifier = GlanceModifier.fillMaxSize()) {
                Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    PulseText("Plateau watch", 15.sp, GlanceModifier.defaultWeight(), FontWeight.Medium)
                    PulseText("recent sessions", 12.sp, color = GlanceTheme.colors.onSurfaceVariant)
                }
                Spacer(GlanceModifier.height(8.dp))
                if (model.rows.isEmpty()) {
                    PulseText("Not enough history yet.", 14.sp, weight = FontWeight.Bold)
                    PulseText("Log three sessions of a lift to see its trend.", 13.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = 2)
                }
                for (row in model.rows) {
                    Row(modifier = GlanceModifier.fillMaxWidth().height(ROW_DP.dp), verticalAlignment = Alignment.CenterVertically) {
                        StatusDot(ExtrasPalette.trend(row.status))
                        Spacer(GlanceModifier.width(10.dp))
                        PulseText(row.name, 14.sp, GlanceModifier.defaultWeight())
                        PulseText(row.statusText, 14.sp, weight = FontWeight.Bold, color = ExtrasPalette.trendText(row.status))
                    }
                }
                val tip = model.tip
                if (tip != null && tipFits) {
                    Spacer(GlanceModifier.defaultWeight())
                    PulseText("Tip: $tip", 12.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = 2)
                }
            }
        }
    }

    private companion object {
        const val TITLE_DP = 20f
        const val ROW_DP = 24f
        const val TIP_DP = 18f
    }
}

class PlateauReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = PlateauWidget()
}
