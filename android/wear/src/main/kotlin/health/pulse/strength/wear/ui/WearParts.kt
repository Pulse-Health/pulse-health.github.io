package health.pulse.strength.wear.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import health.pulse.strength.core.widgets.DayCell

/** The size every tap target on the watch has at least. */
internal val TouchTarget = 48.dp

private const val RingStartAngle = -90f
private const val RingFullSweep = 360f

/** A ring that fills clockwise from the top: the week against the goal, or the time left of a rest. */
@Composable
internal fun ProgressRing(
    progress: Float,
    modifier: Modifier,
    stroke: Dp,
    color: Color = WearColors.Green,
    track: Color = WearColors.GreenTrack,
) {
    Canvas(modifier) {
        val strokePx = stroke.toPx()
        val topLeft = Offset(strokePx / 2f, strokePx / 2f)
        val arc = Size(size.width - strokePx, size.height - strokePx)
        drawArc(track, RingStartAngle, RingFullSweep, useCenter = false, topLeft = topLeft, size = arc, style = Stroke(strokePx))
        val sweep = RingFullSweep * progress.coerceIn(0f, 1f)
        if (sweep > 0f) {
            drawArc(color, RingStartAngle, sweep, useCenter = false, topLeft = topLeft, size = arc, style = Stroke(strokePx, cap = StrokeCap.Round))
        }
    }
}

/**
 * A round button, [TouchTarget] across. [description] is what a screen reader says; the visible [content] (a sign or a few characters)
 * is hidden from it so that the button is not announced twice.
 */
@Composable
internal fun RoundButton(
    description: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    primary: Boolean = false,
    enabled: Boolean = true,
    content: @Composable () -> Unit,
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .size(TouchTarget)
            .semantics { contentDescription = description },
        colors = if (primary) ButtonDefaults.primaryButtonColors() else ButtonDefaults.secondaryButtonColors(),
    ) {
        Box(Modifier.clearAndSetSemantics {}, contentAlignment = Alignment.Center) { content() }
    }
}

/** The text on a [RoundButton]: rounded tabular figures in the button's own content colour. */
@Composable
internal fun ButtonLabel(text: String) {
    Text(text, style = numberStyle(size = 15f, weight = FontWeight.SemiBold, color = Color.Unspecified), maxLines = 1)
}

/** A full-width chip with a centred [label]; [icon] is a drawable resource shown in front of it. */
@Composable
internal fun ActionChip(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    primary: Boolean = true,
    enabled: Boolean = true,
    icon: Int? = null,
) {
    val iconSlot: (@Composable BoxScope.() -> Unit)? = if (icon == null) {
        null
    } else {
        val slot: @Composable BoxScope.() -> Unit = {
            Icon(painterResource(icon), contentDescription = null, modifier = Modifier.size(ChipDefaults.IconSize))
        }
        slot
    }
    Chip(
        label = { Text(label, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        onClick = onClick,
        modifier = modifier.fillMaxWidth(),
        icon = iconSlot,
        colors = if (primary) ChipDefaults.primaryChipColors() else ChipDefaults.secondaryChipColors(),
        enabled = enabled,
    )
}

/** The line at the top of a screen: a short [title] in green and, optionally, a figure such as the workout clock at its end. */
@Composable
internal fun ScreenHeader(title: String, trailing: String? = null, trailingDescription: String? = null) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 6.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            title,
            modifier = Modifier.weight(1f, fill = trailing == null),
            style = MaterialTheme.typography.caption1,
            color = WearColors.Green,
            fontWeight = FontWeight.SemiBold,
            textAlign = if (trailing == null) TextAlign.Center else TextAlign.Start,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (trailing != null) {
            Spacer(Modifier.width(6.dp))
            Text(
                trailing,
                modifier = Modifier.semantics { trailingDescription?.let { contentDescription = it } },
                style = numberStyle(size = 14f, weight = FontWeight.SemiBold),
                maxLines = 1,
            )
        }
    }
}

/** The seven days of the week as letters over dots: a filled dot for a day with a workout, a ring for today, a plain dot otherwise. */
@Composable
internal fun DayDots(days: List<DayCell>) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Top) {
        days.forEach { day ->
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    day.letter,
                    style = MaterialTheme.typography.caption3,
                    color = if (day.isToday) WearColors.Ink else WearColors.Secondary,
                    fontWeight = if (day.isToday) FontWeight.Bold else FontWeight.Normal,
                )
                Spacer(Modifier.height(2.dp))
                val dot = Modifier.size(8.dp).clip(CircleShape)
                Box(
                    when {
                        day.sessions > 0 -> dot.background(WearColors.Green)
                        day.isToday -> dot.border(1.5.dp, WearColors.Green, CircleShape)
                        day.isFuture -> dot.border(1.dp, WearColors.Raised, CircleShape)
                        else -> dot.background(WearColors.Raised)
                    },
                )
            }
        }
    }
}

/** A rounded surface for a block of related lines. */
@Composable
internal fun Panel(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(WearColors.Surface)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) { content() }
}
