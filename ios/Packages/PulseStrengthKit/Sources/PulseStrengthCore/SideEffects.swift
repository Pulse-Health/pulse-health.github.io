import Foundation

/// Platform services (Live Activity, Watch sync, notifications, HealthKit, haptics) plug into the
/// `WorkoutController` through this protocol, so the controller itself stays platform neutral.
@MainActor
public protocol WorkoutSideEffect: AnyObject {
    /// A workout was started or restored from disk.
    func workoutStarted(_ state: WorkoutState)
    /// The state changed because of `action`.
    func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin)
    /// The workout was finished (`completed != nil`) or discarded (`completed == nil`).
    func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?)
}

public extension WorkoutSideEffect {
    func workoutStarted(_ state: WorkoutState) {}
    func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {}
    func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) {}
}
