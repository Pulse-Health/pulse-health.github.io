import XCTest
@testable import PulseStrengthCore

// MARK: - Fixtures

/// Deterministic fixtures for the progression engine tests (no clock, no randomness).
enum CoachFix {
    /// "Today" for every test.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func date(daysAgo: Int) -> Date { now.addingTimeInterval(-Double(daysAgo) * 86_400) }

    static func lib(_ id: String) -> Exercise {
        guard let exercise = ExerciseLibrary.exercise(id: id) else { preconditionFailure("unknown exercise \(id)") }
        return exercise
    }

    /// A working set; `rir` nil = not recorded.
    static func set(_ kg: Double, _ reps: Int, _ rir: Int? = nil, type: SetType = .normal) -> CompletedSet {
        CompletedSet(type: type, weightKg: kg, reps: reps, rir: rir)
    }

    /// One set per entry of `reps` at `kg`; `rirs` is aligned with `reps` (shorter = remaining sets have no RIR).
    static func sets(_ kg: Double, _ reps: [Int], rir rirs: [Int?] = []) -> [CompletedSet] {
        reps.enumerated().map { index, count in set(kg, count, index < rirs.count ? rirs[index] : nil) }
    }

    static func session(_ daysAgo: Int, _ sets: [CompletedSet]) -> ExerciseSession {
        ExerciseSession(id: UUID(), date: date(daysAgo: daysAgo), workoutName: "Workout", sets: sets, isPersonalRecord: false)
    }

    /// History with `sessions` newest first.
    static func history(_ exercise: Exercise, _ sessions: [ExerciseSession]) -> ExerciseHistory {
        ExerciseHistory(
            exerciseID: exercise.id, sessions: sessions, e1RMSeries: [], bestE1RM: 0,
            volumeLast30Days: 0, sessionsLast30Days: 0, records: []
        )
    }

    static func recommend(
        _ exercise: Exercise, _ sessions: [ExerciseSession],
        audience: AudienceProfile = .adult, config: CoachConfig = CoachConfig()
    ) -> Recommendation {
        ProgressionEngine.recommend(
            for: exercise, history: history(exercise, sessions), audience: audience, config: config, now: now
        )
    }
}

// MARK: - Golden cases

/// One case per policy rule. The expected values are the **starting policy** in `CoachConfig`; they are what a qualified coach
/// is asked to review and sign off, so a change to a threshold must change a case here on purpose.
final class CoachEngineGoldenTests: XCTestCase {
    private let bench = CoachFix.lib("bench")      // barbell, 2.5 kg increment
    private let lateral = CoachFix.lib("lateral")  // dumbbell, 2 kg increment
    private let crossover = CoachFix.lib("crossover") // cable, 2.5 kg increment

    private func check(
        _ result: Recommendation, _ verdict: Verdict, weight: Double? = nil, reps: Int? = nil,
        reasons: [ReasonCode] = [], file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(result.verdict, verdict, "verdict", file: file, line: line)
        XCTAssertEqual(result.targetWeightKg, weight, "weight", file: file, line: line)
        XCTAssertEqual(result.targetReps, reps, "reps", file: file, line: line)
        for reason in reasons {
            XCTAssertTrue(result.reasons.contains(reason), "missing reason \(reason) in \(result.reasons)", file: file, line: line)
        }
        XCTAssertEqual(result.engineVersion, ProgressionEngine.version, file: file, line: line)
    }

    // MARK: Not enough to say anything

    func testNoHistoryOrOneSessionSaysNothing() {
        check(CoachFix.recommend(bench, []), .insufficientData, reasons: [.tooFewSessions])
        let one = CoachFix.recommend(bench, [CoachFix.session(3, CoachFix.sets(80, [6, 6, 6], rir: [2, 2, 2]))])
        check(one, .insufficientData, reasons: [.tooFewSessions])
        XCTAssertEqual(one.sessionsUsed, 1)
    }

    func testSessionsWithoutWorkingSetsDoNotCount() {
        let warmupsOnly = CoachFix.session(3, [CoachFix.set(50, 8, type: .warmup), CoachFix.set(60, 8, type: .drop)])
        let real = CoachFix.session(10, CoachFix.sets(80, [6, 6, 6], rir: [2, 2, 2]))
        check(CoachFix.recommend(bench, [warmupsOnly, real]), .insufficientData, reasons: [.tooFewSessions])
    }

    func testBodyweightAndDurationSaySNothing() {
        let pushup = CoachFix.lib("pushup")
        XCTAssertNotEqual(pushup.tracking, .weightReps)
        let sessions = [CoachFix.session(3, [CoachFix.set(0, 12, 2)]), CoachFix.session(10, [CoachFix.set(0, 12, 2)])]
        check(CoachFix.recommend(pushup, sessions), .insufficientData, reasons: [.unsupportedTracking])
    }

    func testAvoidedMuscleIsSilent() {
        let sessions = [
            CoachFix.session(3, CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3])),
            CoachFix.session(10, CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3])),
        ]
        let audience = AudienceProfile(ageGroup: .adult, avoidMuscles: [.chest])
        check(CoachFix.recommend(bench, sessions, audience: audience), .insufficientData, reasons: [.audienceRestricted])
        // Another muscle is unaffected.
        let other = AudienceProfile(ageGroup: .adult, avoidMuscles: [.legs])
        XCTAssertEqual(CoachFix.recommend(bench, sessions, audience: other).verdict, .progress)
    }

    func testHistoryOfAnotherExerciseIsIgnored() {
        let mismatch = CoachFix.history(CoachFix.lib("squat"), [CoachFix.session(3, CoachFix.sets(80, [6], rir: [3]))])
        let result = ProgressionEngine.recommend(for: bench, history: mismatch, now: CoachFix.now)
        check(result, .insufficientData, reasons: [.tooFewSessions])
    }

    // MARK: Progress

    func testTwoCleanSessionsAtTheSameWeightProgressOneStep() {
        let sessions = [
            CoachFix.session(3, CoachFix.sets(80, [6, 6, 6], rir: [2, 3, 2])),
            CoachFix.session(10, CoachFix.sets(80, [6, 6, 6], rir: [2, 2, 3])),
        ]
        check(CoachFix.recommend(bench, sessions), .progress, weight: 82.5, reps: 6, reasons: [.cleanSessionsWithReserve])
    }

    func testProgressIgnoresWarmUpsAndDropSets() {
        let clean = CoachFix.sets(80, [6, 6, 6], rir: [2, 2, 2])
        let noisy = [CoachFix.set(50, 8, 4, type: .warmup)] + clean + [CoachFix.set(60, 12, 0, type: .drop)]
        let sessions = [CoachFix.session(3, noisy), CoachFix.session(10, clean)]
        check(CoachFix.recommend(bench, sessions), .progress, weight: 82.5, reps: 6)
    }

    func testOnlyTheTopWeightOfASessionIsJudged() {
        // A heavy top set and a lighter back-off set: the back-off's easy RIR must not hide the hard top set.
        let hard = [CoachFix.set(85, 5, 0), CoachFix.set(75, 8, 4)]
        let sessions = [CoachFix.session(3, hard), CoachFix.session(10, hard)]
        check(CoachFix.recommend(bench, sessions), .hold, weight: 85, reps: 5, reasons: [.lastSessionNearFailure])
    }

    func testAFailureSetCountsAsZeroRepsInReserve() {
        // Two sets with RIR 3 and one to-failure set without a value: mean (3 + 3 + 0) / 3 = 2.
        let session = [CoachFix.set(80, 6, 3), CoachFix.set(80, 6, 3), CoachFix.set(80, 5, nil, type: .failure)]
        let result = CoachFix.recommend(bench, [CoachFix.session(3, session), CoachFix.session(10, session)])
        check(result, .progress, weight: 82.5, reps: 6)
    }

    func testSmallestStepTooBigForTheWeightAddsARepInstead() {
        // 8 kg lateral raise: a 2 kg step is 25 %, well over the 7.5 % cap.
        let sessions = [
            CoachFix.session(3, CoachFix.sets(8, [15, 15, 15], rir: [3, 3, 3])),
            CoachFix.session(10, CoachFix.sets(8, [15, 15, 15], rir: [3, 3, 3])),
        ]
        check(CoachFix.recommend(lateral, sessions), .addRep, weight: 8, reps: 16, reasons: [.cleanSessionsWithReserve, .stepExceedsCap])
    }

    func testTheCapDependsOnTheAudience() {
        // Cable at 40 kg: a 2.5 kg step is 6.25 %. Fine for an adult (7.5 %), too much for an unknown audience (5 %).
        let sessions = [
            CoachFix.session(3, CoachFix.sets(40, [10, 10, 10], rir: [3, 3, 3])),
            CoachFix.session(10, CoachFix.sets(40, [10, 10, 10], rir: [3, 3, 3])),
        ]
        check(CoachFix.recommend(crossover, sessions, audience: .adult), .progress, weight: 42.5, reps: 10)
        check(CoachFix.recommend(crossover, sessions, audience: .unknown), .addRep, weight: 40, reps: 11)
        let minor = AudienceProfile(ageGroup: .minor)
        check(CoachFix.recommend(crossover, sessions, audience: minor), .addRep, weight: 40, reps: 11)
    }

    func testAHeavyBarbellProgressesEvenForAnUnknownAudience() {
        // 2.5 / 80 = 3.1 %, under both caps.
        let sessions = [
            CoachFix.session(3, CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3])),
            CoachFix.session(10, CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3])),
        ]
        check(CoachFix.recommend(bench, sessions, audience: .unknown), .progress, weight: 82.5, reps: 6)
    }

    func testARepTargetIsNeverRaisedPastTheMaximum() {
        var config = CoachConfig()
        config.maximumTargetReps = 15
        let sessions = [
            CoachFix.session(3, CoachFix.sets(8, [15, 15, 15], rir: [3, 3, 3])),
            CoachFix.session(10, CoachFix.sets(8, [15, 15, 15], rir: [3, 3, 3])),
        ]
        check(CoachFix.recommend(lateral, sessions, config: config), .hold, weight: 8, reps: 15, reasons: [.stepExceedsCap])
    }

    // MARK: Hold

    func testAfterAnIncreaseOneMoreCleanSessionIsNeeded() {
        let sessions = [
            CoachFix.session(3, CoachFix.sets(82.5, [6, 6, 6], rir: [3, 3, 3])),
            CoachFix.session(10, CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3])),
        ]
        check(CoachFix.recommend(bench, sessions), .hold, weight: 82.5, reps: 6, reasons: [.awaitingSecondCleanSession])
    }

    func testTheEarlierSessionNeedsEffortDataToo() {
        let sessions = [
            CoachFix.session(3, CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3])),
            CoachFix.session(10, CoachFix.sets(80, [6, 6, 6])),
        ]
        check(CoachFix.recommend(bench, sessions), .hold, weight: 80, reps: 6, reasons: [.awaitingSecondCleanSession])
    }

    func testARepDropBetweenTheTwoSessionsWaits() {
        let sessions = [
            CoachFix.session(3, CoachFix.sets(80, [5, 5, 5], rir: [3, 3, 3])),
            CoachFix.session(10, CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3])),
        ]
        check(CoachFix.recommend(bench, sessions), .hold, weight: 80, reps: 5, reasons: [.awaitingSecondCleanSession])
    }

    func testModerateEffortHolds() {
        // Mean RIR 5/3 = 1.67: not near failure (<= 1) and not comfortable (>= 2).
        let session = CoachFix.sets(80, [6, 6, 6], rir: [1, 2, 2])
        check(
            CoachFix.recommend(bench, [CoachFix.session(3, session), CoachFix.session(10, session)]),
            .hold, weight: 80, reps: 6, reasons: [.moderateEffort]
        )
    }

    func testANearFailureSessionHolds() {
        let session = CoachFix.sets(80, [6, 6, 6], rir: [0, 1, 1])
        check(
            CoachFix.recommend(bench, [CoachFix.session(3, session), CoachFix.session(10, session)]),
            .hold, weight: 80, reps: 6, reasons: [.lastSessionNearFailure]
        )
    }

    func testAfterALongBreakTheOldNumbersAreKept() {
        let clean = CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3])
        let result = CoachFix.recommend(bench, [CoachFix.session(45, clean), CoachFix.session(52, clean)])
        check(result, .hold, weight: 80, reps: 6, reasons: [.returningAfterBreak])
        // Exactly at the limit is not a break.
        let edge = CoachFix.recommend(bench, [CoachFix.session(28, clean), CoachFix.session(35, clean)])
        XCTAssertEqual(edge.verdict, .progress)
    }

    // MARK: Effort data

    func testWithoutRepsInReserveTheCoachAsksForIt() {
        let plain = CoachFix.sets(80, [6, 6, 6])
        let result = CoachFix.recommend(bench, [CoachFix.session(3, plain), CoachFix.session(10, plain)])
        check(result, .noEffortData, reasons: [.noRIRRecorded])
    }

    func testTooFewRecordedSetsCountAsNoEffortData() {
        // One of three sets has a value: coverage 33 % < 67 %.
        let session = CoachFix.sets(80, [6, 6, 6], rir: [3])
        let result = CoachFix.recommend(bench, [CoachFix.session(3, session), CoachFix.session(10, session)])
        check(result, .noEffortData)
        // Two of three is enough.
        let enough = CoachFix.sets(80, [6, 6, 6], rir: [3, 3])
        XCTAssertEqual(CoachFix.recommend(bench, [CoachFix.session(3, enough), CoachFix.session(10, enough)]).verdict, .progress)
    }

    func testOutOfRangeRepsInReserveAreClamped() {
        // 9 and -4 are clamped to 4 and 0: mean (4 + 0 + 4) / 3 = 2.67 -> still comfortable.
        let session = CoachFix.sets(80, [6, 6, 6], rir: [9, -4, 4])
        let result = CoachFix.recommend(bench, [CoachFix.session(3, session), CoachFix.session(10, session)])
        XCTAssertEqual(result.verdict, .progress)
    }

    // MARK: Reduce

    func testRepsFallingTwiceAtTheSameWeightWithHardEffortReduces() {
        // 6,6,6 -> 6,5,5 -> 5,5,4 at 80 kg, RIR 0 or 1. 5 % of 80 kg = 4 kg -> rounded down to one 2.5 kg step.
        let sessions = [
            CoachFix.session(3, CoachFix.sets(80, [5, 5, 4], rir: [0, 1, 0])),
            CoachFix.session(10, CoachFix.sets(80, [6, 5, 5], rir: [1, 1, 0])),
            CoachFix.session(17, CoachFix.sets(80, [6, 6, 6], rir: [2, 2, 2])),
        ]
        check(CoachFix.recommend(bench, sessions), .reduce, weight: 77.5, reps: 5, reasons: [.repsFellAtSameLoad])
    }

    func testRepsFallingWithoutEffortDataHoldsAndAsksForIt() {
        let sessions = [
            CoachFix.session(3, CoachFix.sets(80, [5, 5, 4])),
            CoachFix.session(10, CoachFix.sets(80, [6, 5, 5])),
            CoachFix.session(17, CoachFix.sets(80, [6, 6, 6])),
        ]
        check(CoachFix.recommend(bench, sessions), .hold, weight: 80, reps: 5, reasons: [.repsFellAtSameLoad, .noRIRRecorded])
    }

    func testRepsFallingWithEasyEffortOnlyHolds() {
        let sessions = [
            CoachFix.session(3, CoachFix.sets(80, [5, 5, 4], rir: [3, 3, 3])),
            CoachFix.session(10, CoachFix.sets(80, [6, 5, 5], rir: [3, 3, 3])),
            CoachFix.session(17, CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3])),
        ]
        check(CoachFix.recommend(bench, sessions), .hold, weight: 80, reps: 5, reasons: [.repsFellAtSameLoad])
    }

    func testASmallDropIsTolerated() {
        // Mean 6 -> 5.67 -> 5.33: each drop is 0.33 reps, under the 0.5 tolerance.
        let sessions = [
            CoachFix.session(3, CoachFix.sets(80, [6, 5, 5], rir: [0, 0, 0])),
            CoachFix.session(10, CoachFix.sets(80, [6, 6, 5], rir: [0, 0, 0])),
            CoachFix.session(17, CoachFix.sets(80, [6, 6, 6], rir: [0, 0, 0])),
        ]
        XCTAssertEqual(CoachFix.recommend(bench, sessions).verdict, .hold)
    }

    func testAReduceThatWouldBeTooBigHoldsInstead() {
        // 8 kg dumbbell: one 2 kg step is 25 % of the weight, over the 10 % limit for a reduce.
        let sessions = [
            CoachFix.session(3, CoachFix.sets(8, [10, 10, 9], rir: [0, 0, 0])),
            CoachFix.session(10, CoachFix.sets(8, [12, 11, 11], rir: [0, 0, 0])),
            CoachFix.session(17, CoachFix.sets(8, [13, 13, 13], rir: [0, 0, 0])),
        ]
        check(CoachFix.recommend(lateral, sessions), .hold, weight: 8, reps: 10, reasons: [.repsFellAtSameLoad, .reduceExceedsCap])
    }

    func testALighterWeekAfterSixIncreasesInARow() {
        // Newest first: 72.5, 70, 67.5, 65, 62.5, 60, 57.5 -> six consecutive increases.
        let loads: [Double] = [72.5, 70, 67.5, 65, 62.5, 60, 57.5]
        let sessions = loads.enumerated().map { index, load in
            CoachFix.session(3 + index * 7, CoachFix.sets(load, [6, 6, 6], rir: [3, 3, 3]))
        }
        check(CoachFix.recommend(bench, sessions), .reduce, weight: 70, reps: 6, reasons: [.lighterWeekDue])
        // Five increases are not enough; the weight just changed, so it is a plain hold.
        let five = CoachFix.recommend(bench, Array(sessions.dropLast()))
        check(five, .hold, weight: 72.5, reps: 6, reasons: [.awaitingSecondCleanSession])
    }

    // MARK: Data errors

    func testATypoSetIsIgnoredAndFlagged() {
        // 85 kg x 16 (meant 6) has an estimated 1RM of 130 against a typical best of 96.
        let clean = CoachFix.sets(80, [6, 6, 6], rir: [2, 2, 2])
        var typo = clean
        typo.append(CoachFix.set(85, 16, 2))
        let sessions = [
            CoachFix.session(3, clean), CoachFix.session(10, typo), CoachFix.session(17, clean), CoachFix.session(24, clean),
        ]
        let result = CoachFix.recommend(bench, sessions)
        XCTAssertTrue(result.reasons.contains(.suspectSetExcluded))
        XCTAssertEqual(result.verdict, .progress)
        XCTAssertEqual(result.targetWeightKg, 82.5)
        // With only two sessions there is no way to know what is typical, so nothing is dropped.
        let two = CoachFix.recommend(bench, [CoachFix.session(3, typo), CoachFix.session(10, typo)])
        XCTAssertFalse(two.reasons.contains(.suspectSetExcluded))
    }

    func testImpossibleValuesAreIgnored() {
        let clean = CoachFix.sets(80, [6, 6, 6], rir: [2, 2, 2])
        let garbage = clean + [
            CoachFix.set(.nan, 5, 1), CoachFix.set(.infinity, 5, 1), CoachFix.set(5_000, 5, 1),
            CoachFix.set(-20, 5, 1), CoachFix.set(80, 0, 1), CoachFix.set(80, 5_000, 1),
        ]
        let result = CoachFix.recommend(bench, [CoachFix.session(3, garbage), CoachFix.session(10, clean)])
        XCTAssertEqual(result.verdict, .progress)
        XCTAssertEqual(result.targetWeightKg, 82.5)
    }

    func testOnlyFourVerdictsNameATarget() {
        for verdict in Verdict.allCases {
            XCTAssertEqual(verdict.hasTarget, [.progress, .hold, .reduce, .addRep].contains(verdict), "\(verdict)")
        }
    }
}
