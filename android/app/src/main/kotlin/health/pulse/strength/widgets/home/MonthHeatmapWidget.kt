package health.pulse.strength.widgets.home

import androidx.compose.runtime.Composable
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
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.TextAlign
import health.pulse.strength.core.widgets.MonthSummary
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget

/**
 * HS-12 Month heatmap (4x4): the days of the current month in a Monday-first grid, shaded by the day's volume. Drawn as rows of coloured
 * boxes (no bitmap), so it stays crisp at any size; a day with workouts has a bold number and today is ringed, so the grid does not
 * rest on colour alone.
 */
class MonthHeatmapWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        MonthHeatmapContent(snapshot)
    }
}

class MonthHeatmapReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = MonthHeatmapWidget()
}

/** A square of the grid; [day] is null for the blanks before the 1st and after the last day. */
internal data class MonthCell(val day: Int?, val level: Int, val isToday: Boolean, val isFuture: Boolean, val trained: Boolean)

internal data class MonthGrid(val title: String, val sessions: Int, val weeks: List<List<MonthCell>>, val description: String)

internal object MonthModel {
    val Weekdays = listOf("M", "T", "W", "T", "F", "S", "S")
    private const val CHROME_DP = 28f + 28f + 14f + 22f + 6f
    private const val MIN_CELL_DP = 20f
    private const val MAX_CELL_DP = 40f

    /** Blank cells for the weekdays before the 1st (Monday first), then the days, padded to whole weeks. */
    fun grid(month: MonthSummary): MonthGrid {
        val blanksBefore = month.leadingBlankDays.coerceIn(0, 6)
        val blank = MonthCell(day = null, level = 0, isToday = false, isFuture = false, trained = false)
        val days = month.days.map { MonthCell(it.day, it.level.coerceIn(0, 3), it.isToday, it.isFuture, it.sessions > 0) }
        val cells = List(blanksBefore) { blank } + days
        val padded = cells + List((7 - cells.size % 7) % 7) { blank }
        val trainedDays = month.days.filter { it.sessions > 0 }.map { it.day.toString() }
        return MonthGrid(
            title = month.title,
            sessions = month.sessionCount,
            weeks = padded.chunked(7),
            description = "${month.title}: ${HomeText.sessions(month.sessionCount)}." +
                if (trainedDays.isEmpty()) " No training days yet." else " Trained on days ${HomeText.list(trainedDays)}.",
        )
    }

    /** The height of a week row: what is left of [heightDp] after the padding, the heading, the weekday letters and the legend. */
    fun cellHeight(heightDp: Float, weeks: Int): Float =
        ((heightDp - CHROME_DP) / weeks.coerceAtLeast(1)).coerceIn(MIN_CELL_DP, MAX_CELL_DP)
}

@Composable
internal fun MonthHeatmapContent(snapshot: WidgetSnapshot) {
    val grid = MonthModel.grid(snapshot.month)
    val cellHeight = MonthModel.cellHeight(LocalSize.current.height.value, grid.weeks.size).dp
    WidgetCard(padding = 14.dp, description = grid.description) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Row(modifier = GlanceModifier.fillMaxWidth().padding(bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Label(grid.title, 17.sp, GlanceTheme.colors.onSurface, FontWeight.Bold, GlanceModifier.defaultWeight())
                Label(grid.sessions.toString(), 13.sp, GlanceTheme.colors.onSurface, FontWeight.Bold)
                Label(if (grid.sessions == 1) " session" else " sessions", 13.sp, GlanceTheme.colors.onSurfaceVariant)
            }
            Row(modifier = GlanceModifier.fillMaxWidth()) {
                MonthModel.Weekdays.forEach { letter ->
                    Label(letter, 11.sp, GlanceTheme.colors.onSurfaceVariant, modifier = GlanceModifier.defaultWeight(), align = TextAlign.Center)
                }
            }
            Column(modifier = GlanceModifier.fillMaxWidth()) {
                grid.weeks.forEach { week ->
                    Row(modifier = GlanceModifier.fillMaxWidth().height(cellHeight)) {
                        week.forEach { cell -> DayBox(cell, GlanceModifier.defaultWeight().fillMaxHeight()) }
                    }
                }
            }
            Spacer(GlanceModifier.defaultWeight())
            Legend()
        }
    }
}

/** One square: transparent gap around it, the level colour inside, a ring for today. */
@Composable
private fun DayBox(cell: MonthCell, modifier: GlanceModifier) {
    Box(modifier = modifier.padding(2.dp)) {
        if (cell.day == null) return@Box
        if (cell.isToday) {
            Box(modifier = GlanceModifier.fillMaxSize().background(GlanceTheme.colors.onSurface).cornerRadius(8.dp).padding(2.dp)) {
                DayFill(cell, 6.dp)
            }
        } else {
            DayFill(cell, 8.dp)
        }
    }
}

@Composable
private fun DayFill(cell: MonthCell, radius: Dp) {
    val day = cell.day ?: return
    val base = GlanceModifier.fillMaxSize()
    val shaped = if (cell.isFuture) base else base.background(HomeColors.heatFill(cell.level)).cornerRadius(radius)
    val ink = if (cell.isFuture) GlanceTheme.colors.onSurfaceVariant else HomeColors.heatInk(cell.level)
    Box(modifier = shaped.padding(top = 2.dp, end = 4.dp), contentAlignment = Alignment.TopEnd) {
        Label(day.toString(), 10.sp, ink, if (cell.trained) FontWeight.Bold else FontWeight.Normal, align = TextAlign.End)
    }
}

@Composable
private fun Legend() {
    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Label("Volume", 11.sp, GlanceTheme.colors.onSurfaceVariant, modifier = GlanceModifier.padding(end = 4.dp))
        (0..3).forEach { level ->
            Box(modifier = GlanceModifier.padding(horizontal = 3.dp)) {
                Box(modifier = GlanceModifier.size(14.dp).background(HomeColors.heatFill(level)).cornerRadius(4.dp)) {}
            }
        }
        Label("more", 11.sp, GlanceTheme.colors.onSurfaceVariant, modifier = GlanceModifier.padding(start = 4.dp))
    }
}
