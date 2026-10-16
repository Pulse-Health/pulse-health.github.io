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
    /// An exercise that was replaced by another one (the replacement keeps the entry id): undoing swaps the original back,
    /// with its logged sets and its note.
    case replaced(exercise: WorkoutExercise)
}

/// The last destructive edit (removed or replaced exercise / deleted set), restorable until `expiresAt`.
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
    /// The reported heart-rate samples worth keeping, oldest first: at most one per `WorkoutReducer.heartRateSampleInterval`
    /// seconds and at most `WorkoutReducer.maximumHeartRateSamples` of them. `SummaryBuilder` hands them to the finished workout.
    /// Empty for a workout saved before this field existed.
    public var heartRateSeries: [HeartRateSample]

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
        finishedAt: Date? = nil,
        heartRateSeries: [HeartRateSample] = []
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
        self.heartRateSeries = heartRateSeries
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, templateID, templateBaseline, exercises, currentIndex, startedAt, pausedAt, pausedTotal, rest, lastLogged
        case settings, undo, heartRate, heartRateSum, heartRateCount, usedWatch, revision, finishedAt, heartRateSeries
    }

    /// Reads a state. Every key a build before the heart-rate series wrote is still required as before; a file or an envelope
    /// without `heartRateSeries` decodes to an empty series.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        templateID = try container.decodeIfPresent(UUID.self, forKey: .templateID)
        templateBaseline = try container.decode([UUID].self, forKey: .templateBaseline)
        exercises = try container.decode([WorkoutExercise].self, forKey: .exercises)
        currentIndex = try container.decode(Int.self, forKey: .currentIndex)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        pausedTotal = try container.decode(TimeInterval.self, forKey: .pausedTotal)
        rest = try container.decodeIfPresent(RestState.self, forKey: .rest)
        lastLogged = try container.decodeIfPresent(SetRef.self, forKey: .lastLogged)
        settings = try container.decode(WorkoutSettings.self, forKey: .settings)
        undo = try container.decodeIfPresent(UndoEntry.self, forKey: .undo)
        heartRate = try container.decodeIfPresent(Int.self, forKey: .heartRate)
        heartRateSum = try container.decode(Int.self, forKey: .heartRateSum)
        heartRateCount = try container.decode(Int.self, forKey: .heartRateCount)
        usedWatch = try container.decode(Bool.self, forKey: .usedWatch)
        revision = try container.decode(Int.self, forKey: .revision)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        heartRateSeries = try container.decodeIfPresent([HeartRateSample].self, forKey: .heartRateSeries) ?? []
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
