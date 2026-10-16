import Foundation

/// Builds the saved `CompletedWorkout` (history, summary screen, Health export) from a workout in progress.
public enum SummaryBuilder {
    /// The result of `state` at `finishedAt`: only logged sets count; unlogged sets and exercises without logged sets are left out.
    public static func build(from state: WorkoutState, finishedAt: Date) -> CompletedWorkout {
        var volume = 0.0
        var loggedSets = 0
        var rirSum = 0
        var rirCount = 0
        var musclePerGroup: [MuscleGroup: Int] = [:]
        var exercises: [CompletedExercise] = []
        var records: [PersonalRecord] = []

        for entry in state.exercises {
            let analysis = PresenterSupport.analyse(entry).sets
            var sets: [CompletedSet] = []
            var bestE1RM = 0.0
            var bestIndex: Int?
            var isRecord = false

            for (index, set) in entry.sets.enumerated() where set.isDone {
                sets.append(CompletedSet(type: set.type, weightKg: set.weightKg, reps: set.reps, rir: set.rir))
                loggedSets += 1
                if let rir = set.rir {
                    rirSum += rir
                    rirCount += 1
                }
                if set.type.countsTowardVolume {
                    musclePerGroup[entry.exercise.muscle, default: 0] += 1
                }
                if analysis[index].e1RM > bestE1RM {
                    bestE1RM = analysis[index].e1RM
                    bestIndex = index
                }
                if analysis[index].isRecord { isRecord = true }
            }
            volume += PresenterSupport.volumeKg(of: entry)
            guard !sets.isEmpty else { continue }

            let exercise = entry.exercise
            exercises.append(CompletedExercise(
                id: entry.id,
                exerciseID: exercise.id,
                name: exercise.name,
                muscle: exercise.muscle,
                mediaKey: exercise.mediaKey,
                tracking: exercise.tracking,
                sets: sets,
                isPersonalRecord: isRecord,
                bestE1RM: bestE1RM,
                note: entry.note
            ))

            if isRecord, let bestIndex {
                let bestSet = entry.sets[bestIndex]
                merge(
                    PersonalRecord(
                        exerciseID: exercise.id,
                        exerciseName: exercise.name,
                        weightKg: bestSet.weightKg,
                        reps: bestSet.reps,
                        estimated1RM: bestE1RM,
                        previousBest: exercise.previousBestE1RM
                    ),
                    into: &records
                )
            }
        }

        // Duration: active time up to `finishedAt` (a workout finished while paused ends at the pause).
        var timing = state
        timing.finishedAt = nil
        let duration = timing.elapsedSeconds(now: finishedAt)

        let muscleSets = musclePerGroup
            .filter { $0.value > 0 }
            .map { MuscleSets(muscle: $0.key, sets: $0.value) }
            .sorted { lhs, rhs in
                lhs.sets != rhs.sets ? lhs.sets > rhs.sets : lhs.muscle.rawValue < rhs.muscle.rawValue
            }

        return CompletedWorkout(
            id: state.id,
            name: state.name,
            templateID: state.templateID,
            startedAt: state.startedAt,
            finishedAt: finishedAt,
            durationSeconds: duration,
            volumeKg: volume,
            loggedSets: loggedSets,
            averageHeartRate: state.averageHeartRate,
            averageRIR: rirCount > 0 ? Double(rirSum) / Double(rirCount) : nil,
            exercises: exercises,
            personalRecords: records,
            muscleSets: muscleSets
        )
    }

    /// Adds `record`, or replaces the existing record of the same exercise when it has the higher estimate.
    private static func merge(_ record: PersonalRecord, into records: inout [PersonalRecord]) {
        if let existing = records.firstIndex(where: { $0.exerciseID == record.exerciseID }) {
            if record.estimated1RM > records[existing].estimated1RM { records[existing] = record }
        } else {
            records.append(record)
        }
    }
}
