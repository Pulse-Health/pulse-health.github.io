package health.pulse.strength.widgets.home

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.tablet.TrainingBlockContent

/** One widget as the tests see it: its content, the sizes a launcher gives it, and whether it takes the wallpaper colours. */
internal class WidgetCase(
    val name: String,
    val sizes: List<DpSize>,
    val dynamic: Boolean = false,
    val content: @Composable (WidgetSnapshot) -> Unit,
)

/** Every widget of the Home Screen and tablet groups at the sizes they are offered in (2x2, 4x2, 4x4, 6x4 and what the user can stretch them to). */
internal object WidgetCases {
    private fun size(width: Int, height: Int) = DpSize(width.dp, height.dp)

    val twoByTwo = listOf(size(110, 110), size(160, 160), size(160, 130))
    val fourByTwo = listOf(size(250, 110), size(320, 130), size(320, 150), size(320, 200))
    val fourByFour = listOf(size(250, 180), size(250, 250), size(320, 320), size(360, 400))
    val sixByFour = listOf(size(320, 180), size(390, 250), size(480, 300), size(560, 360))

    val all: List<WidgetCase> = listOf(
        WidgetCase("next-up", twoByTwo + fourByTwo) { NextUpContent(it) },
        WidgetCase("weekly-goal", twoByTwo + fourByTwo) { WeeklyGoalContent(it) },
        WidgetCase("weekly-goal-themed", twoByTwo, dynamic = true) { WeeklyGoalContent(it, WeeklyGoalPalette.themed()) },
        WidgetCase("pr-spotlight", twoByTwo) { PrSpotlightContent(it) },
        WidgetCase("muscle-freshness", twoByTwo) { MuscleFreshnessContent(it) },
        WidgetCase("overload", twoByTwo) { OverloadContent(it) },
        WidgetCase("weekly-sets", fourByTwo) { WeeklySetsContent(it) },
        WidgetCase("lift-trend", fourByTwo) { LiftTrendContent(it, null) },
        WidgetCase("training-week", fourByFour) { TrainingWeekContent(it) },
        WidgetCase("template-launcher", fourByFour) { TemplateLauncherContent(it) },
        WidgetCase("month-heatmap", fourByFour) { MonthHeatmapContent(it) },
        WidgetCase("training-block", sixByFour) { TrainingBlockContent(it) },
    )

    fun named(name: String): WidgetCase = all.first { it.name == name }
}
