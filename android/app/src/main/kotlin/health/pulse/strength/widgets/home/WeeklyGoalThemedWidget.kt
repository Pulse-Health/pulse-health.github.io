package health.pulse.strength.widgets.home

import androidx.compose.runtime.Composable
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget

/**
 * HS-06 Tinted weekly goal: the weekly goal of [WeeklyGoalWidget] in the system's dynamic colours, so it takes the tint of the wallpaper
 * like the iOS widget does in its tinted mode. Its own provider, so the picker offers both.
 */
class WeeklyGoalThemedWidget : PulseWidget() {
    override val useDynamicColors: Boolean = true

    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        WeeklyGoalContent(snapshot, WeeklyGoalPalette.themed())
    }
}

class WeeklyGoalThemedReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = WeeklyGoalThemedWidget()
}
