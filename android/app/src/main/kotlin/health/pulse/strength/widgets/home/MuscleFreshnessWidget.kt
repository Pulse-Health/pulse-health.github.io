package health.pulse.strength.widgets.home

import androidx.compose.runtime.Composable
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
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.unit.ColorProvider
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.widgets.FreshnessStatus
import health.pulse.strength.core.widgets.MuscleFreshness
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseWidget

/** HS-04 Muscle freshness: the muscle groups that have rested longest, with the days since each was trained. */
class MuscleFreshnessWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        MuscleFreshnessContent(snapshot)
    }
}

class MuscleFreshnessReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = MuscleFreshnessWidget()
}

internal data class FreshnessRow(val muscle: String, val days: String, val status: FreshnessStatus, val description: String)

/** [shortHeader] is the heading of a card too narrow for [header]. */
internal data class FreshnessCard(val header: String, val shortHeader: String, val rows: List<FreshnessRow>, val description: String)

internal object FreshnessModel {
    private const val ROW_DP = 23f
    private const val CHROME_DP = 24f + 24f
    private const val MAX_ROWS = 4

    /** How many of the four rows fit a widget of [heightDp]: the padding and the heading take 48 dp, a row 23 dp. */
    fun rowCount(heightDp: Float): Int = HomeLayout.rowsThatFit(heightDp, ROW_DP, reserveDp = CHROME_DP, max = MAX_ROWS)

    /**
     * The [maxRows] groups that were trained longest ago, longest first (a group never trained counts as longest; ties keep the order
     * of [MuscleGroup]). The heading says "Ready to train" while at least one of them is ready, else "Recovering".
     */
    fun card(snapshot: WidgetSnapshot, maxRows: Int): FreshnessCard {
        val order = MuscleGroup.entries
        val stalest = snapshot.freshness
            .sortedWith(compareByDescending<MuscleFreshness> { it.daysSince ?: Int.MAX_VALUE }.thenBy { order.indexOf(it.muscle) })
            .take(maxRows)
        val rows = stalest.map { row ->
            val days = row.daysSince
            FreshnessRow(
                muscle = row.muscle.title,
                days = if (days == null) "never" else HomeText.daysShort(days),
                status = row.status,
                description = "${row.muscle.title}: ${statusWord(row.status)}, " +
                    (if (days == null) "not trained yet" else HomeDates.daysAgoLower(days)),
            )
        }
        val ready = stalest.any { it.status == FreshnessStatus.READY }
        val header = if (ready) "Ready to train" else "Recovering"
        val description = if (rows.isEmpty()) "No recovery data yet" else "$header. " + rows.joinToString(". ") { it.description }
        return FreshnessCard(header, if (ready) "Ready" else header, rows, description)
    }

    fun statusWord(status: FreshnessStatus): String = when (status) {
        FreshnessStatus.READY -> "ready"
        FreshnessStatus.RECOVERING -> "recovering"
        FreshnessStatus.WORKED -> "worked recently"
    }
}

@Composable
internal fun MuscleFreshnessContent(snapshot: WidgetSnapshot) {
    val size = LocalSize.current
    val card = FreshnessModel.card(snapshot, FreshnessModel.rowCount(size.height.value))
    // "READY TO TRAIN" needs about 100 dp: a 2x2 widget on a small phone is narrower than that inside its padding.
    val header = if (size.width < 140.dp) card.shortHeader else card.header
    WidgetCard(padding = 12.dp, horizontalPadding = 14.dp, description = card.description) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Label(HomeText.eyebrow(header), 12.sp, GlanceTheme.colors.onSurfaceVariant, FontWeight.Bold)
            Spacer(GlanceModifier.height(6.dp))
            if (card.rows.isEmpty()) {
                Label("Train a muscle group to see how fresh it is.", 13.sp, GlanceTheme.colors.onSurfaceVariant, maxLines = 3)
            }
            card.rows.forEach { FreshnessLine(it) }
        }
    }
}

@Composable
private fun FreshnessLine(row: FreshnessRow) {
    Row(
        modifier = GlanceModifier.fillMaxWidth().padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(modifier = GlanceModifier.size(10.dp).cornerRadius(5.dp).background(statusColor(row.status))) {}
        Spacer(GlanceModifier.width(8.dp))
        Label(row.muscle, 14.sp, GlanceTheme.colors.onSurface, modifier = GlanceModifier.defaultWeight())
        Label(row.days, 13.sp, GlanceTheme.colors.onSurfaceVariant)
    }
}

private fun statusColor(status: FreshnessStatus): ColorProvider = when (status) {
    FreshnessStatus.READY -> HomeColors.ready
    FreshnessStatus.RECOVERING -> HomeColors.recovering
    FreshnessStatus.WORKED -> HomeColors.worked
}
