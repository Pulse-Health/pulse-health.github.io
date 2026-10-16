package health.pulse.strength.widgets.lock

import androidx.compose.runtime.Composable
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.text.FontWeight
import androidx.glance.text.TextAlign
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget

/** LS-02 Days since training (1x1): "3d" over "SINCE"; an en dash before the first workout. */
class DaysSinceWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val model = LockText.daysSince(snapshot.week)
        val side = squareSide()
        WidgetCard(description = model.description, link = DeepLinks.hub, cornerRadius = side / 2) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                PulseText(model.value, scaledSp(side, 0.36f, 18f), weight = FontWeight.Bold, align = TextAlign.Center)
                Eyebrow(model.caption, size = scaledSp(side, 0.14f, 9f), align = TextAlign.Center)
            }
        }
    }
}

class DaysSinceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = DaysSinceWidget()
}
