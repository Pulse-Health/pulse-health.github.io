package health.pulse.strength.runtime

import android.content.Context
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.core.widgets.WidgetSnapshot
import kotlinx.coroutines.flow.StateFlow

/** Where every surface (widget, tile, notification, ...) reads the current [WidgetSnapshot]. */
interface SnapshotSource {
    /** Emits a new snapshot whenever what it shows changes (data, settings, the running workout, the day). Never empty: a store without data gives the snapshot of an empty week. */
    val snapshot: StateFlow<WidgetSnapshot>

    fun current(): WidgetSnapshot = snapshot.value
}

/** What a surface may ask the workout engine to do (widgets/SPEC.md section 5). Every call returns after the change is applied and the snapshot shows it. */
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
 * The single entry point of the app's data layer for every surface. [init] runs once from `PulseStrengthApplication`: the running app
 * then works on a [LiveRuntime]; until then, and in previews and tests, everything works on the idealised preview snapshot of
 * [PreviewRuntime], so surfaces can be built and looked at independently.
 */
object StrengthRuntime {
    @Volatile
    private var instance: Runtime = PreviewRuntime()

    val snapshots: SnapshotSource get() = instance.snapshots
    val commands: WorkoutCommands get() = instance.commands

    /**
     * Brings the snapshot up to date with the clock, the time zone and the data, and publishes it. For whoever knows that time moved
     * (the receiver for the new day, a changed clock or time zone, a restart of the device or an update of the app); the surfaces are
     * not told, the caller does that with `Surfaces.refreshAll`.
     */
    suspend fun rebuild() = instance.rebuild()

    interface Runtime {
        val snapshots: SnapshotSource
        val commands: WorkoutCommands

        /** Recomputes the snapshot for the current clock, time zone and data and publishes it; does not refresh the surfaces. Nothing to do for a runtime without a clock. */
        suspend fun rebuild() {}
    }

    /** Called from `Application.onCreate`. Safe to call again (the first call wins). */
    @Synchronized
    fun init(context: Context) {
        if (initialised) return
        initialised = true
        instance = RuntimeFactory.create(context.applicationContext)
    }

    private var initialised = false

    /** Test hook: replaces the runtime. A [LiveRuntime] that is replaced stops following the app, so it cannot refresh surfaces during a later test. */
    @Synchronized
    fun installForTest(runtime: Runtime) {
        val replaced = instance
        if (replaced !== runtime && replaced is LiveRuntime) replaced.close()
        instance = runtime
        initialised = true
    }
}
