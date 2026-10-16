package health.pulse.strength.runtime

import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.preview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** The idealised preview snapshot with commands that do nothing: what a surface shows before real data exists, and in previews and tests. */
class PreviewRuntime(initial: WidgetSnapshot = WidgetSnapshot.preview) : StrengthRuntime.Runtime {
    private val state = MutableStateFlow(initial)

    override val snapshots: SnapshotSource = object : SnapshotSource {
        override val snapshot: StateFlow<WidgetSnapshot> = state.asStateFlow()
    }

    /** Every command received, in order (tests read it). */
    val received = mutableListOf<String>()

    override val commands: WorkoutCommands = object : WorkoutCommands {
        override suspend fun startNext() { received += "startNext" }
        override suspend fun startTemplate(templateId: String) { received += "startTemplate:$templateId" }
        override suspend fun startEmpty(name: String) { received += "startEmpty:$name" }
        override suspend fun logNextSet() { received += "logNextSet" }
        override suspend fun logSet(exerciseId: String, setId: String) { received += "logSet:$exerciseId:$setId" }
        override suspend fun nudge(weightSteps: Int, repsSteps: Int) { received += "nudge:$weightSteps:$repsSteps" }
        override suspend fun adjustRest(seconds: Int) { received += "adjustRest:$seconds" }
        override suspend fun skipRest() { received += "skipRest" }
        override suspend fun pause() { received += "pause" }
        override suspend fun resume() { received += "resume" }
        override suspend fun finish() { received += "finish" }
        override suspend fun applyCoachTip(setId: String, weightKg: Double) { received += "applyCoachTip:$setId:$weightKg" }
    }

    /** Test/preview hook: publishes another snapshot. */
    fun publish(snapshot: WidgetSnapshot) {
        state.value = snapshot
    }
}
