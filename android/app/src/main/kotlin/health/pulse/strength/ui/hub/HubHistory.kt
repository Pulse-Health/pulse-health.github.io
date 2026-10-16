package health.pulse.strength.ui.hub

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.EmojiEvents
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.CompletedExercise
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.PersonalRecord
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.ui.components.DumbbellGlyph
import health.pulse.strength.ui.components.ExerciseMediaView
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseCard
import health.pulse.strength.ui.theme.pulseClickable
import java.time.ZoneId
import java.util.UUID

// Workout history: the rows of "Recent Workouts", "See All" and the detail of one finished workout (HubWorkoutRow,
// HubHistoryListView and HubWorkoutDetailView of StrengthHubView.swift).

/** A finished workout: icon, name with its record count, date and time, and the volume and duration at the trailing edge. */
@Composable
internal fun HubWorkoutRow(workout: CompletedWorkout, zone: ZoneId, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    val stacked = isAccessibilityText()
    val volume: @Composable () -> Unit = {
        Text(
            HubFormat.volumeOrDash(workout.volumeKg),
            style = PulseFont.number(12.sp, FontWeight.SemiBold),
            color = colors.ink,
        )
    }
    val duration: @Composable () -> Unit = {
        Text(HubFormat.duration(workout.durationSeconds), style = PulseFont.footnote, color = colors.inkSecondary)
    }
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .pulseClickable(onClick = onClick)
            .hubRowBackground()
            .padding(12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        HubIconBox(fill = hubBlueFill()) { DumbbellGlyph(size = 18.dp, color = colors.blue, strokeWidth = 2.dp) }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    workout.name,
                    modifier = Modifier.weight(1f, fill = false),
                    style = PulseFont.text(15.sp, FontWeight.SemiBold),
                    color = colors.ink,
                    maxLines = lineLimit(),
                    overflow = TextOverflow.Ellipsis,
                )
                if (workout.personalRecords.isNotEmpty()) HubPill(HubFormat.personalRecordTag(workout.personalRecords.size), horizontalPadding = 7.dp, verticalPadding = 2.dp)
            }
            Text(HubFormat.dateTime(workout.startedAt, zone), style = PulseFont.footnote, color = colors.inkSecondary)
            if (stacked) {
                // No room for a column of figures on the right: they follow the date, under the name.
                volume()
                duration()
            }
        }
        if (!stacked) {
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                volume()
                duration()
            }
        }
    }
}

/** The gold "PR" tag. */
@Composable
internal fun HubPill(text: String, horizontalPadding: androidx.compose.ui.unit.Dp, verticalPadding: androidx.compose.ui.unit.Dp) {
    val colors = PulseTheme.colors
    Text(
        text,
        modifier = Modifier.background(colors.prFill, CircleShape).padding(horizontal = horizontalPadding, vertical = verticalPadding),
        style = PulseFont.text(11.sp, FontWeight.Bold),
        color = colors.prText,
        maxLines = 1,
    )
}

// region Recent Workouts > See All

@Composable
internal fun HubHistoryScreen(history: List<CompletedWorkout>, time: HubTime, actions: HubActions, modifier: Modifier = Modifier) {
    HubScreenFrame(title = "Recent Workouts", onBack = actions.pop, modifier = modifier) { inner ->
        HubContentBox(Modifier.hubScreenPadding(inner).fillMaxSize()) { gutter ->
            LazyColumn(
                Modifier.fillMaxSize(),
                contentPadding = hubContentPadding(gutter, bottom = hubBottomPadding(inner)),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(history, key = { it.id }) { workout ->
                    HubWorkoutRow(workout, time.zone, onClick = { actions.push(HubRoute.Workout(workout.id)) })
                }
                if (history.isEmpty()) item(key = "empty") { HubMessage("Finished workouts appear here.") }
            }
        }
    }
}

// endregion

// region Workout detail

/** A finished workout: figures, personal records, the sets of each exercise and the muscles worked. */
@Composable
internal fun HubWorkoutDetailScreen(
    workoutID: UUID,
    history: List<CompletedWorkout>,
    store: StrengthStore,
    time: HubTime,
    actions: HubActions,
    modifier: Modifier = Modifier,
) {
    val workout = history.firstOrNull { it.id == workoutID }
    HubScreenFrame(title = workout?.name ?: "Workout", onBack = actions.pop, modifier = modifier) { inner ->
        if (workout == null) {
            Box(Modifier.padding(inner).fillMaxSize(), contentAlignment = Alignment.Center) {
                HubMessage("This workout is no longer available.")
            }
        } else {
            HubContentBox(Modifier.hubScreenPadding(inner).fillMaxSize()) { gutter ->
                Column(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(start = gutter, end = gutter, top = 8.dp, bottom = hubBottomPadding(inner)),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                ) {
                    HubWorkoutHeader(workout, time)
                    HubWorkoutStatsCard(workout)
                    for (record in workout.personalRecords) HubRecordCard(record)
                    HubWorkoutExercises(workout, store, actions)
                    HubMusclesWorked(workout)
                }
            }
        }
    }
}

@Composable
private fun HubWorkoutHeader(workout: CompletedWorkout, time: HubTime) {
    val colors = PulseTheme.colors
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(workout.name, style = PulseFont.number(28.sp), color = colors.ink)
        Text(
            HubFormat.dateTime(workout.startedAt, time.zone) + " · " + HubFormat.duration(workout.durationSeconds),
            style = PulseFont.subhead,
            color = colors.inkSecondary,
        )
    }
}

@Composable
private fun HubWorkoutStatsCard(workout: CompletedWorkout) {
    val stats = buildList {
        add(HubStat("Duration", HubFormat.duration(workout.durationSeconds)))
        add(HubStat("Volume", HubFormat.volumeOrDash(workout.volumeKg)))
        add(HubStat("Sets", "${workout.loggedSets}"))
        workout.averageHeartRate?.let { add(HubStat("Avg Heart Rate", "$it bpm")) }
        workout.averageRIR?.let { add(HubStat("Avg RIR", HubFormat.averageRIR(it))) }
    }
    val firstRow = stats.take(3)
    val secondRow = stats.drop(3)
    Column(Modifier.fillMaxWidth().hubRowBackground().padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        HubStatRow(firstRow)
        if (secondRow.isNotEmpty()) {
            HubDivider()
            HubStatRow(secondRow)
        }
    }
}

@Composable
private fun HubRecordCard(record: PersonalRecord) {
    val colors = PulseTheme.colors
    Row(
        Modifier.fillMaxWidth().pulseCard().padding(16.dp).semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(52.dp).background(colors.prFill, CircleShape), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.EmojiEvents, contentDescription = null, modifier = Modifier.size(28.dp), tint = colors.prText)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("New personal record", style = PulseFont.text(12.sp, FontWeight.SemiBold), color = colors.prText)
            Text(
                record.exerciseName,
                style = PulseFont.headline,
                color = colors.ink,
                maxLines = if (isLargerText()) Int.MAX_VALUE else 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                HubFormat.recordText(record.weightKg, record.reps, record.estimated1RM),
                style = PulseFont.number(15.sp, FontWeight.Normal),
                color = colors.inkSecondary,
            )
        }
    }
}

@Composable
private fun HubWorkoutExercises(workout: CompletedWorkout, store: StrengthStore, actions: HubActions) {
    if (workout.exercises.isEmpty()) return
    Column(Modifier.fillMaxWidth()) {
        HubSectionHeader(title = "Exercises")
        Column(Modifier.fillMaxWidth().hubRowBackground()) {
            for ((index, item) in workout.exercises.withIndex()) {
                Box {
                    // A logged exercise that is no longer in the library has nothing to open: no chevron.
                    val opensDetail = store.exercise(item.exerciseID) != null
                    HubCompletedExerciseRow(item, onClick = if (opensDetail) ({ actions.push(HubRoute.Exercise(item.exerciseID)) }) else null)
                    if (index > 0) HubDivider(Modifier.align(Alignment.TopStart), inset = 68.dp)
                }
            }
        }
    }
}

@Composable
private fun HubCompletedExerciseRow(item: CompletedExercise, onClick: (() -> Unit)?) {
    val colors = PulseTheme.colors
    val stacked = isAccessibilityText()
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .then(if (onClick != null) Modifier.pulseClickable(onClick = onClick) else Modifier)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ExerciseMediaView(mediaKey = item.mediaKey, modifier = Modifier.size(44.dp), cornerRadius = 10.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                item.name,
                style = PulseFont.text(15.sp, FontWeight.SemiBold),
                color = colors.ink,
                maxLines = lineLimit(),
                overflow = TextOverflow.Ellipsis,
            )
            // The trailing edge is too narrow for the tag at the largest font sizes: it sits under the name.
            if (item.isPersonalRecord && stacked) HubPill("PR", horizontalPadding = 8.dp, verticalPadding = 3.dp)
            Text(
                HubFormat.setsText(item.sets, item.tracking),
                style = PulseFont.number(12.sp, FontWeight.Normal),
                color = colors.inkSecondary,
                maxLines = if (isLargerText()) Int.MAX_VALUE else 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (item.isPersonalRecord && !stacked) HubPill("PR", horizontalPadding = 8.dp, verticalPadding = 3.dp)
        if (onClick != null) HubChevron()
    }
}

@Composable
private fun HubMusclesWorked(workout: CompletedWorkout) {
    if (workout.muscleSets.isEmpty()) return
    val colors = PulseTheme.colors
    val most = maxOf(1, workout.muscleSets.maxOf { it.sets })
    Column(Modifier.fillMaxWidth()) {
        HubSectionHeader(title = "Muscles Worked")
        Column(
            Modifier.fillMaxWidth().hubRowBackground().padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            for (item in workout.muscleSets) {
                Column(Modifier.semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            item.muscle.title,
                            modifier = Modifier.weight(1f),
                            style = PulseFont.text(12.sp, FontWeight.SemiBold),
                            color = colors.ink,
                        )
                        Text(HubFormat.sets(item.sets), style = PulseFont.footnote, color = colors.inkSecondary)
                    }
                    HubBar(fraction = item.sets.toDouble() / most, color = colors.progress)
                }
            }
        }
    }
}

// endregion
