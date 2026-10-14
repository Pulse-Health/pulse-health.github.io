import Foundation

/// Reference to one set of one workout exercise.
public struct SetRef: Codable, Hashable, Sendable {
    public var exerciseID: UUID
    public var setID: UUID

    public init(exerciseID: UUID, setID: UUID) {
        self.exerciseID = exerciseID
        self.setID = setID
    }
}

/// A running (or finished) rest countdown.
public struct RestState: Codable, Hashable, Sendable {
    public var endsAt: Date
    public var totalSeconds: Int
    /// Set while the workout is paused: the remaining time is frozen until resume.
    public var frozenRemaining: TimeInterval?

    public init(endsAt: Date, totalSeconds: Int, frozenRemaining: TimeInterval? = nil) {
        self.endsAt = endsAt
        self.totalSeconds = totalSeconds
        self.frozenRemaining = frozenRemaining
    }
}

public struct WorkoutSettings: Codable, Hashable, Sendable {
    /// Start the rest timer when a set is logged.
    public var autoStartRest: Bool
    /// Haptic / sound / notification when rest ends.
    public var alertWhenRestEnds: Bool

    public init(autoStartRest: Bool = true, alertWhenRestEnds: Bool = true) {
        self.autoStartRest = autoStartRest
        self.alertWhenRestEnds = alertWhenRestEnds
    }
}

public enum UndoPayload: Codable, Hashable, Sendable {
    case exercise(index: Int, exercise: WorkoutExercise)
    case set(exerciseID: UUID, index: Int, set: LoggedSet)
}

/// The last destructive edit (removed exercise / deleted set), restorable until `expiresAt`.
public struct UndoEntry: Codable, Hashable, Sendable {
    public var payload: UndoPayload
    public var title: String
    public var expiresAt: Date

    public init(payload: UndoPayload, title: String, expiresAt: Date) {
        self.payload = payload
        self.title = title
        self.expiresAt = expiresAt
    }
}

/// The complete state of one workout in progress. Value type, Codable: it is persisted,
/// sent to the Watch, and is the single input of the reducer and presenter.
public struct WorkoutState: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var templateID: UUID?
    /// Template entry ids in their original order; the baseline for "update template?" diffs.
    public var templateBaseline: [UUID]
    public var exercises: [WorkoutExercise]
    public var currentIndex: Int
    public var startedAt: Date
    public var pausedAt: Date?
    public var pausedTotal: TimeInterval
    public var rest: RestState?
    public var lastLogged: SetRef?
    public var settings: WorkoutSettings
    public var undo: UndoEntry?
    /// Latest heart rate (bpm) reported by the Watch.
    public var heartRate: Int?
    /// Running totals of the reported heart-rate samples (for the average in the summary).
    public var heartRateSum: Int
    public var heartRateCount: Int
    /// True while an Apple Watch workout session is recording (the phone then does not write HealthKit).
    public var usedWatch: Bool
    /// Incremented by the reducer on every change; used to order sync messages.
    public var revision: Int
    public var finishedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        templateID: UUID? = nil,
        templateBaseline: [UUID] = [],
        exercises: [WorkoutExercise] = [],
        currentIndex: Int = 0,
        startedAt: Date,
        pausedAt: Date? = nil,
        pausedTotal: TimeInterval = 0,
        rest: RestState? = nil,
        lastLogged: SetRef? = nil,
        settings: WorkoutSettings = WorkoutSettings(),
        undo: UndoEntry? = nil,
        heartRate: Int? = nil,
        heartRateSum: Int = 0,
        heartRateCount: Int = 0,
        usedWatch: Bool = false,
        revision: Int = 0,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.templateID = templateID
        self.templateBaseline = templateBaseline
        self.exercises = exercises
        self.currentIndex = currentIndex
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.pausedTotal = pausedTotal
        self.rest = rest
        self.lastLogged = lastLogged
        self.settings = settings
        self.undo = undo
        self.heartRate = heartRate
        self.heartRateSum = heartRateSum
        self.heartRateCount = heartRateCount
        self.usedWatch = usedWatch
        self.revision = revision
        self.finishedAt = finishedAt
    }
}

public extension WorkoutState {
    var isPaused: Bool { pausedAt != nil }

    /// Mean of the reported heart-rate samples, nil without samples.
    var averageHeartRate: Int? {
        heartRateCount > 0 ? Int((Double(heartRateSum) / Double(heartRateCount)).rounded()) : nil
    }

    /// Index clamped into `exercises`; 0 when empty.
    var clampedIndex: Int {
        guard !exercises.isEmpty else { return 0 }
        return max(0, min(currentIndex, exercises.count - 1))
    }

    var currentExercise: WorkoutExercise? {
        exercises.isEmpty ? nil : exercises[clampedIndex]
    }

    func exerciseIndex(id: UUID) -> Int? {
        exercises.firstIndex { $0.id == id }
    }

    /// Whole seconds of active time (pauses excluded).
    func elapsedSeconds(now: Date) -> Int {
        let reference = pausedAt ?? finishedAt ?? now
        let value = reference.timeIntervalSince(startedAt) - pausedTotal
        return max(0, Int(value.rounded(.down)))
    }

    /// Remaining rest in seconds (frozen while paused). nil when no rest is active.
    func restRemaining(now: Date) -> TimeInterval? {
        guard let rest else { return nil }
        if let frozen = rest.frozenRemaining { return max(0, frozen) }
        return max(0, rest.endsAt.timeIntervalSince(now))
    }
}
