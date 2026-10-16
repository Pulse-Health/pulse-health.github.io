import XCTest
@testable import PulseStrengthCore

/// Tests written after mutation-testing `ProgressionEngine` and the `CoachConfig` defaults: each one pins behaviour that a small
/// change to the source (a flipped comparison, a dropped guard, a changed constant) did not break in `CoachEngineGoldenTests` or
/// `CoachPropertyTests`. They are boundary cases (exactly at a threshold), configuration cases (the engine must follow
/// `CoachConfig`, not a copy of its defaults), input-hardening cases and one policy oracle that restates section 6.1 of the
/// harness proposal from the raw sets.
///
/// The expected values are the **starting policy**, like the golden cases: a threshold that is changed on purpose (for example
/// after a coach's sign-off) must change the matching case here, in `testTheStartingPolicyValues` and in the golden cases together.
final class CoachEngineMutationTests: XCTestCase {
    private let bench = CoachFix.lib("bench")         // barbell, 2.5 kg step
    private let lateral = CoachFix.lib("lateral")     // dumbbell, 2 kg step
    private let crossover = CoachFix.lib("crossover") // cable, 2.5 kg step

    // MARK: - Helpers

    private func check(
        _ result: Recommendation, _ verdict: Verdict, weight: Double? = nil, reps: Int? = nil,
        reasons: [ReasonCode]? = nil, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(result.verdict, verdict, "verdict of \(result)", file: file, line: line)
        XCTAssertEqual(result.targetWeightKg, weight, "weight of \(result)", file: file, line: line)
        XCTAssertEqual(result.targetReps, reps, "reps of \(result)", file: file, line: line)
        if let reasons {
            XCTAssertEqual(result.reasons, reasons, "reasons of \(result)", file: file, line: line)
        }
    }

    /// `count` sets at `kg`, all with the same reps and the same reps in reserve (nil = not recorded).
    private func straight(_ daysAgo: Int, _ kg: Double, reps: Int = 6, count: Int = 3, rir: Int? = 3) -> ExerciseSession {
        CoachFix.session(
            daysAgo,
            CoachFix.sets(kg, Array(repeating: reps, count: count), rir: Array(repeating: rir, count: count))
        )
    }

    /// One session with the given reps and (aligned) reps in reserve per set.
    private func day(_ daysAgo: Int, _ kg: Double, _ reps: [Int], _ rir: [Int?]) -> ExerciseSession {
        CoachFix.session(daysAgo, CoachFix.sets(kg, reps, rir: rir))
    }

    /// Seven weekly sessions with a higher weight each time, newest first: 72.5, 70, 67.5 ... 57.5 kg (six increases in a row).
    private func risingSessions(firstDaysAgo: Int = 3) -> [ExerciseSession] {
        let loads: [Double] = [72.5, 70, 67.5, 65, 62.5, 60, 57.5]
        return loads.enumerated().map { straight(firstDaysAgo + $0.offset * 7, $0.element) }
    }

    /// A session whose only reliable set is `kg` x 10 reps (10 reps is the most the suspect-set reference accepts), so its
    /// estimated 1RM is `kg * 4/3`: 60 kg is 80, 66 is 88, 72 is 96, 78 is 104.
    private func reference(_ daysAgo: Int, kg: Double, extra: [CompletedSet] = []) -> ExerciseSession {
        CoachFix.session(daysAgo, [CoachFix.set(kg, 10, 3)] + extra)
    }

    /// A 20-rep set with the given estimated 1RM. It has too many reps to serve as a reference, so it is only ever judged.
    private func probe(_ e1RM: Double) -> CompletedSet {
        CoachFix.set(e1RM / (1 + 20.0 / 30), 20, 3)
    }

    private func isFlagged(_ sessions: [ExerciseSession]) -> Bool {
        CoachFix.recommend(bench, sessions).reasons.contains(.suspectSetExcluded)
    }

    // MARK: - Input that must not be believed or crash

    func testAHistoryOfAnotherExerciseIsIgnoredEvenWhenItIsLong() {
        let squat = CoachFix.lib("squat")
        let clean = CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3])
        let other = CoachFix.history(
            squat, [CoachFix.session(3, clean), CoachFix.session(10, clean), CoachFix.session(17, clean)]
        )
        let result = ProgressionEngine.recommend(for: bench, history: other, audience: .adult, now: CoachFix.now)
        check(result, .insufficientData, reasons: [.tooFewSessions])
        XCTAssertEqual(result.sessionsUsed, 0)
        XCTAssertEqual(result.exerciseID, "bench")
    }

    func testTheEngineAlwaysNeedsTwoSessionsWhateverTheConfigurationSays() {
        for minimum in [0, 1, -3] {
            var config = CoachConfig()
            config.minimumSessions = minimum
            check(CoachFix.recommend(bench, [], config: config), .insufficientData, reasons: [.tooFewSessions])
            let one = CoachFix.recommend(bench, [straight(3, 80)], config: config)
            check(one, .insufficientData, reasons: [.tooFewSessions])
            XCTAssertEqual(one.sessionsUsed, 1, "minimum \(minimum)")
            // Two sessions are enough, and the answer is the usual one.
            check(CoachFix.recommend(bench, [straight(3, 80), straight(10, 80)], config: config), .progress, weight: 82.5, reps: 6)
        }
    }

    func testMoreSessionsCanBeRequiredThroughTheConfiguration() {
        var config = CoachConfig()
        config.minimumSessions = 3
        let two = CoachFix.recommend(bench, [straight(3, 80), straight(10, 80)], config: config)
        check(two, .insufficientData, reasons: [.tooFewSessions])
        XCTAssertEqual(two.sessionsUsed, 2)
        check(
            CoachFix.recommend(bench, [straight(3, 80), straight(10, 80), straight(17, 80)], config: config),
            .progress, weight: 82.5, reps: 6
        )
    }

    func testTheImplausibleSetBoundsAreInclusive() {
        // Heavy but real lifts must not be thrown away as typos.
        let deadlift = CoachFix.lib("deadlift")
        let heavy = CoachFix.recommend(deadlift, [straight(3, 250, reps: 5), straight(10, 250, reps: 5)])
        check(heavy, .progress, weight: 252.5, reps: 5)

        // 2000 kg and 1000 reps are the last believable values; one step beyond is a data error.
        let atLimit = CoachFix.recommend(bench, [straight(3, 2_000, reps: 1), straight(10, 2_000, reps: 1)])
        XCTAssertEqual(atLimit.sessionsUsed, 2)
        XCTAssertEqual(atLimit.verdict, .progress)
        let overWeight = CoachFix.recommend(bench, [straight(3, 2_000.01, reps: 1), straight(10, 2_000.01, reps: 1)])
        check(overWeight, .insufficientData, reasons: [.tooFewSessions])
        XCTAssertEqual(overWeight.sessionsUsed, 0)

        let manyReps = CoachFix.recommend(bench, [straight(3, 80, reps: 1_000), straight(10, 80, reps: 1_000)])
        XCTAssertEqual(manyReps.sessionsUsed, 2)
        let tooManyReps = CoachFix.recommend(bench, [straight(3, 80, reps: 1_001), straight(10, 80, reps: 1_001)])
        check(tooManyReps, .insufficientData, reasons: [.tooFewSessions])
        XCTAssertEqual(tooManyReps.sessionsUsed, 0)
    }

    func testASessionOfOnlyZeroWeightOrZeroRepSetsDoesNotCount() {
        let real = straight(10, 80)
        for empty in [CoachFix.session(3, [CoachFix.set(0, 8, 3), CoachFix.set(0, 8, 3)]),
                      CoachFix.session(3, [CoachFix.set(80, 0, 3), CoachFix.set(80, 0, 3)])] {
            let result = CoachFix.recommend(bench, [empty, real])
            check(result, .insufficientData, reasons: [.tooFewSessions])
            XCTAssertEqual(result.sessionsUsed, 1)
        }
    }

    func testSessionsOfToFailureSetsAreWorkingSessions() {
        // No reps in reserve is needed: a to-failure set is reps in reserve 0.
        let failure = (0..<3).map { _ in CoachFix.set(80, 6, nil, type: .failure) }
        let result = CoachFix.recommend(bench, [CoachFix.session(3, failure), CoachFix.session(10, failure)])
        check(result, .hold, weight: 80, reps: 6, reasons: [.lastSessionNearFailure])
        XCTAssertEqual(result.sessionsUsed, 2)
    }

    // MARK: - Break and lighter week

    func testALongBreakBeatsTheLighterWeekRule() {
        let result = CoachFix.recommend(bench, risingSessions(firstDaysAgo: 40))
        check(result, .hold, weight: 72.5, reps: 6, reasons: [.returningAfterBreak])
    }

    func testTheBreakIsMeasuredInWholeDaysAndFollowsTheConfiguration() {
        // 28 days is still fine (golden), 29 is a break.
        check(
            CoachFix.recommend(bench, [straight(29, 80), straight(36, 80)]),
            .hold, weight: 80, reps: 6, reasons: [.returningAfterBreak]
        )
        var week = CoachConfig()
        week.breakDays = 7
        check(CoachFix.recommend(bench, [straight(8, 80), straight(15, 80)], config: week), .hold, weight: 80, reps: 6, reasons: [.returningAfterBreak])
        check(CoachFix.recommend(bench, [straight(7, 80), straight(14, 80)], config: week), .progress, weight: 82.5, reps: 6)
    }

    func testTheLighterWeekCanBeSwitchedOffAndItsLengthChanged() {
        var off = CoachConfig()
        off.lighterWeekAfterIncreases = 0
        check(
            CoachFix.recommend(bench, risingSessions(), config: off),
            .hold, weight: 72.5, reps: 6, reasons: [.awaitingSecondCleanSession]
        )
        off.lighterWeekAfterIncreases = -1
        check(
            CoachFix.recommend(bench, risingSessions(), config: off),
            .hold, weight: 72.5, reps: 6, reasons: [.awaitingSecondCleanSession]
        )

        var three = CoachConfig()
        three.lighterWeekAfterIncreases = 3
        // 72.5, 70, 67.5, 65: three increases in a row.
        check(
            CoachFix.recommend(bench, Array(risingSessions().prefix(4)), config: three),
            .reduce, weight: 70, reps: 6, reasons: [.lighterWeekDue]
        )
        // 72.5, 70, 67.5: two increases.
        check(
            CoachFix.recommend(bench, Array(risingSessions().prefix(3)), config: three),
            .hold, weight: 72.5, reps: 6, reasons: [.awaitingSecondCleanSession]
        )
    }

    func testWeightsAGramApartAreTheSameWeightNotAnIncrease() {
        // Seven sessions that differ by 1 g each: no streak of increases, so two clean sessions at the "same" weight progress.
        let loads = (0..<7).map { 80.006 - Double($0) * 0.001 }
        let sessions = loads.enumerated().map { straight(3 + $0.offset * 7, $0.element) }
        let result = CoachFix.recommend(bench, sessions)
        check(result, .progress, weight: 82.51, reps: 6, reasons: [.cleanSessionsWithReserve])
    }

    func testWeightsATenthOfAKiloApartAreDifferentWeights() {
        // Seven sessions that rise by 0.1 kg each are six increases in a row.
        let loads = (0..<7).map { 80.6 - Double($0) * 0.1 }
        let sessions = loads.enumerated().map { straight(3 + $0.offset * 7, $0.element) }
        check(CoachFix.recommend(bench, sessions), .reduce, weight: 78.1, reps: 6, reasons: [.lighterWeekDue])
        // And two sessions 0.1 kg apart are not "the same weight": wait for a second clean session at the new one.
        check(
            CoachFix.recommend(bench, [straight(3, 80.1), straight(10, 80)]),
            .hold, weight: 80.1, reps: 6, reasons: [.awaitingSecondCleanSession]
        )
    }

    func testTheSameWeightToleranceIsStrictlyBelowFiveGrams() {
        // 0.01 and 0.005 kg differ by exactly 0.005 kg, which is not "closer than" the tolerance.
        check(
            CoachFix.recommend(bench, [straight(3, 0.01), straight(10, 0.005)]),
            .hold, weight: 0.01, reps: 6, reasons: [.awaitingSecondCleanSession]
        )
    }

    // MARK: - Reps falling at the same weight

    func testTheSameWeightRuleLooksAtAllThreeSessions() {
        // Newest 80, previous 80, oldest 77.5: the weight changed, so falling reps do not mean a stall at one load.
        let oldestLighter = [
            straight(3, 80, reps: 4, rir: 0), straight(10, 80, reps: 5, rir: 0), straight(17, 77.5, reps: 6, rir: 0),
        ]
        check(CoachFix.recommend(bench, oldestLighter), .hold, weight: 80, reps: 4, reasons: [.lastSessionNearFailure])
        // Newest 82.5, previous 80, oldest 80.
        let newestHeavier = [
            straight(3, 82.5, reps: 4, rir: 0), straight(10, 80, reps: 5, rir: 0), straight(17, 80, reps: 6, rir: 0),
        ]
        check(CoachFix.recommend(bench, newestHeavier), .hold, weight: 82.5, reps: 4, reasons: [.lastSessionNearFailure])
        // The control: the same reps at one weight is a stall.
        let sameWeight = [
            straight(3, 80, reps: 4, rir: 0), straight(10, 80, reps: 5, rir: 0), straight(17, 80, reps: 6, rir: 0),
        ]
        check(CoachFix.recommend(bench, sameWeight), .reduce, weight: 77.5, reps: 4, reasons: [.repsFellAtSameLoad])
    }

    func testRepsMustFallByMoreThanTheToleranceTwiceInARow() {
        // Newest drop of exactly half a rep (6 -> 5.5) is within the tolerance, however far the older one fell (7 -> 6).
        let newestAtTolerance = [
            day(3, 80, [5, 6], [0, 0]), day(10, 80, [6, 6], [0, 0]), day(17, 80, [7, 7], [0, 0]),
        ]
        check(CoachFix.recommend(bench, newestAtTolerance), .hold, weight: 80, reps: 6, reasons: [.lastSessionNearFailure])
        // Older drop of exactly half a rep (6 -> 5.5), newest drop large (5.5 -> 4).
        let olderAtTolerance = [
            day(3, 80, [4, 4], [0, 0]), day(10, 80, [5, 6], [0, 0]), day(17, 80, [6, 6], [0, 0]),
        ]
        check(CoachFix.recommend(bench, olderAtTolerance), .hold, weight: 80, reps: 4, reasons: [.lastSessionNearFailure])
        // Only the newest session fell.
        let onlyNewest = [
            straight(3, 80, reps: 5, rir: 0), straight(10, 80, reps: 6, rir: 0), straight(17, 80, reps: 6, rir: 0),
        ]
        check(CoachFix.recommend(bench, onlyNewest), .hold, weight: 80, reps: 5, reasons: [.lastSessionNearFailure])
        // Only the older step fell; the newest session held its reps.
        let onlyOlder = [
            straight(3, 80, reps: 5, rir: 0), straight(10, 80, reps: 5, rir: 0), straight(17, 80, reps: 6, rir: 0),
        ]
        check(CoachFix.recommend(bench, onlyOlder), .hold, weight: 80, reps: 5, reasons: [.lastSessionNearFailure])
    }

    func testAReduceNeedsEffortAtTheHoldLimitOrBelowAndEnoughEffortData() {
        func stall(newest rir: [Int?]) -> [ExerciseSession] {
            [day(3, 80, [5, 5, 5], rir), day(10, 80, [6, 6, 6], [0, 0, 0]), day(17, 80, [7, 7, 7], [0, 0, 0])]
        }
        // Mean RIR exactly 1: still "ended at RIR 1 or less".
        check(CoachFix.recommend(bench, stall(newest: [1, 1, 1])), .reduce, weight: 77.5, reps: 5, reasons: [.repsFellAtSameLoad])
        // Two of three sets recorded is exactly the coverage that is enough.
        check(CoachFix.recommend(bench, stall(newest: [0, 0, nil])), .reduce, weight: 77.5, reps: 5, reasons: [.repsFellAtSameLoad])
        // The same coverage with an easy session: hold, and there is nothing to ask for.
        check(CoachFix.recommend(bench, stall(newest: [3, 3, nil])), .hold, weight: 80, reps: 5, reasons: [.repsFellAtSameLoad])
        // One of three is not enough: hold and ask for RIR.
        check(
            CoachFix.recommend(bench, stall(newest: [0, nil, nil])),
            .hold, weight: 80, reps: 5, reasons: [.repsFellAtSameLoad, .noRIRRecorded]
        )
        // Mean 1.33 is above the limit.
        check(CoachFix.recommend(bench, stall(newest: [1, 1, 2])), .hold, weight: 80, reps: 5, reasons: [.repsFellAtSameLoad])
    }

    // MARK: - How much a reduce takes off

    func testAReduceIsBoundedByTheCapAndRoundedDownToWholeSteps() {
        func stall(_ kg: Double) -> Recommendation {
            CoachFix.recommend(bench, [
                straight(3, kg, reps: 5, rir: 0), straight(10, kg, reps: 6, rir: 0), straight(17, kg, reps: 7, rir: 0),
            ])
        }
        // One 2.5 kg step is exactly 10 % of 25 kg: allowed. It is 12.5 % of 20 kg: not allowed.
        check(stall(25), .reduce, weight: 22.5, reps: 5, reasons: [.repsFellAtSameLoad])
        check(stall(20), .hold, weight: 20, reps: 5, reasons: [.repsFellAtSameLoad, .reduceExceedsCap])
        // 5 % of the weight, rounded down to whole steps (at least one).
        check(stall(120), .reduce, weight: 115, reps: 5)    // 6 kg -> 2 steps
        check(stall(160), .reduce, weight: 152.5, reps: 5)  // 8 kg -> 3 steps (3.2)
        check(stall(175), .reduce, weight: 167.5, reps: 5)  // 8.75 kg -> 3 steps (3.5 rounds down, not up)
        check(stall(80), .reduce, weight: 77.5, reps: 5)    // 4 kg -> 1 step (1.6)
    }

    func testAReduceNeverTargetsZeroKilograms() {
        // With a cap that would allow taking everything off, the reduce still must not go to zero or below.
        var generous = CoachConfig()
        generous.maximumReduceFraction = 5
        for kg in [2.0, 1.5] {
            let stall = [
                straight(3, kg, reps: 5, rir: 0), straight(10, kg, reps: 6, rir: 0), straight(17, kg, reps: 7, rir: 0),
            ]
            check(
                CoachFix.recommend(lateral, stall, config: generous),
                .hold, weight: kg, reps: 5, reasons: [.repsFellAtSameLoad, .reduceExceedsCap]
            )
        }
    }

    func testTargetWeightsAreRoundedToTheHundredthOfAKilogram() {
        // 61.51 + 2.5 and 64.01 - 2.5 are not exact in binary floating point.
        check(
            CoachFix.recommend(bench, [straight(3, 61.51), straight(10, 61.51)]),
            .progress, weight: 64.01, reps: 6, reasons: [.cleanSessionsWithReserve]
        )
        let stall = [
            straight(3, 64.01, reps: 5, rir: 0), straight(10, 64.01, reps: 6, rir: 0), straight(17, 64.01, reps: 7, rir: 0),
        ]
        check(CoachFix.recommend(bench, stall), .reduce, weight: 61.51, reps: 5)
    }

    // MARK: - Effort

    func testExactlyOneRepInReserveOnAverageStillHolds() {
        check(
            CoachFix.recommend(bench, [straight(3, 80, rir: 1), straight(10, 80, rir: 1)]),
            .hold, weight: 80, reps: 6, reasons: [.lastSessionNearFailure]
        )
    }

    func testTheEarlierSessionNeedsEnoughEffortDataNotJustOneComfortableValue() {
        let sparse = CoachFix.session(10, CoachFix.sets(80, [6, 6, 6], rir: [3])) // one of three sets, and it looks comfortable
        check(
            CoachFix.recommend(bench, [straight(3, 80), sparse]),
            .hold, weight: 80, reps: 6, reasons: [.awaitingSecondCleanSession]
        )
    }

    func testAHalfRepDropBetweenTheTwoSessionsIsTolerated() {
        // Means 6 -> 5.5.
        check(
            CoachFix.recommend(bench, [day(3, 80, [6, 5], [3, 3]), day(10, 80, [6, 6], [3, 3])]),
            .progress, weight: 82.5, reps: 6, reasons: [.cleanSessionsWithReserve]
        )
        // Means 6 -> 5.33 is more than half a rep.
        check(
            CoachFix.recommend(bench, [day(3, 80, [6, 5, 5], [3, 3, 3]), day(10, 80, [6, 6, 6], [3, 3, 3])]),
            .hold, weight: 80, reps: 5, reasons: [.awaitingSecondCleanSession]
        )
    }

    func testTheShareOfSetsWithRepsInReserveDecidesWhetherEffortCanBeJudged() {
        // One of two sets (50 %) is not enough; three of four (75 %) is.
        let half = CoachFix.sets(80, [6, 6], rir: [3])
        check(
            CoachFix.recommend(bench, [CoachFix.session(3, half), CoachFix.session(10, half)]),
            .noEffortData, reasons: [.noRIRRecorded]
        )
        let threeOfFour = CoachFix.sets(80, [6, 6, 6, 6], rir: [3, 3, 3])
        check(
            CoachFix.recommend(bench, [CoachFix.session(3, threeOfFour), CoachFix.session(10, threeOfFour)]),
            .progress, weight: 82.5, reps: 6
        )
    }

    func testSetsWithoutRepsInReserveDoNotLowerTheAverage() {
        // Two recorded values of 2 (mean 2.0), one set without a value: still comfortable.
        let sets = CoachFix.sets(80, [6, 6, 6], rir: [2, 2])
        check(
            CoachFix.recommend(bench, [CoachFix.session(3, sets), CoachFix.session(10, sets)]),
            .progress, weight: 82.5, reps: 6
        )
    }

    func testAToFailureSetWithoutAValueCountsAsZeroRepsInReserve() {
        // 3, 2 and a to-failure set: mean 1.67, moderate. If the to-failure set were ignored the mean would be 2.5 and it would progress.
        let mixed = [CoachFix.set(80, 6, 3), CoachFix.set(80, 6, 2), CoachFix.set(80, 5, nil, type: .failure)]
        check(
            CoachFix.recommend(bench, [CoachFix.session(3, mixed), CoachFix.session(10, mixed)]),
            .hold, weight: 80, reps: 6, reasons: [.moderateEffort]
        )
    }

    func testRepsInReserveAboveFourAreClampedToFour() {
        // 9 counts as 4: (4 + 0 + 0) / 3 = 1.33 is moderate. Unclamped it would be (9 + 0 + 0) / 3 = 3 and progress.
        let sets = CoachFix.sets(80, [6, 6, 6], rir: [9, 0, 0])
        check(
            CoachFix.recommend(bench, [CoachFix.session(3, sets), CoachFix.session(10, sets)]),
            .hold, weight: 80, reps: 6, reasons: [.moderateEffort]
        )
    }

    func testSetsWithinFiveGramsOfTheTopSetAreAtTheTopLoad() {
        // 79.998 kg is the same load as 80 kg: three sets at the top, mean reps (6 + 6 + 4) / 3 = 5.33.
        let close = [CoachFix.set(80, 6, 3), CoachFix.set(80, 6, 3), CoachFix.set(79.998, 4, 3)]
        check(
            CoachFix.recommend(bench, [CoachFix.session(3, close), CoachFix.session(10, close)]),
            .progress, weight: 82.5, reps: 5
        )
        // 79.99 kg is a different (lighter) weight and is not judged.
        let far = [CoachFix.set(80, 6, 3), CoachFix.set(80, 6, 3), CoachFix.set(79.99, 4, 3)]
        check(
            CoachFix.recommend(bench, [CoachFix.session(3, far), CoachFix.session(10, far)]),
            .progress, weight: 82.5, reps: 6
        )
    }

    // MARK: - The size of a step

    func testTheJumpCapIsInclusiveAndDependsOnTheAudience() {
        func cable(_ kg: Double, _ audience: AudienceProfile) -> Recommendation {
            CoachFix.recommend(crossover, [straight(3, kg, reps: 10), straight(10, kg, reps: 10)], audience: audience)
        }
        // 2.5 kg is exactly 5 % of 50 kg: allowed for an unknown audience. 49 kg is over, and so is 45 kg (5.6 %).
        check(cable(50, .unknown), .progress, weight: 52.5, reps: 10)
        check(cable(49, .unknown), .addRep, weight: 49, reps: 11)
        check(cable(45, .unknown), .addRep, weight: 45, reps: 11)
        check(cable(45, AudienceProfile(ageGroup: .minor)), .addRep, weight: 45, reps: 11)
        // An adult may take the same step (5.6 %), up to 7.5 %: 34 kg is 7.35 %, 30 kg is 8.3 %.
        check(cable(45, .adult), .progress, weight: 47.5, reps: 10)
        check(cable(34, .adult), .progress, weight: 36.5, reps: 10)
        check(cable(30, .adult), .addRep, weight: 30, reps: 11)

        // A 3 kg step on 40 kg is exactly 7.5 %.
        var config = CoachConfig()
        config.incrementsKg[.barbell] = 3
        check(
            CoachFix.recommend(bench, [straight(3, 40), straight(10, 40)], config: config),
            .progress, weight: 43, reps: 6
        )
        check(
            CoachFix.recommend(bench, [straight(3, 39), straight(10, 39)], config: config),
            .addRep, weight: 39, reps: 7
        )
    }

    func testTheRepCeilingIsInclusive() {
        func dumbbell(_ reps: Int, _ config: CoachConfig = CoachConfig()) -> Recommendation {
            CoachFix.recommend(lateral, [straight(3, 8, reps: reps), straight(10, 8, reps: reps)], config: config)
        }
        let reasons: [ReasonCode] = [.cleanSessionsWithReserve, .stepExceedsCap]
        check(dumbbell(29), .addRep, weight: 8, reps: 30, reasons: reasons)
        check(dumbbell(30), .hold, weight: 8, reps: 30, reasons: reasons)
        var config = CoachConfig()
        config.maximumTargetReps = 15
        check(dumbbell(14, config), .addRep, weight: 8, reps: 15, reasons: reasons)
        check(dumbbell(15, config), .hold, weight: 8, reps: 15, reasons: reasons)
    }

    func testEveryEquipmentProgressesByItsOwnStep() {
        XCTAssertEqual(Set(CoachConfig().incrementsKg.keys), Set(Equipment.allCases))
        func progressed(_ exercise: Exercise, _ kg: Double) -> Double? {
            let result = CoachFix.recommend(exercise, [straight(3, kg), straight(10, kg)])
            XCTAssertEqual(result.verdict, .progress, "\(exercise.equipment)")
            return result.targetWeightKg
        }
        XCTAssertEqual(progressed(bench, 80), 82.5)
        XCTAssertEqual(progressed(lateral, 40), 42)
        XCTAssertEqual(progressed(crossover, 40), 42.5)
        XCTAssertEqual(progressed(CoachFix.lib("legpress"), 100), 102.5)
        let weightedDip = Exercise.custom(name: "Weighted dip", muscle: .chest, equipment: .bodyweight, tracking: .weightReps)
        XCTAssertEqual(progressed(weightedDip, 20), 21)
        let sandbag = Exercise.custom(name: "Sandbag carry", muscle: .core, equipment: .other, tracking: .weightReps)
        XCTAssertEqual(progressed(sandbag, 20), 21)
    }

    func testAnUnusableConfiguredStepFallsBackToTheKeypadStep() {
        for bad in [0.0, -2.5, .nan, .infinity, -.infinity] {
            var config = CoachConfig()
            config.incrementsKg[.barbell] = bad
            XCTAssertEqual(config.increment(for: bench), 2.5, "\(bad)")
            check(
                CoachFix.recommend(bench, [straight(3, 80), straight(10, 80)], config: config),
                .progress, weight: 82.5, reps: 6
            )
        }
        // A missing entry uses the exercise's own step (2.5 kg for a cable), not an invented one.
        var missing = CoachConfig()
        missing.incrementsKg[.cable] = nil
        XCTAssertEqual(missing.increment(for: crossover), 2.5)
        check(
            CoachFix.recommend(crossover, [straight(3, 40), straight(10, 40)], config: missing),
            .progress, weight: 42.5, reps: 6
        )
        // A usable entry wins.
        var custom = CoachConfig()
        custom.incrementsKg[.dumbbell] = 1.25
        XCTAssertEqual(custom.increment(for: lateral), 1.25)
    }

    // MARK: - Suspect sets

    func testTheSuspectReferenceComesFromTheLastSixSessions() {
        // Estimated 1RM of the reference set, newest first: 80, 80, 80, 96, 96, 96, 96. The limit is 1.25 times the median.
        func history(probing e1RM: Double) -> [ExerciseSession] {
            let kgs: [Double] = [60, 60, 60, 72, 72, 72, 72]
            return kgs.enumerated().map { index, kg in
                reference(3 + index * 7, kg: kg, extra: index == 0 ? [probe(e1RM)] : [])
            }
        }
        // Six sessions: median 88, limit 110. With five the median would be 80 (limit 100), with seven 96 (limit 120).
        XCTAssertFalse(isFlagged(history(probing: 104)))
        XCTAssertTrue(isFlagged(history(probing: 116)))
    }

    func testThreeSessionsAreEnoughToKnowWhatIsTypical() {
        let clean = CoachFix.sets(80, [6, 6, 6], rir: [2, 2, 2])
        let typo = clean + [CoachFix.set(85, 16, 2)]
        let result = CoachFix.recommend(
            bench, [CoachFix.session(3, clean), CoachFix.session(10, typo), CoachFix.session(17, clean)]
        )
        check(result, .progress, weight: 82.5, reps: 6, reasons: [.suspectSetExcluded, .cleanSessionsWithReserve])
    }

    func testTheReferenceIsTheMedianOfAnOddNumberOfSessions() {
        // Bests 104, 80, 96: median 96, limit 120, so a set of 115 is kept. (The mean of the lower two, 88, would give 110.)
        let sessions = [reference(3, kg: 78, extra: [probe(115)]), reference(10, kg: 60), reference(17, kg: 72)]
        XCTAssertFalse(isFlagged(sessions))
    }

    func testTheReferenceIsTheMiddleOfTwoMiddleValuesForAnEvenNumberOfSessions() {
        // Bests 104, 88, 80, 96: sorted 80, 88, 96, 104, median 92, limit 115, so a set of 117 is dropped. (96 alone would allow 120.)
        let sessions = [
            reference(3, kg: 78, extra: [probe(117)]), reference(10, kg: 66), reference(17, kg: 60), reference(24, kg: 72),
        ]
        XCTAssertTrue(isFlagged(sessions))
    }

    func testASetExactlyAtTheLimitIsKept() {
        // 75 kg x 10 is exactly 1.25 times 60 kg x 10 (the premise of this test).
        XCTAssertEqual(Estimated1RM.epley(weightKg: 75, reps: 10), 1.25 * Estimated1RM.epley(weightKg: 60, reps: 10))
        let sessions = [
            reference(3, kg: 60, extra: [CoachFix.set(75, 10, 3)]), reference(10, kg: 60), reference(17, kg: 60),
        ]
        XCTAssertFalse(isFlagged(sessions))
    }

    func testTheReferenceUsesEachSessionsBestSetNotItsWeakest() {
        // Every session has an 80 and a 96 set; a set of 110 is under 1.25 times 96 but over 1.25 times 80.
        let sessions = (0..<3).map { index in
            CoachFix.session(3 + index * 7, [CoachFix.set(60, 10, 3), CoachFix.set(72, 10, 3)] + (index == 0 ? [probe(110)] : []))
        }
        XCTAssertFalse(isFlagged(sessions))
    }

    func testTheSuspectLimitIsOneAndAQuarterTimesTheReference() {
        // Reference 96: a set of 122 (ratio 1.27) is dropped, one of 118 (1.23) is kept.
        func sessions(probing e1RM: Double) -> [ExerciseSession] {
            (0..<3).map { reference(3 + $0 * 7, kg: 72, extra: $0 == 0 ? [probe(e1RM)] : []) }
        }
        XCTAssertTrue(isFlagged(sessions(probing: 122)))
        XCTAssertFalse(isFlagged(sessions(probing: 118)))
    }

    func testSetsOfMoreThanTenRepsDoNotMakeTheReference() {
        // Three sessions of 50 kg x 11 would give a reference of 68 if 11 reps were trusted; they are not, so the heavy single
        // set of 100 kg x 3 (estimated 1RM 110) has nothing to be compared with and is kept.
        let sessions = [
            CoachFix.session(3, [CoachFix.set(50, 11, 3), CoachFix.set(100, 3, 3)]),
            CoachFix.session(10, [CoachFix.set(50, 11, 3)]),
            CoachFix.session(17, [CoachFix.set(50, 11, 3)]),
        ]
        XCTAssertFalse(isFlagged(sessions))
    }

    func testTheSuspectNoteAccompaniesEveryAnswerThatIsBuiltOnData() {
        let typo = CoachFix.set(85, 16, 2) // estimated 1RM 130 against a typical 96
        func inserting(_ set: CompletedSet, into sessions: [ExerciseSession], at index: Int) -> [ExerciseSession] {
            var copy = sessions
            copy[index].sets.append(set)
            return copy
        }

        let hold = inserting(typo, into: (0..<4).map { day(3 + $0 * 7, 80, [6, 6, 6], [0, 1, 1]) }, at: 1)
        let held = CoachFix.recommend(bench, hold)
        check(held, .hold, weight: 80, reps: 6, reasons: [.suspectSetExcluded, .lastSessionNearFailure])
        XCTAssertEqual(held.sessionsUsed, 4)

        let progress = inserting(typo, into: (0..<4).map { straight(3 + $0 * 7, 80) }, at: 1)
        let progressed = CoachFix.recommend(bench, progress)
        check(progressed, .progress, weight: 82.5, reps: 6, reasons: [.suspectSetExcluded, .cleanSessionsWithReserve])
        XCTAssertEqual(progressed.sessionsUsed, 4)

        let stall = inserting(typo, into: [
            day(3, 80, [5, 5, 4], [0, 1, 0]), day(10, 80, [6, 5, 5], [1, 1, 0]),
            day(17, 80, [6, 6, 6], [2, 2, 2]), day(24, 80, [6, 6, 6], [2, 2, 2]),
        ], at: 3)
        let reduced = CoachFix.recommend(bench, stall)
        check(reduced, .reduce, weight: 77.5, reps: 5, reasons: [.suspectSetExcluded, .repsFellAtSameLoad])
        XCTAssertEqual(reduced.sessionsUsed, 4)

        // A cable at 40 kg is a 6.25 % step: too much for an unknown audience, so it adds a rep. The typo is 60 kg x 10.
        let cableSessions = inserting(
            CoachFix.set(60, 10, 3), into: (0..<4).map { straight(3 + $0 * 7, 40, reps: 10) }, at: 1
        )
        let added = CoachFix.recommend(crossover, cableSessions, audience: .unknown)
        check(added, .addRep, weight: 40, reps: 11, reasons: [.suspectSetExcluded, .cleanSessionsWithReserve, .stepExceedsCap])
        XCTAssertEqual(added.sessionsUsed, 4)

        let plain = CoachFix.sets(80, [6, 6, 6])
        let unknownEffort = CoachFix.recommend(bench, [
            CoachFix.session(3, plain), CoachFix.session(10, plain + [CoachFix.set(85, 16)]),
            CoachFix.session(17, plain), CoachFix.session(24, plain),
        ])
        check(unknownEffort, .noEffortData, reasons: [.suspectSetExcluded, .noRIRRecorded])
        XCTAssertEqual(unknownEffort.sessionsUsed, 4)
    }

    // MARK: - The starting policy, in one place

    func testTheStartingPolicyValues() {
        let config = CoachConfig()
        XCTAssertEqual(config.minimumSessions, 2)
        XCTAssertEqual(config.progressMinimumRIR, 2.0)
        XCTAssertEqual(config.effortCoverage, 2.0 / 3.0)
        XCTAssertEqual(config.holdMaximumRIR, 1.0)
        XCTAssertEqual(config.repsFallTolerance, 0.5)
        XCTAssertEqual(config.reduceFraction, 0.05)
        XCTAssertEqual(config.maximumReduceFraction, 0.10)
        XCTAssertEqual(config.maximumJumpFraction, 0.075)
        XCTAssertEqual(config.maximumJumpFractionRestricted, 0.05)
        XCTAssertEqual(config.breakDays, 28)
        XCTAssertEqual(config.maximumRepsForReference, 10)
        XCTAssertEqual(config.suspectRatio, 1.25)
        XCTAssertEqual(config.lighterWeekAfterIncreases, 6)
        XCTAssertEqual(config.maximumTargetReps, 30)
        let steps: [Equipment: Double] = [.barbell: 2.5, .dumbbell: 2, .cable: 2.5, .machine: 2.5, .bodyweight: 1, .other: 1]
        XCTAssertEqual(config.incrementsKg, steps)
        // The version stamp changes together with a rule; changing it is a deliberate act that also changes this line.
        XCTAssertEqual(ProgressionEngine.version, 1)
    }

    func testOnlyKnownAdultsGetTheLargerJumpCap() {
        let config = CoachConfig()
        XCTAssertEqual(config.jumpCap(for: .adult), 0.075)
        XCTAssertEqual(config.jumpCap(for: .unknown), 0.05)
        XCTAssertEqual(config.jumpCap(for: AudienceProfile(ageGroup: .minor)), 0.05)
        XCTAssertFalse(AudienceProfile.adult.isRestricted)
        XCTAssertTrue(AudienceProfile.unknown.isRestricted)
        XCTAssertTrue(AudienceProfile(ageGroup: .minor).isRestricted)
        // The restricted cap can never be looser than the normal one, even if both are configured the wrong way round.
        var odd = CoachConfig()
        odd.maximumJumpFraction = 0.04
        odd.maximumJumpFractionRestricted = 0.06
        XCTAssertEqual(odd.jumpCap(for: .unknown), 0.04)
        XCTAssertEqual(odd.jumpCap(for: .adult), 0.04)
    }

    // MARK: - Policy oracle

    /// What the proposal's section 6.1 says about the last two sessions, restated from the raw sets.
    private struct TopSets {
        var load: Double
        var meanReps: Double
        var coverage: Double
        var meanRIR: Double?

        init(_ session: ExerciseSession) {
            let top = session.sets.map { $0.weightKg }.max() ?? 0
            let atTop = session.sets.filter { $0.weightKg >= top - 0.005 }
            var efforts: [Int] = []
            for set in atTop {
                if let value = set.rir {
                    efforts.append(min(4, max(0, value)))
                } else if set.type == .failure {
                    efforts.append(0)
                }
            }
            load = top
            meanReps = Double(atTop.map { $0.reps }.reduce(0, +)) / Double(atTop.count)
            coverage = Double(efforts.count) / Double(atTop.count)
            meanRIR = efforts.isEmpty ? nil : Double(efforts.reduce(0, +)) / Double(efforts.count)
        }

        var hasEffortData: Bool { coverage >= 2.0 / 3.0 && meanRIR != nil }
        var isComfortable: Bool { hasEffortData && (meanRIR ?? 0) >= 2.0 }
    }

    func testProgressAndReduceHappenExactlyWhenTheDocumentedConditionsHold() {
        var rng = RedLCG(seed: 20_261_017)
        var seen: [Verdict: Int] = [:]
        var skipped = 0
        for index in 0..<4_000 {
            let falling = rng.chance(25)
            let count = rng.int(2...5)
            // 20 to 100 kg; a third of the cases start light enough for the 2.5 kg step to exceed the jump cap (under 33 kg).
            var load = rng.chance(33) ? Double(rng.int(8...13)) * 2.5 : Double(rng.int(14...40)) * 2.5
            var sessions: [ExerciseSession] = []
            let firstDay = rng.int(1...34)
            var dayOffset = firstDay
            for position in 0..<count {
                if !falling { load = max(20, load + rng.pick([-2.5, 0, 0, 0, 0, 2.5])) }
                let reps = falling ? 4 + position : rng.int(4...9)
                var sets: [CompletedSet] = []
                for _ in 0..<rng.int(2...4) {
                    let type: SetType = rng.chance(8) ? .failure : .normal
                    // A to-failure set carries no explicit value here: that is the unambiguous case (reps in reserve 0).
                    let rir: Int? = (type == .failure || rng.chance(20)) ? nil : (falling ? rng.int(0...1) : rng.int(0...4))
                    let weight = rng.chance(15) ? load - 5 : load
                    sets.append(CoachFix.set(weight, reps + rng.int(-1...1), rir, type: type))
                }
                sessions.append(CoachFix.session(dayOffset, sets))
                dayOffset += rng.int(2...9)
            }

            let result = CoachFix.recommend(bench, sessions)
            seen[result.verdict, default: 0] += 1
            if result.reasons.contains(.suspectSetExcluded) {
                skipped += 1 // the engine then judged a subset of the sets; the oracle below judges all of them
                continue
            }
            let context = "case \(index) \(result)"
            let tops = sessions.map { TopSets($0) }
            let newest = tops[0]
            let previous = tops[1]
            let recent = firstDay <= 28

            // Progress needs two sessions at one weight, both comfortable, no rep drop, and no long break.
            let sameLoad = abs(newest.load - previous.load) < 0.005
            let noRepDrop = newest.meanReps >= previous.meanReps - 0.5
            let ready = recent && sameLoad && newest.isComfortable && previous.isComfortable && noRepDrop
            let raised = [Verdict.progress, .addRep].contains(result.verdict)
            XCTAssertEqual(raised, ready, context)
            if ready {
                let reps = Int(newest.meanReps.rounded())
                if 2.5 / newest.load > 0.075 + 1e-9 {
                    check(result, .addRep, weight: newest.load, reps: reps + 1)
                } else {
                    check(result, .progress, weight: ((newest.load + 2.5) * 100).rounded() / 100, reps: reps)
                }
            }

            // A reduce needs reps that fell twice at one weight, and a hard last session.
            var stalled = false
            if count >= 3 {
                let oldest = tops[2]
                let oneWeight = abs(newest.load - previous.load) < 0.005 && abs(previous.load - oldest.load) < 0.005
                let fellTwice = newest.meanReps < previous.meanReps - 0.5 && previous.meanReps < oldest.meanReps - 0.5
                stalled = oneWeight && fellTwice && newest.hasEffortData && (newest.meanRIR ?? 9) <= 1.0
            }
            let amount = max(2.5, (newest.load * 0.05 / 2.5).rounded(.down) * 2.5)
            let reduceAllowed = amount / newest.load <= 0.10 + 1e-9
            XCTAssertEqual(result.verdict == .reduce, recent && stalled && reduceAllowed, context)
            if result.verdict == .reduce, let weight = result.targetWeightKg {
                XCTAssertEqual(weight, ((newest.load - amount) * 100).rounded() / 100, context)
            }

            // The reasons for a hold or a missing answer match the effort that was logged.
            if result.reasons.contains(.lastSessionNearFailure) {
                XCTAssertTrue(newest.hasEffortData && (newest.meanRIR ?? 9) <= 1.0, context)
            }
            if result.reasons.contains(.moderateEffort) {
                XCTAssertTrue(newest.hasEffortData && (newest.meanRIR ?? 0) > 1.0 && (newest.meanRIR ?? 9) < 2.0, context)
            }
            if result.verdict == .noEffortData {
                XCTAssertFalse(newest.hasEffortData, context)
            }
        }
        // The generator must reach every branch, otherwise the equivalences above prove little.
        XCTAssertGreaterThan(seen[.progress, default: 0], 60, "\(seen)")
        XCTAssertGreaterThan(seen[.addRep, default: 0], 15, "\(seen)")
        XCTAssertGreaterThan(seen[.reduce, default: 0], 50, "\(seen)")
        XCTAssertGreaterThan(seen[.hold, default: 0], 100, "\(seen)")
        XCTAssertGreaterThan(seen[.noEffortData, default: 0], 50, "\(seen)")
        XCTAssertLessThan(skipped, 300, "too many cases skipped: \(skipped)")
    }
}
