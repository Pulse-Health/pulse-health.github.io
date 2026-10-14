import Foundation

/// Builds the small `WorkoutSnapshot` shown by the Live Activity, the Dynamic Island and the Apple Watch.
public enum SnapshotBuilder {
    /// The snapshot of `state` at `now`; its target is the next pending set (`WorkoutTargets.nextPending`).
    public static func make(from state: WorkoutState, now: Date) -> WorkoutSnapshot {
        let target = WorkoutTargets.nextPending(in: state)
        let totals = PresenterSupport.totals(of: state)

        // The exercise shown is the one that owns the target set (the current one while it still has pending sets).
        let shownIndex = target?.exerciseIndex ?? state.clampedIndex
        let shown: WorkoutExercise? = state.exercises.isEmpty ? nil : state.exercises[shownIndex]
        let targetSet: LoggedSet? = target.map { state.exercises[$0.exerciseIndex].sets[$0.setIndex] }

        let remaining = PresenterSupport.restRemainingSeconds(state, now: now)
        let phase: SnapshotPhase
        if target == nil {
            phase = .complete
        } else if let remaining {
            phase = remaining > 0 ? .resting : .restOver
        } else {
            phase = .logging
        }

        let tracking = shown?.exercise.tracking ?? .weightReps
        let setLabel: String
        let nextSetText: String
        let weightText: String
        let repsText: String
        if let shown, let target, let targetSet {
            let position = "Set \(target.setIndex + 1) of \(shown.sets.count)"
            setLabel = targetSet.type == .warmup ? "Warm-up · " + position : position
            nextSetText = nextText(targetSet, position: target.setIndex + 1, exercise: shown.exercise)
            weightText = PresenterSupport.weightText(targetSet, exercise: shown.exercise)
            repsText = String(targetSet.reps)
        } else {
            setLabel = "All sets logged"
            nextSetText = "All sets logged"
            weightText = "–"
            repsText = "–"
        }

        let rest = state.rest
        return WorkoutSnapshot(
            workoutID: state.id,
            revision: state.revision,
            workoutName: state.name,
            activeStart: state.startedAt.addingTimeInterval(state.pausedTotal),
            isPaused: state.isPaused,
            elapsedWhenPaused: state.isPaused ? state.elapsedSeconds(now: now) : 0,
            phase: phase,
            exerciseName: shown?.exercise.name ?? "",
            exerciseIndex: shownIndex,
            exerciseCount: state.exercises.count,
            targetExerciseID: target.map { state.exercises[$0.exerciseIndex].id },
            targetSetID: targetSet?.id,
            setLabel: setLabel,
            tracking: tracking,
            weightText: weightText,
            repsText: repsText,
            repsUnit: tracking == .duration ? "sec" : "reps",
            showsWeight: tracking == .weightReps,
            restStartedAt: rest.map { $0.endsAt.addingTimeInterval(-Double($0.totalSeconds)) },
            restEndsAt: rest?.endsAt,
            restTotalSeconds: rest?.totalSeconds ?? 0,
            restFrozenRemaining: state.isPaused ? remaining : nil,
            heartRate: state.heartRate,
            volumeText: NumberText.thousands(totals.volumeKg),
            loggedSets: totals.loggedSets,
            totalSets: totals.totalSets,
            nextSetText: nextSetText,
            nextExerciseName: nextExerciseName(in: state, after: shownIndex)
        )
    }

    /// "Set 4 · 82.5 kg × 6", "Warm-up · 50 kg × 8", "Set 1 · 12 reps" or "Set 1 · 45 s".
    private static func nextText(_ set: LoggedSet, position: Int, exercise: Exercise) -> String {
        let label = set.type == .warmup ? "Warm-up" : "Set \(position)"
        return label + " · " + PresenterSupport.workText(set, exercise: exercise)
    }

    /// The first exercise after `index` that still has pending sets.
    private static func nextExerciseName(in state: WorkoutState, after index: Int) -> String? {
        guard index + 1 < state.exercises.count else { return nil }
        let following = state.exercises[(index + 1)...]
        return following.first(where: { $0.sets.contains(where: { !$0.isDone }) })?.exercise.name
    }
}
