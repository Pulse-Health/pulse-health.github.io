package health.pulse.strength.widgets.home

import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.background
import androidx.glance.currentState
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
import androidx.glance.text.TextAlign
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.LiftTrend
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.ChartBitmaps
import health.pulse.strength.widgets.common.MaskImage
import health.pulse.strength.widgets.common.PulseActions
import health.pulse.strength.widgets.common.PulseWidget
import health.pulse.strength.widgets.common.toPx
import kotlin.math.abs

/**
 * HS-09 Lift trend (4x2): the estimated one-rep max of one lift over its last sessions as a sparkline, the personal-record session in gold.
 * The lift is chosen per widget in [LiftTrendConfigActivity] and kept in the widget's Glance state under [LiftKey]; a widget whose lift is
 * not (or no longer) among the snapshot's lifts shows the first one.
 */
class LiftTrendWidget : PulseWidget() {
    @Composable
    override fun Content(snapshot: WidgetSnapshot) {
        LiftTrendContent(snapshot, currentState(LiftKey))
    }

    companion object {
        /** The exercise id the user picked, in the Glance preferences state of the widget id. */
        val LiftKey = stringPreferencesKey("lift_trend.exercise_id")
    }
}

class LiftTrendReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = LiftTrendWidget()
}

internal data class LiftCard(
    val exerciseId: String,
    val name: String,
    val subtitle: String,
    val value: String,
    val delta: String?,
    val values: List<Double>,
    val prIndex: Int?,
    val firstLabel: String?,
    val lastLabel: String?,
    val description: String,
    val chartDescription: String,
)

/** The vertical split of the chart area: what fits below the header of a widget of a given height. */
internal data class LiftChartPlan(val chartHeight: Float, val showPrBand: Boolean, val showAxis: Boolean) {
    val showChart: Boolean get() = chartHeight >= MIN_CHART_DP

    companion object {
        const val MIN_CHART_DP = 24f
        const val BAND_DP = 14f
        private const val CHROME_DP = 20f + 40f + 4f
        private const val COMFORTABLE_DP = 30f

        /** Sets aside the padding (20), the header (40) and the gap (4), then gives the "PR" band and the day labels what the chart can spare. */
        fun forHeight(heightDp: Float, hasPr: Boolean): LiftChartPlan {
            val room = heightDp - CHROME_DP
            val prBandWanted = if (hasPr) BAND_DP else 0f
            val axis = room - BAND_DP - prBandWanted >= COMFORTABLE_DP
            val axisHeight = if (axis) BAND_DP else 0f
            val band = hasPr && room - axisHeight - BAND_DP >= COMFORTABLE_DP
            return LiftChartPlan(room - axisHeight - (if (band) BAND_DP else 0f), band, axis)
        }
    }
}

/** Where the points of a sparkline lie; the same maths as `ChartBitmaps` (inset on every side, first to last across the width). */
internal object SparklineGeometry {
    fun points(widthDp: Float, heightDp: Float, values: List<Double>, insetDp: Float): List<Pair<Float, Float>> {
        if (values.isEmpty()) return emptyList()
        val lowest = values.min()
        val range = maxOf(values.max() - lowest, 1.0)
        val usableWidth = widthDp - 2 * insetDp
        val usableHeight = heightDp - 2 * insetDp
        return values.mapIndexed { index, value ->
            val x = if (values.size > 1) insetDp + usableWidth * index / (values.size - 1) else widthDp / 2f
            val y = insetDp + usableHeight * (1f - ((value - lowest) / range).toFloat())
            x to y
        }
    }
}

internal object LiftTrendModel {
    const val EmptyTitle = "No lifts yet"
    const val EmptyMessage = "Train a lift in a few workouts and its estimated 1RM shows up here."

    /** The lift with [chosenId], else the first one (the ranking puts the most trained lift first). */
    fun select(lifts: List<LiftTrend>, chosenId: String?): LiftTrend? =
        lifts.firstOrNull { it.exerciseID == chosenId } ?: lifts.firstOrNull()

    fun card(snapshot: WidgetSnapshot, chosenId: String?): LiftCard? {
        val lift = select(snapshot.lifts, chosenId) ?: return null
        val zone = HomeDates.zoneOf(snapshot)
        val points = lift.points
        val plotted = points.size >= 2
        val delta = if (plotted) deltaText(lift.deltaKg) else null
        val record = lift.prIndex?.takeIf { it in points.indices }
        val ages = points.map { HomeDates.daysBetween(it.date, snapshot.generatedAt, zone) }
        val value = HomeText.kg(lift.currentE1RM)
        val series = points.joinToString(", ") { HomeText.kg(it.value) }
        val chartDescription = "Estimated one-rep max over the last ${HomeText.sessions(points.size)}: $series kilograms"
        return LiftCard(
            exerciseId = lift.exerciseID,
            name = lift.name,
            subtitle = if (plotted) "Estimated 1RM · ${HomeText.sessions(points.size)}" else "Estimated 1RM",
            value = value,
            delta = delta,
            values = points.map { it.value },
            prIndex = record,
            firstLabel = if (plotted) ageLabel(ages.first()) else null,
            lastLabel = if (plotted) ageLabel(ages.last()) else null,
            description = "${lift.name}: estimated one-rep max $value kilograms" +
                (if (plotted) deltaWords(lift.deltaKg) else "") +
                (record?.let { ", personal record ${HomeText.kg(points[it].value)} kilograms" } ?: ""),
            chartDescription = chartDescription,
        )
    }

    /** "+3 kg vs last", "−3 kg vs last", "No change". */
    fun deltaText(deltaKg: Double): String =
        if (abs(deltaKg) < 0.005) "No change" else HomeText.signed(deltaKg) + " kg vs last"

    /** ", up 3 kilograms since the last session" for a screen reader. */
    fun deltaWords(deltaKg: Double): String = when {
        abs(deltaKg) < 0.005 -> ", unchanged since the last session"
        deltaKg > 0 -> ", up ${HomeText.kg(deltaKg)} kilograms since the last session"
        else -> ", down ${HomeText.kg(-deltaKg)} kilograms since the last session"
    }

    /** "today" or "5d": how long ago a session was. */
    fun ageLabel(days: Int): String = if (days <= 0) "today" else "${days}d"

    /** The horizontal side of the "PR" label that keeps it inside the chart. */
    fun prLabelStart(pointX: Float, widthDp: Float, labelWidthDp: Float): Float =
        (pointX - labelWidthDp / 2f).coerceIn(0f, maxOf(0f, widthDp - labelWidthDp))
}

@Composable
internal fun LiftTrendContent(snapshot: WidgetSnapshot, chosenId: String?) {
    val card = LiftTrendModel.card(snapshot, chosenId)
    val size = LocalSize.current
    if (card == null) {
        LiftTrendEmpty()
        return
    }
    val chartWidth = size.width - 28.dp
    val plan = LiftChartPlan.forHeight(size.height.value, card.prIndex != null)
    WidgetCard(
        padding = 10.dp,
        horizontalPadding = 14.dp,
        description = card.description,
        onClick = PulseActions.link(DeepLinks.exercise(card.exerciseId)),
    ) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                Column(modifier = GlanceModifier.defaultWeight()) {
                    Label(card.name, 15.sp, GlanceTheme.colors.onSurface, FontWeight.Medium)
                    Label(card.subtitle, 12.sp, GlanceTheme.colors.onSurfaceVariant)
                }
                Column(horizontalAlignment = Alignment.End) {
                    Row(verticalAlignment = Alignment.Bottom) {
                        Label(card.value, 28.sp, GlanceTheme.colors.onSurface, FontWeight.Bold)
                        Label(" kg", 13.sp, GlanceTheme.colors.onSurfaceVariant, modifier = GlanceModifier.padding(bottom = 4.dp))
                    }
                    card.delta?.let { Label(it, 12.sp, GlanceTheme.colors.onSurfaceVariant, align = TextAlign.End) }
                }
            }
            if (plan.showChart) {
                Spacer(GlanceModifier.height(4.dp))
                if (plan.showPrBand) PrBand(card, chartWidth)
                Sparkline(card, chartWidth, plan.chartHeight.dp)
                if (plan.showAxis) AxisLabels(card)
            }
        }
    }
}

@Composable
private fun LiftTrendEmpty() {
    WidgetCard(padding = 12.dp, horizontalPadding = 14.dp, description = "${LiftTrendModel.EmptyTitle}. ${LiftTrendModel.EmptyMessage}") {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Eyebrow("Lift trend")
            Spacer(GlanceModifier.height(2.dp))
            Label(LiftTrendModel.EmptyTitle, 17.sp, GlanceTheme.colors.onSurface, FontWeight.Bold)
            Label(LiftTrendModel.EmptyMessage, 13.sp, GlanceTheme.colors.onSurfaceVariant, maxLines = 3)
        }
    }
}

private const val SPARK_INSET_DP = 8f
private const val PR_DOT_DP = 12f
private const val PR_LABEL_DP = 20f

/** The "PR" tag above the record point, which is always the highest point of the chart. */
@Composable
private fun PrBand(card: LiftCard, chartWidth: Dp) {
    val index = card.prIndex ?: return
    val x = SparklineGeometry.points(chartWidth.value, 1f, card.values, SPARK_INSET_DP)[index].first
    val start = LiftTrendModel.prLabelStart(x, chartWidth.value, PR_LABEL_DP)
    Box(modifier = GlanceModifier.fillMaxWidth().height(LiftChartPlan.BAND_DP.dp).padding(start = start.dp)) {
        Label("PR", 11.sp, HomeColors.goldText, FontWeight.Bold, GlanceModifier.width(PR_LABEL_DP.dp), align = TextAlign.Center)
    }
}

/** The line and its dots as one mask in the line colour, the record dot as a second, small mask in gold. */
@Composable
private fun Sparkline(card: LiftCard, width: Dp, height: Dp) {
    val widthPx = width.toPx()
    val heightPx = height.toPx()
    val density = widthPx / width.value
    val insetPx = SPARK_INSET_DP * density
    val values = card.values
    val body = mergeMasks(
        ChartBitmaps.line(widthPx, heightPx, values, strokePx = 2.5f * density, insetPx = insetPx),
        ChartBitmaps.dots(widthPx, heightPx, values, radiusPx = 4.5f * density, insetPx = insetPx, skipIndex = card.prIndex),
    )
    val recordPoint = card.prIndex?.let { SparklineGeometry.points(width.value, height.value, values, SPARK_INSET_DP)[it] }
    Box(modifier = GlanceModifier.size(width, height)) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Spacer(GlanceModifier.defaultWeight())
            Box(modifier = GlanceModifier.fillMaxWidth().height(1.dp).background(GlanceTheme.colors.outline)) {}
        }
        MaskImage(body, GlanceTheme.colors.primary, GlanceModifier.fillMaxSize(), contentDescription = card.chartDescription)
        if (recordPoint != null) {
            val dotPx = PR_DOT_DP.dp.toPx()
            val dot = ChartBitmaps.mask(dotPx, dotPx) { canvas, paint ->
                paint.style = android.graphics.Paint.Style.FILL
                canvas.drawCircle(dotPx / 2f, dotPx / 2f, dotPx / 2f, paint)
            }
            Box(modifier = GlanceModifier.padding(start = (recordPoint.first - PR_DOT_DP / 2f).dp, top = (recordPoint.second - PR_DOT_DP / 2f).dp)) {
                MaskImage(dot, HomeColors.gold, GlanceModifier.size(PR_DOT_DP.dp))
            }
        }
    }
}

@Composable
private fun AxisLabels(card: LiftCard) {
    Row(modifier = GlanceModifier.fillMaxWidth().height(LiftChartPlan.BAND_DP.dp)) {
        Label(card.firstLabel.orEmpty(), 11.sp, GlanceTheme.colors.onSurfaceVariant, modifier = GlanceModifier.defaultWeight())
        Label(card.lastLabel.orEmpty(), 11.sp, GlanceTheme.colors.onSurfaceVariant, align = TextAlign.End)
    }
}
