import Foundation

/// Decides which of two copies of a workout is current when the phone (authority) and the Watch (mirror) disagree.
public enum SyncReconciler {
    /// True when `incoming` should replace `local`: no local state, a different workout id, or a higher revision.
    ///
    /// Heart-rate samples do not change the revision, so a copy that differs only in heart rate is not newer.
    public static func isNewer(_ incoming: WorkoutState, than local: WorkoutState?) -> Bool {
        guard let local else { return true }
        if incoming.id != local.id { return true }
        return incoming.revision > local.revision
    }
}
