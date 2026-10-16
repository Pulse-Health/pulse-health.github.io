package health.pulse.strength.runtime

import android.content.Context
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.core.widgets.WidgetSnapshot
import kotlinx.coroutines.flow.StateFlow

/** Where every surface (widget, tile, notification, ...) reads the current [WidgetSnapshot]. */
interface SnapshotSource {
    /** Emits a new snapshot whenever data or the running workout changes. Never empty: uses the preview until real data exists. */
    val snapshot: StateFlow<WidgetSnapshot>

    fun current(): WidgetSnapshot = snapshot.value
}

/** What a surface may ask the workout engine to do (widgets/SPEC.md section 5). Every call returns after the change is applied. */
interface WorkoutCommands {
    suspend fun startNext()
    suspend fun startTemplate(templateId: String)
    suspend fun startEmpty(name: String)
    suspend fun logNextSet()
    suspend fun logSet(exerciseId: String, setId: String)
    suspend fun nudge(weightSteps: Int, repsSteps: Int)
    suspend fun adjustRest(seconds: Int)
    suspend fun skipRest()
    suspend fun pause()
    suspend fun resume()
    suspend fun finish()
    suspend fun applyCoachTip(setId: String, weightKg: Double)

    /** Log set while logging, skip rest while resting, start the next workout with none running. */
    suspend fun primaryAction() {
        val active = StrengthRuntime.snapshots.current().active
        when {
            active == null -> startNext()
            active.phase == health.pulse.strength.core.SnapshotPhase.RESTING -> skipRest()
            else -> logNextSet()
        }
    }

    /** Runs a command that arrived as data (a Wear message, a notification extra). Unknown names are ignored. */
    suspend fun execute(command: WidgetCommand) {
        val args = command.args
        when (command.name) {
            WidgetCommands.START_NEXT -> startNext()
            WidgetCommands.START_TEMPLATE -> args[WidgetCommands.ARG_TEMPLATE_ID]?.let { startTemplate(it) }
            WidgetCommands.START_EMPTY -> startEmpty(args[WidgetCommands.ARG_NAME] ?: "Workout")
            WidgetCommands.LOG_NEXT_SET -> logNextSet()
            WidgetCommands.LOG_SET -> {
                val exercise = args[WidgetCommands.ARG_EXERCISE_ID]
                val set = args[WidgetCommands.ARG_SET_ID]
                if (exercise != null && set != null) logSet(exercise, set)
            }
            WidgetCommands.NUDGE -> nudge(
                args[WidgetCommands.ARG_WEIGHT_STEPS]?.toIntOrNull() ?: 0,
                args[WidgetCommands.ARG_REPS_STEPS]?.toIntOrNull() ?: 0,
            )
            WidgetCommands.ADJUST_REST -> adjustRest(args[WidgetCommands.ARG_SECONDS]?.toIntOrNull() ?: 0)
            WidgetCommands.SKIP_REST -> skipRest()
            WidgetCommands.PAUSE -> pause()
            WidgetCommands.RESUME -> resume()
            WidgetCommands.FINISH -> finish()
            WidgetCommands.APPLY_COACH_TIP -> {
                val set = args[WidgetCommands.ARG_SET_ID]
                val kg = args[WidgetCommands.ARG_WEIGHT_KG]?.toDoubleOrNull()
                if (set != null && kg != null) applyCoachTip(set, kg)
            }
            WidgetCommands.PRIMARY_ACTION -> primaryAction()
        }
    }
}

/**
 * The single entry point of the app's data layer for every surface. [init] runs once from `PulseApp`. Until the real runtime
 * (the owner `core`) replaces [PreviewRuntime], everything works on the idealised preview snapshot so surfaces can be built and
 * looked at independently.
 */
object StrengthRuntime {
    @Volatile
    private var instance: Runtime = PreviewRuntime()

    val snapshots: SnapshotSource get() = instance.snapshots
    val commands: WorkoutCommands get() = instance.commands

    interface Runtime {
        val snapshots: SnapshotSource
        val commands: WorkoutCommands
    }

    /** Called from `Application.onCreate`. Safe to call again (the first call wins). */
    @Synchronized
    fun init(context: Context) {
        if (initialised) return
        initialised = true
        instance = RuntimeFactory.create(context.applicationContext)
    }

    private var initialised = false

    /** Test hook: replaces the runtime. */
    fun installForTest(runtime: Runtime) {
        instance = runtime
        initialised = true
    }
}
