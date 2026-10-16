package health.pulse.strength.ui.active

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.keyframes
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Icon
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
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.ActiveWorkoutPresentation
import health.pulse.strength.ui.theme.LocalReduceMotion
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulsePillButton
import health.pulse.strength.ui.theme.PulseTheme
import kotlin.math.max

/** Clock colour while the workout is paused (amber text). */
@Composable
private fun pausedClockColor(): Color = if (PulseTheme.colors.isDark) Color(0xFFFFB340) else Color(0xFF9A5B00)

/** The 0.5 dp line under the header (the design's rgba(60,60,67,0.29)). */
@Composable
private fun hairlineColor(): Color =
    if (PulseTheme.colors.isDark) Color(0xFF545458).copy(alpha = 0.65f) else Color(0xFF3C3C43).copy(alpha = 0.29f)

/**
 * Header of the active-workout screen: minimise chevron, workout title with the running clock, More button (with its menu), blue
 * Finish pill, the Volume / Sets / heart-rate line and the segmented progress strip. The white background extends under the
 * status bar; the content is centred and at most [PulseMetrics.maxContentWidth] wide.
 *
 * [menuContent] fills the More menu; it gets a function that closes the menu.
 */
@Composable
internal fun ActiveHeader(
    header: ActiveWorkoutPresentation.Header,
    onMinimise: () -> Unit,
    onFinish: () -> Unit,
    modifier: Modifier = Modifier,
    menuContent: @Composable ColumnScope.(dismiss: () -> Unit) -> Unit,
) {
    val hairline = hairlineColor()
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(PulseTheme.colors.card)
            .drawBehind {
                val width = max(1f, 0.5.dp.toPx())
                drawRect(hairline, topLeft = Offset(0f, size.height - width), size = Size(size.width, width))
            }
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal)),
    ) {
        Column(
            Modifier
                .widthIn(max = PulseMetrics.maxContentWidth)
                .fillMaxWidth()
                .align(Alignment.CenterHorizontally),
        ) {
            HeaderTitleRow(
                modifier = Modifier.padding(start = 4.dp, end = PulseMetrics.screenInset),
                minimise = {
                    ActiveIconButton(
                        icon = Icons.Rounded.KeyboardArrowDown,
                        label = "Minimise workout",
                        onClick = onMinimise,
                        tint = PulseTheme.colors.green,
                        iconSize = 28.dp,
                        tag = "active-minimise",
                    )
                },
                title = { TitleBlock(header) },
                more = { MoreButton(menuContent) },
                finish = { PulsePillButton(text = "Finish", onClick = onFinish, modifier = Modifier.testTag("active-finish")) },
            )
            StatsRow(header, Modifier.padding(horizontal = PulseMetrics.screenInset).padding(top = 2.dp))
        }
        ProgressStrip(header.segments, Modifier.padding(top = 6.dp))
    }
}

// region Title row

/**
 * One line: minimise button, title block (the flexible part), More button and Finish pill. When the user's font size leaves the
 * title too little room (big text on a narrow window) the title moves onto a second line under the three buttons instead of
 * truncating to nothing.
 */
@Composable
private fun HeaderTitleRow(
    modifier: Modifier,
    minimise: @Composable () -> Unit,
    title: @Composable () -> Unit,
    more: @Composable () -> Unit,
    finish: @Composable () -> Unit,
) {
    Layout(contents = listOf(minimise, title, more, finish), modifier = modifier) { measurables, constraints ->
        val spacing = 4.dp.roundToPx()
        // The title needs room for a name on one line: more with a bigger font size.
        val minTitleWidth = (72.dp * fontScale.coerceIn(1f, 2f) + 40.dp).roundToPx()
        val width = constraints.maxWidth
        val loose = Constraints(maxWidth = width)
        val minimiseP = measurables[0].map { it.measure(loose) }
        val moreP = measurables[2].map { it.measure(loose) }
        val finishP = measurables[3].map { it.measure(loose) }
        val buttons = (minimiseP + moreP + finishP)
        val fixedWidth = buttons.sumOf { it.width } + spacing * 3
        val titleRoom = width - fixedWidth
        val stacked = titleRoom < minTitleWidth

        if (!stacked) {
            val titleP = measurables[1].map { it.measure(Constraints(minWidth = titleRoom, maxWidth = titleRoom)) }
            val rowHeight = max(buttons.maxOf { it.height }, titleP.maxOfOrNull { it.height } ?: 0)
            layout(width, rowHeight) {
                var x = 0
                minimiseP.forEach { it.placeRelative(x, (rowHeight - it.height) / 2); x += it.width + spacing }
                titleP.forEach { it.placeRelative(x, (rowHeight - it.height) / 2) }
                x += titleRoom + spacing
                moreP.forEach { it.placeRelative(x, (rowHeight - it.height) / 2); x += it.width + spacing }
                finishP.forEach { it.placeRelative(x, (rowHeight - it.height) / 2) }
            }
        } else {
            val titleP = measurables[1].map { it.measure(Constraints(minWidth = width, maxWidth = width)) }
            val buttonsHeight = buttons.maxOf { it.height }
            val titleHeight = titleP.maxOfOrNull { it.height } ?: 0
            layout(width, buttonsHeight + titleHeight) {
                minimiseP.forEach { it.placeRelative(0, (buttonsHeight - it.height) / 2) }
                var x = width
                finishP.forEach { x -= it.width; it.placeRelative(x, (buttonsHeight - it.height) / 2); x -= spacing }
                moreP.forEach { x -= it.width; it.placeRelative(x, (buttonsHeight - it.height) / 2) }
                titleP.forEach { it.placeRelative(0, buttonsHeight) }
            }
        }
    }
}

@Composable
private fun TitleBlock(header: ActiveWorkoutPresentation.Header, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    val largeText = isLargeText()
    Column(
        modifier = modifier
            .semantics(mergeDescendants = true) {
                contentDescription = header.title
                stateDescription = if (header.isPaused) header.clockText else "Elapsed " + header.clockText
            },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(1.dp),
    ) {
        Text(
            text = header.title,
            style = PulseFont.headline,
            color = colors.ink,
            textAlign = TextAlign.Center,
            maxLines = if (largeText) 2 else 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.testTag("active-title"),
        )
        Text(
            text = header.clockText,
            style = PulseFont.number(15.sp, FontWeight.Normal),
            color = if (header.isPaused) pausedClockColor() else colors.inkSecondary,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.testTag("active-clock"),
        )
    }
}

@Composable
private fun MoreButton(menuContent: @Composable ColumnScope.(dismiss: () -> Unit) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        ActiveTapTarget(label = "More", onClick = { expanded = true }, tag = "active-more") {
            EllipsisCircleIcon(tint = PulseTheme.colors.green, size = 26.dp)
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            containerColor = PulseTheme.colors.card,
            shape = androidx.compose.foundation.shape.RoundedCornerShape(14.dp),
        ) {
            menuContent { expanded = false }
        }
    }
}

// endregion

// region Stats

/**
 * Volume / Sets / heart rate in one line (the design). With bigger text the figures wrap onto a second line instead of
 * truncating. The heart rate is shown only while a source reports one.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StatsRow(header: ActiveWorkoutPresentation.Header, modifier: Modifier = Modifier) {
    FlowRow(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 30.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalArrangement = Arrangement.spacedBy(2.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) {
        StatItem(
            label = "Volume",
            value = header.volumeText,
            unit = "kg",
            description = "Volume",
            spoken = header.volumeText + " kilograms",
            tag = "active-volume",
        )
        StatItem(label = "Sets", value = header.setsText, unit = null, description = "Sets logged", spoken = header.setsText, tag = "active-sets")
        if (header.hasHeartRate) HeartItem(header)
    }
}

@Composable
private fun StatItem(
    label: String,
    value: String,
    unit: String?,
    description: String,
    spoken: String,
    tag: String,
) {
    val colors = PulseTheme.colors
    Row(
        modifier = Modifier.semantics(mergeDescendants = true) {
            contentDescription = description
            stateDescription = spoken
        },
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        Text(label, style = PulseFont.caption, color = colors.inkSecondary, maxLines = 1, modifier = Modifier.alignByBaseline())
        Text(
            value,
            style = PulseFont.number(15.sp),
            color = colors.ink,
            maxLines = 1,
            modifier = Modifier.alignByBaseline().testTag(tag),
        )
        if (unit != null) Text(unit, style = PulseFont.caption, color = colors.inkSecondary, maxLines = 1, modifier = Modifier.alignByBaseline())
    }
}

@Composable
private fun HeartItem(header: ActiveWorkoutPresentation.Header) {
    val colors = PulseTheme.colors
    Row(
        modifier = Modifier.semantics(mergeDescendants = true) {
            contentDescription = "Heart rate"
            stateDescription = if (header.hasHeartRate) header.heartRateText + " beats per minute" else "Not available"
        },
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        HeartBeat(isBeating = header.hasHeartRate)
        Text(header.heartRateText, style = PulseFont.number(15.sp), color = colors.ink, maxLines = 1)
        Text("bpm", style = PulseFont.caption, color = colors.inkSecondary, maxLines = 1)
    }
}

/** The small heart next to the bpm figure: beats once a second while a heart rate is received, still and grey otherwise. */
@Composable
private fun HeartBeat(isBeating: Boolean) {
    val colors = PulseTheme.colors
    val reduceMotion = LocalReduceMotion.current
    val scale = if (isBeating && !reduceMotion) {
        val transition = rememberInfiniteTransition(label = "heartBeat")
        transition.animateFloat(
            initialValue = 1f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = keyframes {
                    durationMillis = 1000
                    1f at 0 using FastOutSlowInEasing
                    1.25f at 150 using FastOutSlowInEasing
                    1f at 300
                    1f at 1000
                },
                repeatMode = RepeatMode.Restart,
            ),
            label = "heartScale",
        ).value
    } else {
        1f
    }
    Icon(
        imageVector = Icons.Rounded.Favorite,
        contentDescription = null,
        tint = if (isBeating) colors.heart else colors.inkTertiary,
        modifier = Modifier
            .size(13.dp)
            .graphicsLayer { scaleX = scale; scaleY = scale },
    )
}

// endregion

// region Progress strip

/** One thin bar per exercise (4 dp high, 2 dp gaps, full width); the fill is the share of logged sets. */
@Composable
private fun ProgressStrip(segments: List<ActiveWorkoutPresentation.Segment>, modifier: Modifier = Modifier) {
    val done = segments.count { it.fraction >= 0.999 }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(4.dp)
            .semantics(mergeDescendants = true) {
                contentDescription = "Workout progress"
                stateDescription = "$done of ${segments.size} exercises complete"
            },
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        segments.forEach { segment -> ProgressSegment(segment, Modifier.weight(1f)) }
    }
}

@Composable
private fun ProgressSegment(segment: ActiveWorkoutPresentation.Segment, modifier: Modifier) {
    val colors = PulseTheme.colors
    val reduceMotion = LocalReduceMotion.current
    val target = segment.fraction.toFloat().coerceIn(0f, 1f)
    val fraction by animateFloatAsState(
        targetValue = target,
        animationSpec = if (reduceMotion) snap() else tween(250),
        label = "segmentFill",
    )
    val track = if (segment.isCurrent) colors.progressTrackCurrent else colors.progressTrack
    Box(modifier.fillMaxHeight().background(track)) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(fraction).background(colors.progress))
    }
}

// endregion
