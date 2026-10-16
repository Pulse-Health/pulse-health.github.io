package health.pulse.strength.widgets.lock

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.sp
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
import health.pulse.strength.widgets.common.WidgetDimens

/** LS-03 Week streak (1x1): the flame over "6 wk"; the flame is grey while there is no streak. */
class StreakWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val model = LockText.streak(snapshot.week)
        val side = squareSide()
        // The label grows with the cell but never past what is left of it under the flame, so the pair fits the smallest cell too.
        val flame = side * 0.34f
        val room = ((side - WidgetDimens.paddingCompact * 2 - flame).value - 2f) / TextFit.LINE_FACTOR
        WidgetCard(description = model.description, link = DeepLinks.hub, cornerRadius = side / 2) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Glyph(
                    icon = R.drawable.ic_flame,
                    size = flame,
                    tint = if (model.isActive) GlanceTheme.colors.primary else GlanceTheme.colors.onSurfaceVariant,
                )
                PulseText(model.label, minOf(side.value * 0.24f, room).coerceAtLeast(11f).sp, weight = FontWeight.Bold, align = TextAlign.Center)
            }
        }
    }
}

class StreakReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = StreakWidget()
}
