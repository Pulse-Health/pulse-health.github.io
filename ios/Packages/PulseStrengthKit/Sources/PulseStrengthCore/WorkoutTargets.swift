import Foundation

/// Address of one set inside a workout: the exercise position and the set position.
public struct SetTarget: Hashable, Sendable {
    /// Index into `WorkoutState.exercises`.
    public var exerciseIndex: Int
    /// Index into that exercise's `sets`.
    public var setIndex: Int

    /// Creates a target from an exercise index and a set index.
    public init(exerciseIndex: Int, setIndex: Int) {
        self.exerciseIndex = exerciseIndex
        self.setIndex = setIndex
    }
}

/// Finds the set that "log next set" (Watch, Live Activity, nudges) acts on.
public enum WorkoutTargets {
    /// First pending set of the current exercise; else of the following exercises, then of the earlier ones; nil when all are logged.
    public static func nextPending(in state: WorkoutState) -> SetTarget? {
        let count = state.exercises.count
        guard count > 0 else { return nil }
        let start = state.clampedIndex
        for offset in 0..<count {
            let exerciseIndex = (start + offset) % count
            if let setIndex = state.exercises[exerciseIndex].sets.firstIndex(where: { !$0.isDone }) {
                return SetTarget(exerciseIndex: exerciseIndex, setIndex: setIndex)
            }
        }
        return nil
    }
}
