package health.pulse.strength.core

import java.time.Instant
import java.util.UUID

/** Creates workouts from nothing or from a template, and turns a workout back into a template. */
object WorkoutFactory {
    /** A workout without exercises, started [now]. */
    fun makeEmpty(name: String, now: Instant, id: UUID = UUID.randomUUID()): WorkoutState =
        WorkoutState(id = id, name = name, startedAt = now)

    /** A workout whose exercises, sets (all pending), rest times and supersets come from [template]. */
    fun makeWorkout(template: WorkoutTemplate, now: Instant, id: UUID = UUID.randomUUID()): WorkoutState {
        val groupSizes = mutableMapOf<String, Int>()
        for (entry in template.entries) {
            entry.supersetGroup?.let { groupSizes[it] = (groupSizes[it] ?: 0) + 1 }
        }
        val exercises = template.entries.map { entry ->
            // A superset group needs at least two members; a lone letter in a template is dropped.
            val group = entry.supersetGroup?.takeIf { (groupSizes[it] ?: 0) >= 2 }
            WorkoutExercise(
                id = UUID.randomUUID(),
                exercise = entry.exercise,
                sets = entry.plannedSets.map { LoggedSet(type = it.type, weightKg = it.weightKg, reps = it.reps) },
                restSeconds = maxOf(0, entry.restSeconds),
                supersetGroup = group,
                note = "",
                templateEntryID = entry.id,
            )
        }
        return WorkoutState(
            id = id,
            name = template.name,
            templateID = template.id,
            templateBaseline = template.entries.map { it.id },
            exercises = exercises,
            currentIndex = 0,
            startedAt = now,
        )
    }

    /** [template] rebuilt from the workout's current exercises; kept entries keep their id, new exercises get new ones. */
    fun updatedTemplate(template: WorkoutTemplate, state: WorkoutState): WorkoutTemplate {
        val usedIDs = mutableSetOf<UUID>()
        val entries = mutableListOf<TemplateEntry>()
        for (workoutExercise in state.exercises) {
            var entryID = workoutExercise.templateEntryID ?: UUID.randomUUID()
            if (entryID in usedIDs) entryID = UUID.randomUUID()
            usedIDs.add(entryID)
            entries.add(entry(entryID, workoutExercise))
        }
        return template.copy(entries = entries)
    }

    /** A new template (new ids, never performed) holding the workout's current exercises ("save as template"). */
    fun template(state: WorkoutState, name: String): WorkoutTemplate {
        val trimmed = name.trimmedFoundation()
        val fallback = state.name.trimmedFoundation()
        val title = if (trimmed.isNotEmpty()) trimmed else if (fallback.isNotEmpty()) fallback else "Workout"
        return WorkoutTemplate(
            id = UUID.randomUUID(),
            name = title,
            entries = state.exercises.map { entry(UUID.randomUUID(), it) },
            lastPerformed = null,
        )
    }

    private fun entry(id: UUID, workoutExercise: WorkoutExercise): TemplateEntry = TemplateEntry(
        id = id,
        exercise = workoutExercise.exercise,
        plannedSets = workoutExercise.sets.map { PlannedSet(type = it.type, weightKg = it.weightKg, reps = it.reps) },
        restSeconds = workoutExercise.restSeconds,
        supersetGroup = workoutExercise.supersetGroup,
    )
}
