package health.pulse.strength.wear.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.ScalingLazyListScope
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.NextUpSummary
import health.pulse.strength.core.widgets.WeekSummary
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.wear.R
import health.pulse.strength.wear.data.WearCommands
import health.pulse.strength.wear.model.WearText
import java.time.Duration
import java.time.Instant
import kotlin.math.ceil
import kotlin.math.max

/** Everything the watch app draws, as plain values: the stateless input of [WearScreen]. */
internal data class WearUiState(
    val snapshot: WidgetSnapshot,
    /** True while only the preview exists (nothing has arrived from the phone yet). */
    val isPlaceholder: Boolean,
    /** The time the clock and the rest countdown are drawn for. */
    val now: Instant,
    /** The phone was asked to start the next workout and has not answered yet. */
    val starting: Boolean = false,
    /** A short problem to show over the list, such as an unreachable phone. */
    val notice: String? = null,
)

/**
 * The watch app: with nothing from the phone yet a "waiting" page; with no workout the week ring and the next workout with Start; with a
 * workout the controls for the state it is in (log a set and change weight or reps, the rest countdown with -15 / Skip / +15, pause and
 * resume, finish). Every control is a command to the phone ([onCommand]).
 */
@Composable
internal fun WearScreen(state: WearUiState, onCommand: (WidgetCommand) -> Unit) {
    val listState = rememberScalingLazyListState()
    val haptic = LocalHapticFeedback.current
    val send: (WidgetCommand) -> Unit = { command ->
        haptic.performHapticFeedback(HapticFeedbackType.Confirm)
        onCommand(command)
    }
    val active = state.snapshot.active
    Scaffold(
        timeText = { TimeText() },
        vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(modifier = Modifier.fillMaxSize(), state = listState) {
            when {
                state.isPlaceholder -> waitingItems()
                active != null -> activeItems(state, active, send)
                else -> idleItems(state, send)
            }
        }
        state.notice?.let { notice ->
            Box(Modifier.fillMaxSize().padding(bottom = 18.dp), contentAlignment = Alignment.BottomCenter) {
                Panel(Modifier.padding(horizontal = 24.dp)) {
                    Text(notice, style = MaterialTheme.typography.caption2, color = WearColors.Red, textAlign = TextAlign.Center)
                }
            }
        }
    }
}

private fun ScalingLazyListScope.waitingItems() {
    item { ScreenHeader("Pulse Strength") }
    item {
        Column(Modifier.padding(horizontal = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(painterResource(R.drawable.ic_dumbbell), contentDescription = null, modifier = Modifier.size(28.dp), tint = WearColors.Green)
            Spacer(Modifier.height(6.dp))
            Text("Waiting for your phone", style = MaterialTheme.typography.title3, textAlign = TextAlign.Center)
            Spacer(Modifier.height(4.dp))
            Text(
                "Open Pulse Strength on your phone to sync your week.",
                style = MaterialTheme.typography.caption1,
                color = WearColors.Secondary,
                textAlign = TextAlign.Center,
            )
        }
    }
}

private fun ScalingLazyListScope.idleItems(state: WearUiState, send: (WidgetCommand) -> Unit) {
    val snapshot = state.snapshot
    item { ScreenHeader("This week") }
    item { WeekCard(snapshot.week) }
    item { NextUpPanel(snapshot.nextUp, state.starting) { send(WearCommands.startNext()) } }
}

@Composable
private fun WeekCard(week: WeekSummary) {
    val goal = max(week.goal, 1)
    val last = week.daysSinceLastWorkout
    val streak = if (week.streakWeeks > 0) "${week.streakWeeks} week streak" else null
    val lastWorkout = last?.let { WearText.daysSpoken(it) }
    Column(
        Modifier.semantics(mergeDescendants = true) {
            contentDescription = listOfNotNull("${week.completed} of $goal workouts this week", streak, lastWorkout).joinToString(". ")
        },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.size(84.dp), contentAlignment = Alignment.Center) {
            ProgressRing(week.completed.toFloat() / goal, Modifier.fillMaxSize(), stroke = 8.dp)
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("${week.completed}/$goal", style = numberStyle(24f))
                Text("workouts", style = MaterialTheme.typography.caption3, color = WearColors.Secondary)
            }
        }
        Spacer(Modifier.height(6.dp))
        DayDots(week.days)
        listOfNotNull(streak, lastWorkout).forEach { line ->
            Text(line, style = MaterialTheme.typography.caption2, color = WearColors.Secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun NextUpPanel(nextUp: NextUpSummary?, starting: Boolean, onStart: () -> Unit) {
    Panel {
        if (nextUp == null) {
            Text("No workout planned", style = MaterialTheme.typography.title3, textAlign = TextAlign.Center)
            Text("Add one in Pulse on your phone.", style = MaterialTheme.typography.caption2, color = WearColors.Secondary, textAlign = TextAlign.Center)
        } else {
            Text(nextUp.splitLabel, style = MaterialTheme.typography.caption1, color = WearColors.Green, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(nextUp.name, style = MaterialTheme.typography.title3, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                WearText.planSummary(nextUp.exerciseCount, nextUp.estimatedMinutes),
                style = MaterialTheme.typography.caption2,
                color = WearColors.Secondary,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(8.dp))
            ActionChip(if (starting) "Starting…" else "Start", onStart, enabled = !starting, icon = R.drawable.ic_play)
        }
    }
}

private fun ScalingLazyListScope.activeItems(state: WearUiState, active: WorkoutSnapshot, send: (WidgetCommand) -> Unit) {
    val elapsed = elapsedSeconds(active, state.now)
    item {
        ScreenHeader(
            title = active.workoutName,
            trailing = WearText.clock(elapsed),
            trailingDescription = (if (active.isPaused) "Paused at " else "Elapsed ") + WearText.spoken(elapsed),
        )
    }
    val endsAt = active.restEndsAt
    when {
        active.phase == SnapshotPhase.COMPLETE -> completeItems(active, send)
        active.isPaused -> pausedItems(active, send)
        active.phase == SnapshotPhase.RESTING && endsAt != null && endsAt.isAfter(state.now) -> restingItems(active, endsAt, state.now, send)
        else -> loggingItems(active, restOver = active.phase != SnapshotPhase.LOGGING, send)
    }
}

private fun ScalingLazyListScope.loggingItems(active: WorkoutSnapshot, restOver: Boolean, send: (WidgetCommand) -> Unit) {
    item { WorkSummary(active, restOver) }
    item { ActionChip("Log set", { send(WearCommands.logNextSet()) }, icon = R.drawable.ic_check) }
    if (active.showsWeight) {
        item {
            Stepper(
                value = active.weightText,
                unit = "kg",
                spokenUnit = "kilograms",
                label = "weight",
                onMinus = { send(WearCommands.nudge(-1, 0)) },
                onPlus = { send(WearCommands.nudge(1, 0)) },
            )
        }
    }
    item {
        Stepper(
            value = active.repsText,
            unit = active.repsUnit,
            spokenUnit = if (active.repsUnit == "sec") "seconds" else "reps",
            label = if (active.repsUnit == "sec") "duration" else "reps",
            onMinus = { send(WearCommands.nudge(0, -1)) },
            onPlus = { send(WearCommands.nudge(0, 1)) },
        )
    }
    item { PauseChip(send) }
}

private fun ScalingLazyListScope.restingItems(active: WorkoutSnapshot, endsAt: Instant, now: Instant, send: (WidgetCommand) -> Unit) {
    val remaining = ceil(Duration.between(now, endsAt).toMillis() / 1000.0).toInt()
    val total = max(max(active.restTotalSeconds, remaining), 1)
    item { RestRing(remaining, total, WearText.nextSet(active)) }
    item {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
            RoundButton("Subtract 15 seconds from the rest", { send(WearCommands.adjustRest(-WearCommands.REST_STEP_SECONDS)) }) { ButtonLabel("−15") }
            RoundButton("Skip rest", { send(WearCommands.skipRest()) }, primary = true) { ButtonLabel("Skip") }
            RoundButton("Add 15 seconds to the rest", { send(WearCommands.adjustRest(WearCommands.REST_STEP_SECONDS)) }) { ButtonLabel("+15") }
        }
    }
    item { ActionChip("Log set", { send(WearCommands.logNextSet()) }, primary = false, icon = R.drawable.ic_check) }
    item { PauseChip(send) }
}

private fun ScalingLazyListScope.pausedItems(active: WorkoutSnapshot, send: (WidgetCommand) -> Unit) {
    item {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Paused", style = MaterialTheme.typography.title2, color = WearColors.Gold, fontWeight = FontWeight.Bold)
            active.restFrozenRemaining?.let { remaining ->
                Text("Rest ${WearText.clock(remaining)} left", style = MaterialTheme.typography.caption1, color = WearColors.Secondary)
            }
        }
    }
    item { ActionChip("Resume", { send(WearCommands.resume()) }, icon = R.drawable.ic_play) }
}

private fun ScalingLazyListScope.completeItems(active: WorkoutSnapshot, send: (WidgetCommand) -> Unit) {
    item {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(painterResource(R.drawable.ic_check), contentDescription = null, modifier = Modifier.size(28.dp), tint = WearColors.Green)
            Text("All sets logged", style = MaterialTheme.typography.title3, textAlign = TextAlign.Center)
            Text(WearText.plural(active.loggedSets, "set"), style = MaterialTheme.typography.caption1, color = WearColors.Secondary)
        }
    }
    item { ActionChip("Finish workout", { send(WearCommands.finish()) }) }
}

@Composable
private fun WorkSummary(active: WorkoutSnapshot, restOver: Boolean) {
    Column(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) {
            contentDescription = listOfNotNull("Rest over".takeIf { restOver }, active.exerciseName, active.setLabel, WearText.work(active)).joinToString(". ")
        },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (restOver) Text("Rest over", style = MaterialTheme.typography.caption1, color = WearColors.Green, fontWeight = FontWeight.Bold)
        Text(active.exerciseName, style = MaterialTheme.typography.title3, textAlign = TextAlign.Center, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(active.setLabel, style = MaterialTheme.typography.caption2, color = WearColors.Secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(WearText.work(active), style = numberStyle(26f), maxLines = 1)
    }
}

/** A value with a round minus on its left and a round plus on its right. */
@Composable
private fun Stepper(value: String, unit: String, spokenUnit: String, label: String, onMinus: () -> Unit, onPlus: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        RoundButton("Decrease $label", onMinus) { ButtonLabel("−") }
        Column(
            Modifier.semantics(mergeDescendants = true) { contentDescription = "$label, $value $spokenUnit" },
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(value, style = numberStyle(24f), maxLines = 1)
            Text(unit, style = MaterialTheme.typography.caption2, color = WearColors.Secondary)
        }
        RoundButton("Increase $label", onPlus) { ButtonLabel("+") }
    }
}

@Composable
private fun RestRing(remainingSeconds: Int, totalSeconds: Int, next: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier.size(104.dp).semantics(mergeDescendants = true) {
                contentDescription = "Rest timer"
                stateDescription = WearText.spoken(remainingSeconds) + " left"
            },
            contentAlignment = Alignment.Center,
        ) {
            ProgressRing(remainingSeconds.toFloat() / totalSeconds, Modifier.fillMaxSize(), stroke = 9.dp)
            Text(WearText.clock(remainingSeconds), style = numberStyle(30f), maxLines = 1)
        }
        Text(next, style = MaterialTheme.typography.caption1, color = WearColors.Ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun PauseChip(send: (WidgetCommand) -> Unit) {
    ActionChip("Pause", { send(WearCommands.pause()) }, primary = false, icon = R.drawable.ic_pause)
}

/** Elapsed active seconds: frozen while paused, otherwise `now - activeStart`. */
internal fun elapsedSeconds(active: WorkoutSnapshot, now: Instant): Int =
    if (active.isPaused) max(0, active.elapsedWhenPaused) else max(0L, Duration.between(active.activeStart, now).seconds).toInt()
