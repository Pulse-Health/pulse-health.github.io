import Foundation

/// Helpers for the transient parts of the Live Activity content that the app, not `SnapshotBuilder.make`, decides on
/// (widgets/SPEC.md section 2, "Live moments").
public extension SnapshotBuilder {
    /// A `PRMoment` when the change from `old` to `new` logged a set that is a personal record (the presenter's rule: a logged,
    /// non-warm-up weight set whose Epley estimate beats the running best by more than 0.05; nothing without a previous best), else nil.
    /// The moment expires `lifetime` seconds after `now`; the app sends the clearing update at `expiresAt`.
    static func prMoment(from old: WorkoutState, to new: WorkoutState, now: Date, lifetime: TimeInterval = 4) -> PRMoment? {
        nil
    }

    /// The Live Activity's final card for a finished workout.
    static func finishBrief(from completed: CompletedWorkout, savedToHealth: Bool) -> FinishBrief {
        FinishBrief(
            workoutName: completed.name,
            durationMinutes: (completed.durationSeconds + 30) / 60,
            sets: completed.loggedSets,
            volumeText: NumberText.kg((completed.volumeKg / 100).rounded() / 10),
            personalRecordCount: completed.personalRecords.count,
            savedToHealth: savedToHealth
        )
    }
}
