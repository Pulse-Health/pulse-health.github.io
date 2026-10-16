package health.pulse.strength

import health.pulse.strength.core.widgets.StrengthDeepLink
import health.pulse.strength.runtime.StrengthRuntime
import health.pulse.strength.runtime.WorkoutCommands

/**
 * Applies a [StrengthDeepLink] that a widget, tile, notification or the launcher opened: starts the workout the link names, then asks the
 * UI to show the matching screen. Starting goes through the same commands as the widget buttons, so a link and a button behave alike
 * (a link never starts a second workout while one runs: the command is ignored and the running one is shown).
 */
class DeepLinkRouter(
    private val environment: StrengthAppEnvironment,
    private val commands: () -> WorkoutCommands = { StrengthRuntime.commands },
) {
    suspend fun open(link: StrengthDeepLink) {
        when (link) {
            // The Android workout screen shows the plates on the set card; there is no separate plate calculator page to open.
            StrengthDeepLink.Workout, StrengthDeepLink.Plates -> showWorkoutOrHub()
            StrengthDeepLink.StartNext -> {
                commands().startNext()
                showWorkoutOrHub()
            }
            is StrengthDeepLink.Start -> {
                commands().startTemplate(link.templateId.toString())
                showWorkoutOrHub()
            }
            is StrengthDeepLink.StartEmpty -> {
                commands().startEmpty(link.name)
                showWorkoutOrHub()
            }
            is StrengthDeepLink.Exercise -> environment.hostRequests.post(HostRequest.OpenExercise(link.id))
            // The app keeps no body weight yet, so the weigh-in link lands on the hub.
            StrengthDeepLink.Hub, StrengthDeepLink.Weight -> environment.hostRequests.post(HostRequest.OpenHub)
        }
    }

    private fun showWorkoutOrHub() {
        val request = if (environment.controller.state.value != null) HostRequest.OpenWorkout else HostRequest.OpenHub
        environment.hostRequests.post(request)
    }
}
