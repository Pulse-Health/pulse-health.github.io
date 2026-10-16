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
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.TextAlign
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.widgets.MuscleSetsProgress
import health.pulse.strength.core.widgets.SetsStatus
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget

/** HS-08 Weekly sets per muscle: this week's working sets against the target range; groups under target fade to grey. */
class WeeklySetsWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        WeeklySetsContent(snapshot)
    }
}

class WeeklySetsReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = WeeklySetsWidget()
}

internal data class SetsRow(val muscle: String, val sets: Int, val fraction: Float, val status: SetsStatus, val description: String)

internal data class SetsCard(val caption: String, val rows: List<SetsRow>, val description: String)

internal object SetsModel {
    private val Majors = setOf(MuscleGroup.CHEST, MuscleGroup.BACK, MuscleGroup.SHOULDERS, MuscleGroup.LEGS)
    private const val ROW_DP = 21f
    private const val CHROME_DP = 20f + 26f

    /** How many rows fit a widget of [heightDp]: 20 dp of padding and the 26 dp heading are set aside, a row takes 21 dp. */
    fun rowCount(heightDp: Float): Int = HomeLayout.rowsThatFit(heightDp, ROW_DP, reserveDp = CHROME_DP, max = 6)

    /**
     * The first [maxRows] groups, the four major groups before arms and core. The bar fills to the group's sets over the top of its target
     * range; the caption names the range when every shown group shares it and otherwise the week's total.
     */
    fun card(snapshot: WidgetSnapshot, maxRows: Int): SetsCard {
        val muscles = snapshot.weeklySets.muscles
        val shown = (muscles.filter { it.muscle in Majors } + muscles.filter { it.muscle !in Majors }).take(maxRows)
        val rows = shown.map(::row)
        val ranges = shown.map { it.targetLow to it.targetHigh }.distinct()
        val caption = if (ranges.size == 1) {
            "target ${ranges[0].first}–${ranges[0].second}"
        } else {
            "${snapshot.weeklySets.totalSets} of ${snapshot.weeklySets.totalTarget} sets"
        }
        val summary = "Sets this week, ${snapshot.weeklySets.totalSets} of ${snapshot.weeklySets.totalTarget}. "
        return SetsCard(caption, rows, summary + rows.joinToString(". ") { it.description })
    }

    private fun row(progress: MuscleSetsProgress): SetsRow {
        val fraction = if (progress.targetHigh > 0) (progress.sets.toFloat() / progress.targetHigh).coerceIn(0f, 1f) else 0f
        return SetsRow(
            muscle = progress.muscle.title,
            sets = progress.sets,
            fraction = fraction,
            status = progress.status,
            description = "${progress.muscle.title}: ${HomeText.sets(progress.sets)}, ${statusWord(progress.status)}, " +
                "target ${progress.targetLow} to ${progress.targetHigh}",
        )
    }

    fun statusWord(status: SetsStatus): String = when (status) {
        SetsStatus.UNDER -> "under target"
        SetsStatus.ON_TARGET -> "on target"
        SetsStatus.OVER -> "over target"
    }
}

@Composable
internal fun WeeklySetsContent(snapshot: WidgetSnapshot) {
    val size = LocalSize.current
    val card = SetsModel.card(snapshot, SetsModel.rowCount(size.height.value))
    val labelWidth = 64.dp
    val valueWidth = 24.dp
    val gap = 10.dp
    val trackWidth = (size.width - 28.dp - labelWidth - valueWidth - gap * 2).coerceAtLeast(24.dp)
    WidgetCard(padding = 10.dp, horizontalPadding = 14.dp, description = card.description) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Row(modifier = GlanceModifier.fillMaxWidth().padding(bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Label("Sets this week", 15.sp, GlanceTheme.colors.onSurface, FontWeight.Medium, GlanceModifier.defaultWeight())
                Label(card.caption, 12.sp, GlanceTheme.colors.onSurfaceVariant)
            }
            card.rows.forEach { row ->
                Row(modifier = GlanceModifier.fillMaxWidth().padding(vertical = 1.5.dp), verticalAlignment = Alignment.CenterVertically) {
                    Label(row.muscle, 13.sp, GlanceTheme.colors.onSurface, modifier = GlanceModifier.width(labelWidth))
                    Spacer(GlanceModifier.width(gap))
                    Meter(
                        width = trackWidth,
                        height = 10.dp,
                        fraction = row.fraction,
                        fill = if (row.status == SetsStatus.UNDER) HomeColors.trackStrong else HomeColors.progress,
                        track = GlanceTheme.colors.outline,
                    )
                    Spacer(GlanceModifier.width(gap))
                    Label(
                        text = row.sets.toString(),
                        size = 13.sp,
                        color = GlanceTheme.colors.onSurface,
                        weight = FontWeight.Bold,
                        modifier = GlanceModifier.width(valueWidth),
                        align = TextAlign.End,
                    )
                }
            }
        }
    }
}
