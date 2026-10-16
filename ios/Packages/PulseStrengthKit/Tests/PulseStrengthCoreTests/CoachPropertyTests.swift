import XCTest
@testable import PulseStrengthCore

/// Random but plausible histories (seeded, so every run is the same) checked against properties the engine must always keep,
/// plus metamorphic checks: changes that must not change the answer.
final class CoachPropertyTests: XCTestCase {
    // MARK: Generator

    private struct Generator {
        var rng: RedLCG
        private static let ids = ["bench", "incline", "lateral", "crossover", "squat", "legpress", "deadlift", "ohp", "curl", "pushdown"]

        init(seed: UInt64) { rng = RedLCG(seed: seed) }

        mutating func exercise() -> Exercise { CoachFix.lib(rng.pick(Self.ids)) }

        mutating func sessions() -> [ExerciseSession] {
            let count = rng.int(0...9)
            var base = Double(rng.int(2...80)) * 2.5
            var day = rng.int(1...40)
            var result: [ExerciseSession] = []
            for _ in 0..<count {
                base = max(2.5, base + rng.pick([-5.0, -2.5, 0, 0, 0, 2.5, 5]))
                var sets: [CompletedSet] = []
                for _ in 0..<rng.int(1...6) {
                    let roll = rng.int(0...99)
                    let type: SetType = roll < 72 ? .normal : (roll < 82 ? .warmup : (roll < 90 ? .drop : .failure))
                    var weight = rng.chance(20) ? max(2.5, base - 10) : base
                    if rng.chance(2) { weight *= 10 }
                    if rng.chance(1) { weight = rng.pick([.nan, .infinity, -5, 0]) }
                    let reps = rng.chance(1) ? rng.pick([0, -3, 5_000]) : rng.int(1...20)
                    let rir: Int? = rng.chance(40) ? nil : rng.int(-2...6)
                    sets.append(CoachFix.set(weight, reps, rir, type: type))
                }
                result.append(CoachFix.session(day, sets))
                day += rng.int(1...20)
            }
            return result
        }
    }

    private static let cases = 1_500

    private func forEachCase(_ body: (Exercise, [ExerciseSession], AudienceProfile, Int) -> Void) {
        var generator = Generator(seed: 20_261_016)
        for index in 0..<Self.cases {
            let exercise = generator.exercise()
            let sessions = generator.sessions()
            let audience = generator.rng.pick([AudienceProfile.adult, .unknown, AudienceProfile(ageGroup: .minor)])
            body(exercise, sessions, audience, index)
        }
    }

    /// The heaviest valid working weight anywhere in the history: no target may be built from more than that. (The engine may skip
    /// a newest session whose only sets look like typos and build on an older one, so the bound is not the newest session's.)
    private func heaviestValid(_ sessions: [ExerciseSession]) -> Double {
        var heaviest = 0.0
        for session in sessions {
            for set in session.sets where isValidWorkingSet(set) {
                heaviest = max(heaviest, set.weightKg)
            }
        }
        return heaviest
    }

    private func isValidWorkingSet(_ set: CompletedSet) -> Bool {
        let working: Bool = set.type == .normal || set.type == .failure
        let weightOK: Bool = set.weightKg.isFinite && set.weightKg > 0 && set.weightKg <= 2_000
        let repsOK: Bool = set.reps > 0 && set.reps <= 1_000
        return working && weightOK && repsOK
    }

    // MARK: Properties

    func testTheAnswerIsAlwaysWellFormed() {
        var seenVerdicts = Set<Verdict>()
        forEachCase { exercise, sessions, audience, index in
            let result = CoachFix.recommend(exercise, sessions, audience: audience)
            let context = "case \(index) \(exercise.id) \(result)"
            seenVerdicts.insert(result.verdict)

            XCTAssertEqual(result, CoachFix.recommend(exercise, sessions, audience: audience), "not deterministic: \(context)")
            XCTAssertEqual(result.verdict.hasTarget, result.targetWeightKg != nil && result.targetReps != nil, context)
            if !result.verdict.hasTarget {
                XCTAssertNil(result.targetWeightKg, context)
                XCTAssertNil(result.targetReps, context)
            }
            if let weight = result.targetWeightKg {
                XCTAssertTrue(weight.isFinite && weight > 0, context)
            }
            if let reps = result.targetReps {
                XCTAssertTrue(reps >= 1 && reps <= 1_000, context)
            }
            XCTAssertLessThanOrEqual(result.sessionsUsed, sessions.count, context)
            XCTAssertEqual(result.exerciseID, exercise.id, context)
            XCTAssertEqual(result.engineVersion, ProgressionEngine.version, context)
        }
        // The generator must exercise every kind of answer, otherwise these properties prove little.
        XCTAssertEqual(seenVerdicts, Set(Verdict.allCases), "verdicts seen: \(seenVerdicts)")
    }

    func testTargetsStayWithinTheBoundsOfTheHistory() {
        forEachCase { exercise, sessions, audience, index in
            let result = CoachFix.recommend(exercise, sessions, audience: audience)
            guard let weight = result.targetWeightKg else { return }
            let top = heaviestValid(sessions)
            let context = "case \(index) \(exercise.id) \(result) top \(top)"
            let cap = audience.isRestricted ? 0.05 : 0.075
            switch result.verdict {
            case .progress:
                XCTAssertLessThanOrEqual(weight, top * (1 + cap) + 0.006, context)
                let increment = CoachConfig().increment(for: exercise)
                // The step itself respects the cap: increment / previous weight.
                XCTAssertLessThanOrEqual(increment / (weight - increment), cap + 1e-6, context)
            case .addRep:
                XCTAssertLessThanOrEqual(weight, top + 0.006, context)
                XCTAssertGreaterThanOrEqual(result.targetReps ?? 0, 2, context)
            case .reduce:
                XCTAssertLessThan(weight, top, context)
            case .hold:
                XCTAssertLessThanOrEqual(weight, top + 0.006, context)
            case .noEffortData, .insufficientData:
                XCTFail("no target expected: \(context)")
            }
        }
    }

    func testWithoutAnyEffortDataTheCoachNeverRaisesTheWeight() {
        forEachCase { exercise, sessions, audience, index in
            let stripped = sessions.map { session -> ExerciseSession in
                var copy = session
                copy.sets = session.sets.map { set in
                    CompletedSet(type: set.type == .failure ? .normal : set.type, weightKg: set.weightKg, reps: set.reps, rir: nil)
                }
                return copy
            }
            let result = CoachFix.recommend(exercise, stripped, audience: audience)
            XCTAssertFalse([.progress, .addRep].contains(result.verdict), "case \(index) \(result)")
        }
    }

    func testTheOrderOfSetsInASessionDoesNotMatter() {
        forEachCase { exercise, sessions, audience, index in
            let reversed = sessions.map { session -> ExerciseSession in
                var copy = session
                copy.sets = session.sets.reversed()
                return copy
            }
            XCTAssertEqual(
                CoachFix.recommend(exercise, sessions, audience: audience),
                CoachFix.recommend(exercise, reversed, audience: audience), "case \(index)"
            )
        }
    }

    func testWarmUpsAndDropSetsNeverChangeTheAnswer() {
        forEachCase { exercise, sessions, audience, index in
            let working = sessions.map { session -> ExerciseSession in
                var copy = session
                copy.sets = session.sets.filter { $0.type == .normal || $0.type == .failure }
                return copy
            }
            XCTAssertEqual(
                CoachFix.recommend(exercise, sessions, audience: audience),
                CoachFix.recommend(exercise, working, audience: audience), "case \(index)"
            )
            let padded = working.map { session -> ExerciseSession in
                var copy = session
                copy.sets += [CoachFix.set(20, 15, 4, type: .warmup), CoachFix.set(1_000, 1, 0, type: .drop)]
                return copy
            }
            XCTAssertEqual(
                CoachFix.recommend(exercise, working, audience: audience),
                CoachFix.recommend(exercise, padded, audience: audience), "padded case \(index)"
            )
        }
    }

    func testShiftingEveryDateByTheSameAmountChangesNothing() {
        forEachCase { exercise, sessions, audience, index in
            let delta: TimeInterval = 400 * 86_400
            let shifted = sessions.map { session -> ExerciseSession in
                var copy = session
                copy.date = session.date.addingTimeInterval(delta)
                return copy
            }
            let original = CoachFix.recommend(exercise, sessions, audience: audience)
            let moved = ProgressionEngine.recommend(
                for: exercise, history: CoachFix.history(exercise, shifted), audience: audience,
                config: CoachConfig(), now: CoachFix.now.addingTimeInterval(delta)
            )
            XCTAssertEqual(original, moved, "case \(index)")
        }
    }

    func testAnAvoidedMuscleIsAlwaysSilent() {
        forEachCase { exercise, sessions, _, index in
            let audience = AudienceProfile(ageGroup: .adult, avoidMuscles: [exercise.muscle])
            let result = CoachFix.recommend(exercise, sessions, audience: audience)
            XCTAssertEqual(result.verdict, .insufficientData, "case \(index)")
            XCTAssertEqual(result.reasons, [.audienceRestricted], "case \(index)")
        }
    }

    func testAHugeHistoryIsHandled() {
        let exercise = CoachFix.lib("bench")
        let clean = CoachFix.sets(80, [6, 6, 6], rir: [2, 2, 2])
        let sessions = (0..<3_000).map { CoachFix.session(3 + $0, clean) }
        let result = CoachFix.recommend(exercise, sessions)
        XCTAssertEqual(result.verdict, .progress)
    }
}
