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
import androidx.glance.text.FontWeight
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.WidgetDimens
import health.pulse.strength.widgets.lock.Eyebrow
import health.pulse.strength.widgets.lock.FitSafety
import health.pulse.strength.widgets.lock.PulseText
import health.pulse.strength.widgets.lock.TextFit
import health.pulse.strength.widgets.lock.WidgetCard
import health.pulse.strength.widgets.lock.fitEyebrow
import health.pulse.strength.widgets.lock.rememberTextMeter
import health.pulse.strength.widgets.lock.textHeight

/**
 * WI-04 Form cue (2x2): one coaching cue for the first lift of the next workout, with its place among the exercise's cues. The cue is set
 * as large as it can be while all of it still fits (counted by wrapping it with the real font), and cut with an ellipsis only at the
 * smallest size; a small widget keeps just the lift's name above it.
 */
class FormCueWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val cue = ExtrasText.formCue(snapshot.formCue)
        val size = LocalSize.current
        val roomy = size.width >= 140.dp
        val compact = textHeight() < ExtrasText.COMPACT_BELOW_DP.dp
        val padding = if (roomy) WidgetDimens.padding else WidgetDimens.paddingCompact
        val innerWidth = size.width - padding * 2
        val textWidth = innerWidth - FitSafety
        // The eyebrow is "Form cue · Bench Press", or the lift's name alone where that does not fit two lines (a small widget has only
        // the name); it takes the lines it needs, and the cue may use the height left under it and above the footer.
        val eyebrow = fitEyebrow(if (compact) listOf(cue.shortEyebrow) else listOf(cue.eyebrow, cue.shortEyebrow), innerWidth, MAX_EYEBROW_LINES)
        val footerHeight = if (compact || cue.footer.isEmpty()) 0f else TextFit.height(FOOTER_SP)
        val room = (textHeight() - padding * 2).value - TextFit.height(EYEBROW_SP, eyebrow.lines) - footerHeight - GAP
        val width = textWidth.value
        val sizes = ExtrasText.cueTextSizes(roomy)
        val meters = sizes.map { rememberTextMeter(it.sp, bold = true) }
        fun linesAt(sp: Float) = (room / TextFit.height(sp)).toInt().coerceAtLeast(1)
        val index = sizes.indices.firstOrNull { TextFit.lineCount(cue.cue, width, meters[it]) <= linesAt(sizes[it]) } ?: sizes.lastIndex
        WidgetCard(
            description = "${cue.eyebrow}. ${cue.cue} ${cue.footer}".trim(),
            link = cue.link,
            padding = padding,
            contentAlignment = Alignment.TopStart,
        ) {
            Column(modifier = GlanceModifier.fillMaxSize()) {
                Eyebrow(eyebrow.text, size = EYEBROW_SP.sp, color = ExtrasPalette.blueText, maxLines = eyebrow.lines)
                Spacer(GlanceModifier.defaultWeight())
                PulseText(cue.cue, sizes[index].sp, weight = FontWeight.Bold, maxLines = linesAt(sizes[index]))
                Spacer(GlanceModifier.defaultWeight())
                if (!compact && cue.footer.isNotEmpty()) PulseText(cue.footer, FOOTER_SP.sp, color = GlanceTheme.colors.onSurfaceVariant)
            }
        }
    }

    private companion object {
        const val EYEBROW_SP = 12f
        const val FOOTER_SP = 12f
        const val GAP = 4f
        const val MAX_EYEBROW_LINES = 2
    }
}

class FormCueReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = FormCueWidget()
}
