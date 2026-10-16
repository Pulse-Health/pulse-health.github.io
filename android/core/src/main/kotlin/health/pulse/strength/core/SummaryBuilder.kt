package health.pulse.strength.core

import java.time.Instant

/** Builds the saved [CompletedWorkout] (history, summary screen, Health export) from a workout in progress. */
object SummaryBuilder {
    /** The result of [state] at [finishedAt]: only logged sets count; unlogged sets and exercises without logged sets are left out. */
    fun build(state: WorkoutState, finishedAt: Instant): CompletedWorkout {
        var volume = 0.0
        var loggedSets = 0
        var rirSum = 0
        var rirCount = 0
        val musclePerGroup = mutableMapOf<MuscleGroup, Int>()
        val exercises = mutableListOf<CompletedExercise>()
        val records = mutableListOf<PersonalRecord>()

        for (entry in state.exercises) {
            val analysis = PresenterSupport.analyse(entry).sets
            val sets = mutableListOf<CompletedSet>()
            var bestE1RM = 0.0
            var bestIndex: Int? = null
            var isRecord = false

            for ((index, set) in entry.sets.withIndex()) {
                if (!set.isDone) continue
                sets.add(CompletedSet(type = set.type, weightKg = set.weightKg, reps = set.reps, rir = set.rir))
                loggedSets += 1
                set.rir?.let {
                    rirSum += it
                    rirCount += 1
                }
                if (set.type.countsTowardVolume) {
                    musclePerGroup[entry.exercise.muscle] = (musclePerGroup[entry.exercise.muscle] ?: 0) + 1
                }
                if (analysis[index].e1RM > bestE1RM) {
                    bestE1RM = analysis[index].e1RM
                    bestIndex = index
                }
                if (analysis[index].isRecord) isRecord = true
            }
            volume += PresenterSupport.volumeKg(entry)
            if (sets.isEmpty()) continue

            val exercise = entry.exercise
            exercises.add(
                CompletedExercise(
                    id = entry.id,
                    exerciseID = exercise.id,
                    name = exercise.name,
                    muscle = exercise.muscle,
                    mediaKey = exercise.mediaKey,
                    tracking = exercise.tracking,
                    sets = sets,
                    isPersonalRecord = isRecord,
                    bestE1RM = bestE1RM,
                ),
            )

            if (isRecord && bestIndex != null) {
                val bestSet = entry.sets[bestIndex]
                merge(
                    PersonalRecord(
                        exerciseID = exercise.id,
                        exerciseName = exercise.name,
                        weightKg = bestSet.weightKg,
                        reps = bestSet.reps,
                        estimated1RM = bestE1RM,
                        previousBest = exercise.previousBestE1RM,
                    ),
                    records,
                )
            }
        }

        // Duration: active time up to `finishedAt` (a workout finished while paused ends at the pause).
        val duration = state.copy(finishedAt = null).elapsedSeconds(finishedAt)

        val muscleSets = musclePerGroup
            .filter { it.value > 0 }
            .map { MuscleSets(muscle = it.key, sets = it.value) }
            .sortedWith { lhs, rhs ->
                if (lhs.sets != rhs.sets) rhs.sets.compareTo(lhs.sets) else lhs.muscle.rawValue.compareTo(rhs.muscle.rawValue)
            }

        return CompletedWorkout(
            id = state.id,
            name = state.name,
            templateID = state.templateID,
            startedAt = state.startedAt,
            finishedAt = finishedAt,
            durationSeconds = duration,
            volumeKg = volume,
            loggedSets = loggedSets,
            averageHeartRate = state.averageHeartRate,
            averageRIR = if (rirCount > 0) rirSum.toDouble() / rirCount.toDouble() else null,
            exercises = exercises,
            personalRecords = records,
            muscleSets = muscleSets,
        )
    }

    /** Adds [record], or replaces the existing record of the same exercise when it has the higher estimate. */
    private fun merge(record: PersonalRecord, records: MutableList<PersonalRecord>) {
        val existing = records.indexOfFirst { it.exerciseID == record.exerciseID }
        if (existing >= 0) {
            if (record.estimated1RM > records[existing].estimated1RM) records[existing] = record
        } else {
            records.add(record)
        }
    }
}
