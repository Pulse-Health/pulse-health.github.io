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

/** LS-02 Days since training (1x1): "3d" over "SINCE"; an en dash before the first workout. */
class DaysSinceWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val model = LockText.daysSince(snapshot.week)
        val side = squareSide()
        val padding = squarePadding(side)
        val inner = side - padding * 2
        // Both lines are set as large as the cell allows: the caption by its width, then the figure by what is left of the height under it
        // and by its own width, so "104d" after a long break is made smaller instead of being cut.
        val captionSp = fittingSp(model.caption.uppercase(), inner - FitSafety, maxSp = scaledSp(side, 0.14f, 9f).value, minSp = 6f)
        val room = (inner.value - 2f) / TextFit.LINE_FACTOR - captionSp
        val valueSp = fittingSp(model.value, inner - FitSafety, maxSp = minOf(side.value * 0.36f, room), minSp = 9f)
        WidgetCard(description = model.description, link = DeepLinks.hub, cornerRadius = side / 2, padding = padding) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                PulseText(model.value, valueSp.sp, weight = FontWeight.Bold, align = TextAlign.Center)
                Eyebrow(model.caption, size = captionSp.sp, align = TextAlign.Center)
            }
        }
    }
}

class DaysSinceReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = DaysSinceWidget()
}
