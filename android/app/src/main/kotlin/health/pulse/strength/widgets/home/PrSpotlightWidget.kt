package health.pulse.strength.widgets.home

import androidx.compose.runtime.Composable
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
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseActions
import health.pulse.strength.widgets.common.PulseWidget

/** HS-03 PR spotlight: the newest personal record on a gold card. Opens that exercise. */
class PrSpotlightWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        PrSpotlightContent(snapshot)
    }
}

class PrSpotlightReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = PrSpotlightWidget()
}

/** What the card says. [figure] and [detail] are absent on the empty card. */
internal data class PrCard(
    val header: String,
    val age: String?,
    val exercise: String,
    val figure: String?,
    val detail: String?,
    val description: String,
    val link: String,
)

internal object PrModel {
    fun card(snapshot: WidgetSnapshot): PrCard {
        val pr = snapshot.latestPR ?: return PrCard(
            header = "Personal record",
            age = null,
            exercise = "No records yet",
            figure = null,
            detail = "Your first record shows up here.",
            description = "No personal records yet. Your first record shows up here.",
            link = DeepLinks.hub,
        )
        val header = if (pr.isFresh) "New PR" else "Latest PR"
        val ago = HomeDates.daysBetween(pr.achievedAt, snapshot.generatedAt, HomeDates.zoneOf(snapshot))
        val delta = pr.deltaKg.takeIf { it > 0.005 }
        val estimate = "e1RM ${HomeText.kg(pr.estimated1RM)} kg"
        return PrCard(
            header = header,
            age = if (pr.isFresh) null else HomeDates.shortAgo(ago),
            exercise = pr.exerciseName,
            figure = HomeText.weightReps(pr.weightKg, pr.reps),
            detail = HomeText.dotted(estimate, delta?.let { "+" + HomeText.kg(it) }),
            description = "$header: ${pr.exerciseName}, ${HomeText.kilograms(pr.weightKg)} for ${pr.reps} reps. " +
                "Estimated one-rep max ${HomeText.kilograms(pr.estimated1RM)}" +
                (delta?.let { ", up ${HomeText.kilograms(it)}" } ?: ""),
            link = DeepLinks.exercise(pr.exerciseID),
        )
    }
}

@Composable
internal fun PrSpotlightContent(snapshot: WidgetSnapshot) {
    val card = PrModel.card(snapshot)
    val size = LocalSize.current
    val showDetail = size.height >= 125.dp
    val figureSp = card.figure?.let { HomeLayout.fittedSp(it, size.width.value - 32f, baseSp = 30f, minSp = 20f) }
    WidgetCard(
        background = HomeColors.goldFill,
        description = card.description,
        onClick = PulseActions.link(card.link),
    ) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Icon(HomeIcons.Trophy, HomeColors.goldText, 18.dp)
                Spacer(GlanceModifier.width(6.dp))
                Label(HomeText.eyebrow(card.header), 12.sp, HomeColors.goldText, FontWeight.Bold, GlanceModifier.defaultWeight())
                card.age?.let { Label(it, 12.sp, HomeColors.goldText) }
            }
            Spacer(GlanceModifier.defaultWeight())
            Label(card.exercise, 15.sp, GlanceTheme.colors.onSurface, FontWeight.Medium)
            if (card.figure != null && figureSp != null) {
                Label(card.figure, figureSp.sp, GlanceTheme.colors.onSurface, FontWeight.Bold)
            }
            if (showDetail && card.detail != null) {
                Label(card.detail, 13.sp, HomeColors.goldText, maxLines = if (card.figure == null) 2 else 1)
            }
        }
    }
}
