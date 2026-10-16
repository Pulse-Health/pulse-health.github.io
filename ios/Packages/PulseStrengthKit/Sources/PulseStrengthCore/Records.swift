import Foundation

// MARK: - Kinds of personal record

/// The kind of personal record a set broke. A set that breaks several carries the first of this list: the estimated 1RM, then the
/// heaviest weight, then a rep record, then reps, then duration.
public enum PRKind: Codable, Hashable, Sendable {
    /// The estimated one-rep max (Epley, sets of 1...`Estimated1RM.maximumReliableReps` reps) beat the best before.
    case estimated1RM
    /// More weight than any set before, whatever its reps.
    case heaviest
    /// More weight than any earlier set with at least `reps` reps. `RecordMarks.openEndedReps` (13) stands for "13 or more".
    case repRecord(reps: Int)
    /// More reps than any earlier set without added weight (reps-only exercises).
    case reps
    /// A longer hold than any earlier timed set (duration exercises).
    case duration

    // Stored as one string, so that every platform reads it the same way: "estimated1RM", "heaviest", "reps", "duration" or
    // "repRecord:5". A string this version does not know cannot be decoded (the types that hold a kind read that as "no kind").
    private static let repRecordPrefix = "repRecord:"

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        switch text {
        case "estimated1RM": self = .estimated1RM
        case "heaviest": self = .heaviest
        case "reps": self = .reps
        case "duration": self = .duration
        default:
            guard text.hasPrefix(Self.repRecordPrefix), let reps = Int(text.dropFirst(Self.repRecordPrefix.count)), reps >= 1 else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown record kind \(text)")
                )
            }
            self = .repRecord(reps: reps)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .estimated1RM: try container.encode("estimated1RM")
        case .heaviest: try container.encode("heaviest")
        case let .repRecord(reps): try container.encode(Self.repRecordPrefix + String(reps))
        case .reps: try container.encode("reps")
        case .duration: try container.encode("duration")
        }
    }

    /// Which kind wins when one set breaks several (higher first).
    var rank: Int {
        switch self {
        case .estimated1RM: return 5
        case .heaviest: return 4
        case .repRecord: return 3
        case .reps: return 2
        case .duration: return 1
        }
    }

    /// The short label of a chip: "Est. 1RM", "Heaviest", "5RM", "13+ reps", "Most reps", "Longest hold".
    public var shortTitle: String {
        switch self {
        case .estimated1RM: return "Est. 1RM"
        case .heaviest: return "Heaviest"
        case let .repRecord(reps):
            return reps >= RecordMarks.openEndedReps ? String(format: "%ld+ reps", RecordMarks.openEndedReps) : String(format: "%ldRM", reps)
        case .reps: return "Most reps"
        case .duration: return "Longest hold"
        }
    }

    /// The kind as it is read aloud or put into a sentence: "estimated one rep max", "best 5 rep max", "longest hold".
    public var spokenTitle: String {
        switch self {
        case .estimated1RM: return "estimated one rep max"
        case .heaviest: return "heaviest weight"
        case let .repRecord(reps):
            return reps >= RecordMarks.openEndedReps
                ? String(format: "heaviest weight for %ld or more reps", RecordMarks.openEndedReps)
                : String(format: "best %ld rep max", reps)
        case .reps: return "most reps in a set"
        case .duration: return "longest hold"
        }
    }
}

// MARK: - Record marks

/// What the logged sets of one exercise achieved, apart from the estimated 1RM: the marks a new set has to beat.
///
/// Only non-warm-up sets count. How a set counts depends on the tracking kind and the load:
/// * weight x reps (weight above 0) and reps-only sets WITH an added or assisted load (any signed weight except 0) raise
///   `heaviestKg` and the `repRecords`;
/// * reps-only sets without a load (weight 0, "BW") raise `bestReps`; on an exercise that carries a load (`Exercise.carriesLoad`)
///   they also count as a load of 0, so that going from assisted to bodyweight is progress and a step back to an assisted load is not;
/// * duration sets raise `bestSeconds`.
///
/// Sets without reps (or seconds) count for nothing.
public struct RecordMarks: Codable, Hashable, Sendable {
    /// The key of `repRecords` that stands for "13 or more reps".
    public static let openEndedReps = 13

    /// The heaviest signed weight of any counted set (kg); nil without one. Negative for an exercise that was only done assisted.
    public var heaviestKg: Double?
    /// Reps -> the heaviest signed weight (kg) lifted for AT LEAST that many reps. Keys are 1...12 and 13 ("13 or more reps",
    /// `openEndedReps`); a key exists only when a set reached that many reps, so a set of 5 reps writes the keys 1...5 and a set of
    /// 20 reps writes 1...13.
    public var repRecords: [Int: Double]
    /// The most reps in a set without added weight; 0 when there is none.
    public var bestReps: Int
    /// The most seconds in a timed set; 0 when there is none.
    public var bestSeconds: Int

    public init(heaviestKg: Double? = nil, repRecords: [Int: Double] = [:], bestReps: Int = 0, bestSeconds: Int = 0) {
        self.heaviestKg = heaviestKg
        self.repRecords = repRecords
        self.bestReps = bestReps
        self.bestSeconds = bestSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case heaviestKg, repRecords, bestReps, bestSeconds
    }

    // Every entry is optional: a mark that is missing is not reached.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.heaviestKg = try container.decodeIfPresent(Double.self, forKey: .heaviestKg)
        self.repRecords = container.decodeRepRecords(forKey: .repRecords)
        self.bestReps = try container.decodeIfPresent(Int.self, forKey: .bestReps) ?? 0
        self.bestSeconds = try container.decodeIfPresent(Int.self, forKey: .bestSeconds) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(heaviestKg, forKey: .heaviestKg)
        try container.encodeRepRecords(repRecords, forKey: .repRecords)
        try container.encode(bestReps, forKey: .bestReps)
        try container.encode(bestSeconds, forKey: .bestSeconds)
    }

    /// True when no mark exists.
    public var isEmpty: Bool {
        heaviestKg == nil && repRecords.isEmpty && bestReps == 0 && bestSeconds == 0
    }

    /// The `repRecords` key of a set with `reps` reps: the reps up to 12, 13 above.
    public static func bucket(forReps reps: Int) -> Int { min(reps, openEndedReps) }

    /// What a set can raise, by the rules above.
    enum Contribution: Equatable {
        case load(weightKg: Double, reps: Int)
        case reps(Int)
        case seconds(Int)
    }

    /// What a set of an exercise tracking `tracking` contributes (`carriesLoad`: see `Exercise.carriesLoad`); empty when it counts for nothing.
    static func contributions(weightKg: Double, reps: Int, tracking: TrackingKind, carriesLoad: Bool) -> [Contribution] {
        guard reps >= 1 else { return [] }
        switch tracking {
        case .weightReps:
            return weightKg > 0 && weightKg.isFinite ? [.load(weightKg: weightKg, reps: reps)] : []
        case .repsOnly:
            guard weightKg.isFinite else { return [] }
            if abs(weightKg) >= 0.005 { return [.load(weightKg: weightKg, reps: reps)] }
            return carriesLoad ? [.reps(reps), .load(weightKg: 0, reps: reps)] : [.reps(reps)]
        case .duration:
            return [.seconds(reps)]
        }
    }

    /// Raises the marks with one contribution.
    mutating func add(_ contribution: Contribution) {
        switch contribution {
        case let .load(weightKg, reps):
            heaviestKg = max(heaviestKg ?? weightKg, weightKg)
            for key in 1...Self.bucket(forReps: reps) {
                repRecords[key] = max(repRecords[key] ?? weightKg, weightKg)
            }
        case let .reps(reps):
            bestReps = max(bestReps, reps)
        case let .seconds(seconds):
            bestSeconds = max(bestSeconds, seconds)
        }
    }

    /// Raises the marks with a set of an exercise tracking `tracking` (a warm-up counts for nothing).
    mutating func add(weightKg: Double, reps: Int, type: SetType, tracking: TrackingKind, carriesLoad: Bool = false) {
        guard type.countsTowardVolume else { return }
        for contribution in Self.contributions(weightKg: weightKg, reps: reps, tracking: tracking, carriesLoad: carriesLoad) {
            add(contribution)
        }
    }

    /// Raises every mark to the higher of the two.
    mutating func merge(_ other: RecordMarks) {
        if let heaviest = other.heaviestKg { heaviestKg = max(heaviestKg ?? heaviest, heaviest) }
        for (key, weight) in other.repRecords { repRecords[key] = max(repRecords[key] ?? weight, weight) }
        bestReps = max(bestReps, other.bestReps)
        bestSeconds = max(bestSeconds, other.bestSeconds)
    }

    /// The marks of the non-warm-up sets of a finished exercise.
    init(sets: [CompletedSet], tracking: TrackingKind, carriesLoad: Bool = false) {
        self.init()
        for set in sets {
            add(weightKg: set.weightKg, reps: set.reps, type: set.type, tracking: tracking, carriesLoad: carriesLoad)
        }
    }

    /// The marks of a finished exercise entry.
    init(entry: CompletedExercise) {
        self.init(sets: entry.sets, tracking: entry.tracking, carriesLoad: entry.carriesLoad)
    }
}

// MARK: - Coding of the rep records

extension KeyedEncodingContainer {
    /// Writes `repRecords` as a JSON object keyed by the reps as text (`{"5": 100.0}`): the default coding of a dictionary with
    /// integer keys is a flat array of alternating keys and values, which other platforms cannot read as a map.
    mutating func encodeRepRecords(_ records: [Int: Double], forKey key: Key) throws {
        var text: [String: Double] = [:]
        for (reps, weightKg) in records { text[String(reps)] = weightKg }
        try encode(text, forKey: key)
    }
}

extension KeyedDecodingContainer {
    /// Reads `repRecords` (see `encodeRepRecords`). The marks are derived data: a missing, damaged or unknown entry reads as not
    /// reached (and is made again by `StrengthData.recomputePersonalBests()`).
    func decodeRepRecords(forKey key: Key) -> [Int: Double] {
        guard let text = (try? decodeIfPresent([String: Double].self, forKey: key)) ?? nil else { return [:] }
        var records: [Int: Double] = [:]
        for (reps, weightKg) in text {
            if let key = Int(reps), key >= 1, weightKg.isFinite { records[key] = weightKg }
        }
        return records
    }
}

// MARK: - Live records

/// The personal-record rules of a workout in progress. The presenter and the summary builder share them (`PresenterSupport.analyse`),
/// so what the screen flags is what the saved workout records.
///
/// A logged, non-warm-up set is a record when it beats, by more than `margin` kilograms (reps and seconds: by at least one), a value
/// that EXISTED before the workout, in the first of these that applies:
/// * weight x reps, 1...12 reps: the estimated 1RM (`previousBestE1RM`);
/// * a load (weight x reps, or a reps-only set with an added or assisted load): the heaviest weight (`heaviestKg`), then the weight
///   for that many reps (`repRecords` of the reps, 13 for more than 12). No estimate for a reps-only set;
/// * a reps-only set without a load: `bestReps` (and, on an exercise that carries a load, a load of 0 like the above); a timed set:
///   `bestSeconds`.
///
/// A record needs its own earlier value: the first time an exercise is done, a rep range is reached or a hold is timed nothing is
/// flagged. The values rise with every logged set of the workout, so a second set has to beat the first.
struct RecordTracker {
    /// A record must beat the running best by more than this many kilograms.
    static let margin = 0.05

    /// What the workout is judged against before its first set.
    private let initialE1RM: Double
    private let initialMarks: RecordMarks
    private let tracking: TrackingKind
    private let carriesLoad: Bool
    /// The values with the logged sets of the workout so far.
    private(set) var e1RM: Double
    private var marks: RecordMarks

    /// A record that a set broke: its kind and the value of that record before the workout.
    struct Broken: Equatable {
        var kind: PRKind
        /// Kilograms (estimated 1RM, heaviest, rep record), reps or seconds.
        var previous: Double
    }

    init(_ exercise: Exercise) {
        initialE1RM = max(0, exercise.previousBestE1RM)
        initialMarks = exercise.previousRecords
        tracking = exercise.tracking
        carriesLoad = exercise.carriesLoad
        e1RM = initialE1RM
        marks = exercise.previousRecords
    }

    /// Judges a logged, non-warm-up set and raises the running values with it; the record it broke, nil for none.
    mutating func log(weightKg: Double, reps: Int) -> Broken? {
        let contributions = RecordMarks.contributions(weightKg: weightKg, reps: reps, tracking: tracking, carriesLoad: carriesLoad)
        let broken = contributions.compactMap { judge($0) }.max { $0.kind.rank < $1.kind.rank }
        for contribution in contributions { add(contribution) }
        return broken
    }

    private func judge(_ contribution: RecordMarks.Contribution) -> Broken? {
        switch contribution {
        case let .load(weightKg, reps):
            if tracking == .weightReps, initialE1RM > 0, let estimate = Estimated1RM.estimate(weightKg: weightKg, reps: reps),
               estimate > e1RM + Self.margin {
                return Broken(kind: .estimated1RM, previous: initialE1RM)
            }
            if let heaviest = initialMarks.heaviestKg, weightKg > (marks.heaviestKg ?? heaviest) + Self.margin {
                return Broken(kind: .heaviest, previous: heaviest)
            }
            let key = RecordMarks.bucket(forReps: reps)
            if let initial = initialMarks.repRecords[key], weightKg > (marks.repRecords[key] ?? initial) + Self.margin {
                return Broken(kind: .repRecord(reps: key), previous: initial)
            }
            return nil
        case let .reps(reps):
            return initialMarks.bestReps > 0 && reps > marks.bestReps
                ? Broken(kind: .reps, previous: Double(initialMarks.bestReps)) : nil
        case let .seconds(seconds):
            return initialMarks.bestSeconds > 0 && seconds > marks.bestSeconds
                ? Broken(kind: .duration, previous: Double(initialMarks.bestSeconds)) : nil
        }
    }

    private mutating func add(_ contribution: RecordMarks.Contribution) {
        marks.add(contribution)
        if case let .load(weightKg, reps) = contribution, tracking == .weightReps,
           let estimate = Estimated1RM.estimate(weightKg: weightKg, reps: reps) {
            e1RM = max(e1RM, estimate)
        }
    }
}
