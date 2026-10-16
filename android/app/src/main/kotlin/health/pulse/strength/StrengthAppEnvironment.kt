package health.pulse.strength

import android.content.Context
import health.pulse.strength.core.FileStrengthPersistence
import health.pulse.strength.core.RecoveryModel
import health.pulse.strength.core.RecoveryProvider
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.services.PulseServices
import java.io.File
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Everything the strength feature needs at runtime, created once and shared by the screens and the services: persistence
 * (the app's private `files/PulseStrength` folder), the store and the workout controller.
 *
 * The live environment is created by [PulseStrengthApplication] when the process starts, so a notification action that wakes the
 * process in the background finds the running workout already restored.
 */
class StrengthAppEnvironment private constructor(
    val persistence: FileStrengthPersistence,
    val store: StrengthStore,
    val controller: WorkoutController,
    /** The platform services (notification, rest alerts, Health Connect); null for [preview], which must not touch the system. */
    val services: PulseServices?,
) {
    /** False for [preview]: the platform services are inert and must not ask for permissions. */
    val hasSystemServices: Boolean get() = services != null

    private val mutableOpenWorkoutRequests = MutableSharedFlow<Unit>(extraBufferCapacity = 1)

    /** Emits when something outside the UI (the deep link, a notification tap) asks to show the running workout. */
    val openWorkoutRequests: SharedFlow<Unit> = mutableOpenWorkoutRequests.asSharedFlow()

    /** The screen that a widget, tile or notification link asked for; the root composable shows it and clears it. */
    val hostRequests = HostRequests()

    /** Asks the UI to show the active workout (no effect without a workout in progress). */
    fun requestOpenWorkout() {
        mutableOpenWorkoutRequests.tryEmit(Unit)
    }

    companion object {
        /**
         * Builds the environment of the running app. A real install starts empty: no demo templates or history, no invented "previous"
         * results on the library exercises, and recovery percentages worked out from the user's own finished workouts.
         */
        fun live(context: Context, recovery: ((StrengthStore) -> RecoveryProvider)? = null): StrengthAppEnvironment {
            val persistence = FileStrengthPersistence(File(context.applicationContext.filesDir, "PulseStrength"))
            val store = StrengthStore(persistence, seedDemoData = false, usesLibraryHistory = false)
            val provider = recovery?.invoke(store) ?: RecoveryModel({ store.history }).provider
            val controller = WorkoutController(store, persistence, provider)
            val services = PulseServices(context.applicationContext, controller)
            return StrengthAppEnvironment(persistence, store, controller, services)
        }

        /** An environment around ready-made parts, without platform services: for tests that need to control the store and the clock. */
        internal fun forParts(persistence: FileStrengthPersistence, store: StrengthStore, controller: WorkoutController) =
            StrengthAppEnvironment(persistence, store, controller, services = null)

        /** Temporary persistence with the sample data and no live services; optionally with a workout already running. */
        fun preview(withActiveWorkout: Boolean = false): StrengthAppEnvironment {
            val persistence = FileStrengthPersistence.temporary()
            val store = StrengthStore(persistence, seedDemoData = true)
            val controller = WorkoutController(store, persistence)
            if (withActiveWorkout) controller.startWorkout(store.templates.firstOrNull())
            return StrengthAppEnvironment(persistence, store, controller, services = null)
        }
    }
}
