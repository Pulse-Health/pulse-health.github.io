import Foundation

/// The rules that keep the Watch's copy of a workout (the mirror) in line with the phone's (the authority).
///
/// The Watch applies its own edits at once (optimistically) and sends each one to the phone as a `RemoteCommand`. The phone
/// applies the command, adds its id to the acknowledgements of every `SyncEnvelope` it sends (`ackedCommandIDs`) and sends an
/// envelope even when the command changed nothing. The Watch therefore always shows
///
///     the phone's last adopted state + the edits the phone has not acknowledged yet, replayed in order
///
/// and an unacknowledged edit is dropped once it is older than `pendingLifetime` (the command was lost). Delivery is unreliable
/// (messages can be duplicated, late, out of order or never arrive), so every rule below is idempotent and order tolerant.
public enum SyncReconciler {
    /// How long the Watch keeps showing an edit the phone has not acknowledged (15 seconds, by the Watch's clock).
    public static let pendingLifetime: TimeInterval = 15

    /// How many unacknowledged edits the Watch keeps; when more pile up the oldest is forgotten.
    public static let pendingCapacity = 64

    /// How many of the most recent command ids every envelope acknowledges.
    public static let acknowledgementWindow = 64

    /// How many applied command ids the phone remembers (to drop duplicates and to acknowledge them again).
    public static let acknowledgedMemory = 256

    /// True when `incoming` is a different workout than `local`, or has a strictly higher revision.
    ///
    /// This is the first-generation rule, kept for compatibility. The mirror no longer uses it: a Watch whose optimistic edits
    /// raised its local revision above the phone's would ignore every envelope with it. The mirror decides with
    /// `shouldAdopt(incoming:authoritativeRevision:currentWorkoutID:)`, which compares against the phone's own revision.
    ///
    /// Heart-rate samples do not change the revision, so a copy that differs only in heart rate is not newer.
    public static func isNewer(_ incoming: WorkoutState, than local: WorkoutState?) -> Bool {
        guard let local else { return true }
        if incoming.id != local.id { return true }
        return incoming.revision > local.revision
    }

    /// Whether the mirror adopts the phone's `incoming` state.
    ///
    /// * `authoritativeRevision` is the revision of the last phone state the mirror adopted for the workout it shows
    ///   (`currentWorkoutID`), not the revision of its own, optimistically edited copy.
    /// * A state of another workout, or any state while the mirror shows no workout, is adopted.
    /// * For the same workout the state is adopted when its revision is at least `authoritativeRevision`. An equal revision is
    ///   adopted on purpose: an envelope that only acknowledges commands (the phone found them to be no-ops or duplicates) carries
    ///   the same revision. A lower revision is stale (it overtook, or was overtaken by, a newer envelope) and ignored.
    public static func shouldAdopt(incoming: WorkoutState, authoritativeRevision: Int?, currentWorkoutID: UUID?) -> Bool {
        guard incoming.id == currentWorkoutID, let authoritativeRevision else { return true }
        return incoming.revision >= authoritativeRevision
    }

    /// The edits that are still unacknowledged at `now`: not in `acknowledged` and not older than `pendingLifetime`.
    ///
    /// The order of `pending` is kept. An edit issued after `now` (the Watch's clock moved backwards) counts as new.
    public static func remainingPending(_ pending: [RemoteCommand], acknowledged: [UUID], now: Date) -> [RemoteCommand] {
        let acknowledgedIDs = Set(acknowledged)
        return pending.filter { command in
            !acknowledgedIDs.contains(command.id) && now.timeIntervalSince(command.issuedAt) <= pendingLifetime
        }
    }

    /// The state the mirror shows: the phone's `authoritative` state with the unacknowledged `pending` edits replayed on top, in
    /// order, each at the time it was issued. An edit whose targets no longer exist in the phone's state does nothing (the phone
    /// wins), and a command for another workout is skipped.
    public static func rebase(_ authoritative: WorkoutState, replaying pending: [RemoteCommand]) -> WorkoutState {
        var result = authoritative
        for command in pending where command.workoutID == nil || command.workoutID == authoritative.id {
            WorkoutReducer.reduce(&result, command.action, now: command.issuedAt)
        }
        return result
    }
}
