package health.pulse.strength.ui.detail

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.NumberText
import health.pulse.strength.core.timeIntervalSince
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseCard
import kotlin.math.max

// The estimated-1RM chart card: heading with the range menu, the Canvas chart and the three dates under it.

/** Text with non-breaking spaces, so a short date wraps as a whole. */
private fun String.keepTogether(): String = replace(' ', '\u00A0')

/** Grid lines of the chart (rgba(142,142,147,0.25) in the design). */
private val GridLineColor = Color(0xFF8E8E93).copy(alpha = 0.25f)

@Composable
internal fun ExerciseDetailChartCard(
    progress: ExerciseDetailProgress,
    hasSeries: Boolean,
    range: ExerciseDetailRange,
    onRangeChange: (ExerciseDetailRange) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = PulseTheme.colors
    Column(
        modifier
            .fillMaxWidth()
            .pulseCard()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
            Column(
                Modifier
                    .weight(1f)
                    .semantics(mergeDescendants = true) {},
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text("Estimated 1RM", style = PulseFont.text(15.sp), color = colors.inkSecondary)
                FitText(
                    text = progress.bestText,
                    style = PulseFont.number(28.sp).copy(lineHeight = 34.sp),
                    color = colors.ink,
                )
                if (progress.points.isNotEmpty()) {
                    // A date never breaks between month and day; the range may break at the dash.
                    Text(
                        progress.startLabel.keepTogether() + " – " + progress.endLabel.keepTogether(),
                        style = PulseFont.text(12.sp),
                        color = colors.inkSecondary,
                    )
                }
            }
            ExerciseDetailRangeMenu(selection = range, onSelect = onRangeChange)
        }

        val chartHeight = scaledDp(112.dp, maxScale = 1.5f)
        if (progress.points.isEmpty()) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = chartHeight)
                    // An empty chart keeps its frame: a faint line at the top and the bottom of the plot.
                    .drawBehind {
                        val width = max(1f, 0.5.dp.toPx())
                        drawLine(GridLineColor, Offset(0f, 0f), Offset(size.width, 0f), strokeWidth = width)
                        drawLine(GridLineColor, Offset(0f, size.height), Offset(size.width, size.height), strokeWidth = width)
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = if (hasSeries) "No sessions in this range" else "No sessions logged yet",
                    style = PulseFont.text(13.sp),
                    color = colors.inkSecondary,
                    textAlign = TextAlign.Center,
                )
            }
        } else {
            ExerciseDetailChart(progress = progress, height = chartHeight)
        }

        Text(
            "Estimated with weight × (1 + reps ÷ 30). Warm-up sets are left out.",
            style = PulseFont.text(11.sp),
            color = colors.inkSecondary,
        )
    }
}

/** The "12w" button with its range menu. */
@Composable
private fun ExerciseDetailRangeMenu(selection: ExerciseDetailRange, onSelect: (ExerciseDetailRange) -> Unit) {
    val colors = PulseTheme.colors
    var expanded by remember { mutableStateOf(false) }
    Box {
        // The chip is small as designed; its touch target is 48 dp.
        Box(
            Modifier
                .sizeIn(minWidth = 48.dp, minHeight = 48.dp)
                .clickable(role = Role.DropdownList, onClickLabel = "Choose chart range") { expanded = true }
                .semantics {
                    contentDescription = "Chart range"
                    stateDescription = selection.menuTitle
                },
            contentAlignment = Alignment.TopEnd,
        ) {
            Row(
                Modifier
                    .background(colors.progressTrack, RoundedCornerShape(8.dp))
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(selection.chipTitle, style = PulseFont.text(12.sp, FontWeight.SemiBold), color = colors.inkSecondary)
                Icon(
                    Icons.Rounded.KeyboardArrowDown,
                    contentDescription = null,
                    tint = colors.inkSecondary,
                    modifier = Modifier.size(scaledDp(14.dp, maxScale = 1.5f)),
                )
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            for (option in ExerciseDetailRange.entries) {
                DropdownMenuItem(
                    text = {
                        Text(
                            option.menuTitle,
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = if (option == selection) FontWeight.SemiBold else FontWeight.Normal,
                        )
                    },
                    trailingIcon = {
                        if (option == selection) Icon(Icons.Rounded.Check, contentDescription = "Selected", tint = colors.green)
                    },
                    onClick = {
                        expanded = false
                        onSelect(option)
                    },
                )
            }
        }
    }
}

/**
 * Estimated 1RM per session: a green line with round caps and joins, a point per session (the latest one larger) and a soft fill
 * under the line; grid lines and value labels sit on the trailing side like in the design. The three dates sit under the plot.
 *
 * A canvas is invisible to TalkBack, so the plot carries the [ExerciseDetailProgress.summary] as its description.
 */
@Composable
internal fun ExerciseDetailChart(progress: ExerciseDetailProgress, height: Dp, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    val density = LocalDensity.current
    val measurer = rememberTextMeasurer()
    val labelStyle = PulseFont.text(9.sp)
    val axis = progress.axis
    val labels: List<TextLayoutResult> = remember(axis, labelStyle, measurer) {
        axis.ticks.map { measurer.measure(NumberText.kg(it), labelStyle, maxLines = 1, softWrap = false) }
    }
    val labelWidth = labels.maxOf { it.size.width }
    val labelHeight = labels.maxOf { it.size.height }
    val gap = with(density) { 6.dp.toPx() }
    // The value labels take the trailing edge; the dates below leave the same room.
    val trailingInset = with(density) { (labelWidth + gap).toDp() }

    Column(modifier) {
        Canvas(
            Modifier
                .fillMaxWidth()
                .height(height)
                .semantics {
                    contentDescription = progress.summary
                    role = Role.Image
                },
        ) {
            drawChart(
                progress = progress,
                labels = labels,
                labelColor = colors.inkSecondary,
                lineColor = colors.recoveryGood,
                labelWidth = labelWidth,
                labelHeight = labelHeight,
                gap = gap,
            )
        }
        Spacer(Modifier.height(4.dp))
        ExerciseDetailDateRow(
            start = progress.startLabel,
            middle = progress.middleLabel,
            end = progress.endLabel,
            trailingInset = trailingInset,
        )
    }
}

private fun DrawScope.drawChart(
    progress: ExerciseDetailProgress,
    labels: List<TextLayoutResult>,
    labelColor: Color,
    lineColor: Color,
    labelWidth: Int,
    labelHeight: Int,
    gap: Float,
) {
    val axis = progress.axis
    val gridRight = size.width - labelWidth - gap
    val smallRadius = 3.2.dp.toPx()
    val largeRadius = 4.7.dp.toPx()
    // Room above and below for half a label and a full dot.
    val verticalPad = max(labelHeight / 2f, largeRadius + 1.dp.toPx())
    val plotTop = verticalPad
    val plotBottom = size.height - verticalPad
    val span = (axis.upper - axis.lower).takeIf { it > 0 } ?: 1.0
    val domain = progress.end.timeIntervalSince(progress.start).takeIf { it > 0 } ?: 1.0

    fun yOf(value: Double): Float = (plotBottom - ((value - axis.lower) / span).toFloat() * (plotBottom - plotTop))
    fun xOf(point: ExerciseDetailChartPoint): Float =
        (gridRight * (point.date.timeIntervalSince(progress.start) / domain).toFloat().coerceIn(0f, 1f))

    // Grid lines and value labels.
    val gridWidth = max(1f, 0.5.dp.toPx())
    axis.ticks.forEachIndexed { index, tick ->
        val y = yOf(tick)
        drawLine(GridLineColor, Offset(0f, y), Offset(gridRight, y), strokeWidth = gridWidth)
        val label = labels[index]
        drawText(label, color = labelColor, topLeft = Offset(gridRight + gap, y - label.size.height / 2f))
    }

    val points = progress.points
    if (points.isEmpty()) return
    val xs = points.map { xOf(it) }
    val ys = points.map { yOf(it.value) }

    if (points.size >= 2) {
        val baseline = plotBottom
        val area = Path().apply {
            moveTo(xs.first(), baseline)
            for (i in points.indices) lineTo(xs[i], ys[i])
            lineTo(xs.last(), baseline)
            close()
        }
        val top = ys.min()
        drawPath(
            area,
            brush = Brush.verticalGradient(
                0f to lineColor.copy(alpha = 0.30f),
                0.6f to lineColor.copy(alpha = 0.08f),
                1f to lineColor.copy(alpha = 0f),
                startY = top,
                endY = max(baseline, top + 1f),
            ),
        )
        val line = Path().apply {
            moveTo(xs.first(), ys.first())
            for (i in 1 until points.size) lineTo(xs[i], ys[i])
        }
        drawPath(line, lineColor, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
    points.forEachIndexed { index, point ->
        drawCircle(lineColor, radius = if (point.isLast) largeRadius else smallRadius, center = Offset(xs[index], ys[index]))
    }
}

/**
 * The three dates under the chart: start, middle, end. The middle one is left out when it would touch a neighbour; when even the
 * outer two do not fit side by side (very large text on a narrow screen) the end date moves to a second line.
 */
@Composable
private fun ExerciseDetailDateRow(start: String, middle: String, end: String, trailingInset: Dp, modifier: Modifier = Modifier) {
    val style = PulseFont.text(11.sp)
    val color = PulseTheme.colors.inkSecondary
    val gap = with(LocalDensity.current) { 8.dp.roundToPx() }
    Layout(
        content = {
            Text(start, style = style, color = color, maxLines = 1)
            Text(middle, style = style, color = color, maxLines = 1)
            Text(end, style = style, color = color, maxLines = 1)
        },
        // The row is decoration: TalkBack reads the dates from the chart's description.
        modifier = modifier
            .fillMaxWidth()
            .padding(end = trailingInset)
            .clearAndSetSemantics {},
    ) { measurables, constraints ->
        val loose = constraints.copy(minWidth = 0, minHeight = 0)
        val startPlaceable = measurables[0].measure(loose)
        val middlePlaceable = measurables[1].measure(loose)
        val endPlaceable = measurables[2].measure(loose)
        val width = if (constraints.hasBoundedWidth) {
            constraints.maxWidth
        } else {
            startPlaceable.width + endPlaceable.width + gap
        }
        val twoRows = startPlaceable.width + gap + endPlaceable.width > width
        val middleX = (width - middlePlaceable.width) / 2
        val showsMiddle = !twoRows && middle.isNotEmpty() && middle != start && middle != end &&
            middleX >= startPlaceable.width + gap && middleX + middlePlaceable.width + gap <= width - endPlaceable.width
        val height = if (twoRows) startPlaceable.height + endPlaceable.height else max(startPlaceable.height, endPlaceable.height)
        layout(width, height) {
            startPlaceable.placeRelative(0, 0)
            if (twoRows) {
                endPlaceable.placeRelative(width - endPlaceable.width, startPlaceable.height)
            } else {
                endPlaceable.placeRelative(width - endPlaceable.width, 0)
                if (showsMiddle) middlePlaceable.placeRelative(middleX, 0)
            }
        }
    }
}
