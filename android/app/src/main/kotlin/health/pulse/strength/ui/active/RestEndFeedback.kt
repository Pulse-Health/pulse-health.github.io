package health.pulse.strength.ui.active

import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import health.pulse.strength.core.ActiveWorkoutPresentation
import health.pulse.strength.ui.components.rememberPulseHaptics

/**
 * Whether the running workout has "Alert when rest ends" on. [WorkoutInProgressBar] has only the presentation to go by, so a host
 * that knows the setting provides it here (`controller.state.value?.settings?.alertWhenRestEnds`); the default is the setting's
 * default (on).
 */
val LocalRestAlertsEnabled = compositionLocalOf { true }

/** What happens when a rest ends: a success haptic and a screen-reader announcement. */
internal fun interface RestEndPlayer {
    fun play()
}

/** Replaces the real haptic + announcement (tests). */
internal val LocalRestEndPlayer = compositionLocalOf<RestEndPlayer?> { null }

/**
 * The foreground cue for the end of a rest (port of `RestEndFeedback.swift`): a success haptic and a TalkBack "Rest over"
 * announcement.
 *
 * The system notification at the rest end is not shown while the app is in the foreground, so this is what tells the user,
 * wherever the rest dock is not the thing on screen: the active-workout screen plays it while it is open and
 * [WorkoutInProgressBar] while the workout is minimised. The two are never on screen together, so it fires once.
 */
internal object RestEndFeedback {
    const val Announcement = "Rest over"

    /**
     * True when the dock phase turned from RUNNING to FINISHED, the app is in the foreground (lifecycle RESUMED) and the workout
     * has "Alert when rest ends" on.
     */
    fun shouldPlay(
        oldPhase: ActiveWorkoutPresentation.DockPhase?,
        newPhase: ActiveWorkoutPresentation.DockPhase?,
        isForeground: Boolean,
        alertsEnabled: Boolean,
    ): Boolean =
        oldPhase == ActiveWorkoutPresentation.DockPhase.RUNNING &&
            newPhase == ActiveWorkoutPresentation.DockPhase.FINISHED &&
            isForeground &&
            alertsEnabled
}

/** The haptic + announcement of a finished rest. */
@Composable
internal fun rememberRestEndPlayer(): RestEndPlayer {
    LocalRestEndPlayer.current?.let { return it }
    val haptics = rememberPulseHaptics()
    val view = LocalView.current
    return remember(haptics, view) {
        RestEndPlayer {
            haptics.success()
            announce(view, RestEndFeedback.Announcement)
        }
    }
}

@Suppress("DEPRECATION")
private fun announce(view: View, text: String) {
    view.announceForAccessibility(text)
}

private class PhaseHolder(var phase: ActiveWorkoutPresentation.DockPhase?)

/**
 * Plays [RestEndFeedback] when [phase] turns from RUNNING to FINISHED while this composable is in the composition and the app is in
 * the foreground. Call it with the current dock phase (null without a dock) from the screen and from the in-progress bar.
 */
@Composable
internal fun RestEndFeedbackEffect(
    phase: ActiveWorkoutPresentation.DockPhase?,
    alertsEnabled: Boolean,
) {
    val player = rememberRestEndPlayer()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val previous = remember { PhaseHolder(phase) }
    val currentAlerts by rememberUpdatedState(alertsEnabled)
    val currentPlayer by rememberUpdatedState(player)
    LaunchedEffect(phase) {
        val old = previous.phase
        previous.phase = phase
        val foreground = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
        if (RestEndFeedback.shouldPlay(old, phase, foreground, currentAlerts)) currentPlayer.play()
    }
}
