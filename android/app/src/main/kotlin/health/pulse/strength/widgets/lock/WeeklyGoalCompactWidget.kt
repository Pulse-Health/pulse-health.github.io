package health.pulse.strength.widgets.lock

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.WidgetDimens

/** LS-01 Weekly goal gauge (1x1): "3/4" on a 270 degree gauge, for the lock screen and the glanceable hub. */
class WeeklyGoalCompactWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val model = LockText.weeklyGoal(snapshot.week)
        val side = squareSide()
        WidgetCard(description = model.description, link = DeepLinks.hub, cornerRadius = side / 2) {
            GaugeDial(model, (side - WidgetDimens.paddingCompact * 2).coerceAtLeast(24.dp))
        }
    }
}

class WeeklyGoalCompactReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = WeeklyGoalCompactWidget()
}
