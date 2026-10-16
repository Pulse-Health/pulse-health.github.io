package health.pulse.strength.widgets.extras

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.text.FontWeight
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.WidgetDimens
import health.pulse.strength.widgets.lock.Eyebrow
import health.pulse.strength.widgets.lock.MeterBar
import health.pulse.strength.widgets.lock.PulseText
import health.pulse.strength.widgets.lock.WidgetCard

/**
 * WI-07 Strength ratio (2x2): a main lift's estimated 1RM against bodyweight ("1.24×") with a bar toward the goal ratio. Without a
 * bodyweight it shows the 1RM and asks for the weight in Health Connect.
 */
class StrengthRatioWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val model = ExtrasText.strengthRatio(snapshot.strengthRatio)
        val size = LocalSize.current
        val roomy = size.width >= 140.dp
        val padding = if (roomy) WidgetDimens.padding else WidgetDimens.paddingCompact
        val fraction = model.fraction
        WidgetCard(
            description = model.description,
            link = DeepLinks.hub,
            padding = padding,
            contentAlignment = Alignment.TopStart,
        ) {
            Column(modifier = GlanceModifier.fillMaxSize()) {
                Eyebrow(model.eyebrow, maxLines = 2)
                Spacer(GlanceModifier.defaultWeight())
                PulseText(model.figure, if (roomy) 36.sp else 28.sp, weight = FontWeight.Bold)
                Spacer(GlanceModifier.height(6.dp))
                if (fraction != null) {
                    MeterBar(
                        fraction = fraction,
                        width = size.width - padding * 2,
                        height = 8.dp,
                        fill = GlanceTheme.colors.primary,
                        track = GlanceTheme.colors.outline,
                        description = "${(fraction * 100).toInt()}% of the goal ratio",
                    )
                    Spacer(GlanceModifier.height(4.dp))
                }
                PulseText(model.footer, 12.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = if (fraction == null) 3 else 1)
            }
        }
    }
}

class StrengthRatioReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = StrengthRatioWidget()
}
