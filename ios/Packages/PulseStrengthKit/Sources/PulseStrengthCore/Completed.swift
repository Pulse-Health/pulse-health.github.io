import Foundation

// MARK: - Finished workouts

public struct CompletedSet: Codable, Hashable, Sendable {
    public var type: SetType
    /// Kilograms; negative for an assisted load of a reps-only exercise (see `Exercise.allowsAddedWeight`).
    public var weightKg: Double
    /// Reps, or seconds when the exercise tracks duration.
    public var reps: Int
    public var rir: Int?
    /// The personal record this set was when the workout was saved; nil for a set that was none (and in a file that predates it).
    public var prKind: PRKind?

    public init(type: SetType, weightKg: Double, reps: Int, rir: Int? = nil, prKind: PRKind? = nil) {
        self.type = type
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
        self.prKind = prKind
    }

    private enum CodingKeys: String, CodingKey {
        case type, weightKg, reps, rir, prKind
    }

    // `prKind` came later, and a kind that a newer version added reads as none: the set itself still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(SetType.self, forKey: .type)
        self.weightKg = try container.decode(Double.self, forKey: .weightKg)
        self.reps = try container.decode(Int.self, forKey: .reps)
        self.rir = try container.decodeIfPresent(Int.self, forKey: .rir)
        self.prKind = (try? container.decodeIfPresent(PRKind.self, forKey: .prKind)) ?? nil
    }
}

public struct CompletedExercise: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var exerciseID: String
    public var name: String
    public var muscle: MuscleGroup
    public var mediaKey: String?
    public var tracking: TrackingKind
    /// Only logged sets.
    public var sets: [CompletedSet]
    public var isPersonalRecord: Bool
    /// Best estimated 1RM of the logged non-warm-up sets (0 when not applicable).
    public var bestE1RM: Double
    /// The note typed for this exercise during the workout (empty when none).
    public var note: String

    public init(
        id: UUID = UUID(),
        exerciseID: String,
        name: String,
        muscle: MuscleGroup,
        mediaKey: String?,
        tracking: TrackingKind,
        sets: [CompletedSet],
        isPersonalRecord: Bool,
        bestE1RM: Double,
        note: String = ""
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.name = name
        self.muscle = muscle
        self.mediaKey = mediaKey
        self.tracking = tracking
        self.sets = sets
        self.isPersonalRecord = isPersonalRecord
        self.bestE1RM = bestE1RM
        self.note = note
    }

    /// True when the weight of its sets is a signed load (`Exercise.carriesLoad`). The entry does not store the flag: a built-in
    /// exercise answers from the library, any other reps-only id is a custom exercise, which always allows an added load.
    var carriesLoad: Bool {
        tracking == .repsOnly && (ExerciseLibrary.exercise(id: exerciseID)?.allowsAddedWeight ?? true)
    }

    private enum CodingKeys: String, CodingKey {
        case id, exerciseID, name, muscle, mediaKey, tracking, sets, isPersonalRecord, bestE1RM, note
    }

    // `note` came later: a file written before it reads with an empty note.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.exerciseID = try container.decode(String.self, forKey: .exerciseID)
        self.name = try container.decode(String.self, forKey: .name)
        self.muscle = try container.decode(MuscleGroup.self, forKey: .muscle)
        self.mediaKey = try container.decodeIfPresent(String.self, forKey: .mediaKey)
        self.tracking = try container.decode(TrackingKind.self, forKey: .tracking)
        self.sets = try container.decode([CompletedSet].self, forKey: .sets)
        self.isPersonalRecord = try container.decode(Bool.self, forKey: .isPersonalRecord)
        self.bestE1RM = try container.decode(Double.self, forKey: .bestE1RM)
        self.note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

/// The best personal record of one exercise in a workout (one per exercise: the highest `kind`, then the best set).
public struct PersonalRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String { exerciseID }
    public var exerciseID: String
    public var exerciseName: String
    /// The weight of the record set (kg; signed for a reps-only exercise with an added or assisted load).
    public var weightKg: Double
    /// The reps of the record set, or its seconds for a timed exercise.
    public var reps: Int
    /// The estimated 1RM of the record set; 0 when the set has none (more than 12 reps, no weight).
    public var estimated1RM: Double
    /// The record before this workout, in the unit of `kind`: kilograms of estimated 1RM, heaviest weight or rep-range weight, reps,
    /// or seconds.
    public var previousBest: Double
    /// What kind of record it is.
    public var kind: PRKind

    public init(
        exerciseID: String,
        exerciseName: String,
        weightKg: Double,
        reps: Int,
        estimated1RM: Double,
        previousBest: Double,
        kind: PRKind = .estimated1RM
    ) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.weightKg = weightKg
        self.reps = reps
        self.estimated1RM = estimated1RM
        self.previousBest = previousBest
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case exerciseID, exerciseName, weightKg, reps, estimated1RM, previousBest, kind
    }

    // `kind` came later: a record saved before it was an estimated 1RM record.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.exerciseID = try container.decode(String.self, forKey: .exerciseID)
        self.exerciseName = try container.decode(String.self, forKey: .exerciseName)
        self.weightKg = try container.decode(Double.self, forKey: .weightKg)
        self.reps = try container.decode(Int.self, forKey: .reps)
        self.estimated1RM = try container.decode(Double.self, forKey: .estimated1RM)
        self.previousBest = try container.decode(Double.self, forKey: .previousBest)
        self.kind = (try? container.decodeIfPresent(PRKind.self, forKey: .kind)) ?? .estimated1RM
    }
}

public struct MuscleSets: Identifiable, Codable, Hashable, Sendable {
    public var id: String { muscle.rawValue }
    public var muscle: MuscleGroup
    public var sets: Int

    public init(muscle: MuscleGroup, sets: Int) {
        self.muscle = muscle
        self.sets = sets
    }
}

/// The saved result of a workout (history, summary screen, Health export).
public struct CompletedWorkout: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var templateID: UUID?
    public var startedAt: Date
    public var finishedAt: Date
    public var durationSeconds: Int
    /// Warm-up sets excluded; weight-tracking exercises and the positive added loads of reps-only exercises (`WorkoutExercise.loggedVolumeKg`).
    public var volumeKg: Double
    public var loggedSets: Int
    public var averageHeartRate: Int?
    /// Mean of recorded RIR values; nil when none recorded.
    public var averageRIR: Double?
    public var exercises: [CompletedExercise]
    public var personalRecords: [PersonalRecord]
    public var muscleSets: [MuscleSets]

    public init(
        id: UUID,
        name: String,
        templateID: UUID?,
        startedAt: Date,
        finishedAt: Date,
        durationSeconds: Int,
        volumeKg: Double,
        loggedSets: Int,
        averageHeartRate: Int?,
        averageRIR: Double?,
        exercises: [CompletedExercise],
        personalRecords: [PersonalRecord],
        muscleSets: [MuscleSets]
    ) {
        self.id = id
        self.name = name
        self.templateID = templateID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.durationSeconds = durationSeconds
        self.volumeKg = volumeKg
        self.loggedSets = loggedSets
        self.averageHeartRate = averageHeartRate
        self.averageRIR = averageRIR
        self.exercises = exercises
        self.personalRecords = personalRecords
        self.muscleSets = muscleSets
    }
}

// MARK: - Personal bests and per-exercise history

/// The bests of one exercise over the whole history (see `StrengthData.recomputedPersonalBests()`).
///
/// `estimated1RM`, `weightKg`, `reps` and `date` describe the set with the best estimated 1RM (0, 0, 0 for an exercise without an
/// estimate), `date` being when it was reached (the earliest workout on a tie); an exercise without an estimate has the date of its
/// earliest workout with any mark. The marks of `RecordMarks` follow, as flat fields: `heaviestKg`, `repRecords` (reps ->
/// heaviest weight for at least that many reps; key 13 means "13 or more"), `bestReps` and `bestSeconds`. A file written before the marks
/// existed has none of them: the exercise overlay takes them from the history as well, and the next recompute writes them.
public struct PersonalBest: Codable, Hashable, Sendable {
    public var exerciseID: String
    public var estimated1RM: Double
    public var weightKg: Double
    public var reps: Int
    public var date: Date
    /// The heaviest weight of any counted set (kg); nil without one.
    public var heaviestKg: Double?
    /// Reps -> heaviest weight for at least that many reps (kg); see `RecordMarks.repRecords`.
    public var repRecords: [Int: Double]
    /// The most reps in a set without added weight; 0 for none.
    public var bestReps: Int
    /// The most seconds in a timed set; 0 for none.
    public var bestSeconds: Int

    public init(
        exerciseID: String,
        estimated1RM: Double,
        weightKg: Double,
        reps: Int,
        date: Date,
        heaviestKg: Double? = nil,
        repRecords: [Int: Double] = [:],
        bestReps: Int = 0,
        bestSeconds: Int = 0
    ) {
        self.exerciseID = exerciseID
        self.estimated1RM = estimated1RM
        self.weightKg = weightKg
        self.reps = reps
        self.date = date
        self.heaviestKg = heaviestKg
        self.repRecords = repRecords
        self.bestReps = bestReps
        self.bestSeconds = bestSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case exerciseID, estimated1RM, weightKg, reps, date, heaviestKg, repRecords, bestReps, bestSeconds
    }

    // The marks came later: a best written before them reads with none.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.exerciseID = try container.decode(String.self, forKey: .exerciseID)
        self.estimated1RM = try container.decode(Double.self, forKey: .estimated1RM)
        self.weightKg = try container.decode(Double.self, forKey: .weightKg)
        self.reps = try container.decode(Int.self, forKey: .reps)
        self.date = try container.decode(Date.self, forKey: .date)
        self.heaviestKg = try container.decodeIfPresent(Double.self, forKey: .heaviestKg)
        self.repRecords = container.decodeRepRecords(forKey: .repRecords)
        self.bestReps = try container.decodeIfPresent(Int.self, forKey: .bestReps) ?? 0
        self.bestSeconds = try container.decodeIfPresent(Int.self, forKey: .bestSeconds) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exerciseID, forKey: .exerciseID)
        try container.encode(estimated1RM, forKey: .estimated1RM)
        try container.encode(weightKg, forKey: .weightKg)
        try container.encode(reps, forKey: .reps)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(heaviestKg, forKey: .heaviestKg)
        try container.encodeRepRecords(repRecords, forKey: .repRecords)
        try container.encode(bestReps, forKey: .bestReps)
        try container.encode(bestSeconds, forKey: .bestSeconds)
    }

    /// The marks as one value.
    public var marks: RecordMarks {
        get { RecordMarks(heaviestKg: heaviestKg, repRecords: repRecords, bestReps: bestReps, bestSeconds: bestSeconds) }
        set {
            heaviestKg = newValue.heaviestKg
            repRecords = newValue.repRecords
            bestReps = newValue.bestReps
            bestSeconds = newValue.bestSeconds
        }
    }

    /// This best raised by `other` (the best of the same exercise from other workouts): every mark takes the higher value; the
    /// estimate, with its set, reps and date, is replaced when the other one is higher, or equal and earlier; for an exercise without
    /// an estimate the date is the earliest of the two. Taking the best of any number of bests in any order gives the same result.
    /// An estimate of this best that is no estimate any more (`withoutUnreliableEstimate`) counts as none.
    func raised(by other: PersonalBest) -> PersonalBest {
        var result = withoutUnreliableEstimate
        var merged = marks
        merged.merge(other.marks)
        result.marks = merged
        if other.estimated1RM > 0 {
            if result.estimated1RM == 0 || other.estimated1RM > result.estimated1RM
                || (other.estimated1RM == result.estimated1RM && other.date < result.date) {
                result.estimated1RM = other.estimated1RM
                result.weightKg = other.weightKg
                result.reps = other.reps
                result.date = other.date
            }
        } else if result.estimated1RM == 0 {
            result.date = min(date, other.date)
        }
        return result
    }

    /// This best without its estimate when the estimate comes from a set of more than `Estimated1RM.maximumReliableReps` reps: a best
    /// written before that cap existed can hold one (20 kg x 100 reps was "estimated" at 87 kg). The marks stay.
    var withoutUnreliableEstimate: PersonalBest {
        guard reps > Estimated1RM.maximumReliableReps else { return self }
        var result = self
        result.estimated1RM = 0
        result.weightKg = 0
        result.reps = 0
        return result
    }
}

public struct E1RMPoint: Codable, Hashable, Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public struct ExerciseSession: Identifiable, Hashable, Sendable {
    /// The CompletedWorkout id.
    public var id: UUID
    public var date: Date
    public var workoutName: String
    public var sets: [CompletedSet]
    public var isPersonalRecord: Bool

    public init(id: UUID, date: Date, workoutName: String, sets: [CompletedSet], isPersonalRecord: Bool) {
        self.id = id
        self.date = date
        self.workoutName = workoutName
        self.sets = sets
        self.isPersonalRecord = isPersonalRecord
    }
}

public struct ExerciseRecordRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var value: String
    public var date: Date?

    public init(id: String, label: String, value: String, date: Date? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.date = date
    }
}

/// Data behind the exercise-detail screen. Built by `StrengthStore.history(for:now:)`.
public struct ExerciseHistory: Equatable, Sendable {
    public var exerciseID: String
    /// Newest first.
    public var sessions: [ExerciseSession]
    /// Oldest first, one point per session (best non-warm-up e1RM).
    public var e1RMSeries: [E1RMPoint]
    public var bestE1RM: Double
    /// "85 kg × 5"
    public var bestSetText: String?
    public var bestSetDate: Date?
    public var volumeLast30Days: Double
    public var sessionsLast30Days: Int
    public var records: [ExerciseRecordRow]
    /// The sets of the most recent session (what the PREVIOUS column matches), empty without history.
    public var previousSets: [PreviousSet]

    public init(
        exerciseID: String,
        sessions: [ExerciseSession],
        e1RMSeries: [E1RMPoint],
        bestE1RM: Double,
        bestSetText: String? = nil,
        bestSetDate: Date? = nil,
        volumeLast30Days: Double,
        sessionsLast30Days: Int,
        records: [ExerciseRecordRow],
        previousSets: [PreviousSet] = []
    ) {
        self.exerciseID = exerciseID
        self.sessions = sessions
        self.e1RMSeries = e1RMSeries
        self.bestE1RM = bestE1RM
        self.bestSetText = bestSetText
        self.bestSetDate = bestSetDate
        self.volumeLast30Days = volumeLast30Days
        self.sessionsLast30Days = sessionsLast30Days
        self.records = records
        self.previousSets = previousSets
    }
}
