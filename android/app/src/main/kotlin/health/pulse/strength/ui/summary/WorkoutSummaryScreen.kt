package health.pulse.strength.ui.summary

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.NumberText
import health.pulse.strength.ui.components.rememberNow
import health.pulse.strength.ui.components.rememberPulseHaptics
import health.pulse.strength.ui.detail.StrengthHairline
import health.pulse.strength.ui.detail.StrengthResultText
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulsePrimaryButton
import health.pulse.strength.ui.theme.PulseTheme

/**
 * "Workout Complete": shown full screen over the app after a workout is finished and saved (port of `WorkoutSummaryView`).
 *
 * From top to bottom: the title with the workout name, date and duration; the personal-record card (only with PRs); the figure
 * tiles (duration, volume, sets, and average heart rate / average RIR when they were recorded); the per-exercise results; the sets
 * per muscle group; and a "Done" button that stays pinned at the bottom. The content scrolls and is centred in a column of at most
 * [PulseMetrics.maxContentWidth]. A success haptic plays once when the screen appears.
 *
 * Like the iOS screen it has no heart-rate zones, calories, coach text, "Save to Health" switch or template row: a
 * [CompletedWorkout] does not carry that data (it is already saved when this screen appears). The muscle bars show sets.
 */
@Composable
fun WorkoutSummaryScreen(workout: CompletedWorkout, onDone: () -> Unit, modifier: Modifier = Modifier) {
    val haptics = rememberPulseHaptics()
    val now by rememberNow(periodMillis = 60_000L)
    // Once per summary: a rotation or a fold must not buzz again.
    var didAnnounce by rememberSaveable(workout.id.toString()) { mutableStateOf(false) }
    LaunchedEffect(workout.id) {
        if (!didAnnounce) {
            didAnnounce = true
            haptics.success()
        }
    }

    val tiles = remember(workout) { summaryTiles(workout) }
    val subtitle = workout.name + " · " + StrengthResultText.weekdayMonthDay(workout.finishedAt, now) + " · " +
        StrengthResultText.durationSubtitle(workout.durationSeconds)

    Column(modifier.fillMaxSize().background(PulseTheme.colors.ground)) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal)),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(
                    Modifier
                        .widthIn(max = PulseMetrics.maxContentWidth)
                        .fillMaxWidth()
                        .padding(start = PulseMetrics.screenInset, end = PulseMetrics.screenInset, top = 28.dp, bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                ) {
                    WorkoutSummaryHeader(subtitle)
                    if (workout.personalRecords.isNotEmpty()) WorkoutSummaryRecordsCard(workout.personalRecords)
                    WorkoutSummaryStatsCard(tiles)
                    if (workout.exercises.isNotEmpty()) WorkoutSummaryExercisesSection(workout.exercises)
                    if (workout.muscleSets.isNotEmpty()) WorkoutSummaryMusclesSection(workout.muscleSets)
                }
            }
        }
        WorkoutSummaryDoneBar(
            onClick = {
                haptics.light()
                onDone()
            },
        )
    }
}

@Composable
private fun WorkoutSummaryHeader(subtitle: String) {
    val colors = PulseTheme.colors
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            text = "Workout Complete",
            style = PulseFont.text(34.sp, FontWeight.Bold).copy(letterSpacing = 0.37.sp),
            color = colors.ink,
            modifier = Modifier.semantics { heading() },
        )
        Text(text = subtitle, style = PulseFont.text(15.sp), color = colors.inkSecondary)
    }
}

/** The figure tiles: duration, volume and sets, plus average heart rate and average RIR when they were recorded. */
internal fun summaryTiles(workout: CompletedWorkout): List<WorkoutSummaryTile> {
    val tiles = mutableListOf<WorkoutSummaryTile>()
    tiles.add(
        WorkoutSummaryTile(
            id = "duration",
            title = "Duration",
            value = StrengthResultText.durationTile(workout.durationSeconds),
            spoken = StrengthResultText.durationSpoken(workout.durationSeconds),
        ),
    )
    val volume = NumberText.thousands(workout.volumeKg)
    tiles.add(WorkoutSummaryTile(id = "volume", title = "Volume", value = "$volume kg", spoken = "$volume kilograms"))
    val sets = workout.loggedSets.toString()
    tiles.add(WorkoutSummaryTile(id = "sets", title = "Sets", value = sets, spoken = sets))
    val bpm = workout.averageHeartRate
    if (bpm != null && bpm > 0) {
        tiles.add(WorkoutSummaryTile(id = "heartRate", title = "Avg Heart Rate", value = "$bpm bpm", spoken = "$bpm beats per minute"))
    }
    val rir = workout.averageRIR
    if (rir != null) {
        val text = StrengthResultText.oneDecimal(rir)
        tiles.add(WorkoutSummaryTile(id = "rir", title = "Avg RIR", value = text, spoken = "$text reps in reserve"))
    }
    return tiles
}

/** The "Done" button pinned at the bottom, above the system navigation bar, with a hairline on top. */
@Composable
private fun WorkoutSummaryDoneBar(onClick: () -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(PulseTheme.colors.ground)
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom + WindowInsetsSides.Horizontal)),
    ) {
        StrengthHairline()
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            // The same column as the content above: at most the content width, gutters inside it.
            Box(
                Modifier
                    .widthIn(max = PulseMetrics.maxContentWidth)
                    .fillMaxWidth()
                    .padding(start = PulseMetrics.screenInset, end = PulseMetrics.screenInset, top = 10.dp, bottom = 8.dp),
            ) {
                PulsePrimaryButton(text = "Done", onClick = onClick)
            }
        }
    }
}
