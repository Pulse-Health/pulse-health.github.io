package health.pulse.strength.widgets.lock

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.text.FontWeight
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget

/** LS-06 Volume progress (3x1): the week's sets, a meter against the 48-set target and "11 to go · legs lagging". */
class WeeklySetsCompactWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val card = LockText.weeklySets(snapshot.weeklySets)
        val size = LocalSize.current
        val metrics = CompactMetrics.forHeight(size.height)
        WidgetCard(description = card.description, link = DeepLinks.hub, padding = metrics.padding) {
            Column(modifier = GlanceModifier.fillMaxWidth()) {
                Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    PulseText(card.title, metrics.detail, GlanceModifier.defaultWeight(), FontWeight.Bold)
                    PulseText(card.value, metrics.detail, weight = FontWeight.Bold)
                }
                Spacer(GlanceModifier.height(4.dp))
                MeterBar(
                    fraction = card.fraction,
                    width = size.width - metrics.padding * 2,
                    height = 8.dp,
                    fill = GlanceTheme.colors.secondary,
                    track = GlanceTheme.colors.outline,
                    description = "${card.value} sets",
                )
                Spacer(GlanceModifier.height(4.dp))
                PulseText(card.detail, metrics.eyebrow, color = GlanceTheme.colors.onSurfaceVariant)
            }
        }
    }
}

class WeeklySetsCompactReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = WeeklySetsCompactWidget()
}
