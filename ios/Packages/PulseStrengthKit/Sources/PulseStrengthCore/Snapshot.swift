import Foundation

// MARK: - Snapshot (Live Activity content, Watch screens)

public enum SnapshotPhase: String, Codable, Hashable, Sendable {
    /// A set is waiting to be logged.
    case logging
    /// Rest countdown is running.
    case resting
    /// Rest countdown reached zero and has not been dismissed.
    case restOver
    /// Every set of every exercise is logged.
    case complete
}

/// A small, flat summary of the workout for surfaces that cannot render the full state:
/// the Live Activity / Dynamic Island and the Apple Watch. It is the `ContentState` of the
/// Live Activity, so it must stay small (ActivityKit limit: 4 KB).
/// Built by `SnapshotBuilder.make(from:now:)`.
public struct WorkoutSnapshot: Codable, Hashable, Sendable {
    public var workoutID: UUID
    public var revision: Int
    public var workoutName: String

    /// `startedAt + pausedTotal`: elapsed active time is `now - activeStart` while running.
    public var activeStart: Date
    public var isPaused: Bool
    /// Elapsed seconds, valid while paused (frozen).
    public var elapsedWhenPaused: Int

    public var phase: SnapshotPhase
    public var exerciseName: String
    /// 0-based position of the current exercise.
    public var exerciseIndex: Int
    public var exerciseCount: Int

    /// The set a "Log set" button logs (the next pending set); nil when `phase == .complete`.
    public var targetExerciseID: UUID?
    public var targetSetID: UUID?
    /// "Set 4 of 5" or "Warm-up 1 of 2" style label for the target set.
    public var setLabel: String
    public var tracking: TrackingKind
    public var weightText: String
    public var repsText: String
    /// "reps" or "sec".
    public var repsUnit: String
    /// True when the target exercise logs a weight (weightReps).
    public var showsWeight: Bool

    /// Rest countdown: `restStartedAt ... restEndsAt` for `Text(timerInterval:)` / `ProgressView(timerInterval:)`.
    public var restStartedAt: Date?
    public var restEndsAt: Date?
    public var restTotalSeconds: Int
    /// Seconds left while the workout is paused (frozen rest).
    public var restFrozenRemaining: Int?

    public var heartRate: Int?
    public var volumeText: String
    public var loggedSets: Int
    public var totalSets: Int
    /// "Set 4 · 82.5 kg × 6"
    public var nextSetText: String
    public var nextExerciseName: String?
}

// MARK: - Watch / Live Activity -> phone sync

/// A command issued on another surface (Watch, Live Activity button) and executed by the phone.
public struct RemoteCommand: Codable, Hashable, Sendable, Identifiable {
    /// Unique id so the receiver can drop duplicates (WatchConnectivity may redeliver).
    public var id: UUID
    public var action: WorkoutAction
    public var origin: ActionOrigin
    public var issuedAt: Date

    public init(id: UUID = UUID(), action: WorkoutAction, origin: ActionOrigin, issuedAt: Date = Date()) {
        self.id = id
        self.action = action
        self.origin = origin
        self.issuedAt = issuedAt
    }
}

/// The phone's authoritative state, pushed to the Watch after every change.
public struct SyncEnvelope: Codable, Hashable, Sendable {
    /// nil = the workout ended; see `endedWorkoutID`.
    public var state: WorkoutState?
    public var endedWorkoutID: UUID?
    public var sentAt: Date

    public init(state: WorkoutState?, endedWorkoutID: UUID? = nil, sentAt: Date = Date()) {
        self.state = state
        self.endedWorkoutID = endedWorkoutID
        self.sentAt = sentAt
    }
}

public struct HeartRateSample: Codable, Hashable, Sendable {
    public var bpm: Int
    public var at: Date

    public init(bpm: Int, at: Date = Date()) {
        self.bpm = bpm
        self.at = at
    }
}

/// Every message that crosses the WatchConnectivity channel.
public enum SyncMessage: Codable, Hashable, Sendable {
    /// Phone -> Watch.
    case state(SyncEnvelope)
    /// Watch -> phone.
    case command(RemoteCommand)
    /// Watch -> phone.
    case heartRate(HeartRateSample)
    /// Watch -> phone: the Watch workout session started / stopped recording.
    case watchSession(isRecording: Bool)
    /// Watch -> phone: send me the current state.
    case requestState
}
