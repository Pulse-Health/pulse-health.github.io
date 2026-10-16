package health.pulse.strength

import android.content.Context
import health.pulse.strength.core.DemoRecovery
import health.pulse.strength.core.FileStrengthPersistence
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

    /** Asks the UI to show the active workout (no effect without a workout in progress). */
    fun requestOpenWorkout() {
        mutableOpenWorkoutRequests.tryEmit(Unit)
    }

    companion object {
        /** Builds the environment of the running app and restores a workout that was running when the process last ended. */
        fun live(context: Context, recovery: RecoveryProvider = DemoRecovery.provider): StrengthAppEnvironment {
            val persistence = FileStrengthPersistence(File(context.applicationContext.filesDir, "PulseStrength"))
            val store = StrengthStore(persistence, seedDemoData = false)
            val controller = WorkoutController(store, persistence, recovery)
            val services = PulseServices(context.applicationContext, controller)
            return StrengthAppEnvironment(persistence, store, controller, services)
        }

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
