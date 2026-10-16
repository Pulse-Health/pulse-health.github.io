package health.pulse.strength

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** A screen that something outside the UI (a widget, a tile, a notification, the launcher) asked the app to show. */
sealed interface HostRequest {
    /** The running workout. */
    data object OpenWorkout : HostRequest

    /** The Strength hub, with every layer above it closed. */
    data object OpenHub : HostRequest

    /** The detail of one exercise. */
    data class OpenExercise(val exerciseID: String) : HostRequest
}

/**
 * The request to show a screen, kept until the root composable has shown it. A link that cold-starts the app is posted before the
 * first composition exists, so it cannot be a plain event: a flow without replay would drop it.
 */
class HostRequests {
    private val pending = MutableStateFlow<HostRequest?>(null)

    val current: StateFlow<HostRequest?> = pending.asStateFlow()

    fun post(request: HostRequest) {
        pending.value = request
    }

    /** Clears [request] once it was shown; a newer request that arrived meanwhile stays. */
    fun consume(request: HostRequest) {
        pending.compareAndSet(request, null)
    }
}
