package health.pulse.strength.widgets.lock

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.sp
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.text.FontWeight
import androidx.glance.text.TextAlign
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.WidgetDimens

/** LS-02 Days since training (1x1): "3d" over "SINCE"; an en dash before the first workout. */
class DaysSinceWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val model = LockText.daysSince(snapshot.week)
        val side = squareSide()
        // The figure grows with the cell but never past what is left of it under the caption, so the pair fits the smallest cell too.
        val captionSp = scaledSp(side, 0.14f, 9f)
        val room = ((side - WidgetDimens.paddingCompact * 2).value - 2f) / TextFit.LINE_FACTOR - captionSp.value
        WidgetCard(description = model.description, link = DeepLinks.hub, cornerRadius = side / 2) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                PulseText(model.value, minOf(side.value * 0.36f, room).coerceAtLeast(12f).sp, weight = FontWeight.Bold, align = TextAlign.Center)
                Eyebrow(model.caption, size = captionSp, align = TextAlign.Center)
            }
        }
    }
}

class DaysSinceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = DaysSinceWidget()
}
