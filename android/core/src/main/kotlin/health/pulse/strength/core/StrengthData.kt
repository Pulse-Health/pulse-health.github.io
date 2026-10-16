package health.pulse.strength.core

import java.time.Instant
import java.util.UUID

// region Pure data

/**
 * Everything the strength feature remembers between workouts, with the rules that change and read it.
 *
 * An immutable value type: the stores and tests drive it directly, nothing here touches disk or the clock. Every "changing"
 * function returns the new value.
 */
data class StrengthData(
    /** Saved workout templates, in the order they are shown. */
    val templates: List<WorkoutTemplate> = emptyList(),
    /** Finished workouts, newest first. */
    val history: List<CompletedWorkout> = emptyList(),
    /** Exercises the user created. */
    val customExercises: List<Exercise> = emptyList(),
    /** Best estimated 1RM per exercise id. */
    val personalBests: Map<String, PersonalBest> = emptyMap(),
) {
    /** True when there are neither templates nor finished workouts (the condition for seeding demo data). */
    val isEmpty: Boolean get() = templates.isEmpty() && history.isEmpty()

    /** The template with the given id. */
    fun template(id: UUID): WorkoutTemplate? = templates.firstOrNull { it.id == id }

    // region Exercises with remembered results

    /**
     * The built-in library plus the custom exercises, each with `previousBestE1RM` and `previousSets` taken from the user's results.
     *
     * An exercise with no personal best or history keeps the values it already carries (the library's demo values).
     * A custom exercise whose id equals a built-in id is ignored.
     */
    fun exercises(): List<Exercise> {
        val memory = exerciseMemory()
        return allExercises().map { overlay(it, memory) }
    }

    /** One exercise (built-in first, then custom) with the remembered results overlaid; null for an unknown id. */
    fun exercise(id: String): Exercise? {
        val base = ExerciseLibrary.exercise(id) ?: customExercises.firstOrNull { it.id == id } ?: return null
        return overlay(base, exerciseMemory(only = id))
    }

    /** [exercise] with the remembered best e1RM and last sets of the same exercise id applied (anything remembered wins). */
    fun overlay(exercise: Exercise): Exercise = overlay(exercise, exerciseMemory(only = exercise.id))

    private fun allExercises(): List<Exercise> {
        val seen = ExerciseLibrary.builtIn.map { it.id }.toMutableSet()
        val result = ExerciseLibrary.builtIn.toMutableList()
        for (custom in customExercises) {
            if (seen.add(custom.id)) result.add(custom)
        }
        return result
    }

    private fun overlay(exercise: Exercise, memory: Map<String, ExerciseMemory>): Exercise {
        val remembered = memory[exercise.id]
        val best = maxOf(personalBests[exercise.id]?.estimated1RM ?: 0.0, remembered?.bestE1RM ?: 0.0)
        var result = exercise
        if (best > 0) result = result.copy(previousBestE1RM = best)
        val sets = remembered?.lastSets
        if (sets != null && sets.isNotEmpty()) result = result.copy(previousSets = sets)
        return result
    }

    /** One pass over the history (optionally for a single exercise id): latest sets and best e1RM per exercise. */
    private fun exerciseMemory(only: String? = null): Map<String, ExerciseMemory> {
        val memory = mutableMapOf<String, ExerciseMemory>()
        for (workout in history) {
            val setsByExercise = mutableMapOf<String, MutableList<CompletedSet>>()
            val bestByExercise = mutableMapOf<String, Double>()
            val order = mutableListOf<String>()
            for (entry in workout.exercises) {
                if (only != null && entry.exerciseID != only) continue
                if (setsByExercise[entry.exerciseID] == null) order.add(entry.exerciseID)
                setsByExercise.getOrPut(entry.exerciseID) { mutableListOf() }.addAll(entry.sets)
                bestByExercise[entry.exerciseID] = maxOf(bestByExercise[entry.exerciseID] ?: 0.0, bestE1RM(entry))
            }
            for (exerciseID in order) {
                val sets = setsByExercise[exerciseID] ?: emptyList()
                var item = memory[exerciseID] ?: ExerciseMemory(lastDate = Instant.MIN, lastSets = emptyList(), bestE1RM = 0.0)
                item = item.copy(bestE1RM = maxOf(item.bestE1RM, bestByExercise[exerciseID] ?: 0.0))
                if (sets.isNotEmpty() && (item.lastSets.isEmpty() || workout.finishedAt.isAfter(item.lastDate))) {
                    item = item.copy(
                        lastDate = workout.finishedAt,
                        lastSets = sets.map { PreviousSet(weightKg = it.weightKg, reps = it.reps) },
                    )
                }
                memory[exerciseID] = item
            }
        }
        return memory
    }

    // endregion

    // region Changes

    /** Adds (or replaces, by id) a custom exercise. An id that belongs to a built-in exercise is ignored. */
    fun addingCustomExercise(exercise: Exercise): StrengthData {
        if (ExerciseLibrary.exercise(exercise.id) != null) return this
        val stored = exercise.copy(isCustom = true)
        val index = customExercises.indexOfFirst { it.id == stored.id }
        val updated = customExercises.toMutableList()
        if (index >= 0) updated[index] = stored else updated.add(stored)
        return copy(customExercises = updated)
    }

    /** Inserts a template, or replaces the one with the same id (keeping its position). */
    fun savingTemplate(template: WorkoutTemplate): StrengthData {
        val index = templates.indexOfFirst { it.id == template.id }
        val updated = templates.toMutableList()
        if (index >= 0) updated[index] = template else updated.add(template)
        return copy(templates = updated)
    }

    /**
     * Records a finished workout.
     *
     * * History: inserted newest first (a workout with the same id is replaced).
     * * Personal bests: raised for every exercise whose best estimated 1RM beats the stored one.
     * * Templates: the workout's template gets `lastPerformed`; [updateTemplate] (when given) replaces the stored template with the same id
     *   (or is added) and also gets `lastPerformed`.
     */
    fun recording(completed: CompletedWorkout, updateTemplate: WorkoutTemplate?): StrengthData {
        val newHistory = history.filter { it.id != completed.id }.toMutableList()
        val position = newHistory.indexOfFirst { !it.finishedAt.isAfter(completed.finishedAt) }
        newHistory.add(if (position >= 0) position else newHistory.size, completed)

        val bests = personalBests.toMutableMap()
        for (entry in completed.exercises) {
            val value = bestE1RM(entry)
            if (!(value > 0 && value > (bests[entry.exerciseID]?.estimated1RM ?: 0.0))) continue
            val set = bestSet(entry.sets, entry.tracking)
            bests[entry.exerciseID] = PersonalBest(
                exerciseID = entry.exerciseID,
                estimated1RM = value,
                weightKg = set?.weightKg ?: 0.0,
                reps = set?.reps ?: 0,
                date = completed.finishedAt,
            )
        }

        var result = copy(history = newHistory, personalBests = bests)

        val templateID = completed.templateID
        if (templateID != null) {
            val position2 = result.templates.indexOfFirst { it.id == templateID }
            if (position2 >= 0) {
                val updated = result.templates.toMutableList()
                updated[position2] = updated[position2].copy(lastPerformed = later(updated[position2].lastPerformed, completed.finishedAt))
                result = result.copy(templates = updated)
            }
        }
        if (updateTemplate != null) {
            result = result.savingTemplate(updateTemplate.copy(lastPerformed = later(updateTemplate.lastPerformed, completed.finishedAt)))
        }
        return result
    }

    /** Fills an empty store (no templates, no history) with the demo templates, history and personal bests; this when it is not empty. */
    fun seedingDemoDataIfEmpty(now: Instant): StrengthData {
        if (!isEmpty) return this
        val demo = demo(now)
        return copy(
            templates = demo.templates,
            history = demo.history,
            personalBests = if (personalBests.isEmpty()) demo.personalBests else personalBests,
        )
    }

    // endregion

    // region Exercise history

    /** The sessions, e1RM trend, records and 30-day totals behind the exercise detail screen. */
    fun history(exerciseID: String, now: Instant): ExerciseHistory {
        val sessions = exerciseSessions(exerciseID)
        val tracking = sessions.firstOrNull()?.tracking
            ?: ExerciseLibrary.exercise(exerciseID)?.tracking
            ?: customExercises.firstOrNull { it.id == exerciseID }?.tracking
            ?: TrackingKind.WEIGHT_REPS

        // Oldest first for the trend.
        val series = sessions.asReversed().mapNotNull { item ->
            if (item.e1RM > 0) E1RMPoint(date = item.session.date, value = item.e1RM) else null
        }

        var bestValue = 0.0
        var bestWeight = 0.0
        var bestReps = 0
        var bestDate: Instant? = null
        for (item in sessions.asReversed()) {
            val set = bestSet(item.session.sets, tracking)
            if (set == null || !(set.e1RM > bestValue)) continue
            bestValue = set.e1RM
            bestWeight = set.weightKg
            bestReps = set.reps
            bestDate = item.session.date
        }
        val seriesBest = series.maxOfOrNull { it.value } ?: 0.0
        bestValue = maxOf(bestValue, seriesBest)
        val stored = personalBests[exerciseID]
        if (stored != null && stored.estimated1RM > bestValue + 1e-9) {
            bestValue = stored.estimated1RM
            bestWeight = stored.weightKg
            bestReps = stored.reps
            bestDate = stored.date
        }

        val threshold = now.addingTimeInterval(-30 * 86_400.0)
        val recent = sessions.filter { !it.session.date.isBefore(threshold) }
        val volume = recent.fold(0.0) { acc, item -> acc + item.volumeKg }

        var bestSetText: String? = null
        when (tracking) {
            TrackingKind.WEIGHT_REPS -> {
                if (bestValue > 0 && bestReps > 0) bestSetText = NumberText.kg(bestWeight) + " kg × " + bestReps.toString()
            }
            TrackingKind.REPS_ONLY -> {
                val top = topSet(sessions) { it.reps }
                if (top != null) {
                    bestSetText = top.value.toString() + if (top.value == 1) " rep" else " reps"
                    bestDate = top.date
                }
            }
            TrackingKind.DURATION -> {
                val top = topSet(sessions) { it.reps }
                if (top != null) {
                    bestSetText = top.value.toString() + " s"
                    bestDate = top.date
                }
            }
        }

        return ExerciseHistory(
            exerciseID = exerciseID,
            sessions = sessions.map { it.session },
            e1RMSeries = series,
            bestE1RM = if (tracking == TrackingKind.WEIGHT_REPS) bestValue else 0.0,
            bestSetText = bestSetText,
            bestSetDate = if (bestSetText == null) null else bestDate,
            volumeLast30Days = volume,
            sessionsLast30Days = recent.size,
            records = records(tracking, sessions, bestValue, bestDate, bestSetText),
        )
    }

    /** Every workout that contains the exercise, newest first (entries of one workout are merged into one session). */
    private fun exerciseSessions(exerciseID: String): List<SessionItem> {
        class Indexed(val offset: Int, val item: SessionItem)
        val items = mutableListOf<Indexed>()
        for ((offset, workout) in history.withIndex()) {
            val entries = workout.exercises.filter { it.exerciseID == exerciseID && it.sets.isNotEmpty() }
            val first = entries.firstOrNull() ?: continue
            val sets = entries.flatMap { it.sets }
            val volume = if (first.tracking == TrackingKind.WEIGHT_REPS) {
                sets.fold(0.0) { acc, set -> acc + if (set.type == SetType.WARMUP) 0.0 else set.weightKg * set.reps.toDouble() }
            } else {
                0.0
            }
            val session = ExerciseSession(
                id = workout.id,
                date = workout.finishedAt,
                workoutName = workout.name,
                sets = sets,
                isPersonalRecord = entries.any { it.isPersonalRecord },
            )
            val e1RM = entries.maxOfOrNull { bestE1RM(it) } ?: 0.0
            items.add(Indexed(offset, SessionItem(session = session, tracking = first.tracking, e1RM = e1RM, volumeKg = volume)))
        }
        items.sortWith { lhs, rhs ->
            if (lhs.item.session.date != rhs.item.session.date) {
                rhs.item.session.date.compareTo(lhs.item.session.date)
            } else {
                lhs.offset.compareTo(rhs.offset)
            }
        }
        return items.map { it.item }
    }

    private fun records(
        tracking: TrackingKind,
        sessions: List<SessionItem>,
        bestE1RM: Double,
        bestDate: Instant?,
        bestSetText: String?,
    ): List<ExerciseRecordRow> {
        if (sessions.isEmpty()) return emptyList()
        val rows = mutableListOf<ExerciseRecordRow>()

        // Best session by a numeric measure (the newest session wins a tie).
        fun bestSession(measure: (SessionItem) -> Double): Pair<Double, Instant>? {
            var best: Pair<Double, Instant>? = null
            for (item in sessions) {
                val value = measure(item)
                if (value > 0 && value > (best?.first ?: 0.0)) best = value to item.session.date
            }
            return best
        }

        when (tracking) {
            TrackingKind.WEIGHT_REPS -> {
                if (bestE1RM > 0) {
                    rows.add(ExerciseRecordRow(id = "e1rm", label = "Estimated 1RM", value = NumberText.thousands(bestE1RM) + " kg", date = bestDate))
                }
                if (bestSetText != null) {
                    rows.add(ExerciseRecordRow(id = "bestSet", label = "Best set", value = bestSetText, date = bestDate))
                }
                val common = commonWorkingWeight(sessions)
                if (common != null) {
                    var most = 0
                    var mostDate: Instant? = null
                    for (item in sessions) {
                        for (set in item.session.sets) {
                            if (set.type != SetType.WARMUP && set.weightKg == common && set.reps > most) {
                                most = set.reps
                                mostDate = item.session.date
                            }
                        }
                    }
                    if (most > 0) {
                        rows.add(
                            ExerciseRecordRow(
                                id = "repsAtWeight",
                                label = "Most reps at " + NumberText.kg(common) + " kg",
                                value = most.toString(),
                                date = mostDate,
                            ),
                        )
                    }
                }
                val top = bestSession { it.volumeKg }
                if (top != null) {
                    rows.add(ExerciseRecordRow(id = "bestVolume", label = "Best session volume", value = NumberText.thousands(top.first) + " kg", date = top.second))
                }
            }
            TrackingKind.REPS_ONLY -> {
                val top = topSet(sessions) { it.reps }
                if (top != null) {
                    rows.add(ExerciseRecordRow(id = "mostReps", label = "Most reps in a set", value = top.value.toString(), date = top.date))
                }
                val session = bestSession { item -> item.session.sets.fold(0) { acc, set -> acc + if (set.type == SetType.WARMUP) 0 else set.reps }.toDouble() }
                if (session != null) {
                    rows.add(ExerciseRecordRow(id = "bestSessionReps", label = "Best session reps", value = NumberText.thousands(session.first), date = session.second))
                }
            }
            TrackingKind.DURATION -> {
                val top = topSet(sessions) { it.reps }
                if (top != null) {
                    rows.add(ExerciseRecordRow(id = "longest", label = "Longest set", value = top.value.toString() + " s", date = top.date))
                }
                val session = bestSession { item -> item.session.sets.fold(0) { acc, set -> acc + if (set.type == SetType.WARMUP) 0 else set.reps }.toDouble() }
                if (session != null) {
                    rows.add(ExerciseRecordRow(id = "bestSessionTime", label = "Best session time", value = NumberText.clock(session.first.toInt()), date = session.second))
                }
            }
        }
        return rows
    }

    /** The working (non-warm-up, weight above zero) weight used in the most sets; the heavier one on a tie. */
    private fun commonWorkingWeight(sessions: List<SessionItem>): Double? {
        val counts = mutableMapOf<Double, Int>()
        for (item in sessions) {
            for (set in item.session.sets) {
                if (set.type != SetType.WARMUP && set.weightKg > 0) counts[set.weightKg] = (counts[set.weightKg] ?: 0) + 1
            }
        }
        var best: Pair<Double, Int>? = null
        for ((weight, count) in counts) {
            val current = best
            if (current != null && (count < current.second || (count == current.second && weight < current.first))) continue
            best = weight to count
        }
        return best?.first
    }

    // endregion

    /** What the history says about one exercise: its latest sets and its best estimated 1RM. */
    private data class ExerciseMemory(val lastDate: Instant, val lastSets: List<PreviousSet>, val bestE1RM: Double)

    private data class SessionItem(val session: ExerciseSession, val tracking: TrackingKind, val e1RM: Double, val volumeKg: Double)

    private data class TopSet(val value: Int, val date: Instant)

    /** The set with the highest [value] (the newest session wins a tie), with the session date. */
    private fun topSet(sessions: List<SessionItem>, value: (CompletedSet) -> Int): TopSet? {
        var best: TopSet? = null
        for (item in sessions) {
            for (set in item.session.sets) {
                if (set.type == SetType.WARMUP) continue
                val candidate = value(set)
                if (candidate > 0 && candidate > (best?.value ?: 0)) best = TopSet(candidate, item.session.date)
            }
        }
        return best
    }

    companion object {
        /** The best set of one exercise entry: highest Epley estimate, with the weight and reps that produced it. */
        data class BestSet(val e1RM: Double, val weightKg: Double, val reps: Int)

        /** The e1RM recorded on the entry, or (when none was recorded) the best Epley estimate of its non-warm-up sets. */
        internal fun bestE1RM(entry: CompletedExercise): Double {
            if (entry.bestE1RM > 0) return entry.bestE1RM
            return bestSet(entry.sets, entry.tracking)?.e1RM ?: 0.0
        }

        /** The non-warm-up set with the highest Epley estimate (the first one on a tie); null without a weight-tracking set. */
        internal fun bestSet(sets: List<CompletedSet>, tracking: TrackingKind): BestSet? {
            if (tracking != TrackingKind.WEIGHT_REPS) return null
            var best: BestSet? = null
            for (set in sets) {
                if (set.type == SetType.WARMUP) continue
                val value = Estimated1RM.epley(set.weightKg, set.reps)
                if (value > 0 && value > (best?.e1RM ?: 0.0)) best = BestSet(value, set.weightKg, set.reps)
            }
            return best
        }

        /** The demo data for [now] (see [SampleData]): three templates, five finished workouts and the matching personal bests. */
        fun demo(now: Instant): StrengthData = StrengthData(
            templates = SampleData.templates(now),
            history = SampleData.history(now),
            customExercises = emptyList(),
            personalBests = SampleData.personalBests(now),
        )

        private fun later(existing: Instant?, candidate: Instant): Instant {
            if (existing == null) return candidate
            return if (existing.isAfter(candidate)) existing else candidate
        }
    }
}

// endregion
