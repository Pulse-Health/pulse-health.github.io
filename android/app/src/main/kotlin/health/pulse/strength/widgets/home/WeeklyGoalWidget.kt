package health.pulse.strength.widgets.home

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.DayCell
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.ChartBitmaps
import health.pulse.strength.widgets.common.MaskImage
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.WidgetDimens
import health.pulse.strength.widgets.common.WidgetSizes
import health.pulse.strength.widgets.common.dayNight
import health.pulse.strength.widgets.common.onLink
import health.pulse.strength.widgets.common.toPx
import health.pulse.strength.widgets.common.PulseColors

/**
 * HS-02 Weekly goal (the reference widget of the Glance foundation: read the snapshot, lay out by size, draw a ring from two tinted masks,
 * open the app on a deep link). Small: ring and the seven day dots; wide: ring on the left, the days and a sentence on the right.
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

@Composable
internal fun WeeklyGoalContent(snapshot: WidgetSnapshot) {
    val week = snapshot.week
    val size = LocalSize.current
    val wide = WidgetSizes.isWide(size)
    val progress = if (week.goal > 0) week.completed.toFloat() / week.goal else 0f
    val ringSize = if (wide) 96.dp else 92.dp

    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .appWidgetBackground()
            .background(GlanceTheme.colors.surface)
            .cornerRadius(WidgetDimens.corner)
            .padding(WidgetDimens.paddingCompact)
            .onLink(DeepLinks.hub),
        contentAlignment = Alignment.Center,
    ) {
        if (wide) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Ring(progress = progress, size = ringSize, completed = week.completed, goal = week.goal)
                Spacer(GlanceModifier.width(16.dp))
                Column {
                    Text(
                        text = if (week.completed >= week.goal) "Goal reached" else "${week.goal - week.completed} to go",
                        style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = 17.sp, fontWeight = FontWeight.Bold),
                    )
                    Text(
                        text = if (week.streakWeeks > 0) "${week.streakWeeks} week streak" else "This week",
                        style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 13.sp),
                    )
                    Spacer(GlanceModifier.size(8.dp))
                    DayDots(week.days)
                }
            }
        } else {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Ring(progress = progress, size = ringSize, completed = week.completed, goal = week.goal)
                Spacer(GlanceModifier.size(8.dp))
                DayDots(week.days)
            }
        }
    }
}

@Composable
private fun Ring(progress: Float, size: androidx.compose.ui.unit.Dp, completed: Int, goal: Int) {
    val px = size.toPx()
    val stroke = px * 0.11f
    val track = ChartBitmaps.ringTrack(px, stroke)
    val arc = ChartBitmaps.ringArc(px, stroke, progress)
    Box(modifier = GlanceModifier.size(size), contentAlignment = Alignment.Center) {
        MaskImage(track, dayNight(Color(0xFFE5E5EA), Color(0xFF3A3A3C)), GlanceModifier.size(size))
        MaskImage(arc, dayNight(PulseColors.ProgressLight, PulseColors.ProgressDark), GlanceModifier.size(size), contentDescription = "$completed of $goal workouts this week")
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = "$completed/$goal",
                style = TextStyle(color = GlanceTheme.colors.onSurface, fontSize = 26.sp, fontWeight = FontWeight.Bold),
            )
            Text(
                text = "this week",
                style = TextStyle(color = GlanceTheme.colors.onSurfaceVariant, fontSize = 11.sp),
            )
        }
    }
}

@Composable
private fun DayDots(days: List<DayCell>) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        days.forEachIndexed { index, day ->
            if (index > 0) Spacer(GlanceModifier.width(5.dp))
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    modifier = GlanceModifier
                        .size(8.dp)
                        .cornerRadius(4.dp)
                        .background(
                            when {
                                day.sessions > 0 -> dayNight(PulseColors.ProgressLight, PulseColors.ProgressDark)
                                day.isToday -> dayNight(PulseColors.GreenLight, PulseColors.GreenDark)
                                else -> dayNight(Color(0xFFE5E5EA), Color(0xFF3A3A3C))
                            },
                        ),
                ) {}
                Text(
                    text = day.letter,
                    style = TextStyle(
                        color = if (day.isToday) GlanceTheme.colors.onSurface else GlanceTheme.colors.onSurfaceVariant,
                        fontSize = 9.sp,
                        fontWeight = if (day.isToday) FontWeight.Bold else FontWeight.Normal,
                    ),
                )
            }
        }
    }
}
