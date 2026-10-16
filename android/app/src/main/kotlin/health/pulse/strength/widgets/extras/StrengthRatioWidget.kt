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
import health.pulse.strength.widgets.lock.fitEyebrow
import health.pulse.strength.widgets.lock.fittingSp
import health.pulse.strength.widgets.lock.fontScale
import health.pulse.strength.widgets.lock.rememberTextMeter
import health.pulse.strength.widgets.lock.textHeight

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
        val compact = textHeight() < ExtrasText.COMPACT_BELOW_DP.dp
        val padding = if (roomy) WidgetDimens.padding else WidgetDimens.paddingCompact
        val fraction = model.fraction
        val innerWidth = size.width - padding * 2
        val textWidth = innerWidth - FitSafety
        // The eyebrow is "Bench Press / bodyweight", or the lift's name alone where that does not fit two lines (a small widget has only
        // the name).
        val eyebrow = fitEyebrow(if (compact) listOf(model.shortEyebrow) else listOf(model.eyebrow, model.shortEyebrow), innerWidth, MAX_EYEBROW_LINES)
        // Heights are real dp: a line of text is as high as the user's font size makes it. The figure takes what the eyebrow, the bar and a
        // line of footer leave, and is no wider than the card ("99.2 kg" is wider than "1.24×"). Where that would make the figure too small
        // to read (two lines of eyebrow in a small widget, or large text) the footer goes first.
        val scale = fontScale()
        val room = (size.height - padding * 2).value
        val eyebrowHeight = TextFit.height(EYEBROW_SP, eyebrow.lines) * scale
        val footerLine = TextFit.height(FOOTER_SP) * scale
        val lineHeight = TextFit.LINE_FACTOR * scale
        val aboveFigure = eyebrowHeight + FIGURE_GAP_DP + (if (fraction != null) BAR_BLOCK_DP else 0f)
        val showsFooter = (room - aboveFigure - footerLine) / lineHeight >= MIN_FIGURE_SP
        val figureRoom = (room - aboveFigure - (if (showsFooter) footerLine else 0f)) / lineHeight
        val figureSp = fittingSp(model.figure, textWidth, maxSp = minOf(if (roomy) 36f else 28f, figureRoom), minSp = MIN_FIGURE_SP)
        // A footer that is the only thing under the figure may take the lines that are left; with a bar below the figure it has one.
        val footerLines = if (fraction != null) {
            1
        } else {
            ((room - eyebrowHeight - FIGURE_GAP_DP - TextFit.height(figureSp) * scale) / footerLine).toInt().coerceIn(1, 3)
        }
        // The wording of the footer that says the most in the lines there are.
        val footer = TextFit.firstWithin(model.footers, textWidth.value, footerLines, rememberTextMeter(FOOTER_SP.sp, bold = false))
        WidgetCard(
            description = model.description,
            link = model.link,
            padding = padding,
            contentAlignment = Alignment.TopStart,
        ) {
            Column(modifier = GlanceModifier.fillMaxSize()) {
                Eyebrow(eyebrow.text, size = EYEBROW_SP.sp, maxLines = eyebrow.lines)
                Spacer(GlanceModifier.defaultWeight())
                PulseText(model.figure, figureSp.sp, weight = FontWeight.Bold)
                Spacer(GlanceModifier.height(FIGURE_GAP_DP.dp))
                if (fraction != null) {
                    MeterBar(
                        fraction = fraction,
                        width = innerWidth,
                        height = BAR_DP.dp,
                        fill = GlanceTheme.colors.primary,
                        track = GlanceTheme.colors.outline,
                        description = "${(fraction * 100).toInt()}% of the goal ratio",
                    )
                    Spacer(GlanceModifier.height(BAR_GAP_DP.dp))
                }
                if (showsFooter) PulseText(footer, FOOTER_SP.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = footerLines)
            }
        }
    }

    private companion object {
        const val EYEBROW_SP = 12f
        const val FOOTER_SP = 12f
        const val MAX_EYEBROW_LINES = 2

        /** The smallest figure that is worth showing next to a footer. */
        const val MIN_FIGURE_SP = 14f

        /** The gap under the figure, the height of the bar and the gap under the bar. */
        const val FIGURE_GAP_DP = 6f
        const val BAR_DP = 8f
        const val BAR_GAP_DP = 4f
        const val BAR_BLOCK_DP = BAR_DP + BAR_GAP_DP
    }
}

class StrengthRatioReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = StrengthRatioWidget()
}
