import Foundation

/// Everything the active-workout screen needs, derived from a `WorkoutState` by
/// `WorkoutPresenter.present(_:now:recovery:locale:)`. Views render this and never recompute it.
/// All strings are display-ready: weights are in the workout's unit (`WorkoutSettings.weightUnit`) and use the decimal and grouping
/// separators of the locale the presentation was made for (en_US by default: "." decimal, "," thousands).
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
        /// Logged volume in the workout's unit without the unit symbol, e.g. "1,980" (warm-up sets excluded).
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
        /// The previous session's set that belongs to this row as text: "80 × 6", "+10 × 8" (a reps-only exercise with an added load),
        /// "8 reps" or "45 s"; "–" when the previous session had no such set (see `previousSet`).
        public var previousText: String
        /// "82.5", "+10" / "−20" or "BW" (a reps-only exercise that allows an added load), "BW" (other reps-only) or "–" (duration).
        public var weightText: String
        /// Reps or seconds as text.
        public var repsText: String
        /// True when the weight cell can be edited: weight-tracking exercises and reps-only exercises that allow an added load.
        public var weightEditable: Bool
        public var isDone: Bool
        /// The first pending set of the current exercise (highlighted).
        public var isNext: Bool
        public var isPersonalRecord: Bool
        /// The estimated one-rep max of an estimated-1RM record set, rounded to a whole number of the workout's unit (nil for a
        /// record of another kind).
        public var estimated1RM: Int?
        public var rir: Int?
        /// "RIR 3" / "RIR 4+" when recorded on a done set.
        public var rirText: String?
        public var accessibilityLabel: String
        /// The kind of record a logged set is (`isPersonalRecord` is `prKind != nil`); nil for a set that is none.
        public var prKind: PRKind?
        /// The set of the previous session that this row is matched to (warm-ups with warm-ups, working sets with working sets, both in
        /// order), nil without one. Carries the set's type and reps in reserve.
        public var previousSet: PreviousSet?

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
            accessibilityLabel: String,
            prKind: PRKind? = nil,
            previousSet: PreviousSet? = nil
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
            self.prKind = prKind
            self.previousSet = previousSet
        }
    }

    public struct Card: Equatable, Sendable {
        public var exerciseID: UUID
        public var exercise: Exercise
        public var recoveryPercent: Int
        public var recoveryLevel: RecoveryLevel
        /// False when `recoveryPercent` is only the default 100 of a history without a recent workout (`RecoveryEstimate.hasData`):
        /// the screen then leaves the recovery line out instead of presenting it as a measurement.
        public var recoveryHasData: Bool
        /// "Superset A" or nil.
        public var supersetLabel: String?
        public var restSeconds: Int
        /// "2:30" or "Off".
        public var restText: String
        public var note: String
        /// The unit symbol ("kg" or "lb"), "Added" (repsOnly) or "" (duration).
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
            recoveryHasData: Bool = true,
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
            self.recoveryHasData = recoveryHasData
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
        /// "Next · Set 4 · 82.5 kg × 6" (or "135 lb × 6") or "All sets logged".
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

    /// The running timed set (a stopwatch towards the seconds of a set of an exercise that tracks duration).
    public struct TimedSetPresentation: Equatable, Sendable {
        public var exerciseID: UUID
        public var setID: UUID
        /// 1-based position of the set among the sets of its exercise.
        public var setNumber: Int
        /// Whole seconds timed so far (frozen while the workout is paused).
        public var elapsedSeconds: Int
        public var targetSeconds: Int
        /// `targetSeconds - elapsedSeconds`, never below 0.
        public var remainingSeconds: Int
        /// True once the elapsed time has reached the target (`targetSeconds` above 0). The reducer does not log the set by itself:
        /// the screen sends `stopTimedSet` (the controller has no clock of its own).
        public var isOverTarget: Bool
        public var isPaused: Bool
        /// "0:34" (m:ss, h:mm:ss from one hour).
        public var elapsedText: String
        public var targetText: String
        public var remainingText: String

        public init(
            exerciseID: UUID,
            setID: UUID,
            setNumber: Int,
            elapsedSeconds: Int,
            targetSeconds: Int,
            remainingSeconds: Int,
            isOverTarget: Bool,
            isPaused: Bool,
            elapsedText: String,
            targetText: String,
            remainingText: String
        ) {
            self.exerciseID = exerciseID
            self.setID = setID
            self.setNumber = setNumber
            self.elapsedSeconds = elapsedSeconds
            self.targetSeconds = targetSeconds
            self.remainingSeconds = remainingSeconds
            self.isOverTarget = isOverTarget
            self.isPaused = isPaused
            self.elapsedText = elapsedText
            self.targetText = targetText
            self.remainingText = remainingText
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
        /// "Changes: 1 added, Bench Press weight, Squat sets." (or "none"); with `StrengthPreferences.askToUpdateTemplate`
        /// `.structureOnly` (and `.never`) only the exercises added, removed or reordered are named.
        public var diffMessage: String
        /// Offer "Update template?" after finishing: a template exists and `StrengthPreferences.askToUpdateTemplate` says its
        /// changes (`.whenChanged`: the exercises and the sets, weights, reps, rest and set types of the kept ones; `.structureOnly`:
        /// the exercises only; `.never`: none) are worth asking about.
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
    /// The running timed set; nil when none runs. No rest dock is shown while it is set.
    public var timedSet: TimedSetPresentation?

    public init(
        header: Header,
        navigator: Navigator? = nil,
        card: Card? = nil,
        dock: Dock? = nil,
        undoText: String? = nil,
        isEmpty: Bool,
        totals: Totals,
        finishCheck: FinishCheck,
        timedSet: TimedSetPresentation? = nil
    ) {
        self.header = header
        self.navigator = navigator
        self.card = card
        self.dock = dock
        self.undoText = undoText
        self.isEmpty = isEmpty
        self.totals = totals
        self.finishCheck = finishCheck
        self.timedSet = timedSet
    }
}

/// What changed relative to the template the workout was started from: the exercises added, removed and reordered, and (when the
/// template is known, see `TemplateDiff.compute(for:against:)`) the kept exercises whose sets or rest changed.
public struct TemplateDiff: Codable, Equatable, Hashable, Sendable {
    /// What can differ in a kept exercise.
    public enum Change: String, Codable, CaseIterable, Hashable, Sendable {
        /// The number of sets (warm-ups included).
        case setCount
        /// The weight of a working set (weight-tracking exercises and added loads).
        case weight
        /// The reps (seconds) of a working set.
        case reps
        /// The rest between the sets.
        case restSeconds
        /// The kind of a set (normal, warm-up, drop, failure).
        case setType
    }

    /// A kept exercise whose sets or rest differ from the template's entry.
    public struct ChangedExercise: Codable, Hashable, Sendable, Identifiable {
        /// The template entry the exercise was started from.
        public var entryID: UUID
        public var name: String
        public var kinds: Set<Change>

        public var id: UUID { entryID }

        public init(entryID: UUID, name: String, kinds: Set<Change>) {
            self.entryID = entryID
            self.name = name
            self.kinds = kinds
        }
    }

    public var added: Int
    public var removed: Int
    public var reordered: Bool
    /// The kept exercises whose sets or rest changed, in workout order; empty when the template was not compared.
    public var changedExercises: [ChangedExercise]

    public init(added: Int = 0, removed: Int = 0, reordered: Bool = false, changedExercises: [ChangedExercise] = []) {
        self.added = added
        self.removed = removed
        self.reordered = reordered
        self.changedExercises = changedExercises
    }

    private enum CodingKeys: String, CodingKey {
        case added, removed, reordered, changedExercises
    }

    // `changedExercises` came later: a diff written before it has none.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.added = try container.decode(Int.self, forKey: .added)
        self.removed = try container.decode(Int.self, forKey: .removed)
        self.reordered = try container.decode(Bool.self, forKey: .reordered)
        self.changedExercises = try container.decodeIfPresent([ChangedExercise].self, forKey: .changedExercises) ?? []
    }

    /// True when exercises were added, removed or reordered.
    public var hasStructureChanges: Bool { added > 0 || removed > 0 || reordered }

    /// True when nothing changed at all: no exercise added, removed or reordered and no kept exercise with other sets or rest.
    public var isEmpty: Bool { !hasStructureChanges && changedExercises.isEmpty }

    /// "1 added, 1 removed, new order, Bench Press weight, Squat sets" ("none" when empty): the structure first, then the first two
    /// changed exercises with what changed in them, then "and 2 more" for the rest.
    public var summary: String { text(includingLoads: true) }

    /// `summary` without the changed exercises: "1 added, 1 removed, new order" ("none" when the structure is unchanged).
    public var structureSummary: String { text(includingLoads: false) }

    /// How many changed exercises `summary` names.
    private static let namedChanges = 2

    private func text(includingLoads: Bool) -> String {
        var parts: [String] = []
        if added > 0 { parts.append("\(added) added") }
        if removed > 0 { parts.append("\(removed) removed") }
        if reordered { parts.append("new order") }
        var more = 0
        if includingLoads {
            let named = changedExercises.prefix(Self.namedChanges)
            for item in named {
                parts.append(String(format: "%@ %@", item.name, Self.kindsText(item.kinds)))
            }
            more = changedExercises.count - named.count
        }
        guard !parts.isEmpty else { return "none" }
        let joined = parts.joined(separator: ", ")
        return more > 0 ? String(format: "%@ and %ld more", joined, more) : joined
    }

    /// "weight", "weight and reps", "sets, weight and rest": the changes in the order of `Change.allCases`.
    private static func kindsText(_ kinds: Set<Change>) -> String {
        let names = Change.allCases.filter { kinds.contains($0) }.map { change -> String in
            switch change {
            case .setCount: return "sets"
            case .weight: return "weight"
            case .reps: return "reps"
            case .restSeconds: return "rest"
            case .setType: return "set types"
            }
        }
        guard let last = names.last else { return "" }
        if names.count == 1 { return last }
        return String(format: "%@ and %@", names.dropLast().joined(separator: ", "), last)
    }
}

/// Muscle recovery lookup (percent 0...100). By default the engine estimates it from the finished workouts (`RecoveryEstimator`);
/// the Pulse app can inject its own model.
public typealias RecoveryProvider = @Sendable (MuscleGroup) -> Int

/// Fixed, invented recovery percentages for previews, UI tests and tests. The app itself never uses them.
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
