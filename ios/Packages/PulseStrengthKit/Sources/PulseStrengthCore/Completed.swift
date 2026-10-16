import Foundation

// MARK: - Finished workouts

public struct CompletedSet: Codable, Hashable, Sendable {
    public var type: SetType
    public var weightKg: Double
    public var reps: Int
    public var rir: Int?
    /// When the set was logged (`LoggedSet.doneAt`); nil for history saved before the time was recorded.
    public var loggedAt: Date?

    public init(type: SetType, weightKg: Double, reps: Int, rir: Int? = nil, loggedAt: Date? = nil) {
        self.type = type
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
        self.loggedAt = loggedAt
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

    public init(
        id: UUID = UUID(),
        exerciseID: String,
        name: String,
        muscle: MuscleGroup,
        mediaKey: String?,
        tracking: TrackingKind,
        sets: [CompletedSet],
        isPersonalRecord: Bool,
        bestE1RM: Double
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
    }
}

public struct PersonalRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String { exerciseID }
    public var exerciseID: String
    public var exerciseName: String
    public var weightKg: Double
    public var reps: Int
    public var estimated1RM: Double
    /// The best estimated 1RM before this workout.
    public var previousBest: Double

    public init(exerciseID: String, exerciseName: String, weightKg: Double, reps: Int, estimated1RM: Double, previousBest: Double) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.weightKg = weightKg
        self.reps = reps
        self.estimated1RM = estimated1RM
        self.previousBest = previousBest
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
    /// Warm-up sets excluded; weight-tracking exercises only.
    public var volumeKg: Double
    public var loggedSets: Int
    public var averageHeartRate: Int?
    /// Mean of recorded RIR values; nil when none recorded.
    public var averageRIR: Double?
    public var exercises: [CompletedExercise]
    public var personalRecords: [PersonalRecord]
    public var muscleSets: [MuscleSets]
    /// The heart-rate samples recorded during the workout, oldest first (`WorkoutState.heartRateSeries`); nil without any, and for
    /// history saved before they were kept.
    public var heartRateSeries: [HeartRateSample]?

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
        muscleSets: [MuscleSets],
        heartRateSeries: [HeartRateSample]? = nil
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
        self.heartRateSeries = heartRateSeries
    }
}

// MARK: - Personal bests and per-exercise history

public struct PersonalBest: Codable, Hashable, Sendable {
    public var exerciseID: String
    public var estimated1RM: Double
    public var weightKg: Double
    public var reps: Int
    public var date: Date

    public init(exerciseID: String, estimated1RM: Double, weightKg: Double, reps: Int, date: Date) {
        self.exerciseID = exerciseID
        self.estimated1RM = estimated1RM
        self.weightKg = weightKg
        self.reps = reps
        self.date = date
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

    public init(
        exerciseID: String,
        sessions: [ExerciseSession],
        e1RMSeries: [E1RMPoint],
        bestE1RM: Double,
        bestSetText: String? = nil,
        bestSetDate: Date? = nil,
        volumeLast30Days: Double,
        sessionsLast30Days: Int,
        records: [ExerciseRecordRow]
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
    }
}
