package health.pulse.strength.ui.hub

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterExitState
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.core.Transition
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.core.RecoveryProvider
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.ui.components.rememberNow
import health.pulse.strength.ui.components.rememberPulseHaptics
import health.pulse.strength.ui.detail.ExerciseDetailScreen
import health.pulse.strength.ui.settings.SettingsScreen
import health.pulse.strength.ui.theme.LocalReduceMotion
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseTheme
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * The Strength hub (design: Main.dc.html, and TrainLive.dc.html while a workout runs): today's recommended template with readiness,
 * muscle chips, coach note and the Start / Resume button, "Start Empty Workout", templates, muscle recovery, recent workouts, this
 * week and the exercise library. A settings button and the "More" menu sit in the top bar.
 *
 * It keeps its own back stack for the screens it opens (the template list and detail, the library and the exercise detail, history,
 * a finished workout, recovery, settings); system back pops it and is not handled at the home screen. Starting a workout is
 * delegated to [onStart] (null = empty workout). The recommended template is the next one in the rotation of the templates (the one
 * after the most recently performed). While a workout runs, the card and the template screen of THAT workout's template read
 * "Resume Workout" and call [onResume]; starting any other workout is refused with a dialog (the running one would be lost) that
 * offers to resume.
 *
 * A first-run store has no templates, history or personal bests: every section then shows its empty state.
 */
@Composable
fun StrengthHubScreen(
    environment: StrengthAppEnvironment,
    onStart: (WorkoutTemplate?) -> Unit,
    onResume: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val store = environment.store
    val controller = environment.controller
    val data by store.data.collectAsState()
    val workoutState = controller.state.collectAsState()
    // Only the template of the running workout matters here; the state itself changes with every logged set.
    val runningTemplateID by remember(workoutState) { derivedStateOf { workoutState.value?.templateID } }
    val isWorkoutRunning by remember(workoutState) { derivedStateOf { workoutState.value != null } }

    val navigator = rememberSaveable(saver = HubNavigator.Saver) { HubNavigator() }
    var editor by rememberSaveable(stateSaver = HubEditorTarget.NullableSaver) { mutableStateOf<HubEditorTarget?>(null) }
    var showsBusyDialog by rememberSaveable { mutableStateOf(false) }

    val currentOnStart by rememberUpdatedState(onStart)
    val currentOnResume by rememberUpdatedState(onResume)
    val haptics = rememberPulseHaptics()
    val actions = remember(navigator, controller) {
        HubActions(
            push = navigator::push,
            pop = { navigator.pop() },
            requestStart = { template ->
                if (controller.state.value != null) {
                    showsBusyDialog = true
                } else {
                    navigator.popToRoot()
                    haptics.medium()
                    currentOnStart(template)
                }
            },
            resume = { currentOnResume() },
            edit = { editor = it },
        )
    }

    val home = remember(data, runningTemplateID) { homeData(data, runningTemplateID) }
    val time = rememberHubTime()
    // The recovery model reads the stored history and the clock, which Compose does not observe: take a new snapshot whenever the data
    // changes and once a minute, so a finished workout shows in every section and the percentages age while the hub stays open.
    val minute by rememberNow(periodMillis = 60_000L)
    val recovery = remember(data, minute, controller) { HubRecoverySnapshot.of(controller.recovery) }

    // System back goes one screen back; at the home screen nothing handles it and the activity closes.
    BackHandler(enabled = !navigator.isAtRoot) { navigator.pop() }
    LaunchedEffect(isWorkoutRunning) { if (!isWorkoutRunning) showsBusyDialog = false }

    val colors = PulseTheme.colors
    val reduceMotion = LocalReduceMotion.current
    val stateHolder = rememberSaveableStateHolder()
    // A screen that is popped takes its saved state with it, so one opened later never starts with its scroll position and text.
    DisposableEffect(navigator, stateHolder) {
        navigator.onRemoved = {
            // The first call stops the screen from saving itself when it leaves the composition; the second drops a copy the holder
            // may already have taken (the activity saving its state while the screen was open).
            stateHolder.removeState(it.id)
            stateHolder.removeState(it.id)
        }
        onDispose { navigator.onRemoved = {} }
    }
    val top = navigator.entries.lastOrNull()
    val page = HubPage(id = top?.id ?: 0, depth = navigator.entries.size, route = top?.route)

    Box(modifier.fillMaxSize().background(colors.ground)) {
        AnimatedContent(
            targetState = page,
            modifier = Modifier.fillMaxSize(),
            transitionSpec = {
                val transition = when {
                    reduceMotion -> EnterTransition.None togetherWith ExitTransition.None
                    targetState.depth > initialState.depth ->
                        (slideInHorizontally { it / 4 } + fadeIn()) togetherWith (slideOutHorizontally { -it / 6 } + fadeOut())
                    else ->
                        (slideInHorizontally { -it / 6 } + fadeIn()) togetherWith (slideOutHorizontally { it / 4 } + fadeOut())
                }
                transition.apply { targetContentZIndex = targetState.depth.toFloat() }
            },
            label = "hub-pages",
        ) { target ->
            // Each screen keeps its scroll position and field contents while it is covered by the one above it.
            stateHolder.SaveableStateProvider(target.id) {
                // The back arrow of a page counts only while that page is the top screen and has come to rest: a double tap would
                // otherwise reach the arrow of the page it is sliding out of, or of the page underneath, and pop a second screen.
                val pageActions = remember(actions, target.id, transition) {
                    actions.withPop { if (transition.isAtRest) navigator.popIf(target.id) }
                }
                HubDestination(
                    route = target.route,
                    environment = environment,
                    store = store,
                    recovery = recovery,
                    home = home,
                    time = time,
                    actions = pageActions,
                )
            }
        }
    }

    editor?.let { target ->
        key(target) {
            val template = (target as? HubEditorTarget.Existing)?.let { existing -> data.templates.firstOrNull { it.id == existing.templateID } }
            HubTemplateEditorSheet(store = store, template = template, onDismiss = { editor = null })
        }
    }

    if (showsBusyDialog) {
        AlertDialog(
            onDismissRequest = { showsBusyDialog = false },
            containerColor = colors.card,
            title = { Text("Workout in progress", style = PulseFont.headline, color = colors.ink) },
            text = { Text(HubFormat.busyMessage(workoutState.value?.name), style = PulseFont.subhead, color = colors.inkSecondary) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showsBusyDialog = false
                        currentOnResume()
                    },
                ) { Text("Resume", style = PulseFont.headline) }
            },
            dismissButton = {
                TextButton(onClick = { showsBusyDialog = false }) { Text("Cancel", style = PulseFont.body) }
            },
        )
    }
}

/** True once a page has fully slid in and is not on its way out. */
private val Transition<EnterExitState>.isAtRest: Boolean
    get() = currentState == EnterExitState.Visible && targetState == EnterExitState.Visible

/** One page of the hub's stack as the transition sees it: its identity, its depth (0 = home) and what it shows. */
private data class HubPage(val id: Int, val depth: Int, val route: HubRoute?)

/** The current calendar day, zone and first day of the week; recomposes only when the day changes. */
@Composable
internal fun rememberHubTime(): HubTime {
    val now = rememberNow(periodMillis = 60_000L)
    val zone = ZoneId.systemDefault()
    val firstDayOfWeek = remember { WeekFields.of(Locale.getDefault()).firstDayOfWeek }
    val today by remember(zone) { derivedStateOf { now.value.atZone(zone).toLocalDate() } }
    return remember(today, zone, firstDayOfWeek) { HubTime(today, zone, firstDayOfWeek) }
}

@Composable
private fun HubDestination(
    route: HubRoute?,
    environment: StrengthAppEnvironment,
    store: StrengthStore,
    recovery: RecoveryProvider,
    home: HubHomeData,
    time: HubTime,
    actions: HubActions,
) {
    when (route) {
        null -> HubHome(store = store, recovery = recovery, home = home, time = time, actions = actions)
        HubRoute.Library -> HubLibraryScreen(store, actions)
        HubRoute.Templates -> HubTemplateListScreen(home, time, actions)
        is HubRoute.Template -> HubTemplateDetailScreen(route.id, home, time, actions)
        HubRoute.History -> HubHistoryScreen(home.history, time, actions)
        is HubRoute.Workout -> HubWorkoutDetailScreen(route.id, home.history, store, time, actions)
        HubRoute.Recovery -> HubRecoveryScreen(recovery, actions)
        is HubRoute.Exercise -> HubExerciseDestination(route.exerciseID, store, actions)
        HubRoute.Settings -> Box(Modifier.fillMaxSize().background(PulseTheme.colors.ground)) {
            SettingsScreen(environment = environment, onBack = actions.pop)
        }
    }
}

/** The exercise detail screen of the other area; an id that no longer resolves shows a message instead of crashing. */
@Composable
private fun HubExerciseDestination(exerciseID: String, store: StrengthStore, actions: HubActions) {
    val data by store.data.collectAsState()
    val exercise = remember(data, exerciseID) { store.exercise(exerciseID) }
    if (exercise != null) {
        Box(Modifier.fillMaxSize().background(PulseTheme.colors.ground)) {
            ExerciseDetailScreen(exercise = exercise, store = store, onBack = actions.pop)
        }
    } else {
        HubScreenFrame(title = "Exercise", onBack = actions.pop) { inner ->
            Box(Modifier.fillMaxSize().padding(inner)) { HubMessage("This exercise is no longer available.") }
        }
    }
}
