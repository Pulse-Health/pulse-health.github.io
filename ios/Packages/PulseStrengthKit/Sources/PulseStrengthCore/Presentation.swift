import Foundation

/// Everything the active-workout screen needs, derived from a `WorkoutState` by
/// `WorkoutPresenter.present(_:now:recovery:)`. Views render this and never recompute it.
/// All strings are display-ready (locale independent: "." decimal, "," thousands).
public struct ActiveWorkoutPresentation: Equatable, Sendable {

    public struct Segment: Equatable, Sendable {
        /// 0...1 share of this exercise's sets that are logged.
        public var fraction: Double
        public var isCurrent: Bool

        public init(fraction: Double, isCurrent: Bool) {
            self.fraction = fraction
            self.isCurrent = isCurrent
        }
    }

    public struct Header: Equatable, Sendable {
        public var title: String
        /// "24:18", "1:02:03" or, when paused, "Paused · 24:18".
        public var clockText: String
        public var isPaused: Bool
        /// Logged volume without separators of unit, e.g. "1,980" (warm-up sets excluded).
        public var volumeText: String
        /// "7 of 19"
        public var setsText: String
        /// "128" or "–" when unknown.
        public var heartRateText: String
        public var hasHeartRate: Bool
        public var segments: [Segment]

        public init(
            title: String,
            clockText: String,
            isPaused: Bool,
            volumeText: String,
            setsText: String,
            heartRateText: String,
            hasHeartRate: Bool,
            segments: [Segment]
        ) {
            self.title = title
            self.clockText = clockText
            self.isPaused = isPaused
            self.volumeText = volumeText
            self.setsText = setsText
            self.heartRateText = heartRateText
            self.hasHeartRate = hasHeartRate
            self.segments = segments
        }
    }

    public struct Navigator: Equatable, Sendable {
        /// 1-based.
        public var position: Int
        public var total: Int
        public var canGoPrevious: Bool
        public var canGoNext: Bool

        public init(position: Int, total: Int, canGoPrevious: Bool, canGoNext: Bool) {
            self.position = position
            self.total = total
            self.canGoPrevious = canGoPrevious
            self.canGoNext = canGoNext
        }
    }

    public enum RecoveryLevel: String, Equatable, Sendable {
        /// >= 80 %
        case good
        /// 60...79 %
        case fair
        /// < 60 %
        case low
    }

    public struct SetRow: Identifiable, Equatable, Sendable {
        public var id: UUID
        /// "1", "2", ... for normal sets (numbered in order), "W", "D" or "F".
        public var number: String
        public var type: SetType
        /// "80 × 6", "8 reps", "45 s" or "–".
        public var previousText: String
        /// "82.5", "BW" (repsOnly) or "–" (duration).
        public var weightText: String
        /// Reps or seconds as text.
        public var repsText: String
        public var weightEditable: Bool
        public var isDone: Bool
        /// The first pending set of the current exercise (highlighted).
        public var isNext: Bool
        public var isPersonalRecord: Bool
        public var estimated1RM: Int?
        public var rir: Int?
        /// "RIR 3" / "RIR 4+" when recorded on a done set.
        public var rirText: String?
        public var accessibilityLabel: String

        public init(
            id: UUID,
            number: String,
            type: SetType,
            previousText: String,
            weightText: String,
            repsText: String,
            weightEditable: Bool,
            isDone: Bool,
            isNext: Bool,
            isPersonalRecord: Bool,
            estimated1RM: Int? = nil,
            rir: Int? = nil,
            rirText: String? = nil,
            accessibilityLabel: String
        ) {
            self.id = id
            self.number = number
            self.type = type
            self.previousText = previousText
            self.weightText = weightText
            self.repsText = repsText
            self.weightEditable = weightEditable
            self.isDone = isDone
            self.isNext = isNext
            self.isPersonalRecord = isPersonalRecord
            self.estimated1RM = estimated1RM
            self.rir = rir
            self.rirText = rirText
            self.accessibilityLabel = accessibilityLabel
        }
    }

    public struct Card: Equatable, Sendable {
        public var exerciseID: UUID
        public var exercise: Exercise
        public var recoveryPercent: Int
        public var recoveryLevel: RecoveryLevel
        /// "Superset A" or nil.
        public var supersetLabel: String?
        public var restSeconds: Int
        /// "2:30" or "Off".
        public var restText: String
        public var note: String
        /// "kg", "Added" (repsOnly) or "" (duration).
        public var weightColumnTitle: String
        /// "Reps" or "Sec".
        public var repsColumnTitle: String
        /// Coach suggestion shown while no rest timer is running (nil otherwise).
        public var coachTip: String?
        public var rows: [SetRow]

        public init(
            exerciseID: UUID,
            exercise: Exercise,
            recoveryPercent: Int,
            recoveryLevel: RecoveryLevel,
            supersetLabel: String? = nil,
            restSeconds: Int,
            restText: String,
            note: String,
            weightColumnTitle: String,
            repsColumnTitle: String,
            coachTip: String? = nil,
            rows: [SetRow]
        ) {
            self.exerciseID = exerciseID
            self.exercise = exercise
            self.recoveryPercent = recoveryPercent
            self.recoveryLevel = recoveryLevel
            self.supersetLabel = supersetLabel
            self.restSeconds = restSeconds
            self.restText = restText
            self.note = note
            self.weightColumnTitle = weightColumnTitle
            self.repsColumnTitle = repsColumnTitle
            self.coachTip = coachTip
            self.rows = rows
        }
    }

    public enum DockPhase: Equatable, Sendable {
        case running
        case finished
    }

    public struct Dock: Equatable, Sendable {
        public var phase: DockPhase
        public var remainingSeconds: Int
        public var totalSeconds: Int
        /// Remaining / total (1 when finished), clamped 0...1.
        public var fraction: Double
        /// "1:12", or "Go" when finished.
        public var remainingText: String
        /// "Next · Set 4 · 82.5 kg × 6" or "All sets logged".
        public var nextSetText: String
        /// Shows the "Reps left" selector (last logged set exists, is done and is not a warm-up).
        public var showsRIR: Bool
        public var rirSelection: Int?
        public var isPaused: Bool

        public init(
            phase: DockPhase,
            remainingSeconds: Int,
            totalSeconds: Int,
            fraction: Double,
            remainingText: String,
            nextSetText: String,
            showsRIR: Bool,
            rirSelection: Int? = nil,
            isPaused: Bool
        ) {
            self.phase = phase
            self.remainingSeconds = remainingSeconds
            self.totalSeconds = totalSeconds
            self.fraction = fraction
            self.remainingText = remainingText
            self.nextSetText = nextSetText
            self.showsRIR = showsRIR
            self.rirSelection = rirSelection
            self.isPaused = isPaused
        }
    }

    public struct Totals: Equatable, Sendable {
        public var loggedSets: Int
        public var totalSets: Int
        public var volumeKg: Double
        public var completedExercises: Int

        public init(loggedSets: Int, totalSets: Int, volumeKg: Double, completedExercises: Int) {
            self.loggedSets = loggedSets
            self.totalSets = totalSets
            self.volumeKg = volumeKg
            self.completedExercises = completedExercises
        }
    }

    public struct FinishCheck: Equatable, Sendable {
        public var loggedSets: Int
        public var unloggedSets: Int
        /// Nothing logged: only "Keep training" / "Discard" make sense.
        public var canFinish: Bool
        public var title: String
        public var message: String
        public var templateDiff: TemplateDiff
        /// "Changes: 1 added, 1 removed." (or "none").
        public var diffMessage: String
        /// Offer "Update template?" after finishing.
        public var asksToUpdateTemplate: Bool

        public init(
            loggedSets: Int,
            unloggedSets: Int,
            canFinish: Bool,
            title: String,
            message: String,
            templateDiff: TemplateDiff,
            diffMessage: String,
            asksToUpdateTemplate: Bool
        ) {
            self.loggedSets = loggedSets
            self.unloggedSets = unloggedSets
            self.canFinish = canFinish
            self.title = title
            self.message = message
            self.templateDiff = templateDiff
            self.diffMessage = diffMessage
            self.asksToUpdateTemplate = asksToUpdateTemplate
        }
    }

    public var header: Header
    public var navigator: Navigator?
    public var card: Card?
    public var dock: Dock?
    /// Undo snackbar text ("Removed Cable crossover") while an undo entry is still valid.
    public var undoText: String?
    public var isEmpty: Bool
    public var totals: Totals
    public var finishCheck: FinishCheck

    public init(
        header: Header,
        navigator: Navigator? = nil,
        card: Card? = nil,
        dock: Dock? = nil,
        undoText: String? = nil,
        isEmpty: Bool,
        totals: Totals,
        finishCheck: FinishCheck
    ) {
        self.header = header
        self.navigator = navigator
        self.card = card
        self.dock = dock
        self.undoText = undoText
        self.isEmpty = isEmpty
        self.totals = totals
        self.finishCheck = finishCheck
    }
}

/// What changed relative to the template the workout was started from.
public struct TemplateDiff: Codable, Equatable, Hashable, Sendable {
    public var added: Int
    public var removed: Int
    public var reordered: Bool

    public init(added: Int = 0, removed: Int = 0, reordered: Bool = false) {
        self.added = added
        self.removed = removed
        self.reordered = reordered
    }

    public var isEmpty: Bool { added == 0 && removed == 0 && !reordered }

    /// "1 added, 1 removed, new order" ("none" when empty).
    public var summary: String {
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if removed > 0 { parts.append("\(removed) removed") }
        if reordered { parts.append("new order") }
        return parts.isEmpty ? "none" : parts.joined(separator: ", ")
    }
}

/// Muscle recovery lookup (percent 0...100). The Pulse app injects its real model; this is the demo data.
public typealias RecoveryProvider = @Sendable (MuscleGroup) -> Int

public enum DemoRecovery {
    public static let provider: RecoveryProvider = { muscle in
        switch muscle {
        case .chest: return 88
        case .back: return 100
        case .shoulders: return 82
        case .arms: return 79
        case .legs: return 64
        case .core: return 100
        }
    }
}
