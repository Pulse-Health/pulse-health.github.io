package health.pulse.strength.core

import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The observable face of a workout in progress, used by the screens and the platform services.
 *
 * A thin wrapper around [WorkoutEngine]: the engine does the work (reduce, save, effects) and this class republishes its state as
 * flows. Drive it from the main thread.
 */
class WorkoutController(
    /** The store that holds templates, history and exercises. */
    val store: StrengthStore,
    persistence: FileStrengthPersistence?,
    recovery: RecoveryProvider = DemoRecovery.provider,
    clock: () -> Instant = { Instant.now() },
) {
    private val engine = WorkoutEngine(persistence, StoreDataAdapter(store), recovery, clock)
    private val mutableState = MutableStateFlow(engine.state)
    private val mutableLastCompleted = MutableStateFlow(engine.lastCompleted)
    private val mutablePersistenceError = MutableStateFlow(engine.lastPersistenceError)

    /** The workout in progress; null when there is none. */
    val state: StateFlow<WorkoutState?> = mutableState.asStateFlow()

    /** The workout finished most recently (cleared when the next one starts). */
    val lastCompleted: StateFlow<CompletedWorkout?> = mutableLastCompleted.asStateFlow()

    /** Muscle recovery lookup used by [presentation]. */
    var recovery: RecoveryProvider
        get() = engine.recovery
        set(value) {
            engine.recovery = value
        }

    /** True when the last attempt to save the workout in progress (or a finished workout) failed. */
    val lastPersistenceError: Throwable? get() = engine.lastPersistenceError

    /**
     * The error of the last failed attempt to save the workout in progress (or a finished one); null again after a save worked.
     * The screens use it to tell the user that the workout is not safe on disk (a full phone).
     */
    val persistenceError: StateFlow<Throwable?> = mutablePersistenceError.asStateFlow()

    /** How the workout that ended most recently ended (true = thrown away). Read it from `WorkoutSideEffect.workoutEnded`. */
    val lastEndDiscarded: Boolean get() = engine.lastEndDiscarded

    init {
        engine.onUpdate = { republish() }
    }

    /** Registers a side effect (notification, rest alert, Health Connect) that is told about every change. */
    fun addEffect(effect: WorkoutSideEffect) = engine.addEffect(effect)

    /** On launch: reloads the active workout from disk and tells the effects. */
    fun restoreFromDisk() = engine.restore()

    /** Starts a workout from [template], or an empty one named `name ?: "Workout"`; ignored while a workout is in progress. */
    fun startWorkout(template: WorkoutTemplate?, name: String? = null): Boolean = engine.start(template, name)

    /** Applies [action]: reduce, save, publish, tell the effects. */
    fun send(action: WorkoutAction, origin: ActionOrigin = ActionOrigin.PHONE) = engine.send(action, origin)

    /** The active-workout screen model for [now]; null without a workout. */
    fun presentation(now: Instant): ActiveWorkoutPresentation? = engine.presentation(now)

    /** The notification snapshot for [now]; null without a workout. */
    fun snapshot(now: Instant): WorkoutSnapshot? = engine.snapshot(now)

    /** What changed against the template the workout started from. */
    fun templateDiff(): TemplateDiff = engine.templateDiff()

    /** Finishes the workout: builds the summary, records it in the store, clears the state and tells the effects. */
    fun finish(updateTemplate: Boolean): CompletedWorkout? = engine.finish(updateTemplate)

    /** Throws the workout away without recording it. */
    fun discard() = engine.discard()

    /** Copies the engine's values into the flows (a flow only emits when the value changed). */
    private fun republish() {
        mutableState.value = engine.state
        mutableLastCompleted.value = engine.lastCompleted
        mutablePersistenceError.value = engine.lastPersistenceError
    }

    /** Lets the engine use the store's public API, so every recorded workout also refreshes the store's flows. */
    private class StoreDataAdapter(private val store: StrengthStore) : WorkoutDataProviding {
        override fun exercise(id: String): Exercise? = store.exercise(id)
        override fun template(id: java.util.UUID): WorkoutTemplate? = store.data.value.template(id)
        override fun record(completed: CompletedWorkout, updateTemplate: WorkoutTemplate?): Result<Unit> =
            store.record(completed, updateTemplate)
    }
}
