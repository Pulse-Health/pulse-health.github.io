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
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.text.FontWeight
import health.pulse.strength.R
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.WidgetDimens
import health.pulse.strength.widgets.lock.Eyebrow
import health.pulse.strength.widgets.lock.PulseText
import health.pulse.strength.widgets.lock.WidgetCard

/**
 * WI-06 Rest-day swap (2x2): on a rest day the slot of the next workout shows a short recovery routine whose Start opens an empty
 * workout with its name; on a training day it shows the next template instead, so the widget is never empty.
 */
class RestDayWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val card = ExtrasText.restDayCard(snapshot)
        val roomy = LocalSize.current.width >= 140.dp
        val padding = if (roomy) WidgetDimens.padding else WidgetDimens.paddingCompact
        when (card) {
            is ExtrasText.RestDayCard.Rest -> WidgetCard(
                description = "${card.reason}: ${card.title}, ${card.focus}. Start",
                link = card.link,
                padding = padding,
                background = GlanceTheme.colors.primaryContainer,
                contentAlignment = Alignment.TopStart,
            ) {
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    Eyebrow(card.reason, color = GlanceTheme.colors.onPrimaryContainer)
                    Spacer(GlanceModifier.defaultWeight())
                    PulseText(card.title, 17.sp, weight = FontWeight.Bold, maxLines = 2)
                    PulseText(card.focus, 13.sp, color = GlanceTheme.colors.onPrimaryContainer, maxLines = 2)
                    Spacer(GlanceModifier.height(8.dp))
                    PillButton(
                        label = "Start",
                        action = null,
                        modifier = GlanceModifier.fillMaxWidth(),
                        fill = GlanceTheme.colors.surface,
                        textColor = GlanceTheme.colors.onPrimaryContainer,
                        height = 36.dp,
                    )
                }
            }
            is ExtrasText.RestDayCard.Training -> WidgetCard(
                description = "Training day: ${card.name}, ${card.detail}. Start",
                link = card.link,
                padding = padding,
                contentAlignment = Alignment.TopStart,
            ) {
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    Eyebrow("Training day")
                    Spacer(GlanceModifier.defaultWeight())
                    PulseText(card.name, 17.sp, weight = FontWeight.Bold, maxLines = 2)
                    PulseText(card.detail, 13.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = 2)
                    Spacer(GlanceModifier.height(8.dp))
                    PillButton(label = "Start", action = null, modifier = GlanceModifier.fillMaxWidth(), height = 36.dp, icon = R.drawable.ic_extras_play)
                }
            }
            ExtrasText.RestDayCard.Empty -> WidgetCard(
                description = "No workout planned. Open Pulse Strength to create one",
                link = card.link,
                padding = padding,
                contentAlignment = Alignment.TopStart,
            ) {
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    Eyebrow("Rest-day swap")
                    Spacer(GlanceModifier.defaultWeight())
                    PulseText("No plan yet", 17.sp, weight = FontWeight.Bold, maxLines = 2)
                    PulseText("Create a workout in Pulse Strength.", 13.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = 3)
                }
            }
        }
    }
}

class RestDayReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = RestDayWidget()
}
