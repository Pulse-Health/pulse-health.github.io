package health.pulse.strength.ui.active

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulseTheme
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * The green "Coach · ..." suggestion block at the bottom of the exercise card (8 dp / 10 dp padding, 10 dp radius, green wash,
 * 18 dp head icon, 13 sp text).
 */
@Composable
internal fun CoachTip(text: String, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    val iconSize = 18.dp.fontScaled()
    val label = buildAnnotatedString {
        withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append("Coach · ") }
        append(text)
    }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(colors.coachTipFill, RoundedCornerShape(PulseMetrics.rowRadius))
            .padding(horizontal = 10.dp, vertical = 8.dp)
            .semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        CoachIcon(tint = colors.green, size = iconSize, modifier = Modifier.padding(top = 1.dp))
        Text(
            text = label,
            style = PulseFont.text(13.sp).copy(lineHeight = 18.sp),
            color = colors.ink,
            modifier = Modifier.weight(1f),
        )
    }
}

// region Icon

/** The "coach" glyph of the design: a head profile with a question mark, stroked in the design's 24 x 24 grid. */
@Composable
private fun CoachIcon(tint: Color, size: Dp, modifier: Modifier = Modifier) {
    val path = remember { coachPath() }
    Canvas(modifier.size(size)) {
        val factor = this.size.minDimension / 24f
        scale(scale = factor, pivot = Offset.Zero) {
            drawPath(path, tint, style = Stroke(width = 1.9f, cap = StrokeCap.Round, join = StrokeJoin.Round))
        }
    }
}

private fun coachPath(): Path {
    val p = Path()
    // Head outline.
    val top = Offset(13f, 3.2f)
    val leftTemple = Offset(5.2f, 9.8f)
    p.moveTo(top.x, top.y)
    p.smallArc(top, leftTemple, 7f, positiveSweep = false)
    p.cubicTo(5.1f, 11.4f, 5.6f, 12.8f, 6.5f, 14f)
    p.lineTo(6.5f, 21f)
    p.lineTo(13f, 21f)
    p.lineTo(13f, 18.4f)
    p.lineTo(15.3f, 18.4f)
    p.smallArc(Offset(15.3f, 18.4f), Offset(17.3f, 16.4f), 2f, positiveSweep = false)
    p.lineTo(17.3f, 14.1f)
    p.lineTo(19.2f, 13.5f)
    val nose = Offset(17.6f, 10.3f)
    p.lineTo(nose.x, nose.y)
    p.smallArc(nose, top, 7f, positiveSweep = false)
    p.close()
    // Question mark hook.
    p.moveTo(10f, 9.6f)
    p.cubicTo(10.2f, 8.4f, 11.2f, 7.6f, 12.4f, 7.6f)
    p.cubicTo(13.7f, 7.6f, 14.8f, 8.6f, 14.8f, 9.9f)
    p.cubicTo(14.8f, 10.8f, 14.3f, 11.5f, 13.5f, 11.9f)
    // Question mark dot.
    p.moveTo(11.5f, 13.5f)
    p.lineTo(13f, 13.5f)
    return p
}

/**
 * A circular arc of at most 180 degrees from [start] to [end], with the SVG sweep convention ([positiveSweep] = increasing angle in
 * the y-down space = clockwise on screen), appended as cubic segments.
 */
private fun Path.smallArc(start: Offset, end: Offset, radius: Float, positiveSweep: Boolean) {
    val dx = (end.x - start.x).toDouble()
    val dy = (end.y - start.y).toDouble()
    val chord = sqrt(dx * dx + dy * dy)
    if (chord <= 0.0) return
    val half = chord / 2
    val height = sqrt(max(0.0, radius.toDouble() * radius - half * half))
    val sign = if (positiveSweep) 1.0 else -1.0
    val centerX = (start.x + end.x) / 2.0 + sign * (-dy / chord) * height
    val centerY = (start.y + end.y) / 2.0 + sign * (dx / chord) * height

    val startAngle = atan2(start.y - centerY, start.x - centerX)
    var endAngle = atan2(end.y - centerY, end.x - centerX)
    if (positiveSweep) {
        while (endAngle < startAngle) endAngle += 2 * PI
    } else {
        while (endAngle > startAngle) endAngle -= 2 * PI
    }
    val total = endAngle - startAngle
    val steps = max(1, ceil(abs(total) / (PI / 2)).toInt())
    val delta = total / steps
    val handle = 4.0 / 3.0 * tan(delta / 4.0) * radius

    var angle = startAngle
    repeat(steps) {
        val next = angle + delta
        val sinA = sin(angle)
        val cosA = cos(angle)
        val sinB = sin(next)
        val cosB = cos(next)
        val p1x = centerX + radius * cosB
        val p1y = centerY + radius * sinB
        val c1x = centerX + radius * cosA - handle * sinA
        val c1y = centerY + radius * sinA + handle * cosA
        val c2x = p1x + handle * sinB
        val c2y = p1y - handle * cosB
        cubicTo(c1x.toFloat(), c1y.toFloat(), c2x.toFloat(), c2y.toFloat(), p1x.toFloat(), p1y.toFloat())
        angle = next
    }
}

// endregion
