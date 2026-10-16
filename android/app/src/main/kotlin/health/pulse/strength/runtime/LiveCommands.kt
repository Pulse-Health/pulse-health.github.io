package health.pulse.strength.runtime

import health.pulse.strength.core.ActionOrigin
import health.pulse.strength.core.SnapshotBuilder
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.core.widgets.WidgetSnapshotBuilder
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext

/**
 * The commands of the surfaces (widgets/SPEC.md section 5), applied to the workout controller.
 *
 * The store and the controller belong to the main thread, so every change runs there. A command returns after the change is applied and
 * [publish] has brought the snapshot up to date, so a surface that redraws right after it already shows the effect. The workout
 * buttons do what the buttons of the ongoing notification do (`NotificationActionReceiver`): the same actions with the same limits,
 * from the origin `LIVE_ACTIVITY`.
 */
internal class LiveCommands(
    private val store: StrengthStore,
    private val controller: WorkoutController,
    private val main: CoroutineDispatcher,
    private val clock: () -> Instant,
    private val publish: suspend () -> Unit,
) : WorkoutCommands {
    override suspend fun startNext() = perform { controller.startWorkout(WidgetSnapshotBuilder.nextTemplate(store.templates)) }

    override suspend fun startTemplate(templateId: String) = perform {
        val id = uuid(templateId) ?: return@perform
        store.templates.firstOrNull { it.id == id }?.let { controller.startWorkout(it) }
    }

    override suspend fun startEmpty(name: String) = perform { controller.startWorkout(null, name) }

    override suspend fun logNextSet() = perform { send(WorkoutAction.LogNextSet) }

    override suspend fun logSet(exerciseId: String, setId: String) = perform {
        val exercise = uuid(exerciseId) ?: return@perform
        val set = uuid(setId) ?: return@perform
        send(WorkoutAction.LogSet(exercise, set))
    }

    override suspend fun nudge(weightSteps: Int, repsSteps: Int) =
        perform { send(WorkoutAction.NudgeNextSet(weightSteps.coerceIn(-1, 1), repsSteps.coerceIn(-1, 1))) }

    override suspend fun adjustRest(seconds: Int) = perform { send(WorkoutAction.AdjustRest(seconds.coerceIn(-60, 60))) }

    override suspend fun skipRest() = perform { send(WorkoutAction.SkipRest) }

    override suspend fun pause() = perform { send(WorkoutAction.Pause) }

    override suspend fun resume() = perform { send(WorkoutAction.Resume) }

    /** Records the workout as it is; a widget never updates the template behind the user's back. */
    override suspend fun finish() = perform { controller.finish(updateTemplate = false) }

    /** Sets the weight of the set the tip names; the weight is absolute, so a repeated tap changes nothing more. */
    override suspend fun applyCoachTip(setId: String, weightKg: Double) = perform {
        val set = uuid(setId) ?: return@perform
        if (!weightKg.isFinite() || weightKg <= 0) return@perform
        val exercise = controller.state.value?.exercises?.firstOrNull { entry -> entry.sets.any { it.id == set } } ?: return@perform
        send(WorkoutAction.SetWeight(exercise.id, set, weightKg))
    }

    /** Decides on the running workout itself, not on the published snapshot, which a second tap right after the first may still find unchanged. */
    override suspend fun primaryAction() = perform {
        val state = controller.state.value
        when {
            state == null -> controller.startWorkout(WidgetSnapshotBuilder.nextTemplate(store.templates))
            SnapshotBuilder.make(state, clock()).phase == SnapshotPhase.RESTING -> send(WorkoutAction.SkipRest)
            else -> send(WorkoutAction.LogNextSet)
        }
    }

    private suspend fun perform(change: () -> Unit) {
        withContext(main) { change() }
        publish()
    }

    private fun send(action: WorkoutAction) = controller.send(action, ActionOrigin.LIVE_ACTIVITY)

    /** Null for a text that is not an id, so a damaged command is ignored instead of crashing the app. */
    private fun uuid(text: String): UUID? = try {
        UUID.fromString(text)
    } catch (_: IllegalArgumentException) {
        null
    }
}
