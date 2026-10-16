import Foundation

// MARK: - Verdict and reasons

/// What the coach tells the user to do with a lift next time.
public enum Verdict: String, Codable, CaseIterable, Sendable {
    /// Add one equipment step of weight.
    case progress
    /// Keep the same weight and reps.
    case hold
    /// Take a bounded amount off the weight.
    case reduce
    /// Keep the weight and add a rep, because the smallest weight step would be too big a jump.
    case addRep
    /// The last session has no (or too little) reps-in-reserve data to judge effort. Never an automatic progress.
    case noEffortData
    /// Nothing to say: too little history, an unsupported exercise, or the user asked to avoid this muscle.
    case insufficientData

    /// True when the recommendation names a weight and reps to aim for.
    public var hasTarget: Bool {
        switch self {
        case .progress, .hold, .reduce, .addRep: return true
        case .noEffortData, .insufficientData: return false
        }
    }
}

/// Why the engine reached a verdict. Texts are written from these (see `TemplateWriter`); they are also what an evaluation checks.
public enum ReasonCode: String, Codable, CaseIterable, Sendable {
    // Progress / add a rep.
    case cleanSessionsWithReserve
    case stepExceedsCap
    // Hold.
    case awaitingSecondCleanSession
    case moderateEffort
    case lastSessionNearFailure
    case returningAfterBreak
    // Reduce.
    case repsFellAtSameLoad
    case lighterWeekDue
    case reduceExceedsCap
    // Data problems.
    case noRIRRecorded
    case tooFewSessions
    case unsupportedTracking
    case suspectSetExcluded
    case audienceRestricted
}

// MARK: - Recommendation

/// The engine's answer for one exercise. Everything the coach says is derived from this value.
public struct Recommendation: Equatable, Codable, Sendable {
    public var exerciseID: String
    public var verdict: Verdict
    /// Kilograms to aim for; nil unless `verdict.hasTarget`.
    public var targetWeightKg: Double?
    /// Reps to aim for; nil unless `verdict.hasTarget`.
    public var targetReps: Int?
    public var reasons: [ReasonCode]
    /// How many valid past sessions the verdict is based on.
    public var sessionsUsed: Int
    /// The `ProgressionEngine.version` that produced it.
    public var engineVersion: Int

    public init(
        exerciseID: String,
        verdict: Verdict,
        targetWeightKg: Double? = nil,
        targetReps: Int? = nil,
        reasons: [ReasonCode] = [],
        sessionsUsed: Int = 0,
        engineVersion: Int = ProgressionEngine.version
    ) {
        self.exerciseID = exerciseID
        self.verdict = verdict
        self.targetWeightKg = targetWeightKg
        self.targetReps = targetReps
        self.reasons = reasons
        self.sessionsUsed = sessionsUsed
        self.engineVersion = engineVersion
    }
}

// MARK: - Audience

/// What the host app knows about the person, so the coach can be more careful.
///
/// The Pulse app supplies it (it collects age group and limitations); the standalone host knows nothing and uses `.unknown`.
public struct AudienceProfile: Equatable, Sendable {
    public enum AgeGroup: String, Codable, Sendable {
        case adult
        case minor
        case unknown
    }

    public var ageGroup: AgeGroup
    /// Muscle groups the person declared they want to avoid loading. The coach stays silent about them.
    public var avoidMuscles: Set<MuscleGroup>

    public init(ageGroup: AgeGroup = .unknown, avoidMuscles: Set<MuscleGroup> = []) {
        self.ageGroup = ageGroup
        self.avoidMuscles = avoidMuscles
    }

    /// Nothing known: the careful defaults apply.
    public static let unknown = AudienceProfile()

    /// A person known to be an adult with no declared limitations.
    public static let adult = AudienceProfile(ageGroup: .adult)

    /// Minors and unknown audiences get a smaller largest weight jump.
    public var isRestricted: Bool { ageGroup != .adult }

    /// Whether the in-workout "beat your best" tip is shown. Hidden for people known to be minors.
    ///
    /// Deliberately not hidden for `.unknown`: that would silently remove an existing feature from every standalone install. Making
    /// it `isRestricted` instead is a one-line change once the product owner decides.
    public var showsPersonalRecordTips: Bool { ageGroup != .minor }
}

// MARK: - Configuration

/// Thresholds of the progression policy.
///
/// **Starting values. They have not been signed off by a qualified coach.** They are values in one place so that sign-off can
/// change them without touching the engine, and the golden tests (`CoachEngineTests`) pin what each does.
public struct CoachConfig: Equatable, Sendable {
    /// Valid sessions needed before any recommendation (the engine never uses fewer than two).
    public var minimumSessions = 2
    /// Mean reps in reserve needed in each of the last two sessions to move up.
    public var progressMinimumRIR = 2.0
    /// A session has effort data when at least this share of its sets at the working weight carry a reps-in-reserve value.
    public var effortCoverage = 2.0 / 3.0
    /// Mean reps in reserve at or below this holds the weight.
    public var holdMaximumRIR = 1.0
    /// Reps may drop by up to this many per set on average and still count as "no drop".
    public var repsFallTolerance = 0.5
    /// A reduce takes this share of the weight (rounded down to the increment, at least one increment).
    public var reduceFraction = 0.05
    /// A reduce larger than this share of the weight is not suggested; the engine holds instead.
    public var maximumReduceFraction = 0.10
    /// Largest relative weight increase suggested. If the smallest step is bigger, the engine says add a rep instead.
    public var maximumJumpFraction = 0.075
    /// The same for minors and unknown audiences.
    public var maximumJumpFractionRestricted = 0.05
    /// More days than this since the last session counts as returning after a break.
    public var breakDays = 28
    /// Reps above which a set is not trusted when building the reference for the suspect-set check.
    public var maximumRepsForReference = 10
    /// A set whose estimated 1RM is more than this many times the lifter's recent typical best is treated as a typo and ignored.
    public var suspectRatio = 1.25
    /// This many consecutive sessions with a higher weight than the one before → suggest a lighter week. 0 turns it off.
    public var lighterWeekAfterIncreases = 6
    /// Largest rep target ever suggested.
    public var maximumTargetReps = 30
    /// Weight increment per equipment (kg). Falls back to the exercise's keypad step when an entry is missing.
    public var incrementsKg: [Equipment: Double] = [
        .barbell: 2.5, .dumbbell: 2, .cable: 2.5, .machine: 2.5, .bodyweight: 1, .other: 1,
    ]

    public init() {}

    /// The weight increment for `exercise`, always positive.
    public func increment(for exercise: Exercise) -> Double {
        let configured = incrementsKg[exercise.equipment] ?? exercise.weightStepKg
        if configured.isFinite, configured > 0 { return configured }
        return exercise.weightStepKg
    }

    /// The largest relative jump that applies to `audience`.
    public func jumpCap(for audience: AudienceProfile) -> Double {
        audience.isRestricted ? min(maximumJumpFractionRestricted, maximumJumpFraction) : maximumJumpFraction
    }
}
