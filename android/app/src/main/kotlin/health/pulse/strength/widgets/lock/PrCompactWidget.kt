package health.pulse.strength.widgets.lock

import androidx.compose.runtime.Composable
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import health.pulse.strength.R
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget

/** LS-07 Latest record (3x1): the trophy, "LATEST PR" (or "NEW PR" within 24 hours), "Bench Press 85 × 5" and "e1RM 99 kg · +4 kg". */
class PrCompactWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val card = LockText.latestRecord(snapshot.latestPR)
        val metrics = CompactMetrics.forHeight(LocalSize.current.height)
        WidgetCard(description = card.description, link = card.link, padding = metrics.padding) {
            ThreeLineCard(
                card = card,
                metrics = metrics,
                icon = R.drawable.ic_lock_trophy,
                iconTint = if (card.isHighlighted) GlanceTheme.colors.onTertiaryContainer else GlanceTheme.colors.onSurfaceVariant,
            )
        }
    }
}

class PrCompactReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = PrCompactWidget()
}
