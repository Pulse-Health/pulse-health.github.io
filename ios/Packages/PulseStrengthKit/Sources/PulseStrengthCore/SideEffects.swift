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
    /// A mirror controller (the Watch) applied an action the user took on this surface and made `command` of it: the phone has to
    /// run the same action. Called once per command, right after `workoutChanged` for the same action; never for heart-rate
    /// samples, which travel as their own message, and never by an authority controller. The Watch's connectivity client sends
    /// the command to the phone from here. The commands are announced in the order they were made, also when an effect edits
    /// from inside `workoutChanged` or `commandIssued` (that command is announced after the one in progress).
    func commandIssued(_ command: RemoteCommand)
}

public extension WorkoutSideEffect {
    func workoutStarted(_ state: WorkoutState) {}
    func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {}
    func workoutEnded(_ state: WorkoutState, completed: CompletedWorkout?) {}
    func commandIssued(_ command: RemoteCommand) {}
}
