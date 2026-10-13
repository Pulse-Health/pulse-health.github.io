#if os(iOS)
import ActivityKit
import Foundation
import PulseStrengthCore

/// Static attributes of the strength-workout Live Activity.
///
/// The dynamic part, `ContentState`, is the flat `WorkoutSnapshot` built by `SnapshotBuilder`
/// (already `Codable & Hashable`, and kept well below the 4 KB ActivityKit limit). The attributes
/// never change while the activity is running, so they only carry the identity of the workout.
///
/// This type is shared by the app (which starts, updates and ends the activity) and the widget
/// extension (which renders it with `ActivityConfiguration(for: WorkoutActivityAttributes.self)`).
public struct WorkoutActivityAttributes: ActivityAttributes {
    public typealias ContentState = WorkoutSnapshot

    /// `WorkoutState.id` of the workout this activity belongs to.
    public var workoutID: UUID
    /// Display name of the workout, for example "Upper A · Push".
    public var workoutName: String

    public init(workoutID: UUID, workoutName: String) {
        self.workoutID = workoutID
        self.workoutName = workoutName
    }
}
#endif
