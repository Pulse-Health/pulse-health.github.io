package health.pulse.strength.widgets.home

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import health.pulse.strength.core.widgets.DayCell
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.ChartBitmaps
import health.pulse.strength.widgets.common.MaskImage
import health.pulse.strength.widgets.common.PulseColors
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.WidgetDimens
import health.pulse.strength.widgets.common.WidgetSizes
import health.pulse.strength.widgets.common.dayNight
import health.pulse.strength.widgets.common.toPx

/**
 * HS-02 Weekly goal (the reference widget of the Glance foundation: read the snapshot, lay out by size, draw a ring from two tinted masks,
 * open the app on a deep link). Small: ring and the seven day dots; wide: ring on the left, the days and a sentence on the right.
 * Also offered on the glanceable hub (SB-01) and, in the wallpaper colours, as [WeeklyGoalThemedWidget] (HS-06).
 */
class WeeklyGoalWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        WeeklyGoalContent(snapshot)
    }
}

class WeeklyGoalReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = WeeklyGoalWidget()
}

/** The colours of the ring and the day dots: the brand greens, or the wallpaper colours of the themed variant. */
internal class WeeklyGoalPalette(
    val track: ColorProvider,
    val progress: ColorProvider,
    val today: ColorProvider,
    val empty: ColorProvider,
) {
    companion object {
        val Brand = WeeklyGoalPalette(
            track = dayNight(Color(0xFFE5E5EA), Color(0xFF3A3A3C)),
            progress = dayNight(PulseColors.ProgressLight, PulseColors.ProgressDark),
            today = dayNight(PulseColors.GreenLight, PulseColors.GreenDark),
            empty = dayNight(Color(0xFFE5E5EA), Color(0xFF3A3A3C)),
        )

        /** Theme colours are only readable in composition, so this is a function. */
        @Composable
        fun themed() = WeeklyGoalPalette(
            track = GlanceTheme.colors.secondaryContainer,
            progress = GlanceTheme.colors.primary,
            today = GlanceTheme.colors.primary,
            empty = GlanceTheme.colors.secondaryContainer,
        )
    }
}

/** What the weekly goal says in words. */
internal object WeeklyGoalModel {
    fun progress(completed: Int, goal: Int): Float = if (goal > 0) (completed.toFloat() / goal).coerceIn(0f, 1f) else 0f

    fun headline(completed: Int, goal: Int): String = if (completed >= goal) "Goal reached" else "${goal - completed} to go"

    fun subline(streakWeeks: Int): String = if (streakWeeks > 0) "$streakWeeks week streak" else "This week"

    fun description(completed: Int, goal: Int, streakWeeks: Int): String =
        "$completed of $goal workouts this week" + if (streakWeeks > 0) ", $streakWeeks week streak" else ""
}

@Composable
internal fun WeeklyGoalContent(snapshot: WidgetSnapshot, palette: WeeklyGoalPalette = WeeklyGoalPalette.Brand) {
    val week = snapshot.week
    val size = LocalSize.current
    val wide = WidgetSizes.isWide(size)
    val progress = WeeklyGoalModel.progress(week.completed, week.goal)
    val ringSize = if (wide) (size.height - 20.dp).coerceIn(56.dp, 96.dp) else (size.height - 52.dp).coerceIn(56.dp, 92.dp)

    WidgetCard(
        padding = WidgetDimens.paddingCompact,
        description = WeeklyGoalModel.description(week.completed, week.goal, week.streakWeeks),
        contentAlignment = Alignment.Center,
    ) {
        if (wide) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Ring(progress = progress, size = ringSize, completed = week.completed, goal = week.goal, palette = palette)
                Spacer(GlanceModifier.width(16.dp))
                Column {
                    Text(
                        text = WeeklyGoalModel.headline(week.completed, week.goal),
                        style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = 17.sp, fontWeight = FontWeight.Bold),
                        maxLines = 1,
                    )
                    Text(
                        text = WeeklyGoalModel.subline(week.streakWeeks),
                        style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 13.sp),
                        maxLines = 1,
                    )
                    Spacer(GlanceModifier.size(8.dp))
                    DayDots(week.days, palette)
                }
            }
        } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Ring(progress = progress, size = ringSize, completed = week.completed, goal = week.goal, palette = palette)
                Spacer(GlanceModifier.size(8.dp))
                DayDots(week.days, palette)
            }
        }
    }
}

@Composable
private fun Ring(progress: Float, size: Dp, completed: Int, goal: Int, palette: WeeklyGoalPalette) {
    val px = size.toPx()
    val stroke = px * 0.11f
    val track = ChartBitmaps.ringTrack(px, stroke)
    val arc = ChartBitmaps.ringArc(px, stroke, progress)
    val figure = (size.value * 0.28f).coerceAtLeast(14f)
    Box(modifier = GlanceModifier.size(size), contentAlignment = Alignment.Center) {
        MaskImage(track, palette.track, GlanceModifier.size(size))
        MaskImage(arc, palette.progress, GlanceModifier.size(size), contentDescription = "$completed of $goal workouts this week")
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = "$completed/$goal",
                style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = figure.sp, fontWeight = FontWeight.Bold),
                maxLines = 1,
            )
            if (size >= 70.dp) {
                Text(
                    text = "this week",
                    style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 11.sp),
                    maxLines = 1,
                )
            }
        }
    }
}

/**
 * The seven days, Monday first: a filled dot when a workout was finished, a ring for today, a dim dot otherwise. Spacing comes from
 * padding, not spacers: Glance drops every child of a Row beyond the tenth, and 7 days plus 6 spacers are 13.
 */
@Composable
private fun DayDots(days: List<DayCell>, palette: WeeklyGoalPalette) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        days.forEach { day ->
            Column(modifier = GlanceModifier.padding(horizontal = 2.5.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                when {
                    day.sessions > 0 -> Dot(palette.progress)
                    day.isToday -> {
                        Box(modifier = GlanceModifier.size(8.dp).cornerRadius(4.dp).background(palette.today), contentAlignment = Alignment.Center) {
                            Box(modifier = GlanceModifier.size(4.dp).cornerRadius(2.dp).background(GlanceTheme.colors.surface)) {}
                        }
                    }
                    else -> Dot(palette.empty)
                }
                Text(
                    text = day.letter,
                    style = TextStyle(
                        color = if (day.isToday) GlanceTheme.colors.onSurface else GlanceTheme.colors.onSurfaceVariant,
                        fontSize = 9.sp,
                        fontWeight = if (day.isToday) FontWeight.Bold else FontWeight.Normal,
                    ),
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun Dot(color: ColorProvider) {
    Box(modifier = GlanceModifier.size(8.dp).cornerRadius(4.dp).background(color)) {}
}
