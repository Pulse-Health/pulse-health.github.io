package health.pulse.strength.ui.active

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.ActiveWorkoutPresentation
import health.pulse.strength.ui.components.DumbbellGlyph
import health.pulse.strength.ui.theme.LocalReduceMotion
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight

/**
 * The floating "workout in progress" bar shown while a workout runs and its screen is minimised (the Strength hub with a running
 * workout). It renders the presentation it is given; the owner refreshes it every second so the clock keeps running.
 *
 * While the bar is on screen it also plays the rest-over cue ([RestEndFeedback]): the workout screen is not showing, so the bar is
 * the only thing that can tell the user. It honours [LocalRestAlertsEnabled].
 */
@Composable
fun WorkoutInProgressBar(
    presentation: ActiveWorkoutPresentation,
    onResume: () -> Unit,
    modifier: Modifier = Modifier,
) {
    RestEndFeedbackEffect(phase = presentation.dock?.phase, alertsEnabled = LocalRestAlertsEnabled.current)

    val colors = PulseTheme.colors
    val shape = RoundedCornerShape(20.dp)
    val subtitle = remember(presentation.navigator, presentation.header.clockText, presentation.header.setsText) {
        subtitleText(presentation)
    }
    val border = if (colors.isDark) Color.White.copy(alpha = 0.10f) else Color.Black.copy(alpha = 0.05f)
    val spoken = presentation.header.title + ", " + subtitle

    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Row(
            modifier = Modifier
                .widthIn(max = PulseMetrics.maxContentWidth)
                .fillMaxWidth()
                .shadow(14.dp, shape, clip = false, ambientColor = Color.Black.copy(alpha = 0.10f), spotColor = Color.Black.copy(alpha = 0.20f))
                .background(colors.card.copy(alpha = 0.97f), shape)
                .border(1.dp, border, shape)
                .pulseMinHeight(64.dp)
                .testTag("in-progress-bar")
                .pulseClickable(onClickLabel = "Resume workout", onClick = onResume)
                .semantics(mergeDescendants = true) {
                    contentDescription = "Resume workout in progress"
                    stateDescription = spoken
                }
                .padding(start = 12.dp, end = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // With very big text the decorative badge gives its room to the words.
            if (LocalDensity.current.fontScale <= 1.5f) Badge()
            Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
                val largeText = isLargeText()
                Text(
                    text = presentation.header.title,
                    style = PulseFont.text(15.sp, FontWeight.SemiBold),
                    color = colors.ink,
                    maxLines = if (largeText) 2 else 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.testTag("bar-title"),
                )
                Text(
                    text = subtitle,
                    style = PulseFont.number(12.sp, FontWeight.Normal),
                    color = colors.inkSecondary,
                    maxLines = if (largeText) 4 else 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.testTag("bar-subtitle"),
                )
            }
            Box(
                modifier = Modifier
                    .pulseMinHeight(48.dp)
                    .background(colors.green, CircleShape)
                    .padding(horizontal = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text("Resume", style = PulseFont.text(15.sp, FontWeight.SemiBold), color = colors.onGreen, maxLines = 1)
            }
        }
    }
}

/** "Exercise 1 of 6 · 24:18 · 7 of 19 sets" (no exercise part for an empty workout; the clock reads "Paused · 24:18" while paused). */
private fun subtitleText(presentation: ActiveWorkoutPresentation): String {
    val parts = mutableListOf<String>()
    presentation.navigator?.let { parts.add("Exercise ${it.position} of ${it.total}") }
    parts.add(presentation.header.clockText)
    parts.add(presentation.header.setsText + " sets")
    return parts.joinToString(" · ")
}

/** The 40 dp green circle with the dumbbell, which beats like the heart icon (1.2 s loop). Static when animations are off. */
@Composable
private fun Badge() {
    val colors = PulseTheme.colors
    val reduceMotion = LocalReduceMotion.current
    val scale = if (reduceMotion) {
        1f
    } else {
        rememberInfiniteTransition(label = "barBeat").animateFloat(
            initialValue = 1f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = keyframes {
                    durationMillis = 1200
                    1f at 0 using FastOutSlowInEasing
                    1.25f at 180 using FastOutSlowInEasing
                    1f at 360
                    1f at 1200
                },
                repeatMode = RepeatMode.Restart,
            ),
            label = "barBeatScale",
        ).value
    }
    Box(
        modifier = Modifier
            .size(40.dp)
            .background(colors.green.copy(alpha = if (colors.isDark) 0.20f else 0.12f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        DumbbellGlyph(
            size = 22.dp,
            color = colors.green,
            strokeWidth = 2.dp,
            modifier = Modifier.graphicsLayer { scaleX = scale; scaleY = scale },
        )
    }
}
