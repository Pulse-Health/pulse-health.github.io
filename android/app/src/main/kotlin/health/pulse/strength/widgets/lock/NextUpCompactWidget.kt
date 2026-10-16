package health.pulse.strength.widgets.lock

import androidx.compose.runtime.Composable
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget

/** LS-05 Next workout (3x1): "NEXT UP", the template name and "6 exercises · ~55 min"; the running workout takes its place while one runs. */
class NextUpCompactWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val card = LockText.nextUp(snapshot)
        val metrics = CompactMetrics.forHeight(textHeight())
        WidgetCard(description = card.description, link = card.link, padding = metrics.padding) {
            ThreeLineCard(card, metrics)
        }
    }
}

class NextUpCompactReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = NextUpCompactWidget()
}
