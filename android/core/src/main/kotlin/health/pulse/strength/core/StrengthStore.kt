package health.pulse.strength.core

import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The observable store behind the screens: templates, history, custom exercises and personal bests.
 *
 * A thin wrapper around [StrengthDataModel] (which holds [StrengthData] and the persistence): every change is forwarded to the
 * model and the published [data] is refreshed. Drive it from the main thread.
 */
class StrengthStore(
    persistence: FileStrengthPersistence?,
    seedDemoData: Boolean = false,
    now: Instant = Instant.now(),
    /** See [StrengthData.usesLibraryHistory]; a real install passes false. */
    usesLibraryHistory: Boolean = true,
) {
    private val model = StrengthDataModel(persistence, seedDemoData, now, usesLibraryHistory)
    private val mutableData = MutableStateFlow(model.data)

    /** Everything remembered between workouts; emits when it changes. */
    val data: StateFlow<StrengthData> = mutableData.asStateFlow()

    /** Saved workout templates. */
    val templates: List<WorkoutTemplate> get() = data.value.templates

    /** Finished workouts, newest first. */
    val history: List<CompletedWorkout> get() = data.value.history

    /** Exercises the user created. */
    val customExercises: List<Exercise> get() = data.value.customExercises

    /** Best estimated 1RM per exercise id. */
    val personalBests: Map<String, PersonalBest> get() = data.value.personalBests

    /** The first error of the last save that failed; null when the last save wrote every file it was asked to write. */
    val lastPersistenceError: Throwable? get() = model.lastPersistenceError

    /** The built-in and custom exercises with `previousBestE1RM` / `previousSets` overlaid from personal bests and history. */
    val exercises: List<Exercise> get() = model.exercises

    /** One exercise (built-in or custom) with the previous results overlaid; null for an unknown id. */
    fun exercise(id: String): Exercise? = model.exercise(id)

    /** Adds a custom exercise and saves it. */
    fun addCustomExercise(exercise: Exercise) {
        model.addCustomExercise(exercise)
        publish()
    }

    /** Adds a template, or replaces the one with the same id, and saves it. */
    fun saveTemplate(template: WorkoutTemplate) {
        model.saveTemplate(template)
        publish()
    }

    /**
     * Records a finished workout: history (newest first), personal bests, the template's `lastPerformed`, and [updateTemplate] when given.
     *
     * The store changes in every case; the result is a failure when the workout could not be written to the history file.
     */
    fun record(completed: CompletedWorkout, updateTemplate: WorkoutTemplate?): Result<Unit> {
        val result = model.record(completed, updateTemplate)
        publish()
        return result
    }

    /** The sessions, trend, records and 30-day totals of one exercise, relative to [now]. */
    fun history(exerciseID: String, now: Instant): ExerciseHistory = model.history(exerciseID, now)

    /** Re-reads everything from disk. */
    fun reload() {
        model.reload()
        publish()
    }

    private fun publish() {
        mutableData.value = model.data
    }
}
