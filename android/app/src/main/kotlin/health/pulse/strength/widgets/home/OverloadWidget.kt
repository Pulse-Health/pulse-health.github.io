package health.pulse.strength.widgets.home

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.text.FontWeight
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseActions
import health.pulse.strength.widgets.common.PulseWidget

/**
 * HS-05 Beat last time: what you lifted last time and the weight to try today. The card is dark in both appearances on purpose (as on iOS),
 * so it takes its colours from [HomeColors.DarkCard] instead of the theme.
 */
class OverloadWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        OverloadContent(snapshot)
    }
}

class OverloadReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = OverloadWidget()
}

/** What the dark card says. [last] is absent on the empty card. */
internal data class OverloadCard(
    val age: String?,
    val label: String,
    val exercise: String,
    val last: String?,
    val target: String,
    val description: String,
    val link: String,
)

internal object OverloadModel {
    fun card(snapshot: WidgetSnapshot): OverloadCard {
        val overload = snapshot.overload ?: return OverloadCard(
            age = null,
            label = "Beat last time",
            exercise = "No target yet",
            last = null,
            target = "Finish a workout to get one",
            description = "Beat last time: no target yet. Finish a workout to get one.",
            link = DeepLinks.hub,
        )
        val last = HomeText.weightReps(overload.lastWeightKg, overload.lastReps)
        // A heavier target is shown as the weight; when the weight stays, the target is one more rep.
        val target = if (overload.deltaKg > 0.005) {
            "Try ${HomeText.kg(overload.targetWeightKg)} today"
        } else {
            "Try ${HomeText.weightReps(overload.targetWeightKg, overload.targetReps)} today"
        }
        return OverloadCard(
            age = overload.lastDaysAgo?.let { HomeDates.shortAgo(it) },
            label = "Last time",
            exercise = overload.exerciseName,
            last = last,
            target = target,
            description = "Beat last time. ${overload.exerciseName}: ${HomeText.kilograms(overload.lastWeightKg)} for " +
                "${overload.lastReps} reps" + (overload.lastDaysAgo?.let { ", ${HomeDates.daysAgoLower(it)}" } ?: "") + ". " +
                "Today: ${HomeText.kilograms(overload.targetWeightKg)} for ${overload.targetReps} reps in ${overload.targetSets} sets.",
            link = DeepLinks.exercise(overload.exerciseID),
        )
    }
}

@Composable
internal fun OverloadContent(snapshot: WidgetSnapshot) {
    val card = OverloadModel.card(snapshot)
    val size = LocalSize.current
    // The four lines of the smallest card (age, exercise, last time, target) need a smaller figure to fit 110 dp of height.
    val figureSp = if (size.height < 125.dp) 20f else 22f
    val lastSp = card.last?.let { HomeLayout.fittedSp(it, size.width.value - 32f, baseSp = figureSp, minSp = 14f) }
    val showBadge = size.height >= 125.dp
    val showLabel = size.height >= 150.dp
    val colors = HomeColors.DarkCard
    WidgetCard(background = colors.surface, description = card.description, onClick = PulseActions.link(card.link)) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                if (showBadge) IconBadge(HomeIcons.Dumbbell, container = colors.accent, tint = colors.onAccent)
                Spacer(GlanceModifier.defaultWeight())
                card.age?.let { Label(it, 13.sp, colors.inkSecondary) }
            }
            Spacer(GlanceModifier.defaultWeight())
            if (showLabel) Label(card.label, 13.sp, colors.inkSecondary)
            Label(card.exercise, 15.sp, colors.ink, FontWeight.Medium)
            if (card.last != null && lastSp != null) Label(card.last, lastSp.sp, colors.ink, FontWeight.Bold)
            Label(card.target, 13.sp, colors.accent, maxLines = if (card.last == null) 2 else 1)
        }
    }
}
