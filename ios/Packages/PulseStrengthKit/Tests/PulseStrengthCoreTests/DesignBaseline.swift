import Foundation
@testable import PulseStrengthCore

/// The previous results the built-in exercise library used to carry for every design exercise (a best estimated 1RM and the last
/// session's sets). The shipped library no longer carries any history, because it made a new user's first sets compare against records
/// nobody set. The design-parity tests (presenter goldens, personal records, the demo data) still need that baseline, so they apply it
/// explicitly through `DesignBaseline.apply`.
enum DesignBaseline {
    /// How many of the first sets of an exercise's last session were warm-ups (the bench press: 50 x 8 and 70 x 5). The demo history
    /// and the presenter match warm-up rows to warm-ups, so the baseline has to say which sets they were.
    static let warmups: [String: Int] = ["bench": 2]

    /// exercise id -> (best estimated 1RM in kg, last session's sets as (kg, reps)).
    static let values: [String: (e1RM: Double, sets: [(Double, Int)])] = [
        "bench": (99, [(50, 8), (70, 5), (80, 6), (80, 6), (80, 5)]),
        "incline": (38, [(26, 10), (26, 10), (26, 9)]),
        "crossover": (22, [(15, 12), (15, 12), (15, 11)]),
        "pushup": (0, [(0, 15)]),
        "cpress": (0, []),
        "dips": (0, []),
        "pullup": (0, [(0, 8)]),
        "pulldown": (0, [(55, 10)]),
        "brow": (0, [(60, 8)]),
        "crow": (0, [(50, 10)]),
        "dbrow": (0, []),
        "deadlift": (0, [(100, 5)]),
        "facepull": (0, [(20, 15)]),
        "ohp": (58, [(45, 8), (45, 8), (45, 7)]),
        "dbpress": (0, []),
        "lateral": (12.5, [(8, 15), (8, 15), (8, 14)]),
        "rdelt": (0, []),
        "curl": (0, [(30, 10)]),
        "dbcurl": (0, [(12, 10)]),
        "hammer": (0, []),
        "pushdown": (43, [(30, 12), (30, 12), (30, 11)]),
        "skull": (0, [(25, 10)]),
        "ohtri": (0, []),
        "preacher": (0, []),
        "squat": (0, [(80, 6)]),
        "legpress": (0, [(140, 10)]),
        "rdl": (0, [(70, 8)]),
        "lunge": (0, []),
        "legext": (0, [(45, 12)]),
        "legcurl": (0, [(35, 12)]),
        "calf": (0, [(60, 12)]),
        "hipthrust": (0, [(80, 8)]),
        "plank": (0, [(0, 45)]),
        "cablecrunch": (0, [(35, 15)]),
        "hlr": (0, []),
        "abwheel": (0, []),
    ]

    /// The exercise with the design's previous results (unchanged when the id has no baseline).
    static func apply(_ exercise: Exercise) -> Exercise {
        guard let baseline = values[exercise.id] else { return exercise }
        var result = exercise
        result.previousBestE1RM = baseline.e1RM
        let warmupCount = warmups[exercise.id] ?? 0
        result.previousSets = baseline.sets.enumerated().map { index, set in
            PreviousSet(weightKg: set.0, reps: set.1, type: index < warmupCount ? .warmup : nil)
        }
        return result
    }

    /// A built-in exercise with the design's previous results.
    static func exercise(id: String) -> Exercise? {
        ExerciseLibrary.exercise(id: id).map(apply)
    }

    /// The whole built-in library with the design's previous results.
    static var library: [Exercise] { ExerciseLibrary.builtIn.map(apply) }
}
