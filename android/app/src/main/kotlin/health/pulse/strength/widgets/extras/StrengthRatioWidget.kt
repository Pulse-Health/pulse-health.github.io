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
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.WidgetDimens
import health.pulse.strength.widgets.lock.Eyebrow
import health.pulse.strength.widgets.lock.FitSafety
import health.pulse.strength.widgets.lock.MeterBar
import health.pulse.strength.widgets.lock.PulseText
import health.pulse.strength.widgets.lock.TextFit
import health.pulse.strength.widgets.lock.WidgetCard
import health.pulse.strength.widgets.lock.rememberTextMeter

/**
 * WI-07 Strength ratio (2x2): a main lift's estimated 1RM against bodyweight ("1.24×") with a bar toward the goal ratio. Without a
 * bodyweight it shows the 1RM, asks for the weight in Health Connect, and a tap opens the app's body weight entry.
 */
class StrengthRatioWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val model = ExtrasText.strengthRatio(snapshot.strengthRatio)
        val size = LocalSize.current
        val roomy = size.width >= 140.dp
        val compact = size.height < ExtrasText.COMPACT_BELOW_DP.dp
        val padding = if (roomy) WidgetDimens.padding else WidgetDimens.paddingCompact
        val fraction = model.fraction
        val figureSp = if (roomy) 36f else 28f
        // A footer that is the only thing under the figure may take the lines that are left; with a bar below the figure it has one.
        val eyebrowHeight = TextFit.height(EYEBROW_SP, if (compact) 1 else 2)
        val footerLines = if (fraction != null) {
            1
        } else {
            (((size.height - padding * 2).value - eyebrowHeight - TextFit.height(figureSp) - 6f) / TextFit.height(FOOTER_SP)).toInt().coerceIn(1, 3)
        }
        // The wording of the footer that says the most in the lines there are.
        val footer = TextFit.firstWithin(model.footers, (size.width - padding * 2 - FitSafety).value, footerLines, rememberTextMeter(FOOTER_SP.sp, bold = false))
        WidgetCard(
            description = model.description,
            link = model.link,
            padding = padding,
            contentAlignment = Alignment.TopStart,
        ) {
            Column(modifier = GlanceModifier.fillMaxSize()) {
                Eyebrow(if (compact) model.shortEyebrow else model.eyebrow, size = EYEBROW_SP.sp, maxLines = if (compact) 1 else 2)
                Spacer(GlanceModifier.defaultWeight())
                PulseText(model.figure, figureSp.sp, weight = FontWeight.Bold)
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
                PulseText(footer, FOOTER_SP.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = footerLines)
            }
        }
    }

    private companion object {
        const val EYEBROW_SP = 12f
        const val FOOTER_SP = 12f
    }
}

class StrengthRatioReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = StrengthRatioWidget()
}
