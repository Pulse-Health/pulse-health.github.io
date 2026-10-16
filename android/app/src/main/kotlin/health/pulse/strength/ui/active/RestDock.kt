package health.pulse.strength.ui.active

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.ActiveWorkoutPresentation
import health.pulse.strength.ui.theme.LocalReduceMotion
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import kotlin.math.max

/** "Reps left" chips: 0...4, where 4 means "4+". */
private val RirOptions = listOf(0 to "0", 1 to "1", 2 to "2", 3 to "3", 4 to "4+")

// The proportions of the three buttons (design widths 46 / 46 / 58 dp) and the gap between them.
private const val AdjustWeight = 46f
private const val SkipWeight = 58f
private val ButtonGap = 6.dp

/**
 * The floating rest dock at the bottom of the active-workout screen: draining ring, label and countdown, -15 / +15 / Skip (or
 * Dismiss once the rest is over) and the "Reps left" selector for the set that was just logged.
 *
 * The countdown block and the buttons share one line (the design). When the window is too narrow for both (small phones, big
 * text) the buttons move under the countdown and share the full width.
 */
@Composable
internal fun RestDock(
    dock: ActiveWorkoutPresentation.Dock,
    onAdjust: (Int) -> Unit,
    onSkip: () -> Unit,
    onSelectRIR: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = PulseTheme.colors
    val shape = RoundedCornerShape(24.dp)
    val finished = dock.phase == ActiveWorkoutPresentation.DockPhase.FINISHED
    val plate = colors.card.copy(alpha = 0.97f)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .testTag("rest-dock")
            .shadow(14.dp, shape, clip = false, ambientColor = Color.Black.copy(alpha = 0.10f), spotColor = Color.Black.copy(alpha = 0.18f))
            .background(plate, shape)
            .border(1.dp, Color.Black.copy(alpha = 0.05f), shape)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        DockMainRow(
            buttonsWidth = if (finished) null else (AdjustWeight * 2 + SkipWeight).dp.fontScaled() + ButtonGap * 2,
            countdown = { CountdownBlock(dock) },
            buttons = {
                if (finished) {
                    DismissButton(onSkip)
                } else {
                    AdjustButtons(onAdjust, onSkip)
                }
            },
        )
        if (dock.showsRIR) RirRow(dock.rirSelection, onSelectRIR)
    }
}

// region Layout

/**
 * Countdown block at the start, buttons at the end of one line; the buttons go under the countdown (full width) when the line is
 * too narrow for both. [buttonsWidth] is the width the buttons want on the shared line (null = their natural width).
 */
@Composable
private fun DockMainRow(buttonsWidth: Dp?, countdown: @Composable () -> Unit, buttons: @Composable () -> Unit) {
    Layout(contents = listOf(countdown, buttons), modifier = Modifier.fillMaxWidth()) { measurables, constraints ->
        val gap = 12.dp.roundToPx()
        val stackGap = 10.dp.roundToPx()
        val width = constraints.maxWidth
        val countdownM = measurables[0].single()
        val buttonsM = measurables[1].single()
        val buttonsWanted = buttonsWidth?.roundToPx() ?: buttonsM.maxIntrinsicWidth(Constraints.Infinity)
        val countdownWanted = countdownM.maxIntrinsicWidth(Constraints.Infinity)

        if (countdownWanted + gap + buttonsWanted <= width) {
            val buttonsP = buttonsM.measure(Constraints.fixedWidth(buttonsWanted))
            val countdownP = countdownM.measure(Constraints(maxWidth = width - gap - buttonsWanted))
            val height = max(countdownP.height, buttonsP.height)
            layout(width, height) {
                countdownP.placeRelative(0, (height - countdownP.height) / 2)
                buttonsP.placeRelative(width - buttonsWanted, (height - buttonsP.height) / 2)
            }
        } else {
            val countdownP = countdownM.measure(Constraints(maxWidth = width))
            val buttonsP = buttonsM.measure(Constraints.fixedWidth(width))
            layout(width, countdownP.height + stackGap + buttonsP.height) {
                countdownP.placeRelative(0, 0)
                buttonsP.placeRelative(0, countdownP.height + stackGap)
            }
        }
    }
}

// endregion

// region Ring and countdown

@Composable
private fun CountdownBlock(dock: ActiveWorkoutPresentation.Dock) {
    val colors = PulseTheme.colors
    val finished = dock.phase == ActiveWorkoutPresentation.DockPhase.FINISHED
    val labelColor = if (finished) colors.greenText else colors.inkSecondary
    val label = when {
        finished -> "Rest over"
        dock.isPaused -> "Rest · paused"
        else -> "Rest"
    }
    Row(
        modifier = Modifier
            .testTag("rest-countdown")
            .semantics(mergeDescendants = true) {
                contentDescription = when {
                    finished -> "Rest over"
                    dock.isPaused -> "Rest timer, paused"
                    else -> "Rest timer"
                }
                stateDescription = spokenRemaining(dock) + ". " + dock.nextSetText
            },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Ring(fraction = if (finished) 1.0 else dock.fraction, finished = finished)
        Column {
            Text(label, style = PulseFont.text(12.sp, FontWeight.SemiBold), color = labelColor, maxLines = 1)
            Text(
                text = dock.remainingText,
                style = PulseFont.number(30.sp, FontWeight.Bold).copy(letterSpacing = (-0.5).sp),
                color = colors.ink,
                maxLines = 1,
                modifier = Modifier.testTag("rest-remaining"),
            )
        }
    }
}

/** The 44 dp ring (inside a 52 dp frame) that drains with the rest, with the timer glyph in the middle. */
@Composable
private fun Ring(fraction: Double, finished: Boolean) {
    val colors = PulseTheme.colors
    val reduceMotion = LocalReduceMotion.current
    val animated by animateFloatAsState(
        targetValue = fraction.toFloat().coerceIn(0f, 1f),
        animationSpec = if (reduceMotion) snap() else tween(durationMillis = 1000, easing = LinearEasing),
        label = "restRing",
    )
    val tint = if (finished) colors.green else colors.recoveryGood
    val diameter = 44.dp.fontScaled()
    Box(Modifier.size(52.dp.fontScaled()), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(diameter)) {
            val stroke = 5.dp.toPx()
            val inset = stroke / 2
            val arcSize = Size(size.width - stroke, size.height - stroke)
            drawCircle(colors.progressTrack, radius = size.minDimension / 2 - inset, style = Stroke(width = stroke))
            if (animated > 0.001f) {
                drawArc(
                    color = tint,
                    startAngle = -90f,
                    sweepAngle = 360f * animated,
                    useCenter = false,
                    topLeft = Offset(inset, inset),
                    size = arcSize,
                    style = Stroke(width = stroke, cap = StrokeCap.Round),
                )
            }
        }
        Icon(Icons.Rounded.Timer, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp.fontScaled()))
    }
}

/** "1 minute 12 seconds" for the screen reader ("Go" once the rest is over). */
private fun spokenRemaining(dock: ActiveWorkoutPresentation.Dock): String {
    if (dock.phase == ActiveWorkoutPresentation.DockPhase.FINISHED) return "Go"
    val minutes = dock.remainingSeconds / 60
    val seconds = dock.remainingSeconds % 60
    val parts = mutableListOf<String>()
    if (minutes > 0) parts.add(if (minutes == 1) "1 minute" else "$minutes minutes")
    if (seconds > 0 || minutes == 0) parts.add(if (seconds == 1) "1 second" else "$seconds seconds")
    return parts.joinToString(" ")
}

// endregion

// region Buttons

@Composable
private fun AdjustButtons(onAdjust: (Int) -> Unit, onSkip: () -> Unit) {
    val colors = PulseTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(ButtonGap)) {
        DockButton(
            text = "−15",
            description = "Subtract 15 seconds",
            fill = colors.cellFill,
            textColor = colors.ink,
            weight = AdjustWeight,
            tag = "dock-minus",
            onClick = { onAdjust(-15) },
        )
        DockButton(
            text = "+15",
            description = "Add 15 seconds",
            fill = colors.cellFill,
            textColor = colors.ink,
            weight = AdjustWeight,
            tag = "dock-plus",
            onClick = { onAdjust(15) },
        )
        DockButton(
            text = "Skip",
            description = "Skip rest",
            fill = colors.green,
            textColor = colors.onGreen,
            weight = SkipWeight,
            tag = "dock-skip",
            onClick = onSkip,
        )
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.DockButton(
    text: String,
    description: String,
    fill: Color,
    textColor: Color,
    weight: Float,
    tag: String,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .weight(weight)
            .height(48.dp.fontScaled())
            .background(fill, RoundedCornerShape(12.dp))
            .testTag(tag)
            .pulseClickable(onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = PulseFont.number(15.sp, FontWeight.SemiBold), color = textColor, maxLines = 1)
    }
}

@Composable
private fun DismissButton(onClick: () -> Unit) {
    val colors = PulseTheme.colors
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp.fontScaled())
            .background(colors.green, RoundedCornerShape(10.dp))
            .testTag("dock-dismiss")
            .pulseClickable(onClick = onClick)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text("Dismiss", style = PulseFont.text(15.sp, FontWeight.SemiBold), color = colors.onGreen, maxLines = 1)
    }
}

// endregion

// region Reps left

@Composable
private fun RirRow(selection: Int?, onSelect: (Int) -> Unit) {
    val colors = PulseTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(
            "Reps left",
            style = PulseFont.caption,
            color = colors.inkSecondary,
            maxLines = 1,
            modifier = Modifier.widthIn(min = 54.dp),
        )
        RirSelector(selection, onSelect, Modifier.weight(1f))
    }
}

/**
 * The segmented control of the "Reps left" chips (0 1 2 3 4+). Like the shared segmented control, but every segment is a 48 dp tall
 * tap target (the control is used between sets, often with sweaty hands). Tapping the selected chip clears it (the caller toggles).
 */
@Composable
private fun RirSelector(selection: Int?, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Row(
        modifier = modifier
            .background(colors.chipFill, RoundedCornerShape(9.dp))
            .selectableGroup()
            .semantics { contentDescription = "Reps in reserve" }
            .testTag("dock-rir"),
    ) {
        for ((value, title) in RirOptions) {
            val isSelected = value == selection
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(48.dp.fontScaled())
                    .testTag("dock-rir-$value")
                    .semantics { selected = isSelected }
                    .pulseClickable(role = Role.RadioButton, onClick = { onSelect(value) })
                    .padding(2.dp),
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .fillMaxHeight()
                        .then(
                            if (isSelected) {
                                Modifier
                                    .shadow(2.dp, RoundedCornerShape(7.dp), clip = false)
                                    .background(if (colors.isDark) colors.cellOnTint else colors.card, RoundedCornerShape(7.dp))
                            } else {
                                Modifier
                            },
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        title,
                        style = PulseFont.number(15.sp, if (isSelected) FontWeight.Bold else FontWeight.Medium),
                        color = colors.ink,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

// endregion
