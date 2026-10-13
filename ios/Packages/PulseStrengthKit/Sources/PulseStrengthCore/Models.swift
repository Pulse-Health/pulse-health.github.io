import Foundation

// MARK: - Vocabulary

public enum MuscleGroup: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case legs = "Legs"
    case core = "Core"

    public var id: String { rawValue }
    public var title: String { rawValue }
}

public enum Equipment: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case barbell = "Barbell"
    case dumbbell = "Dumbbell"
    case cable = "Cable"
    case machine = "Machine"
    case bodyweight = "Bodyweight"
    case other = "Other"

    public var id: String { rawValue }
    public var title: String { rawValue }
}

public enum TrackingKind: String, Codable, CaseIterable, Hashable, Sendable {
    /// Weight (kg) x reps.
    case weightReps
    /// Reps only (bodyweight). The weight column shows "BW".
    case repsOnly
    /// Duration. `LoggedSet.reps` holds seconds.
    case duration

    public var title: String {
        switch self {
        case .weightReps: return "Weight × reps"
        case .repsOnly: return "Reps"
        case .duration: return "Time"
        }
    }
}

public enum SetType: String, Codable, CaseIterable, Hashable, Sendable {
    case normal
    case warmup
    case drop
    case failure

    public var title: String {
        switch self {
        case .normal: return "Normal"
        case .warmup: return "Warm-up"
        case .drop: return "Drop set"
        case .failure: return "To failure"
        }
    }

    /// One-letter badge used in set rows ("#" is replaced by the working-set number).
    public var badge: String {
        switch self {
        case .normal: return "#"
        case .warmup: return "W"
        case .drop: return "D"
        case .failure: return "F"
        }
    }

    /// Warm-up sets are left out of volume, estimated 1RM and personal records.
    public var countsTowardVolume: Bool { self != .warmup }
}

// MARK: - Exercise library entry

public struct PreviousSet: Codable, Hashable, Sendable {
    public var weightKg: Double
    public var reps: Int

    public init(weightKg: Double, reps: Int) {
        self.weightKg = weightKg
        self.reps = reps
    }
}

public struct ExerciseDefaults: Codable, Hashable, Sendable {
    public var sets: Int
    public var weightKg: Double
    public var reps: Int
    public var restSeconds: Int

    public init(sets: Int, weightKg: Double, reps: Int, restSeconds: Int) {
        self.sets = sets
        self.weightKg = weightKg
        self.reps = reps
        self.restSeconds = restSeconds
    }
}

public struct Exercise: Identifiable, Codable, Hashable, Sendable {
    /// Stable id. Built-in exercises use short slugs ("bench"); custom ones use "custom-<uuid>".
    public var id: String
    public var name: String
    public var muscle: MuscleGroup
    /// Free text shown under the name, e.g. "Shoulders · Triceps".
    public var secondary: String
    public var equipment: Equipment
    public var tracking: TrackingKind
    /// Base name of the two form-demo frames in the IOS resources: "<key>-a" and "<key>-b" (.jpg).
    public var mediaKey: String?
    /// Best estimated 1RM from earlier sessions (kg). 0 means "no history": no PR can be flagged.
    public var previousBestE1RM: Double
    /// Last session's sets, aligned by set index (used for the PREVIOUS column).
    public var previousSets: [PreviousSet]
    public var defaults: ExerciseDefaults
    public var cues: [String]
    /// Empty-bar weight used by the plate calculator (barbell exercises only).
    public var barKg: Double
    public var isCustom: Bool

    public init(
        id: String,
        name: String,
        muscle: MuscleGroup,
        secondary: String = "",
        equipment: Equipment,
        tracking: TrackingKind = .weightReps,
        mediaKey: String? = nil,
        previousBestE1RM: Double = 0,
        previousSets: [PreviousSet] = [],
        defaults: ExerciseDefaults,
        cues: [String] = [],
        barKg: Double = 20,
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.muscle = muscle
        self.secondary = secondary
        self.equipment = equipment
        self.tracking = tracking
        self.mediaKey = mediaKey
        self.previousBestE1RM = previousBestE1RM
        self.previousSets = previousSets
        self.defaults = defaults
        self.cues = cues
        self.barKg = barKg
        self.isCustom = isCustom
    }

    /// Increment used by the - / + steppers (keypad, Watch, Live Activity).
    public var weightStepKg: Double {
        switch equipment {
        case .dumbbell: return 2
        case .barbell, .cable, .machine: return 2.5
        case .bodyweight, .other: return 1
        }
    }

    /// Reps stepper increment; durations move in 5 s steps.
    public var repsStep: Int { tracking == .duration ? 5 : 1 }

    public var tracksWeight: Bool { tracking == .weightReps }
    public var supportsPlates: Bool { equipment == .barbell && tracking == .weightReps }

    /// A user-created exercise with sensible defaults (3 sets, 90 s rest).
    public static func custom(
        name: String,
        muscle: MuscleGroup,
        equipment: Equipment,
        tracking: TrackingKind,
        id: String = "custom-" + UUID().uuidString.lowercased()
    ) -> Exercise {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Exercise(
            id: id,
            name: trimmed.isEmpty ? "Custom exercise" : trimmed,
            muscle: muscle,
            secondary: "Custom",
            equipment: equipment,
            tracking: tracking,
            mediaKey: nil,
            previousBestE1RM: 0,
            previousSets: [],
            defaults: ExerciseDefaults(
                sets: 3,
                weightKg: tracking == .weightReps ? 20 : 0,
                reps: tracking == .duration ? 45 : 10,
                restSeconds: 90
            ),
            cues: ["Your own exercise. Add a note to remember how you like to perform it."],
            barKg: 20,
            isCustom: true
        )
    }
}

// MARK: - Logged workout content

public struct LoggedSet: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var type: SetType
    public var weightKg: Double
    /// Reps, or seconds when the exercise tracks duration.
    public var reps: Int
    public var isDone: Bool
    /// Reps in reserve, 0...4 (4 means "4+"). nil = not recorded.
    public var rir: Int?

    public init(
        id: UUID = UUID(),
        type: SetType = .normal,
        weightKg: Double,
        reps: Int,
        isDone: Bool = false,
        rir: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.weightKg = weightKg
        self.reps = reps
        self.isDone = isDone
        self.rir = rir
    }
}

public struct WorkoutExercise: Identifiable, Codable, Hashable, Sendable {
    /// Unique per workout entry (the same Exercise may appear twice).
    public var id: UUID
    /// Denormalised definition so a state value is self-describing (Watch, Live Activity, sync).
    public var exercise: Exercise
    public var sets: [LoggedSet]
    public var restSeconds: Int
    /// "A", "B", ... Exercises sharing a group alternate sets. nil = not in a superset.
    public var supersetGroup: String?
    public var note: String
    /// The template entry this was created from; nil for exercises added during the workout.
    public var templateEntryID: UUID?

    public init(
        id: UUID = UUID(),
        exercise: Exercise,
        sets: [LoggedSet],
        restSeconds: Int,
        supersetGroup: String? = nil,
        note: String = "",
        templateEntryID: UUID? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.sets = sets
        self.restSeconds = restSeconds
        self.supersetGroup = supersetGroup
        self.note = note
        self.templateEntryID = templateEntryID
    }

    public var doneCount: Int { sets.filter { $0.isDone }.count }
    public var isComplete: Bool { !sets.isEmpty && doneCount == sets.count }
}

// MARK: - Templates

public struct PlannedSet: Codable, Hashable, Sendable {
    public var type: SetType
    public var weightKg: Double
    public var reps: Int

    public init(type: SetType = .normal, weightKg: Double, reps: Int) {
        self.type = type
        self.weightKg = weightKg
        self.reps = reps
    }
}

public struct TemplateEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var exercise: Exercise
    public var plannedSets: [PlannedSet]
    public var restSeconds: Int
    public var supersetGroup: String?

    public init(
        id: UUID = UUID(),
        exercise: Exercise,
        plannedSets: [PlannedSet],
        restSeconds: Int,
        supersetGroup: String? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.plannedSets = plannedSets
        self.restSeconds = restSeconds
        self.supersetGroup = supersetGroup
    }
}

public struct WorkoutTemplate: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var entries: [TemplateEntry]
    public var lastPerformed: Date?

    public init(id: UUID = UUID(), name: String, entries: [TemplateEntry], lastPerformed: Date? = nil) {
        self.id = id
        self.name = name
        self.entries = entries
        self.lastPerformed = lastPerformed
    }

    /// Rough duration: working time per set (45 s) plus rest, rounded to 5 minutes.
    public var estimatedMinutes: Int {
        var seconds = 0
        for entry in entries {
            for set in entry.plannedSets {
                seconds += 45 + (set.type == .warmup ? max(30, entry.restSeconds * 2 / 5) : entry.restSeconds)
            }
        }
        let minutes = Int((Double(seconds) / 60.0 / 5.0).rounded()) * 5
        return max(5, minutes)
    }
}
