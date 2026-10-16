package health.pulse.strength.wear.ui

import android.Manifest
import android.content.Context
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.platform.LocalContext
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.wear.data.WearCommands
import health.pulse.strength.wear.data.WearRuntime
import health.pulse.strength.wear.ongoing.OngoingWorkout
import health.pulse.strength.wear.sync.SnapshotIngest
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

private const val NOTICE_MILLIS = 4_000L
private const val START_TIMEOUT_MILLIS = 8_000L
private const val NO_PHONE = "Your phone is not reachable."
private const val NOT_STARTED = "Your phone did not start the workout."
private const val PREFS = "watch_app"
private const val KEY_NOTIFICATIONS_ASKED = "notifications_asked"

/**
 * Connects [WearScreen] to the runtime: the snapshot from the phone, the clock, the commands, and the "start the next workout" request
 * that a tile or complication hands to the activity ([startRequests] counts them).
 */
@Composable
internal fun WearRoot(startRequests: StateFlow<Int>) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snapshot by WearRuntime.snapshot.collectAsState()
    val placeholder by WearRuntime.isPlaceholder.collectAsState()
    var starting by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }

    val workoutRuns = !placeholder && snapshot.active != null
    val now by rememberNow(enabled = workoutRuns)

    // The app can be opened before the phone ever pushed anything (it was installed later): ask the Data Layer once.
    LaunchedEffect(Unit) { SnapshotIngest.ensureData(context) }
    NotificationPermission(workoutRuns)
    LaunchedEffect(notice) {
        if (notice != null) {
            delay(NOTICE_MILLIS)
            notice = null
        }
    }

    val startNextWorkout: () -> Unit = {
        scope.launch {
            val view = WearRuntime.view()
            if (!starting && !view.isPlaceholder && view.snapshot.active == null) {
                starting = true
                if (WearRuntime.send(WearCommands.startNext())) {
                    withTimeoutOrNull(START_TIMEOUT_MILLIS) { WearRuntime.snapshot.first { it.active != null } }
                    if (WearRuntime.current().active == null) notice = NOT_STARTED
                } else {
                    notice = NO_PHONE
                }
                starting = false
            }
        }
    }
    val requests by startRequests.collectAsState()
    LaunchedEffect(requests) { if (requests > 0) startNextWorkout() }

    WearScreen(
        state = WearUiState(snapshot, placeholder, now, starting, notice),
        onCommand = { command ->
            if (command.name == WidgetCommands.START_NEXT) {
                startNextWorkout()
            } else {
                scope.launch { if (!WearRuntime.send(command)) notice = NO_PHONE }
            }
        },
    )
}

/**
 * Wear OS 4 asks for the notification permission at runtime, and the Ongoing Activity chip on the watch face is a notification: ask once,
 * when a workout is running and the user can see why.
 */
@Composable
private fun NotificationPermission(workoutRuns: Boolean) {
    val context = LocalContext.current
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) OngoingWorkout.sync(context, WearRuntime.current().active)
    }
    LaunchedEffect(workoutRuns) {
        if (workoutRuns && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !OngoingWorkout.mayNotify(context) && !asked(context)) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_NOTIFICATIONS_ASKED, true).apply()
            launcher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}

private fun asked(context: Context): Boolean =
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_NOTIFICATIONS_ASKED, false)
