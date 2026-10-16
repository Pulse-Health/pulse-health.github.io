package health.pulse.strength.live

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.NumberText
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.ui.components.rememberNow
import java.time.ZoneId

/** What the buttons of bench mode do. */
internal class BenchActions(
    val adjustRest: (seconds: Int) -> Unit,
    val skipRest: () -> Unit,
    val logSet: () -> Unit,
    val resume: () -> Unit,
    val openWorkout: () -> Unit,
    val close: () -> Unit,
)

/** The colours of bench mode: white and green on black by day, red on black at night (SB-04). */
@Immutable
internal class BenchPalette(
    val text: Color,
    val secondary: Color,
    val ring: Color,
    val track: Color,
    val buttonFill: Color,
    val buttonText: Color,
    val actionFill: Color,
    val actionText: Color,
)

internal val DayBenchPalette = BenchPalette(
    text = Color.White,
    secondary = Color(0xFF98989D),
    ring = Color(0xFF34C759),
    track = Color(0xFF2C2C2E),
    buttonFill = Color(0xFF2C2C2E),
    buttonText = Color.White,
    actionFill = Color(0xFF1B8448),
    actionText = Color.White,
)

internal val NightBenchPalette = BenchPalette(
    text = Color(0xFFFF3B30),
    secondary = Color(0xE6FF3B30),
    ring = Color(0xFFFF3B30),
    track = Color(0xFF3A0F0C),
    buttonFill = Color(0xFF2A0A08),
    buttonText = Color(0xFFFF3B30),
    actionFill = Color(0xFFFF3B30),
    actionText = Color.Black,
)

private val RingSize = 220.dp
private val RingStroke = 16.dp

/** Tabular numerals, so a counting clock does not jitter. */
private val Digits = TextStyle(fontFeatureSettings = "tnum")

/**
 * SB-02 / SB-04 Bench mode: the phone leans against the bench and is read from two metres. Resting: a 220 dp ring with a 64 sp countdown,
 * the next set, "+15 s" and "Skip"; logging: the weight and reps in large type and "Log set"; no workout: tomorrow's session beside
 * the clock. [forcedNight] true or false forces the look, null picks it from the hour.
 */
@Composable
internal fun BenchModeScreen(snapshot: WidgetSnapshot, forcedNight: Boolean?, is24Hour: Boolean, actions: BenchActions) {
    val now by rememberNow(periodMillis = 250L)
    val localTime = now.atZone(ZoneId.systemDefault()).toLocalTime()
    val palette = if (BenchModeStates.isNight(forcedNight, localTime)) NightBenchPalette else DayBenchPalette
    val state = BenchModeStates.of(snapshot, now, is24Hour)

    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = palette.actionFill,
            onPrimary = palette.actionText,
            background = Color.Black,
            surface = Color.Black,
            onBackground = palette.text,
            onSurface = palette.text,
        ),
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .background(Color.Black)
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(horizontal = 24.dp, vertical = 8.dp),
        ) {
            TopBar(palette, actions)
            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                val wide = maxWidth > maxHeight
                when (state) {
                    is BenchState.Resting -> RestingContent(state, wide, palette, actions)
                    is BenchState.RestOver -> RestOverContent(state, wide, palette, actions)
                    is BenchState.Logging -> LoggingContent(state, palette, actions)
                    is BenchState.Paused -> PausedContent(state, palette, actions)
                    is BenchState.Complete -> CompleteContent(state, palette, actions)
                    is BenchState.Idle -> IdleContent(state, localTime.hour * 60 + localTime.minute, is24Hour, wide, palette)
                }
            }
        }
    }
}

@Composable
private fun TopBar(palette: BenchPalette, actions: BenchActions) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = actions.close, modifier = Modifier.size(48.dp)) {
            Icon(Icons.Filled.Close, contentDescription = "Close bench mode", tint = palette.secondary)
        }
        Spacer(Modifier.weight(1f))
        TextButton(onClick = actions.openWorkout, modifier = Modifier.heightIn(min = 48.dp)) {
            Text("Workout", color = palette.secondary, fontSize = 16.sp)
        }
    }
}

// ---------------------------------------------------------------------------------------------------------------------- states

@Composable
private fun RestingContent(state: BenchState.Resting, wide: Boolean, palette: BenchPalette, actions: BenchActions) {
    val spoken = "Rest, ${spokenDuration(state.remainingSeconds)} left. Next: ${state.next.label}${state.next.work?.let { ", $it" }.orEmpty()}"
    SideBySide(
        wide = wide,
        first = {
            Ring(state.fraction, palette, Modifier.semantics(mergeDescendants = true) { contentDescription = spoken }) {
                Text(NumberText.clock(state.remainingSeconds), color = palette.ring, fontSize = 64.sp, fontWeight = FontWeight.Bold, style = Digits)
            }
        },
        second = { align ->
            Text("Resting · ${state.exercise}", color = palette.secondary, fontSize = 18.sp, textAlign = align, maxLines = 2, overflow = TextOverflow.Ellipsis)
            NextSetText(state.next, palette, align)
            Spacer(Modifier.size(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                BenchButton("+15 s", "Add 15 seconds", palette, { actions.adjustRest(15) })
                BenchButton("Skip", "Skip rest", palette, actions.skipRest)
            }
        },
    )
}

@Composable
private fun RestOverContent(state: BenchState.RestOver, wide: Boolean, palette: BenchPalette, actions: BenchActions) {
    SideBySide(
        wide = wide,
        first = {
            Ring(1f, palette, Modifier.semantics(mergeDescendants = true) { contentDescription = "Rest over. Go" }) {
                Text("Go", color = palette.ring, fontSize = 64.sp, fontWeight = FontWeight.Bold)
            }
        },
        second = { align ->
            Text("Rest over · ${state.exercise}", color = palette.secondary, fontSize = 18.sp, textAlign = align, maxLines = 2, overflow = TextOverflow.Ellipsis)
            NextSetText(state.next, palette, align)
            Spacer(Modifier.size(8.dp))
            BenchButton("Log set", "Log set", palette, actions.logSet, prominent = true)
        },
    )
}

@Composable
private fun LoggingContent(state: BenchState.Logging, palette: BenchPalette, actions: BenchActions) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(state.exercise, color = palette.text, fontSize = 28.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(state.setLabel, color = palette.secondary, fontSize = 18.sp, textAlign = TextAlign.Center)
        // Long numbers ("142.5") get a smaller size so the weight, the cross and the reps still fit one row of a narrow phone.
        val size = if ((state.weight?.length ?: 0) + state.reps.length <= 6) 72.sp else 56.sp
        Row(
            Modifier.semantics(mergeDescendants = true) {
                contentDescription = (state.weight?.let { "$it kilograms, " } ?: "") + "${state.reps} ${if (state.repsUnit == "s") "seconds" else "reps"}"
            },
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            state.weight?.let {
                BigValue(it, "kg", size, palette)
                Text("×", color = palette.secondary, fontSize = 32.sp)
            }
            BigValue(state.reps, state.repsUnit, size, palette)
        }
        Spacer(Modifier.size(8.dp))
        BenchButton("Log set", "Log set", palette, actions.logSet, Modifier.fillMaxWidth(), prominent = true)
    }
}

@Composable
private fun PausedContent(state: BenchState.Paused, palette: BenchPalette, actions: BenchActions) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Paused", color = palette.text, fontSize = 48.sp, fontWeight = FontWeight.Bold)
        Text(state.exercise, color = palette.secondary, fontSize = 20.sp, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(state.elapsed, color = palette.text, fontSize = 40.sp, fontWeight = FontWeight.SemiBold, style = Digits)
        Spacer(Modifier.size(8.dp))
        BenchButton("Resume", "Resume workout", palette, actions.resume, Modifier.fillMaxWidth(), prominent = true)
    }
}

@Composable
private fun CompleteContent(state: BenchState.Complete, palette: BenchPalette, actions: BenchActions) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(state.title, color = palette.text, fontSize = 36.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Text(state.summary, color = palette.secondary, fontSize = 20.sp, textAlign = TextAlign.Center)
        Spacer(Modifier.size(8.dp))
        BenchButton("Open workout", "Open the workout to finish it", palette, actions.openWorkout, Modifier.fillMaxWidth(), prominent = true)
    }
}

/** SB-04: the clock beside the session of tomorrow, like the alarm clock on the night table. */
@Composable
private fun IdleContent(state: BenchState.Idle, minuteOfDay: Int, is24Hour: Boolean, wide: Boolean, palette: BenchPalette) {
    val (digits, suffix) = LiveText.timeParts(minuteOfDay, is24Hour)
    SideBySide(
        wide = wide,
        first = {
            Row(
                Modifier.semantics(mergeDescendants = true) { contentDescription = "Time $digits${suffix?.let { " $it" }.orEmpty()}" },
                verticalAlignment = Alignment.Bottom,
            ) {
                Text(digits, color = palette.text, fontSize = 88.sp, fontWeight = FontWeight.SemiBold, style = Digits, maxLines = 1, softWrap = false)
                suffix?.let { Text(it, color = palette.secondary, fontSize = 24.sp, modifier = Modifier.padding(start = 8.dp, bottom = 14.dp)) }
            }
        },
        second = { align ->
            Text(state.headline, color = palette.secondary, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, textAlign = align)
            state.title?.let { Text(it, color = palette.text, fontSize = 24.sp, fontWeight = FontWeight.Bold, textAlign = align, maxLines = 2, overflow = TextOverflow.Ellipsis) }
            state.detail?.let { Text(it, color = palette.secondary, fontSize = 16.sp, textAlign = align) }
        },
    )
}

// -------------------------------------------------------------------------------------------------------------------- pieces

/** Two blocks side by side on a wide screen (the phone lies on its side), one above the other otherwise. */
@Composable
private fun SideBySide(
    wide: Boolean,
    first: @Composable () -> Unit,
    second: @Composable ColumnScope.(TextAlign) -> Unit,
) {
    if (wide) {
        Row(horizontalArrangement = Arrangement.spacedBy(48.dp), verticalAlignment = Alignment.CenterVertically) {
            first()
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { second(TextAlign.Start) }
        }
    } else {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(24.dp)) {
            first()
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) { second(TextAlign.Center) }
        }
    }
}

/** The rest ring: the part of the rest that is left, clockwise from the top. */
@Composable
private fun Ring(fraction: Float, palette: BenchPalette, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.size(RingSize), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = RingStroke.toPx()
            val topLeft = Offset(stroke / 2, stroke / 2)
            val arc = Size(size.width - stroke, size.height - stroke)
            drawArc(palette.track, startAngle = 0f, sweepAngle = 360f, useCenter = false, topLeft = topLeft, size = arc, style = Stroke(stroke))
            if (fraction > 0f) {
                drawArc(palette.ring, startAngle = -90f, sweepAngle = 360f * fraction, useCenter = false, topLeft = topLeft, size = arc, style = Stroke(stroke, cap = StrokeCap.Round))
            }
        }
        content()
    }
}

@Composable
private fun NextSetText(next: NextSet, palette: BenchPalette, align: TextAlign) {
    Text("Next: ${next.label}", color = palette.text, fontSize = 28.sp, fontWeight = FontWeight.Bold, textAlign = align)
    next.work?.let { Text(it, color = palette.text, fontSize = 28.sp, fontWeight = FontWeight.Bold, textAlign = align, style = Digits) }
}

@Composable
private fun BigValue(value: String, unit: String, size: TextUnit, palette: BenchPalette) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, color = palette.text, fontSize = size, fontWeight = FontWeight.Bold, style = Digits, maxLines = 1, softWrap = false)
        Text(unit, color = palette.secondary, fontSize = 20.sp)
    }
}

/** A pill of at least 64 dp: bench mode is read and pressed from a distance. [description] is what TalkBack says. */
@Composable
private fun BenchButton(
    label: String,
    description: String,
    palette: BenchPalette,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    prominent: Boolean = false,
) {
    Button(
        onClick = onClick,
        modifier = modifier.heightIn(min = 64.dp).semantics { contentDescription = description },
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = if (prominent) palette.actionFill else palette.buttonFill,
            contentColor = if (prominent) palette.actionText else palette.buttonText,
        ),
        contentPadding = PaddingValues(horizontal = 28.dp, vertical = 12.dp),
    ) {
        Text(label, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** "1 minute 24 seconds", for TalkBack. */
internal fun spokenDuration(seconds: Int): String {
    val total = seconds.coerceAtLeast(0)
    val minutes = total / 60
    val secs = total % 60
    val parts = buildList {
        if (minutes > 0) add(if (minutes == 1) "1 minute" else "$minutes minutes")
        if (secs > 0 || minutes == 0) add(if (secs == 1) "1 second" else "$secs seconds")
    }
    return parts.joinToString(" ")
}
