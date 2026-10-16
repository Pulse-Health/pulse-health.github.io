package health.pulse.strength.widgets.lock

import androidx.compose.runtime.Composable
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget

/** LS-08 Overload target (3x1): "TODAY'S TARGET", "Bench Press 4 × 6" and "82.5 kg · +2.5 vs last". */
class OverloadCompactWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val card = LockText.overload(snapshot.overload)
        val metrics = CompactMetrics.forHeight(LocalSize.current.height)
        WidgetCard(description = card.description, link = card.link, padding = metrics.padding) {
            ThreeLineCard(card, metrics)
        }
    }
}

class OverloadCompactReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = OverloadCompactWidget()
}
