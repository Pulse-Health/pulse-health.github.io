package health.pulse.strength.core

import java.time.Instant
import java.util.UUID

/** What the workout engine needs from the app's saved data: exercise lookups and a place to record finished workouts. */
interface WorkoutDataProviding {
    /** The exercise with the remembered previous results overlaid, or null for an unknown id. */
    fun exercise(id: String): Exercise?

    /** The saved template with the given id. */
    fun template(id: UUID): WorkoutTemplate?

    /**
     * Records a finished workout (history, personal bests, template `lastPerformed`) and replaces [updateTemplate] when given.
     *
     * The data changes in memory in every case. The result is a failure when the workout could not be saved to disk (its history
     * file); the engine then keeps the active-workout file, the last saved copy of the workout.
     */
    fun record(completed: CompletedWorkout, updateTemplate: WorkoutTemplate?): Result<Unit>
}

/**
 * A [StrengthData] bound to a [FileStrengthPersistence]: loads on creation, saves what a change touched, caches the exercise overlay.
 *
 * Not thread safe: drive it from one thread (the main thread in the app).
 */
class StrengthDataModel(
    private val persistence: FileStrengthPersistence?,
    seedDemoData: Boolean = false,
    now: Instant = Instant.now(),
    /** See [StrengthData.usesLibraryHistory]; a real install passes false. */
    private val usesLibraryHistory: Boolean = true,
) : WorkoutDataProviding {
    /** The current data. */
    var data: StrengthData = StrengthData(usesLibraryHistory = usesLibraryHistory)
        private set

    /** The first error of the last save that failed; null when the last save wrote every file it was asked to write. */
    var lastPersistenceError: Throwable? = null
        private set

    private class Overlay(val list: List<Exercise>, val byID: Map<String, Exercise>)

    private var cache: Overlay? = null

    init {
        loadFromDisk()
        if (seedDemoData) {
            val seeded = data.seedingDemoDataIfEmpty(now)
            if (seeded != data) {
                data = seeded
                cache = null
                persist(templates = true, history = true, customExercises = false, personalBests = true)
            }
        }
    }

    /** The built-in and custom exercises with the user's previous results overlaid (cached until the next change). */
    val exercises: List<Exercise> get() = overlayCache().list

    /** One exercise by id (built-in or custom) with the user's previous results overlaid. */
    override fun exercise(id: String): Exercise? = overlayCache().byID[id]

    /** One template by id. */
    override fun template(id: UUID): WorkoutTemplate? = data.template(id)

    /** Adds a custom exercise and saves the custom exercises. */
    fun addCustomExercise(exercise: Exercise) {
        val before = data.customExercises
        data = data.addingCustomExercise(exercise)
        if (data.customExercises == before) return
        cache = null
        persist(templates = false, history = false, customExercises = true, personalBests = false)
    }

    /** Adds or replaces a template and saves the templates. */
    fun saveTemplate(template: WorkoutTemplate) {
        data = data.savingTemplate(template)
        persist(templates = true, history = false, customExercises = false, personalBests = false)
    }

    /**
     * Records a finished workout (history, personal bests, template) and saves what changed.
     *
     * The data changes in memory in every case. The result is a failure when the workout could not be written to the history
     * file, which is the only place the workout's sets are kept; the other files are derived (the personal bests are re-read from
     * the history) or secondary (the template), so failing to write them is reported through [lastPersistenceError] only.
     * Every file is rewritten in full by its next save, so unsaved data is saved then.
     */
    override fun record(completed: CompletedWorkout, updateTemplate: WorkoutTemplate?): Result<Unit> {
        data = data.recording(completed, updateTemplate)
        cache = null
        val historyError = persist(templates = true, history = true, customExercises = false, personalBests = true)
        return if (historyError != null) Result.failure(historyError) else Result.success(Unit)
    }

    /** The history of one exercise as shown on its detail screen. */
    fun history(exerciseID: String, now: Instant): ExerciseHistory = data.history(exerciseID, now)

    /** Re-reads everything from disk (no-op without persistence). */
    fun reload() {
        if (persistence == null) return
        loadFromDisk()
    }

    private fun loadFromDisk() {
        val persistence = persistence ?: return
        data = StrengthData(
            templates = persistence.loadTemplates(),
            history = persistence.loadHistory(),
            customExercises = persistence.loadCustomExercises(),
            personalBests = persistence.loadPersonalBests(),
            usesLibraryHistory = usesLibraryHistory,
        )
        cache = null
    }

    private fun overlayCache(): Overlay {
        cache?.let { return it }
        val list = data.exercises()
        val overlay = Overlay(list, list.associateBy { it.id })
        cache = overlay
        return overlay
    }

    /**
     * Writes the requested files, attempting every one even when an earlier one fails.
     *
     * Sets [lastPersistenceError] to the first error (null when every requested file was written) and returns the error of the
     * history file, null when it was written or not requested.
     */
    private fun persist(templates: Boolean, history: Boolean, customExercises: Boolean, personalBests: Boolean): Throwable? {
        val persistence = persistence
        if (persistence == null) {
            lastPersistenceError = null
            return null
        }
        var firstError: Throwable? = null
        var historyError: Throwable? = null
        fun attempt(write: () -> Unit): Throwable? = try {
            write()
            null
        } catch (error: Exception) {
            if (firstError == null) firstError = error
            error
        }
        if (templates) attempt { persistence.saveTemplates(data.templates) }
        if (history) historyError = attempt { persistence.saveHistory(data.history) }
        if (customExercises) attempt { persistence.saveCustomExercises(data.customExercises) }
        if (personalBests) attempt { persistence.savePersonalBests(data.personalBests) }
        lastPersistenceError = firstError
        return historyError
    }
}
