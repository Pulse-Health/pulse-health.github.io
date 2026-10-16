package health.pulse.strength.widgets.extras

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.TextAlign
import androidx.glance.unit.ColorProvider
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.WidgetDimens
import health.pulse.strength.widgets.lock.MeterBar
import health.pulse.strength.widgets.lock.PulseText
import health.pulse.strength.widgets.lock.WidgetCard

/**
 * WI-03 Gym partner (4x2): your week and your training partners' weeks as bars toward each one's goal, with one sentence about who
 * closed their week. Shared goals only, no ranking. Without a partner it invites you to add one.
 */
class PartnerWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        val size = LocalSize.current
        val padding = if (size.height < 130.dp) 12.dp else WidgetDimens.padding
        if (snapshot.partners.isEmpty()) {
            WidgetCard(
                description = "Training partners: invite a partner to share your weekly goal",
                link = DeepLinks.hub,
                padding = padding,
                contentAlignment = Alignment.TopStart,
            ) {
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    PulseText("Training partners", 15.sp, weight = FontWeight.Medium)
                    Spacer(GlanceModifier.defaultWeight())
                    PulseText("Invite a partner", 20.sp, weight = FontWeight.Bold)
                    PulseText("Share your weekly goal. Opt-in, no leaderboard.", 13.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = 2)
                }
            }
            return
        }
        val rows = ExtrasText.partnerRows(snapshot.week, snapshot.partners, ExtrasText.partnerRowCapacity(size.height.value))
        val footer = ExtrasText.partnerFooter(snapshot.week, snapshot.partners)
        val barWidth = size.width - padding * 2 - (AVATAR + GAP * 2 + COUNT)
        val summary = rows.joinToString(". ") { "${it.label} ${it.completed} of ${it.goal}" }
        WidgetCard(
            description = "Training partners this week. $summary. $footer",
            link = DeepLinks.hub,
            padding = padding,
            contentAlignment = Alignment.TopStart,
        ) {
            Column(modifier = GlanceModifier.fillMaxSize()) {
                PulseText("Training partners · this week", 15.sp, weight = FontWeight.Medium)
                Spacer(GlanceModifier.height(8.dp))
                for (row in rows) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Avatar(
                            label = row.label,
                            fill = if (row.isYou) GlanceTheme.colors.primary else GlanceTheme.colors.tertiary,
                            textColor = if (row.isYou) GlanceTheme.colors.onPrimary else ColorProvider(Color.White),
                            size = AVATAR,
                        )
                        Spacer(GlanceModifier.width(GAP))
                        MeterBar(
                            fraction = row.fraction,
                            width = barWidth,
                            height = 10.dp,
                            fill = if (row.isYou) GlanceTheme.colors.secondary else GlanceTheme.colors.tertiary,
                            track = GlanceTheme.colors.outline,
                            description = "${row.completed} of ${row.goal} workouts",
                        )
                        Spacer(GlanceModifier.width(GAP))
                        PulseText(
                            "${row.completed}/${row.goal}",
                            14.sp,
                            GlanceModifier.width(COUNT),
                            FontWeight.Bold,
                            align = TextAlign.End,
                        )
                    }
                    Spacer(GlanceModifier.height(4.dp))
                }
                Spacer(GlanceModifier.defaultWeight())
                PulseText(footer, 13.sp, color = GlanceTheme.colors.onSurfaceVariant, maxLines = 2)
            }
        }
    }

    private companion object {
        val AVATAR = 30.dp
        val GAP = 10.dp
        val COUNT = 34.dp
    }
}

class PartnerReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = PartnerWidget()
}
