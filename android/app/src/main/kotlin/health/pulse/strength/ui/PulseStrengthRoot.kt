package health.pulse.strength.ui

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.ui.active.ActiveWorkoutScreen
import health.pulse.strength.ui.active.LocalRestAlertsEnabled
import health.pulse.strength.ui.active.UnsavedWorkoutDialog
import health.pulse.strength.ui.active.WorkoutInProgressBar
import health.pulse.strength.ui.components.rememberNow
import health.pulse.strength.ui.hub.StrengthHubScreen
import health.pulse.strength.ui.summary.WorkoutSummaryScreen
import health.pulse.strength.ui.theme.PulseTheme
import java.util.UUID

/**
 * The strength feature as one composable: the Strength hub, the active workout as a full-screen layer above it, the
 * workout-in-progress bar below the hub while a workout runs and its screen is minimised, and the summary layer after a workout is
 * finished.
 *
 * * Starting a workout (`controller.startWorkout(template)`) or resuming one shows the active workout.
 * * Minimising (system back or the chevron) hides it; the bar then offers "Resume".
 * * Finishing hides it and shows the summary (discarding shows nothing).
 * * `pulse-strength://workout` and the ongoing notification's tap show the active workout when one exists.
 */
@Composable
fun PulseStrengthRoot(environment: StrengthAppEnvironment) {
    val controller = environment.controller
    val workoutState by controller.state.collectAsState()
    val data by environment.store.data.collectAsState()
    var showsActiveWorkout by rememberSaveable { mutableStateOf(false) }
    var summaryWorkoutID by rememberSaveable { mutableStateOf<String?>(null) }
    var showsUnsavedDialog by rememberSaveable { mutableStateOf(false) }

    val hasWorkout = workoutState != null
    val summary: CompletedWorkout? = summaryWorkoutID?.let { id -> data.history.firstOrNull { it.id.toString() == id } }

    AskForNotificationsWhenAWorkoutStarts(environment, hasWorkout)

    // A request made while the activity was being created (cold start from the notification or the deep link) is waiting here.
    val openRequested by environment.openWorkoutRequested.collectAsState()
    LaunchedEffect(openRequested) {
        if (!openRequested) return@LaunchedEffect
        if (controller.state.value != null) showsActiveWorkout = true
        environment.consumeOpenWorkoutRequest()
    }
    // A workout that ends elsewhere (a notification action, another surface) closes its screen.
    LaunchedEffect(hasWorkout) { if (!hasWorkout) showsActiveWorkout = false }

    val barVisible = hasWorkout && !showsActiveWorkout

    Box(Modifier.fillMaxSize().background(PulseTheme.colors.ground)) {
        Column(Modifier.fillMaxSize()) {
            Box(
                Modifier
                    .weight(1f)
                    .then(if (barVisible) Modifier.consumeWindowInsets(WindowInsets.navigationBars) else Modifier),
            ) {
                StrengthHubScreen(
                    environment = environment,
                    onStart = { template: WorkoutTemplate? ->
                        if (controller.state.value == null) controller.startWorkout(template)
                        if (controller.state.value != null) showsActiveWorkout = true
                    },
                    onResume = { if (controller.state.value != null) showsActiveWorkout = true },
                )
            }
            if (barVisible) {
                val now by rememberNow()
                val presentation = controller.presentation(now)
                if (presentation != null) {
                    Box(Modifier.navigationBarsPadding().padding(start = 14.dp, end = 14.dp, bottom = 8.dp)) {
                        CompositionLocalProvider(
                            LocalRestAlertsEnabled provides (workoutState?.settings?.alertWhenRestEnds ?: true),
                        ) {
                            WorkoutInProgressBar(presentation = presentation, onResume = { showsActiveWorkout = true })
                        }
                    }
                }
            }
        }

        AnimatedVisibility(
            visible = showsActiveWorkout && hasWorkout,
            enter = slideInVertically { it / 6 } + fadeIn(),
            exit = slideOutVertically { it / 6 } + fadeOut(),
        ) {
            BackHandler { showsActiveWorkout = false }
            ActiveWorkoutScreen(
                controller = controller,
                store = environment.store,
                onMinimise = { showsActiveWorkout = false },
                onFinished = { completed: CompletedWorkout? ->
                    showsActiveWorkout = false
                    if (completed != null) {
                        summaryWorkoutID = completed.id.toString()
                        // The finished workout could not be written (a full phone): say so now, the summary alone looks like success.
                        if (controller.lastPersistenceError != null) showsUnsavedDialog = true
                    }
                },
            )
        }

        AnimatedVisibility(
            visible = summary != null,
            enter = slideInVertically { it / 6 } + fadeIn(),
            exit = slideOutVertically { it / 6 } + fadeOut(),
        ) {
            val shown = summary
            if (shown != null) {
                BackHandler { summaryWorkoutID = null }
                WorkoutSummaryScreen(workout = shown, onDone = { summaryWorkoutID = null })
            }
        }

        if (showsUnsavedDialog) {
            UnsavedWorkoutDialog(
                onTryAgain = {
                    showsUnsavedDialog = false
                    // The sets are still in the active-workout file: load the workout back so that Finish can save it again.
                    controller.restoreFromDisk()
                    if (controller.state.value != null) {
                        summaryWorkoutID = null
                        showsActiveWorkout = true
                    }
                },
                onDismiss = { showsUnsavedDialog = false },
            )
        }
    }
}

/**
 * Asks for the notification permission (Android 13+) the first time a workout is running, which is the moment the ongoing notification
 * and the rest alert become useful, instead of at launch. The question is asked once; afterwards Settings > Notifications is the way to
 * change the answer. Granting it shows the notification of the workout that is already running.
 */
@Composable
private fun AskForNotificationsWhenAWorkoutStarts(environment: StrengthAppEnvironment, hasWorkout: Boolean) {
    val services = environment.services
    val context = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) services?.onNotificationPermissionResult()
    }
    LaunchedEffect(hasWorkout) {
        if (!hasWorkout || services == null || Build.VERSION.SDK_INT < 33) return@LaunchedEffect
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        if (granted || services.settings.notificationPermissionAsked) return@LaunchedEffect
        services.settings.notificationPermissionAsked = true
        launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
}
