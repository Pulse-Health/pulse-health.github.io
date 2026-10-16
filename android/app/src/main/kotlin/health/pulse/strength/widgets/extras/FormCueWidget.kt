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
import health.pulse.strength.widgets.lock.PulseText
import health.pulse.strength.widgets.lock.WidgetCard

/** WI-04 Form cue (2x2): one coaching cue for the first lift of the next workout, with its place among the exercise's cues. */
class FormCueWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val cue = ExtrasText.formCue(snapshot.formCue)
        val roomy = LocalSize.current.width >= 140.dp
        WidgetCard(
            description = "${cue.eyebrow}. ${cue.cue} ${cue.footer}".trim(),
            link = cue.link,
            padding = if (roomy) WidgetDimens.padding else WidgetDimens.paddingCompact,
            contentAlignment = Alignment.TopStart,
        ) {
            Column(modifier = GlanceModifier.fillMaxSize()) {
                Eyebrow(cue.eyebrow, color = ExtrasPalette.blueText, maxLines = 2)
                Spacer(GlanceModifier.defaultWeight())
                PulseText(cue.cue, if (roomy) 17.sp else 15.sp, weight = FontWeight.Bold, maxLines = if (roomy) 5 else 4)
                Spacer(GlanceModifier.defaultWeight())
                if (cue.footer.isNotEmpty()) PulseText(cue.footer, 12.sp, color = GlanceTheme.colors.onSurfaceVariant)
            }
        }
    }
}

class FormCueReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = FormCueWidget()
}
