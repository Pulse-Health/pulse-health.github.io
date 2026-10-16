package health.pulse.strength.widgets.lock

import androidx.compose.runtime.Composable
import androidx.glance.GlanceTheme
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.text.FontWeight
import androidx.glance.text.TextAlign
import health.pulse.strength.R
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget

/** LS-03 Week streak (1x1): the flame over "6 wk"; the flame is grey while there is no streak. */
class StreakWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val model = LockText.streak(snapshot.week)
        val side = squareSide()
        WidgetCard(description = model.description, link = DeepLinks.hub, cornerRadius = side / 2) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Glyph(
                    icon = R.drawable.ic_flame,
                    size = side * 0.34f,
                    tint = if (model.isActive) GlanceTheme.colors.primary else GlanceTheme.colors.onSurfaceVariant,
                )
                PulseText(model.label, scaledSp(side, 0.24f, 13f), weight = FontWeight.Bold, align = TextAlign.Center)
            }
        }
    }
}

class StreakReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = StreakWidget()
}
