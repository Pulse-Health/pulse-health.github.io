package health.pulse.strength.ui.active

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.EmojiEvents
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.ActiveWorkoutPresentation
import health.pulse.strength.ui.KeypadField
import health.pulse.strength.ui.theme.LocalReduceMotion
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.badgeBackground
import health.pulse.strength.ui.theme.badgeForeground
import health.pulse.strength.ui.theme.pulseClickable

// The columns of the set table (design geometry): 10 dp leading inset, then
// badge 36 | previous (flexible) | weight 68 | reps 60 | check 48, 6 dp apart.
private val BadgeColumn = 36.dp
private val WeightColumn = 68.dp
private val RepsColumn = 60.dp
private val CheckColumn = 48.dp
private val ColumnGap = 6.dp
private val RowInset = 10.dp

/** Narrowest the Previous column may get; with less room it is hidden (its figures and the PR / RIR tags would only be clipped). */
private val PreviousMinWidth = 44.dp

/** Gap between two rows of the table. */
internal val SetRowGap = 3.dp

/** Height of one set row at the default font size (the design's 48). */
internal val SetRowHeight = 48.dp

// region Column titles

/**
 * "SET  PREVIOUS  KG  REPS" in 11 sp semibold caps. The columns use the same geometry as [SetRowView] so every title sits over its
 * cells. Decorative for screen readers (each row announces its own values).
 */
@Composable
internal fun SetTableHeader(weightTitle: String, repsTitle: String, modifier: Modifier = Modifier) {
    SetColumns(
        modifier = modifier
            .fillMaxWidth()
            .padding(start = RowInset)
            .heightIn(min = 16.dp)
            .clearAndSetSemantics { },
        badge = { ColumnTitle("Set", Modifier.width(BadgeColumn), TextAlign.Start) },
        previous = { ColumnTitle("Previous", Modifier, TextAlign.Start) },
        weight = { ColumnTitle(weightTitle, Modifier.width(WeightColumn), TextAlign.Center) },
        reps = { ColumnTitle(repsTitle, Modifier.width(RepsColumn), TextAlign.Center) },
        check = { Spacer(Modifier.width(CheckColumn)) },
    )
}

@Composable
private fun ColumnTitle(text: String, modifier: Modifier, align: TextAlign) {
    Text(
        text = text.uppercase(),
        modifier = modifier,
        style = PulseFont.text(cappedSp(11f), FontWeight.SemiBold).copy(letterSpacing = 0.4.sp),
        color = PulseTheme.colors.inkSecondary,
        textAlign = align,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
}

/**
 * The five columns of the set table in one line, [ColumnGap] apart: badge | previous | weight | reps | check. The titles and every row
 * use it, so they always line up. The Previous column takes what the other four leave; the check circle is measured first and keeps
 * its full width whatever the window does. A window too narrow for the Previous column (less than [PreviousMinWidth]) hides it and
 * keeps its room empty; one narrower than the other four columns squeezes the badge and the value cells, the reps cell first.
 */
@Composable
private fun SetColumns(
    modifier: Modifier,
    badge: @Composable () -> Unit,
    previous: @Composable () -> Unit,
    weight: @Composable () -> Unit,
    reps: @Composable () -> Unit,
    check: @Composable () -> Unit,
) {
    Layout(contents = listOf(badge, previous, weight, reps, check), modifier = modifier) { measurables, constraints ->
        val gap = ColumnGap.roundToPx()
        val width = constraints.maxWidth
        var room = width
        // Each cell is measured with what the cells before it left (and the gap that follows it), so the later ones give way first.
        fun measureCell(slot: Int, gapAfter: Int): List<Placeable> {
            val placeables = measurables[slot].map { it.measure(Constraints(maxWidth = (room - gapAfter).coerceAtLeast(0))) }
            room -= placeables.sumOf { it.width } + gapAfter
            return placeables
        }
        val checkP = measureCell(4, 0)
        val badgeP = measureCell(0, gap)
        val weightP = measureCell(2, gap)
        val repsP = measureCell(3, gap)
        // What is left belongs to the Previous column and the gap after it.
        val previousWidth = room - gap
        val previousP = if (previousWidth >= PreviousMinWidth.roundToPx()) {
            measurables[1].map { it.measure(Constraints(minWidth = previousWidth, maxWidth = previousWidth)) }
        } else {
            emptyList()
        }
        val cells = badgeP + previousP + weightP + repsP + checkP
        val rowHeight = (cells.maxOfOrNull { it.height } ?: 0).coerceIn(constraints.minHeight, constraints.maxHeight)

        layout(width, rowHeight) {
            val badgeWidth = badgeP.sumOf { it.width }
            badgeP.forEach { it.placeRelative(0, (rowHeight - it.height) / 2) }
            previousP.forEach { it.placeRelative(badgeWidth + gap, (rowHeight - it.height) / 2) }
            // The weight column starts where the Previous column and its gap end (the room stays empty when the column is hidden).
            val weightX = badgeWidth + gap + room.coerceAtLeast(0)
            weightP.forEach { it.placeRelative(weightX, (rowHeight - it.height) / 2) }
            val repsX = weightX + weightP.sumOf { it.width } + gap
            repsP.forEach { it.placeRelative(repsX, (rowHeight - it.height) / 2) }
            checkP.forEach { it.placeRelative(width - it.width, (rowHeight - it.height) / 2) }
        }
    }
}

// endregion

// region Rows

/**
 * The rows of the exercise card in a vertical scroll container: the container takes the natural height of the rows, or the height
 * it is given when that is smaller (then the rows scroll).
 *
 * The next pending set is kept in view: on first show, whenever it changes (a set was logged, another exercise) and whenever
 * [visibilityKey] changes (the room the page offers: the rest dock came or went). The request goes up through every scroll
 * container, so it also scrolls the page when the card is too tall for the window and the page scrolls instead of the rows.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun SetRowList(
    rows: List<ActiveWorkoutPresentation.SetRow>,
    repsAccessibilityName: String,
    visibilityKey: Any?,
    onToggle: (ActiveWorkoutPresentation.SetRow) -> Unit,
    onOpenDetail: (ActiveWorkoutPresentation.SetRow) -> Unit,
    onOpenKeypad: (ActiveWorkoutPresentation.SetRow, KeypadField) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scroll = rememberScrollState()
    val nextRowRequester = remember { BringIntoViewRequester() }
    val nextID = rows.firstOrNull { it.isNext }?.id

    LaunchedEffect(nextID, visibilityKey) {
        if (nextID != null) {
            // The row has its place once the frame that composed it is laid out.
            withFrameNanos { }
            nextRowRequester.bringIntoView()
        }
    }

    Column(
        modifier = modifier.verticalScroll(scroll),
        verticalArrangement = Arrangement.spacedBy(SetRowGap),
    ) {
        rows.forEach { row ->
            key(row.id) {
                SetRowView(
                    row = row,
                    repsAccessibilityName = repsAccessibilityName,
                    onToggle = { onToggle(row) },
                    onOpenDetail = { onOpenDetail(row) },
                    onOpenKeypad = { field -> onOpenKeypad(row, field) },
                    modifier = if (row.isNext) Modifier.bringIntoViewRequester(nextRowRequester) else Modifier,
                )
            }
        }
    }
}

/**
 * One set of the exercise card: at least 48 dp tall (it grows when the text does), 10 dp radius.
 *
 * Columns: type badge | previous + PR / RIR tags (flexible) | weight cell | reps cell | check circle. The row is one screen-reader
 * element labelled with the presenter's `accessibilityLabel`; activating it toggles the set and the type, weight and reps editors
 * are offered as custom actions. Every visible control is a 48 dp tall tap target.
 */
@Composable
internal fun SetRowView(
    row: ActiveWorkoutPresentation.SetRow,
    repsAccessibilityName: String,
    onToggle: () -> Unit,
    onOpenDetail: () -> Unit,
    onOpenKeypad: (KeypadField) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = PulseTheme.colors
    val shape = RoundedCornerShape(PulseMetrics.rowRadius)
    val details = accessibilityDetails(row)
    val toggleLabel = if (row.isDone) "Mark as not logged" else "Log this set"
    SetColumns(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = SetRowHeight)
            .background(if (row.isDone) colors.doneRowFill else colors.rowFill, shape)
            .then(if (row.isNext) Modifier.border(1.5.dp, colors.nextRowRing, shape) else Modifier)
            .testTag("set-row-${row.id}")
            .clearAndSetSemantics {
                contentDescription = row.accessibilityLabel
                if (details.isNotEmpty()) stateDescription = details
                role = Role.Button
                onClick(label = toggleLabel) { onToggle(); true }
                customActions = buildList {
                    add(CustomAccessibilityAction("Change set type") { onOpenDetail(); true })
                    if (row.weightEditable) add(CustomAccessibilityAction("Edit weight") { onOpenKeypad(KeypadField.WEIGHT); true })
                    add(CustomAccessibilityAction("Edit $repsAccessibilityName") { onOpenKeypad(KeypadField.REPS); true })
                }
            }
            .padding(start = RowInset),
        badge = { TypeBadge(row, onOpenDetail) },
        previous = { InfoColumn(row, Modifier) },
        weight = {
            if (row.weightEditable) {
                ValueCell(
                    text = row.weightText,
                    width = WeightColumn,
                    isDone = row.isDone,
                    tag = "set-weight-${row.id}",
                    onClick = { onOpenKeypad(KeypadField.WEIGHT) },
                )
            } else {
                ValueCell(
                    text = row.weightText,
                    width = WeightColumn,
                    isDone = row.isDone,
                    tag = "set-weight-${row.id}",
                    onClick = null,
                    modifier = Modifier.alpha(0.45f),
                )
            }
        },
        reps = {
            ValueCell(
                text = row.repsText,
                width = RepsColumn,
                isDone = row.isDone,
                tag = "set-reps-${row.id}",
                onClick = { onOpenKeypad(KeypadField.REPS) },
            )
        },
        check = { CheckButton(row.isDone, onToggle, Modifier.testTag("set-check-${row.id}")) },
    )
}

/** Extra spoken detail that is not part of the sentence-style label: personal record with its estimated 1RM, and the reps in reserve. */
private fun accessibilityDetails(row: ActiveWorkoutPresentation.SetRow): String {
    val parts = mutableListOf<String>()
    if (row.isPersonalRecord) {
        val e1rm = row.estimated1RM
        parts.add(if (e1rm != null) "Personal record, estimated one rep max $e1rm kilograms" else "Personal record")
    }
    val rir = row.rir
    if (row.isDone && rir != null) {
        parts.add(if (rir >= 4) "4 or more reps in reserve" else "$rir reps in reserve")
    }
    return parts.joinToString(". ")
}

@Composable
private fun TypeBadge(row: ActiveWorkoutPresentation.SetRow, onOpenDetail: () -> Unit) {
    Box(
        modifier = Modifier
            .width(BadgeColumn)
            .heightIn(min = SetRowHeight)
            .testTag("set-badge-${row.id}")
            .pulseClickable(onClick = onOpenDetail),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(BadgeColumn)
                .background(row.type.badgeBackground(), RoundedCornerShape(8.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = row.number,
                style = PulseFont.text(15.sp, FontWeight.Bold),
                color = row.type.badgeForeground(),
                maxLines = 1,
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun InfoColumn(row: ActiveWorkoutPresentation.SetRow, modifier: Modifier) {
    val colors = PulseTheme.colors
    Column(modifier, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        ShrinkToFitText(
            text = row.previousText,
            style = PulseFont.number(13.sp, FontWeight.Normal),
            color = colors.inkSecondary,
            minScale = 0.8f,
        )
        if (row.isDone && (row.isPersonalRecord || row.rirText != null)) {
            // "PR" and "RIR 2" share a line; in a narrow column (small phone, big text) the second moves to the next line.
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                itemVerticalAlignment = Alignment.CenterVertically,
            ) {
                if (row.isPersonalRecord) {
                    Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.EmojiEvents, contentDescription = null, tint = colors.prText, modifier = Modifier.size(12.dp))
                        Text("PR", style = PulseFont.text(11.sp, FontWeight.Bold), color = colors.prText, maxLines = 1)
                    }
                }
                row.rirText?.let { rirText ->
                    Text(
                        text = rirText,
                        style = PulseFont.text(11.sp, FontWeight.SemiBold),
                        color = colors.ink.copy(alpha = 0.75f),
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

/** A value cell (at least 40 dp tall) inside a 48 dp tall tap target; the width is fixed so the columns line up with the titles. */
@Composable
private fun ValueCell(
    text: String,
    width: androidx.compose.ui.unit.Dp,
    isDone: Boolean,
    tag: String,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val colors = PulseTheme.colors
    val fill = if (isDone) colors.cellOnTint.copy(alpha = colors.cellOnTint.alpha * 0.75f) else colors.cellOnTint
    Box(
        modifier = modifier
            .width(width)
            .heightIn(min = SetRowHeight)
            .testTag(tag)
            .then(if (onClick != null) Modifier.pulseClickable(onClick = onClick) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 40.dp)
                .background(fill, RoundedCornerShape(8.dp))
                .padding(horizontal = 4.dp),
            contentAlignment = Alignment.Center,
        ) {
            ShrinkToFitText(
                text = text,
                style = PulseFont.number(18.sp, FontWeight.SemiBold),
                color = colors.ink,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun CheckButton(isDone: Boolean, onToggle: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(CheckColumn)
            .pulseClickable(onClick = onToggle),
        contentAlignment = Alignment.Center,
    ) {
        CheckCircle(isDone)
    }
}

/** The 28 dp log toggle: grey ring while pending, solid green with a white check when logged. */
@Composable
private fun CheckCircle(isDone: Boolean) {
    val colors = PulseTheme.colors
    val reduceMotion = LocalReduceMotion.current
    val fill by animateFloatAsState(
        targetValue = if (isDone) 1f else 0f,
        animationSpec = if (reduceMotion) snap() else tween(150),
        label = "checkFill",
    )
    Canvas(Modifier.size(28.dp)) {
        val strokeWidth = 2.dp.toPx()
        val radius = size.minDimension / 2
        if (fill > 0f) drawCircle(colors.green.copy(alpha = fill), radius = radius)
        drawCircle(
            color = if (isDone) colors.green else colors.inkTertiary,
            radius = radius - strokeWidth / 2,
            style = Stroke(width = strokeWidth),
        )
        if (fill > 0f) {
            // The design's check ("M5 12.5l4.5 4.5L19 7.5" in a 24 x 24 box) drawn in a 16 dp box in the middle of the circle.
            val box = 16.dp.toPx()
            val origin = Offset((size.width - box) / 2, (size.height - box) / 2)
            fun point(x: Float, y: Float) = Offset(origin.x + box * x / 24f, origin.y + box * y / 24f)
            val path = Path().apply {
                moveTo(point(5f, 12.5f).x, point(5f, 12.5f).y)
                lineTo(point(9.5f, 17f).x, point(9.5f, 17f).y)
                lineTo(point(19f, 7.5f).x, point(19f, 7.5f).y)
            }
            drawPath(
                path = path,
                color = colors.onGreen.copy(alpha = fill),
                style = Stroke(width = (3.2f * 16f / 24f).dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round),
            )
        }
    }
}

// endregion
