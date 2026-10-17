package health.pulse.strength.ui.sheets

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.ui.components.DumbbellGlyph
import health.pulse.strength.ui.components.ExerciseMediaStore
import health.pulse.strength.ui.components.ExerciseMediaView
import health.pulse.strength.ui.detail.ExerciseDetailScreen
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight

/**
 * Form demo, muscles and how-to cues of one exercise. Shows its own modal bottom sheet.
 *
 * Title bar ("Form" + Done), then a scrolling page: the large looping demo (3 : 2, 16 dp radius, "Start · End" badge), the exercise
 * name with chips for the primary muscle, the equipment and the secondary muscles, the numbered "How to" cues, the "History &
 * records" row and the photo attribution. The demo is `ExerciseMediaView`, which pauses on the first frame when animations are off.
 *
 * The "History & records" row is shown only when [onShowHistory] is set; it is the way on to the exercise detail screen, which the
 * presenter owns (see [FormInfoHost]).
 */
@Composable
fun FormInfoSheet(exercise: Exercise, onShowHistory: (() -> Unit)?, onDismiss: () -> Unit) {
    PulseSheet(onDismiss = onDismiss, fullHeight = true) { dismiss ->
        FormInfoSheetContent(exercise = exercise, onShowHistory = onShowHistory, onDone = dismiss)
    }
}

/**
 * [FormInfoSheet] hosted so that "History & records" opens the exercise detail screen inside the sheet: two pages in one sheet, and
 * system back returns from the detail screen to the form page. Used wherever the form sheet is opened from (the active workout,
 * the exercise list).
 */
@Composable
fun FormInfoHost(exercise: Exercise, store: StrengthStore, onDismiss: () -> Unit) {
    var showsHistory by rememberSaveable { mutableStateOf(false) }
    PulseSheet(onDismiss = onDismiss, fullHeight = true, dismissOnBack = !showsHistory) { dismiss ->
        BackHandler(enabled = showsHistory) { showsHistory = false }
        if (showsHistory) {
            ExerciseDetailScreen(
                exercise = exercise,
                store = store,
                onBack = { showsHistory = false },
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            FormInfoSheetContent(exercise = exercise, onShowHistory = { showsHistory = true }, onDone = dismiss)
        }
    }
}

/**
 * Everything inside the form sheet's window. [onDone] closes the sheet. In landscape (wide and short) the demo sits beside the
 * name, cues and history row, so the demo does not push everything below the fold.
 */
@Composable
internal fun FormInfoSheetContent(
    exercise: Exercise,
    onShowHistory: (() -> Unit)?,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // A build without the demo photos (the release, see android/README.md) has no demo to show: no tile and no photo credit.
    val photosShipped = ExerciseMediaStore.isShipped(LocalContext.current)
    Column(modifier.fillMaxSize()) {
        SheetTitleBar(title = "Form", trailing = SheetBarButton("Done", onClick = onDone))
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val sideBySide = photosShipped && maxWidth >= 520.dp && maxHeight < 460.dp
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(start = 16.dp, end = 16.dp, bottom = 34.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                if (sideBySide) {
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        Box(Modifier.weight(1f)) { DemoTile(exercise) }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            FormTitleBlock(exercise)
                            if (exercise.cues.isNotEmpty()) CuesCard(exercise.cues)
                            if (onShowHistory != null) HistoryRow(onShowHistory)
                        }
                    }
                } else {
                    if (photosShipped) DemoTile(exercise)
                    FormTitleBlock(exercise)
                    if (exercise.cues.isNotEmpty()) CuesCard(exercise.cues)
                    if (onShowHistory != null) HistoryRow(onShowHistory)
                }
                if (photosShipped && !exercise.mediaKey.isNullOrEmpty()) {
                    Text(
                        "Demo photos from the Free Exercise DB.",
                        style = PulseFont.caption2,
                        color = PulseTheme.colors.inkSecondary,
                    )
                }
            }
        }
    }
}

/** The exercise name with chips for the primary muscle, the equipment and the secondary muscles. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FormTitleBlock(exercise: Exercise) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            exercise.name,
            style = PulseFont.title,
            color = PulseTheme.colors.ink,
            modifier = Modifier.semantics { heading() },
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            FormInfoChip(exercise.muscle.title, isPrimary = true)
            FormInfoChip(exercise.equipment.title, isPrimary = false)
            // Custom exercises carry the placeholder "Custom" instead of secondary muscles; nothing to show then.
            if (exercise.secondary.isNotEmpty() && exercise.secondary != "Custom") FormInfoChip(exercise.secondary, isPrimary = false)
        }
    }
}

// region Demo

/** The looping demo in a 3 : 2 tile (358 x 239 in the design); on a short window it is capped in height. */
@Composable
private fun DemoTile(exercise: Exercise) {
    val hasMedia = !exercise.mediaKey.isNullOrEmpty()
    val description = if (hasMedia) {
        "Form demo for ${exercise.name}, alternating between the start and the end position"
    } else {
        "No form demo for this exercise yet"
    }
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val tileWidth = minOf(maxWidth, MaxDemoHeight * DemoAspect)
        Box(
            Modifier
                .width(tileWidth)
                .aspectRatio(DemoAspect)
                .clip(RoundedCornerShape(16.dp))
                .clearAndSetSemantics { contentDescription = description },
        ) {
            if (hasMedia) {
                ExerciseMediaView(mediaKey = exercise.mediaKey, modifier = Modifier.fillMaxSize(), cornerRadius = 16.dp)
                StartEndBadge()
            } else {
                NoDemoPlaceholder()
            }
        }
    }
}

private const val DemoAspect = 358f / 239f
private val MaxDemoHeight = 300.dp

@Composable
private fun BoxScope.StartEndBadge() {
    Text(
        "Start · End",
        style = PulseFont.text(12.sp, FontWeight.SemiBold),
        color = Color.White,
        modifier = Modifier
            .align(Alignment.BottomStart)
            .padding(10.dp)
            .background(Color.Black.copy(alpha = 0.55f), CircleShape)
            .padding(horizontal = 10.dp, vertical = 4.dp),
    )
}

@Composable
private fun NoDemoPlaceholder() {
    val colors = PulseTheme.colors
    Box(Modifier.fillMaxSize().background(colors.progressTrack), contentAlignment = Alignment.Center) {
        Column(
            Modifier.padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            DumbbellGlyph(size = 44.dp, color = colors.inkTertiary, strokeWidth = 1.4.dp)
            Text(
                "No form demo for this exercise yet",
                style = PulseFont.subhead,
                color = colors.inkSecondary,
                textAlign = TextAlign.Center,
            )
        }
    }
}

// endregion

// region Chips, cues, history

@Composable
private fun greenWash(): Color = PulseTheme.colors.green.copy(alpha = if (PulseTheme.colors.isDark) 0.18f else 0.12f)

/** Pill with the primary muscle (green) or the equipment / secondary muscles (grey). */
@Composable
private fun FormInfoChip(text: String, isPrimary: Boolean) {
    val colors = PulseTheme.colors
    Text(
        text,
        style = PulseFont.text(13.sp, if (isPrimary) FontWeight.SemiBold else FontWeight.Normal),
        color = if (isPrimary) colors.greenText else colors.ink.copy(alpha = 0.8f),
        modifier = Modifier
            .background(if (isPrimary) greenWash() else colors.chipFill, CircleShape)
            .padding(horizontal = 10.dp, vertical = 4.dp),
    )
}

@Composable
private fun CuesCard(cues: List<String>) {
    val colors = PulseTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .background(colors.card, RoundedCornerShape(16.dp))
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("How to", style = PulseFont.headline, color = colors.ink, modifier = Modifier.semantics { heading() })
        for ((index, cue) in cues.withIndex()) CueRow(number = index + 1, text = cue)
    }
}

/** "1  Lie back with your eyes under the bar." A green number badge (24 dp at the default font size) and the cue text. */
@Composable
private fun CueRow(number: Int, text: String) {
    val colors = PulseTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = "Step $number. $text" },
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(24.dp.scaledWithFont()).background(greenWash(), CircleShape), contentAlignment = Alignment.Center) {
            Text(number.toString(), style = PulseFont.number(13.sp, FontWeight.Bold), color = colors.greenText)
        }
        Text(text, style = PulseFont.subhead.copy(lineHeight = 21.sp), color = colors.ink, modifier = Modifier.weight(1f))
    }
}

/** "History & records ›": a 56 dp white row with a 32 dp blue icon tile. */
@Composable
private fun HistoryRow(onClick: () -> Unit) {
    val colors = PulseTheme.colors
    val iconColor = if (colors.isDark) Color(0xFF0A84FF) else Color(0xFF007AFF)
    Row(
        Modifier
            .fillMaxWidth()
            .pulseMinHeight(56.dp)
            .background(colors.card, RoundedCornerShape(12.dp))
            .pulseClickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(32.dp.scaledWithFont())
                .background(iconColor.copy(alpha = if (colors.isDark) 0.24f else 0.10f), RoundedCornerShape(8.dp)),
            contentAlignment = Alignment.Center,
        ) {
            TrendGlyph(size = 18.dp.scaledWithFont(), color = iconColor)
        }
        Text("History & records", style = PulseFont.body, color = colors.ink, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = colors.inkTertiary, modifier = Modifier.size(22.dp))
    }
}

/** The trend glyph of the design (24 x 24 grid): the baseline, the rising line and its arrow head. */
@Composable
private fun TrendGlyph(size: Dp, color: Color) {
    Canvas(Modifier.size(size)) {
        val scale = this.size.minDimension / 24f
        fun point(x: Float, y: Float) = Offset(x * scale, y * scale)
        val path = Path().apply {
            moveTo(point(3f, 20f)); lineTo(point(21f, 20f))
            moveTo(point(4f, 16f)); lineTo(point(9f, 11f)); lineTo(point(13f, 14f)); lineTo(point(20f, 7f))
            moveTo(point(16f, 7f)); lineTo(point(20f, 7f)); lineTo(point(20f, 11f))
        }
        drawPath(path, color, style = Stroke(width = 2f * scale, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

private fun Path.moveTo(offset: Offset) = moveTo(offset.x, offset.y)

private fun Path.lineTo(offset: Offset) = lineTo(offset.x, offset.y)

// endregion
