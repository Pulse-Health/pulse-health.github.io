package health.pulse.strength.widgets.lock

import androidx.compose.runtime.Composable
import androidx.glance.GlanceTheme
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import health.pulse.strength.R
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget

/** LS-04 Quick start (1x1): one play button that starts the next workout (or opens the running one). */
class QuickStartWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val model = LockText.quickStart(snapshot)
        val side = squareSide()
        WidgetCard(description = model.description, link = model.link, cornerRadius = side / 2) {
            Glyph(icon = R.drawable.ic_lock_play_circle, size = side * 0.6f, tint = GlanceTheme.colors.primary)
        }
    }
}

class QuickStartReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = QuickStartWidget()
}
