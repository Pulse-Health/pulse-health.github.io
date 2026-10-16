package health.pulse.strength.core

import java.time.Instant

/**
 * The platform-neutral heart of [WorkoutController]: owns the workout in progress and runs every change through the reducer.
 *
 * The phone is the only authority: it saves the workout after every change and tells the registered side effects. Heart-rate
 * samples are applied to the in-memory state every time, but they are saved and reported to the effects at most once per
 * [heartRateInterval] seconds of the injected clock.
 *
 * Not thread safe: drive it from one thread (the main thread in the app).
 */
class WorkoutEngine(
    private val persistence: FileStrengthPersistence?,
    private val data: WorkoutDataProviding,
    /** Muscle recovery lookup used by [presentation]. */
    var recovery: RecoveryProvider = DemoRecovery.provider,
    private val clock: () -> Instant = { Instant.now() },
) {
    /** The workout in progress; null when there is none. */
    var state: WorkoutState? = null
        private set

    /** The workout finished most recently (cleared when the next one starts). */
    var lastCompleted: CompletedWorkout? = null
        private set

    /**
     * The error of the last failed attempt to save the active workout, or of a finished workout that could not be saved to the
     * history; null after a successful save.
     */
    var lastPersistenceError: Throwable? = null
        private set

    /** Called after [state] or [lastCompleted] changed and before the side effects are told. */
    var onUpdate: (() -> Unit)? = null

    /**
     * How the workout that ended most recently ended: true when it was thrown away, false when it was finished and recorded.
     * Set before [onUpdate] and the effects' `workoutEnded` run. Meaningless before the first workout ended.
     */
    var lastEndDiscarded: Boolean = false
        private set

    private val effects = mutableListOf<WorkoutSideEffect>()
    private var lastHeartRateReport: Instant? = null

    /** Registers a side effect (ignored when the same object is already registered). */
    fun addEffect(effect: WorkoutSideEffect) {
        if (effects.any { it === effect }) return
        effects.add(effect)
    }

    // region Lifecycle

    /**
     * Loads the saved active workout (if any) and tells the effects it was restored.
     *
     * Does nothing without persistence, without a saved workout, or while a workout is already in progress (the in-memory copy
     * can be newer than the file because heart-rate samples are saved only every few seconds).
     */
    fun restore() {
        if (state != null) return
        val persistence = persistence ?: return
        val restored = persistence.loadActiveWorkout() ?: return
        state = restored
        lastHeartRateReport = null
        onUpdate?.invoke()
        for (effect in effects.toList()) effect.workoutStarted(restored)
    }

    /**
     * Starts a workout from [template], or an empty one named [name] (default "Workout"), and tells the effects.
     *
     * Returns false (and changes nothing) while a workout is already in progress, so a double tap cannot replace a running workout.
     */
    fun start(template: WorkoutTemplate?, name: String? = null): Boolean {
        if (state != null) return false
        val now = clock()
        val started: WorkoutState = if (template != null) {
            val made = WorkoutFactory.makeWorkout(template, now)
            made.copy(exercises = made.exercises.map { it.copy(exercise = refreshed(it.exercise)) })
        } else {
            val trimmed = name?.trimmedFoundation() ?: ""
            WorkoutFactory.makeEmpty(if (trimmed.isEmpty()) StrengthConfig.defaultWorkoutName else trimmed, now)
        }
        state = started
        lastCompleted = null
        lastHeartRateReport = null
        persistActiveWorkout()
        onUpdate?.invoke()
        for (effect in effects.toList()) effect.workoutStarted(started)
        return true
    }

    /** Applies [action]: reduce, save, publish, tell the effects. A change-free action does nothing. */
    fun send(action: WorkoutAction, origin: ActionOrigin = ActionOrigin.PHONE) {
        val old = state ?: return
        val now = clock()
        val new = WorkoutReducer.reduce(old, action, now)
        if (new == old) return
        state = new

        if (action is WorkoutAction.UpdateHeartRate) {
            val last = lastHeartRateReport
            if (last != null && !now.isBefore(last) && now.timeIntervalSince(last) < heartRateInterval) {
                onUpdate?.invoke()
                return
            }
            lastHeartRateReport = now
        }

        persistActiveWorkout()
        onUpdate?.invoke()
        for (effect in effects.toList()) effect.workoutChanged(old, new, action, origin)
    }

    /**
     * Finishes the workout: builds the summary, records it (history, bests, template), clears the state and tells the effects.
     *
     * With [updateTemplate] the workout's template is rebuilt from the exercises as they are now. A workout with no logged set is
     * discarded instead (null is returned).
     *
     * The workout is finished (and returned) even when the history cannot be written. The saved active workout is then kept
     * instead of deleted and [lastPersistenceError] is set, so the logged sets are not lost: the next launch restores the workout
     * and finishing it again saves it (a workout is recorded by its id, so it is never saved twice). Starting another workout
     * replaces the kept file; until then the history is rewritten in full by the next successful save.
     */
    fun finish(updateTemplate: Boolean): CompletedWorkout? {
        val current = state ?: return null
        val completed = SummaryBuilder.build(current, clock())
        if (completed.loggedSets <= 0) {
            end(current, completed = null)
            return null
        }
        var updated: WorkoutTemplate? = null
        val templateID = current.templateID
        if (updateTemplate && templateID != null) {
            data.template(templateID)?.let { updated = WorkoutFactory.updatedTemplate(it, current) }
        }
        val saveFailure = data.record(completed, updated).exceptionOrNull()
        lastCompleted = completed
        end(current, completed = completed, unsavedBecause = saveFailure)
        return completed
    }

    /** Throws the workout away without recording it and tells the effects (`completed == null`). */
    fun discard() {
        val current = state ?: return
        end(current, completed = null)
    }

    // endregion

    // region Derived values

    /** The active-workout screen model for [now]; null without a workout. */
    fun presentation(now: Instant): ActiveWorkoutPresentation? = state?.let { WorkoutPresenter.present(it, now, recovery) }

    /** The notification snapshot for [now]; null without a workout. */
    fun snapshot(now: Instant): WorkoutSnapshot? = state?.let { SnapshotBuilder.make(it, now) }

    /** What changed against the template the workout started from (empty without a workout). */
    fun templateDiff(): TemplateDiff = state?.let { TemplateDiff.compute(it) } ?: TemplateDiff()

    // endregion

    // region Helpers

    /**
     * Ends the workout. With [unsavedBecause] (the finished workout could not be written to the history) the active-workout file
     * is left alone: it still holds the workout's sets and is the only copy on disk.
     */
    private fun end(previous: WorkoutState, completed: CompletedWorkout?, unsavedBecause: Throwable? = null) {
        lastEndDiscarded = completed == null
        state = null
        lastHeartRateReport = null
        if (unsavedBecause != null) {
            lastPersistenceError = unsavedBecause
        } else {
            persistActiveWorkout()
        }
        onUpdate?.invoke()
        for (effect in effects.toList()) effect.workoutEnded(previous, completed)
    }

    /** Writes the active workout (or deletes the file when there is none). */
    private fun persistActiveWorkout() {
        val persistence = persistence ?: return
        try {
            persistence.saveActiveWorkout(state)
            lastPersistenceError = null
        } catch (error: Exception) {
            lastPersistenceError = error
        }
    }

    /** The template's exercise with the latest remembered best and last sets (everything else stays as the template has it). */
    private fun refreshed(exercise: Exercise): Exercise {
        val latest = data.exercise(exercise.id) ?: return exercise
        return exercise.copy(previousBestE1RM = latest.previousBestE1RM, previousSets = latest.previousSets)
    }

    // endregion

    companion object {
        /** Minimum time between saving / reporting two heart-rate-only changes (10 seconds). */
        const val heartRateInterval: Double = 10.0
    }
}
