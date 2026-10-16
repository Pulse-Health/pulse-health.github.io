package health.pulse.strength.ui.summary

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.CompletedExercise
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.MuscleSets
import health.pulse.strength.core.NumberText
import health.pulse.strength.core.PersonalRecord
import health.pulse.strength.core.roundedAwayFromZero
import health.pulse.strength.ui.components.ExerciseMediaView
import health.pulse.strength.ui.detail.FitText
import health.pulse.strength.ui.detail.StrengthHairline
import health.pulse.strength.ui.detail.StrengthPRChip
import health.pulse.strength.ui.detail.StrengthResultText
import health.pulse.strength.ui.detail.isLargeFontScale
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseCard

// The sections of the workout summary below the header.

@Composable
internal fun WorkoutSummarySectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = PulseFont.text(17.sp, FontWeight.SemiBold),
        color = PulseTheme.colors.ink,
        modifier = modifier.semantics { heading() },
    )
}

// region Personal records

/** The "New personal record" card: one row per record, separated by a hairline. */
@Composable
internal fun WorkoutSummaryRecordsCard(records: List<PersonalRecord>, modifier: Modifier = Modifier) {
    Column(
        modifier
            .fillMaxWidth()
            .pulseCard()
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        records.forEachIndexed { index, record ->
            if (index > 0) StrengthHairline()
            WorkoutSummaryRecordRow(record)
        }
    }
}

/** Whole-kilogram improvement over the previous best, as printed ("3 kg"); null when it rounds to nothing. */
internal fun PersonalRecord.gainKg(): Double? {
    if (!(previousBest > 0)) return null
    val gain = estimated1RM.roundedAwayFromZero() - previousBest.roundedAwayFromZero()
    return if (gain >= 1) gain else null
}

/** "85 kg × 6 · est. 1RM 102 kg" */
internal fun PersonalRecord.detailText(): String =
    NumberText.kg(weightKg) + " kg × " + reps + " · est. 1RM " + NumberText.kg(estimated1RM.roundedAwayFromZero()) + " kg"

internal fun PersonalRecord.spokenText(): String {
    val weight = NumberText.kg(weightKg)
    val estimate = NumberText.kg(estimated1RM.roundedAwayFromZero())
    var text = "New personal record, $exerciseName, $weight kilograms for $reps " + (if (reps == 1) "rep" else "reps") +
        ", estimated one-rep max $estimate kilograms"
    gainKg()?.let { text += ", up " + NumberText.kg(it) + " kilograms" }
    return text
}

/** Trophy, text and gain in one row; at the biggest font sizes the text gets the full width and the gain moves beside the trophy. */
@Composable
private fun WorkoutSummaryRecordRow(record: PersonalRecord) {
    val colors = PulseTheme.colors
    val gain = record.gainKg()
    val trophy: @Composable () -> Unit = {
        Box(Modifier.size(52.dp).background(colors.prFill, CircleShape), contentAlignment = Alignment.Center) {
            WorkoutSummaryTrophy(size = 26.dp, color = colors.prText)
        }
    }
    val gainView: @Composable () -> Unit = {
        if (gain != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Rounded.ArrowUpward, contentDescription = null, tint = colors.green, modifier = Modifier.size(14.dp))
                Text(NumberText.kg(gain) + " kg", style = PulseFont.number(13.sp, FontWeight.SemiBold), color = colors.green)
            }
        }
    }
    val textColumn: @Composable (Modifier) -> Unit = { modifier ->
        Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("New personal record", style = PulseFont.text(12.sp, FontWeight.SemiBold), color = colors.prText)
            Text(record.exerciseName, style = PulseFont.text(17.sp, FontWeight.SemiBold), color = colors.ink)
            Text(record.detailText(), style = PulseFont.number(15.sp, FontWeight.Normal), color = colors.ink.copy(alpha = 0.76f))
        }
    }
    val rowModifier = Modifier
        .fillMaxWidth()
        .clearAndSetSemantics { contentDescription = record.spokenText() }
    if (isLargeFontScale()) {
        Column(rowModifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                trophy()
                gainView()
            }
            textColumn(Modifier.fillMaxWidth())
        }
    } else {
        Row(rowModifier, horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
            trophy()
            textColumn(Modifier.weight(1f))
            gainView()
        }
    }
}

/** The trophy of the design (24 x 24 viewBox: cup, two handles, stem, base), drawn as strokes. */
@Composable
internal fun WorkoutSummaryTrophy(size: Dp, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) { drawTrophy(color) }
}

private fun DrawScope.drawTrophy(color: Color) {
    val scale = minOf(size.width, size.height) / 24f
    val originX = (size.width - 24 * scale) / 2
    val originY = (size.height - 24 * scale) / 2
    fun x(value: Float) = originX + value * scale
    fun y(value: Float) = originY + value * scale

    val path = Path().apply {
        // Cup: M8 4 h8 v5 a4 4 0 0 1 -8 0 V4 z
        moveTo(x(8f), y(4f))
        lineTo(x(16f), y(4f))
        lineTo(x(16f), y(9f))
        cubicTo(x(16f), y(11.209f), x(14.209f), y(13f), x(12f), y(13f))
        cubicTo(x(9.791f), y(13f), x(8f), y(11.209f), x(8f), y(9f))
        close()
        // Left handle: M8 6 H4 v1 a3 3 0 0 0 3 3
        moveTo(x(8f), y(6f))
        lineTo(x(4f), y(6f))
        lineTo(x(4f), y(7f))
        cubicTo(x(4f), y(8.657f), x(5.343f), y(10f), x(7f), y(10f))
        // Right handle: M16 6 h4 v1 a3 3 0 0 1 -3 3
        moveTo(x(16f), y(6f))
        lineTo(x(20f), y(6f))
        lineTo(x(20f), y(7f))
        cubicTo(x(20f), y(8.657f), x(18.657f), y(10f), x(17f), y(10f))
        // Stem: M12 13 v4
        moveTo(x(12f), y(13f))
        lineTo(x(12f), y(17f))
        // Base: M8 20 h8
        moveTo(x(8f), y(20f))
        lineTo(x(16f), y(20f))
    }
    drawPath(path, color, style = Stroke(width = 1.9f * scale, cap = StrokeCap.Round, join = StrokeJoin.Round))
}

// endregion

// region Figures

/** One figure of the stats card. [spoken] is what TalkBack reads as the value. */
internal class WorkoutSummaryTile(val id: String, val title: String, val value: String, val spoken: String)

/**
 * White card with the figure tiles, three per row at the default text size; a short last row keeps its columns. Bigger text (or a
 * narrow window) gives each figure more room: two per row, then one.
 */
@Composable
internal fun WorkoutSummaryStatsCard(tiles: List<WorkoutSummaryTile>, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val scale = LocalDensity.current.fontScale.coerceAtLeast(1f)
        val inner = maxWidth - 24.dp
        // A figure needs about 80 dp (a value like "1,980 kg") times the font scale.
        val needed = 80.dp * scale
        val columns = when {
            isLargeFontScale() -> 1
            (inner - 64.dp) / 3 >= needed -> 3
            (inner - 32.dp) / 2 >= needed -> 2
            else -> 1
        }
        val rows = tiles.chunked(columns)
        Column(
            Modifier
                .fillMaxWidth()
                .background(PulseTheme.colors.card, RoundedCornerShape(PulseMetrics.listRadius))
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            rows.forEachIndexed { index, row ->
                if (index > 0) StrengthHairline()
                Row(horizontalArrangement = Arrangement.spacedBy(32.dp), verticalAlignment = Alignment.Top) {
                    for (slot in 0 until columns) {
                        if (slot < row.size) {
                            WorkoutSummaryTileView(row[slot], showsDivider = slot > 0, modifier = Modifier.weight(1f))
                        } else {
                            Spacer(Modifier.weight(1f).height(1.dp))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WorkoutSummaryTileView(tile: WorkoutSummaryTile, showsDivider: Boolean, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    val divider = colors.separator
    Column(
        modifier
            .drawBehind {
                if (showsDivider) {
                    // Centred in the 32 dp gap to the previous figure.
                    val x = -16.dp.toPx()
                    drawLine(divider, Offset(x, 0f), Offset(x, size.height), strokeWidth = maxOf(1f, 0.5.dp.toPx()))
                }
            }
            .clearAndSetSemantics { contentDescription = tile.title + ", " + tile.spoken },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        FitText(
            text = tile.title,
            style = PulseFont.text(12.sp).copy(lineHeight = 16.sp),
            color = colors.inkSecondary,
            minScale = 0.8f,
        )
        FitText(
            text = tile.value,
            style = PulseFont.number(20.sp, FontWeight.SemiBold).copy(lineHeight = 25.sp),
            color = colors.ink,
            minScale = 0.7f,
        )
    }
}

// endregion

// region Exercises

@Composable
internal fun WorkoutSummaryExercisesSection(exercises: List<CompletedExercise>, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        WorkoutSummarySectionTitle("Exercises")
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(PulseMetrics.listRadius))
                .background(PulseTheme.colors.card),
        ) {
            exercises.forEachIndexed { index, exercise ->
                if (index > 0) StrengthHairline()
                WorkoutSummaryExerciseRow(exercise)
            }
        }
    }
}

internal fun CompletedExercise.spokenText(): String {
    val count = sets.size
    var text = name + ", " + count + (if (count == 1) " set" else " sets")
    if (isPersonalRecord) text += ", personal record"
    text += ". " + StrengthResultText.setsLine(sets, tracking).replace(" · ", ", ")
    return text
}

/** Picture, text and PR tag in one row; at the biggest font sizes the tag moves into the text column. */
@Composable
private fun WorkoutSummaryExerciseRow(exercise: CompletedExercise) {
    val colors = PulseTheme.colors
    val large = isLargeFontScale()
    // One line for the name as designed (two for a very long one: a name must stay readable); every line with bigger text.
    val wrapsName = LocalDensity.current.fontScale > 1f
    val media: @Composable () -> Unit = {
        ExerciseMediaView(mediaKey = exercise.mediaKey, modifier = Modifier.size(44.dp), cornerRadius = 10.dp)
    }
    val name: @Composable () -> Unit = {
        Text(
            exercise.name,
            style = PulseFont.text(15.sp, FontWeight.SemiBold),
            color = colors.ink,
            maxLines = if (wrapsName) Int.MAX_VALUE else 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
    val sets: @Composable () -> Unit = {
        Text(
            StrengthResultText.setsLine(exercise.sets, exercise.tracking),
            style = PulseFont.number(12.sp, FontWeight.Normal),
            color = colors.inkSecondary,
        )
    }
    val rowModifier = Modifier
        .fillMaxWidth()
        .clearAndSetSemantics { contentDescription = exercise.spokenText() }
        .heightIn(min = 64.dp)
        .padding(horizontal = 12.dp, vertical = 8.dp)
    if (large) {
        Row(rowModifier, horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            media()
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                name()
                if (exercise.isPersonalRecord) StrengthPRChip(horizontal = 8.dp, vertical = 3.dp)
                sets()
            }
        }
    } else {
        Row(rowModifier, horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            media()
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                name()
                sets()
            }
            if (exercise.isPersonalRecord) StrengthPRChip(horizontal = 8.dp, vertical = 3.dp)
        }
    }
}

// endregion

// region Muscles

@Composable
internal fun WorkoutSummaryMusclesSection(muscleSets: List<MuscleSets>, modifier: Modifier = Modifier) {
    val mostSets = maxOf(1, muscleSets.maxOfOrNull { it.sets } ?: 1)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        WorkoutSummarySectionTitle("Muscles Worked")
        Column(
            Modifier
                .fillMaxWidth()
                .background(PulseTheme.colors.card, RoundedCornerShape(PulseMetrics.listRadius))
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            for (item in muscleSets) {
                WorkoutSummaryMuscleRow(muscle = item.muscle, sets = item.sets, fraction = item.sets.toFloat() / mostSets)
            }
        }
    }
}

/** "Chest" and "8 sets" above a 6 dp bar whose length is the share of the most-worked muscle. */
@Composable
private fun WorkoutSummaryMuscleRow(muscle: MuscleGroup, sets: Int, fraction: Float) {
    val colors = PulseTheme.colors
    val setsText = sets.toString() + if (sets == 1) " set" else " sets"
    Column(
        Modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = muscle.title + ", " + setsText },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Bottom) {
            Text(muscle.title, style = PulseFont.text(12.sp, FontWeight.SemiBold), color = colors.ink)
            Spacer(Modifier.weight(1f))
            Text(setsText, style = PulseFont.text(12.sp), color = colors.inkSecondary)
        }
        val track = colors.progressTrack
        val fill = colors.progress
        Canvas(
            Modifier
                .fillMaxWidth()
                .height(6.dp),
        ) {
            val radius = CornerRadius(size.height / 2)
            drawRoundRect(track, size = size, cornerRadius = radius)
            val share = fraction.coerceIn(0f, 1f)
            drawRoundRect(fill, size = Size(maxOf(size.height, size.width * share), size.height), cornerRadius = radius)
        }
    }
}

// endregion
