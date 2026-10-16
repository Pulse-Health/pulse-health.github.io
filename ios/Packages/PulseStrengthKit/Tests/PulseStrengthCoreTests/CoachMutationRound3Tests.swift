import XCTest
@testable import PulseStrengthCore

/// Third round of mutation testing, aimed at the lines the review-fix commit added or changed in `Coach/`. Each test here kills at
/// least one single-site mutant that every earlier test let through (the comment above each test says which change it catches). They
/// pin boundaries, orderings and wiring that the earlier tests left open; none of them introduces or changes policy.
final class CoachMutationRound3Tests: XCTestCase {
    private let now = CoachFix.now
    private let bench = CoachFix.lib("bench")
    private let ohp = CoachFix.lib("ohp")
    private let curl = CoachFix.lib("curl")

    private func session(
        _ daysAgo: Int, _ kg: Double, reps: [Int] = [6, 6, 6], rir: [Int?] = [3, 3, 3],
        name: String = "Workout", id: UUID = UUID()
    ) -> ExerciseSession {
        ExerciseSession(
            id: id, date: CoachFix.date(daysAgo: daysAgo), workoutName: name,
            sets: CoachFix.sets(kg, reps, rir: rir), isPersonalRecord: false
        )
    }

    private func history(_ sessions: [ExerciseSession]) -> ExerciseHistory { CoachFix.history(bench, sessions) }

    /// A session of `reps` repetitions per set at the given weights, all at 3 reps in reserve.
    private func mixed(_ daysAgo: Int, _ weights: [Double], reps: Int = 5) -> ExerciseSession {
        ExerciseSession(
            id: UUID(), date: CoachFix.date(daysAgo: daysAgo), workoutName: "Workout",
            sets: weights.map { CoachFix.set($0, reps, 3) }, isPersonalRecord: false
        )
    }

    private func entry(_ sets: [LoggedSet]) -> WorkoutExercise {
        WorkoutExercise(exercise: bench, sets: sets, restSeconds: 90)
    }

    // MARK: Dates and order

    /// Kills: the future-date filter at its edge (`>` -> `>=`).
    func testASessionExactlyOneDayAheadIsKeptAndOneSecondFurtherIsNot() {
        func ahead(_ seconds: TimeInterval) -> ExerciseSession {
            ExerciseSession(
                id: UUID(), date: now.addingTimeInterval(seconds), workoutName: "Workout",
                sets: CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3]), isPersonalRecord: false
            )
        }
        let atLimit = CoachFix.recommend(bench, [ahead(86_400), session(7, 80)])
        XCTAssertEqual(atLimit.verdict, .progress)
        XCTAssertEqual(atLimit.sessionsUsed, 2)

        let beyond = CoachFix.recommend(bench, [ahead(86_401), session(7, 80)])
        XCTAssertEqual(beyond.verdict, .insufficientData)
        XCTAssertEqual(beyond.reasons, [.tooFewSessions])
        XCTAssertEqual(beyond.sessionsUsed, 1)
    }

    /// Kills: dropping the sort inside the engine (the old order test fed three identical sessions, which look the same in any order).
    func testEveryOrderOfDifferentSessionsGivesTheAnswerForTheNewestFirstOrder() {
        let newest = session(3, 82.5)
        let middle = session(10, 80)
        let oldest = session(17, 77.5)
        let expected = CoachFix.recommend(bench, [newest, middle, oldest])
        XCTAssertEqual(expected.verdict, .hold)
        XCTAssertEqual(expected.targetWeightKg, 82.5, "the newest session is the latest")
        XCTAssertEqual(expected.reasons, [.awaitingSecondCleanSession])

        let all = [newest, middle, oldest]
        for first in 0..<3 {
            for second in 0..<3 where second != first {
                let third = 3 - first - second
                let permuted = [all[first], all[second], all[third]]
                XCTAssertEqual(CoachFix.recommend(bench, permuted), expected, "order \(first)\(second)\(third)")
            }
        }
    }

    /// Kills: reversing the tie-break between two sessions with the same date (`<` -> `>`), and inverting the date comparison.
    func testTwoSessionsWithTheSameDateKeepTheOrderTheyWereGivenIn() {
        let date = CoachFix.date(daysAgo: 3)
        func make(_ kg: Double) -> ExerciseSession {
            ExerciseSession(
                id: UUID(), date: date, workoutName: "Workout",
                sets: CoachFix.sets(kg, [6, 6, 6], rir: [3, 3, 3]), isPersonalRecord: false
            )
        }
        let light = make(80)
        let heavy = make(85)
        let older = session(10, 80)
        XCTAssertEqual(CoachFix.recommend(bench, [light, heavy, older]).targetWeightKg, 80)
        XCTAssertEqual(CoachFix.recommend(bench, [heavy, light, older]).targetWeightKg, 85)
    }

    // MARK: Typo guard

    /// Kills: letting a session without any reference set (all sets above the reference rep limit) count towards the median
    /// (`$0 > 0` -> `$0 >= 0`). Two usable sessions cannot tell which of them has the typo, whatever else is in the history.
    func testASessionOfHighRepSetsDoesNotHelpToResolveAJump() {
        let jump = mixed(3, [100, 100, 160])
        let usual = session(10, 100, reps: [5, 5, 5])
        let highReps = session(17, 60, reps: [15, 15, 15])
        XCTAssertGreaterThan(Estimated1RM.epley(weightKg: 160, reps: 5), 1.25 * Estimated1RM.epley(weightKg: 100, reps: 5))
        let result = CoachFix.recommend(bench, [jump, usual, highReps])
        XCTAssertEqual(result.verdict, .insufficientData)
        XCTAssertEqual(result.reasons, [.suspectSetExcluded])
        XCTAssertEqual(result.sessionsUsed, 3)
    }

    /// Kills: the unresolved-jump edge (`>` -> `>=`) and a wrong session count in that answer.
    func testTwoSessionsExactlyAtTheSuspectRatioAreNotAJump() {
        // One-rep sets at 80 and 100 kg: the estimates differ by exactly the ratio 1.25 in floating point as well.
        XCTAssertEqual(Estimated1RM.epley(weightKg: 100, reps: 1), 1.25 * Estimated1RM.epley(weightKg: 80, reps: 1))
        let exact = CoachFix.recommend(bench, [session(3, 100, reps: [1, 1, 1]), session(10, 80, reps: [1, 1, 1])])
        XCTAssertEqual(exact.verdict, .hold)
        XCTAssertEqual(exact.reasons, [.awaitingSecondCleanSession])
        XCTAssertEqual(exact.targetWeightKg, 100)

        // One set above the limit among sets that agree with the other session: not corroborated, so nothing can be trusted.
        let beyond = CoachFix.recommend(bench, [mixed(3, [80, 80, 101], reps: 1), session(10, 80, reps: [1, 1, 1])])
        XCTAssertEqual(beyond.verdict, .insufficientData)
        XCTAssertEqual(beyond.reasons, [.suspectSetExcluded])
        XCTAssertEqual(beyond.sessionsUsed, 2)
    }

    /// Kills: the jump-from-the-next-older-session edge (`>` -> `>=`).
    func testASetExactlyAtTheRatioAboveTheNextOlderSessionIsKept() {
        XCTAssertEqual(Estimated1RM.epley(weightKg: 125, reps: 1), 1.25 * Estimated1RM.epley(weightKg: 100, reps: 1))
        // Median of the bests is the 90 kg estimate, so 125 kg is far above typical; the next older session is 100 kg, exactly 1.25 below.
        let sessions = [session(3, 125, reps: [1, 1, 1]), session(10, 100, reps: [1, 1, 1])]
            + (2...4).map { session(3 + $0 * 7, 90, reps: [1, 1, 1]) }
        let result = CoachFix.recommend(bench, sessions)
        XCTAssertFalse(result.reasons.contains(.suspectSetExcluded))
        XCTAssertEqual(result.targetWeightKg, 125)
    }

    /// Kills: the far-above-typical edge (`>` -> `>=`).
    func testASetExactlyAtTheRatioAboveTheTypicalBestIsKept() {
        // Median of the bests is the 100 kg estimate; the next older session is 90 kg, so only the typical-best edge decides.
        let sessions = [session(3, 125, reps: [1, 1, 1]), session(10, 90, reps: [1, 1, 1])]
            + (2...4).map { session(3 + $0 * 7, 100, reps: [1, 1, 1]) }
        let result = CoachFix.recommend(bench, sessions)
        XCTAssertFalse(result.reasons.contains(.suspectSetExcluded))
        XCTAssertEqual(result.targetWeightKg, 125)
    }

    /// Kills: dropping the exclusion flag from the "too few sessions" answer.
    func testTheTooFewSessionsAnswerAfterAnExclusionStillSaysSo() {
        var config = CoachConfig()
        config.minimumSessions = 3
        let typo = mixed(3, [160])
        let result = CoachFix.recommend(bench, [typo, session(10, 100, reps: [5, 5, 5]), session(17, 100, reps: [5, 5, 5])], config: config)
        XCTAssertEqual(result.verdict, .insufficientData)
        XCTAssertEqual(result.reasons, [.suspectSetExcluded, .tooFewSessions])
        XCTAssertEqual(result.sessionsUsed, 2)
    }

    // MARK: Recent run and minimum sessions

    /// Kills: the recent-run guard ignoring `minimumSessions` (`max(2, minimumSessions)` -> `2`).
    func testTheRecentRunMustReachTheMinimumNumberOfSessionsToo() {
        var config = CoachConfig()
        config.minimumSessions = 3
        // Three valid sessions, but the oldest is three months before the other two: the run that counts has two.
        let sessions = [session(3, 80), session(10, 80), session(100, 80)]
        let result = CoachFix.recommend(bench, sessions, config: config)
        XCTAssertEqual(result.verdict, .hold)
        XCTAssertEqual(result.reasons, [.awaitingSecondCleanSession])
        XCTAssertEqual(result.targetWeightKg, 80)
        XCTAssertEqual(result.sessionsUsed, 2)
        // With three sessions in the run the same configuration moves on.
        XCTAssertEqual(CoachFix.recommend(bench, [session(3, 80), session(10, 80), session(17, 80)], config: config).verdict, .progress)
    }

    /// Kills: a verdict that reports every valid session as its basis (`sessions: count` -> `prepared.sessions.count`) in the answers
    /// that were not covered: the sessions behind a long gap are not what the answer rests on.
    func testSessionsUsedCountsTheRecentRunOnlyForEveryVerdictThatHasASession() {
        let old = session(200, 80)
        let progress = CoachFix.recommend(bench, [session(3, 80), session(10, 80), old])
        XCTAssertEqual(progress.verdict, .progress)
        XCTAssertEqual(progress.sessionsUsed, 2)

        let falling = [
            session(3, 80, reps: [4, 4, 4], rir: [0, 0, 0]), session(10, 80, reps: [5, 5, 5], rir: [0, 0, 0]),
            session(17, 80, reps: [6, 6, 6], rir: [0, 0, 0]), old,
        ]
        let reduce = CoachFix.recommend(bench, falling)
        XCTAssertEqual(reduce.verdict, .reduce)
        XCTAssertEqual(reduce.sessionsUsed, 3)

        let plain: [Int?] = [nil, nil, nil]
        let noEffort = CoachFix.recommend(bench, [session(3, 80, rir: plain), session(10, 80, rir: plain), old])
        XCTAssertEqual(noEffort.verdict, .noEffortData)
        XCTAssertEqual(noEffort.sessionsUsed, 2)

        // 8 kg on a dumbbell: a 2 kg step is a quarter of the weight, so the answer is one more rep.
        let light = [session(3, 8, reps: [20, 20, 20]), session(10, 8, reps: [20, 20, 20]), old]
        let addRep = CoachFix.recommend(CoachFix.lib("lateral"), light)
        XCTAssertEqual(addRep.verdict, .addRep)
        XCTAssertEqual(addRep.sessionsUsed, 2)
    }

    // MARK: Effort

    private func rising(rir: [Int?], loads: [Double] = [72.5, 70, 67.5, 65, 62.5, 60, 57.5]) -> [ExerciseSession] {
        loads.enumerated().map { session(3 + $0.offset * 7, $0.element, rir: rir) }
    }

    /// Kills: the lighter week without the effort-coverage condition. One set with a value out of three is no effort data.
    func testALighterWeekNeedsEnoughSetsWithAnEffortValue() {
        let result = CoachFix.recommend(bench, rising(rir: [2, nil, nil]))
        XCTAssertEqual(result.verdict, .noEffortData)
        XCTAssertEqual(result.reasons, [.noRIRRecorded])
        XCTAssertEqual(CoachFix.recommend(bench, rising(rir: [2, 2, nil])).verdict, .reduce, "two of three is enough")
    }

    /// Kills: a streak that counts weights closer than the tolerance (0.005 kg) as increases.
    func testWeightsThatAreTheSameWithinTheToleranceAreNoIncrease() {
        let loads: [Double] = [80.012, 80.010, 80.008, 80.006, 80.004, 80.002, 80.0]
        let result = CoachFix.recommend(bench, rising(rir: [2, 2, 2], loads: loads))
        XCTAssertEqual(result.verdict, .progress)
        XCTAssertFalse(result.reasons.contains(.lighterWeekDue))
    }

    /// Kills: dropping the rounding tolerance (1e-9) on the share of comfortable sets. The share is 2 of 3 = 0.6666666666666666; a
    /// threshold written as `1 - 1/3` is one unit in the last place higher, and must still be met.
    func testTheComfortableShareToleratesARoundedThreshold() {
        var config = CoachConfig()
        config.comfortableSetShare = 1.0 - 1.0 / 3.0
        XCTAssertGreaterThan(config.comfortableSetShare, 2.0 / 3.0)
        XCTAssertTrue(config.isValid)
        let twoOfThree: [Int?] = [3, 2, 1]
        let allComfortable: [Int?] = [3, 3, 3]
        let latestIsTwoOfThree = CoachFix.recommend(
            bench, [session(3, 80, rir: twoOfThree), session(10, 80, rir: allComfortable)], config: config
        )
        XCTAssertEqual(latestIsTwoOfThree.verdict, .progress)
        let previousIsTwoOfThree = CoachFix.recommend(
            bench, [session(3, 80, rir: allComfortable), session(10, 80, rir: twoOfThree)], config: config
        )
        XCTAssertEqual(previousIsTwoOfThree.verdict, .progress)
    }

    /// Kills: no upper cap on a stored reps-in-reserve value. A stray 8 counts as 4, so the mean below is 2.0, under the lighter-week
    /// limit of 3; taken at face value the mean would be 3.33 and the lighter week would never come.
    func testAStrayHighRepsInReserveCountsAsFour() {
        let result = CoachFix.recommend(bench, rising(rir: [8, 1, 1]))
        XCTAssertEqual(result.verdict, .reduce)
        XCTAssertEqual(result.reasons, [.lighterWeekDue])
        XCTAssertEqual(result.targetWeightKg, 70)
    }

    // MARK: Caps absorb rounding

    /// Kills: dropping the 1e-9 slack on the jump cap. 0.9 / 15 is 0.06000000000000001 in floating point, a hair above the cap 0.06
    /// that it equals on paper.
    func testAStepExactlyAtTheJumpCapIsAllowedDespiteRounding() {
        var config = CoachConfig()
        config.incrementsKg[.barbell] = 0.9
        config.maximumJumpFraction = 0.06
        XCTAssertGreaterThan(0.9 / 15.0, 0.06)
        let result = CoachFix.recommend(bench, [session(3, 15), session(10, 15)], config: config)
        XCTAssertEqual(result.verdict, .progress)
        XCTAssertEqual(result.targetWeightKg, 15.9)
    }

    /// Kills: dropping the 1e-9 slack on the reduce cap, same arithmetic as above.
    func testAReduceExactlyAtTheCapIsAllowedDespiteRounding() {
        var config = CoachConfig()
        config.incrementsKg[.barbell] = 0.9
        config.maximumReduceFraction = 0.06
        XCTAssertGreaterThan(0.9 / 15.0, 0.06)
        let falling = [
            session(3, 15, reps: [4, 4, 4], rir: [0, 0, 0]),
            session(10, 15, reps: [5, 5, 5], rir: [0, 0, 0]),
            session(17, 15, reps: [6, 6, 6], rir: [0, 0, 0]),
        ]
        let result = CoachFix.recommend(bench, falling, config: config)
        XCTAssertEqual(result.verdict, .reduce)
        XCTAssertEqual(result.targetWeightKg, 14.1)
    }

    // MARK: The tolerances themselves are inclusive

    /// Kills: the share check made strict (`>=` -> `>`) for the latest or the previous session. The threshold sits exactly one rounding
    /// tolerance (1e-9) above the share of 1 comfortable set in 4, which the check has to accept. The per-set limit of 1.5 lets a
    /// single set at RIR 4 carry a mean of 1.75.
    func testAShareExactlyOneToleranceBelowTheThresholdPasses() {
        var config = CoachConfig()
        config.progressMinimumRIR = 1.5
        config.comfortableSetShare = 0.25 + 1e-9
        XCTAssertEqual(config.comfortableSetShare - 1e-9, 0.25, "the threshold is exactly one tolerance above the share")
        let quarter: [Int?] = [4, 1, 1, 1]
        let all: [Int?] = [4, 4, 4, 4]
        func verdict(latest: [Int?], previous: [Int?]) -> Verdict {
            CoachFix.recommend(bench, [
                session(3, 80, reps: [6, 6, 6, 6], rir: latest), session(10, 80, reps: [6, 6, 6, 6], rir: previous),
            ], config: config).verdict
        }
        XCTAssertEqual(verdict(latest: quarter, previous: all), .progress)
        XCTAssertEqual(verdict(latest: all, previous: quarter), .progress)
    }

    /// Kills: the jump cap and the reduce cap made strict (`>` -> `>=`) at their rounding tolerance. 2.5 kg on 5 kg is exactly half the
    /// weight; a cap of 0.499999999 plus the tolerance is exactly 0.5 in floating point, so the step is still allowed.
    func testACapExactlyOneToleranceAboveTheStepStillAllowsIt() {
        XCTAssertEqual(0.499999999 + 1e-9, 2.5 / 5.0)
        var jump = CoachConfig()
        jump.maximumJumpFraction = 0.499999999
        let progress = CoachFix.recommend(bench, [session(3, 5), session(10, 5)], config: jump)
        XCTAssertEqual(progress.verdict, .progress)
        XCTAssertEqual(progress.targetWeightKg, 7.5)

        var reduce = CoachConfig()
        reduce.maximumReduceFraction = 0.499999999
        let falling = [
            session(3, 5, reps: [4, 4, 4], rir: [0, 0, 0]), session(10, 5, reps: [5, 5, 5], rir: [0, 0, 0]),
            session(17, 5, reps: [6, 6, 6], rir: [0, 0, 0]),
        ]
        let reduced = CoachFix.recommend(bench, falling, config: reduce)
        XCTAssertEqual(reduced.verdict, .reduce)
        XCTAssertEqual(reduced.targetWeightKg, 2.5)
    }

    /// Kills: the lighter-week streak counting a difference of exactly the weight tolerance as an increase (`>` -> `>=`). Each load is
    /// the one below it plus 0.005 as the computer adds it, so the comparison lands on the edge.
    func testAnIncreaseOfExactlyTheWeightToleranceIsNoIncrease() {
        var loads = [80.0]
        for _ in 1..<7 { loads.append(loads[loads.count - 1] + 0.005) }
        let result = CoachFix.recommend(bench, rising(rir: [2, 2, 2], loads: Array(loads.reversed())))
        XCTAssertFalse(result.reasons.contains(.lighterWeekDue))
        XCTAssertNotEqual(result.verdict, .reduce)
    }

    // MARK: Configuration

    /// Kills: every mutant of the limits inside `isValid` that moves a bound by one step or forgets that infinity is not a number
    /// you can compare with.
    func testTheEdgesOfTheValidityCheck() {
        func valid(_ change: (inout CoachConfig) -> Void) -> Bool {
            var config = CoachConfig()
            change(&config)
            return config.isValid
        }
        // Fractions: (0, 1].
        XCTAssertFalse(valid { $0.reduceFraction = 1.5 })
        XCTAssertFalse(valid { $0.maximumJumpFraction = 1.000_001 })
        XCTAssertFalse(valid { $0.maximumReduceFraction = 2 })
        XCTAssertTrue(valid { $0.maximumJumpFractionRestricted = 1 })
        // Coverage and the comfortable share: (0, 1].
        XCTAssertFalse(valid { $0.effortCoverage = 0 })
        XCTAssertTrue(valid { $0.effortCoverage = 1 })
        XCTAssertFalse(valid { $0.comfortableSetShare = 1.5 })
        XCTAssertTrue(valid { $0.comfortableSetShare = 1 })
        // Ratio: finite and above 1.
        XCTAssertFalse(valid { $0.suspectRatio = .infinity })
        XCTAssertTrue(valid { $0.suspectRatio = 1.000_001 })
        // Effort limits: finite and not negative; zero is fine.
        XCTAssertFalse(valid { $0.progressMinimumRIR = .infinity })
        XCTAssertFalse(valid { $0.holdMaximumRIR = .infinity })
        XCTAssertFalse(valid { $0.lighterWeekMaximumRIR = .infinity })
        XCTAssertFalse(valid { $0.repsFallTolerance = .infinity })
        XCTAssertTrue(valid { $0.progressMinimumRIR = 0 })
        XCTAssertTrue(valid { $0.holdMaximumRIR = 0 })
        XCTAssertTrue(valid { $0.lighterWeekMaximumRIR = 0 })
        XCTAssertTrue(valid { $0.repsFallTolerance = 0 })
    }

    // MARK: Planner

    /// Kills: `nextTime` writing its sentences without the configuration (the in-workout suggestion already had a test).
    func testTheHubLinesNameTheConfiguredThreshold() throws {
        var config = CoachConfig()
        config.progressMinimumRIR = 3
        let template = WorkoutTemplate(name: "Push", entries: [
            TemplateEntry(exercise: bench, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90),
        ])
        let sessions = [session(3, 80), session(10, 80)]
        let items = CoachPlanner.nextTime(
            for: template, exercise: { _ in nil }, history: { _ in self.history(sessions) }, audience: .adult, config: config, now: now
        )
        let item = try XCTUnwrap(items.first)
        XCTAssertEqual(item.recommendation.verdict, .progress)
        XCTAssertEqual(item.line.detail, "Two clean sessions at RIR 3 or more.")
    }

    /// Kills: a top group that is wider than "the same weight" (tolerance 0.005 -> 5 kg). A back-off one plate below the top set is
    /// the usual case, not a rounding error.
    func testApplyKeepsABackOffOnePlateBelowTheTopSet() throws {
        let clean = [session(3, 100, reps: [5], rir: [3]), session(10, 100, reps: [5], rir: [3])]
        let current = entry([LoggedSet(weightKg: 100, reps: 5), LoggedSet(weightKg: 97.5, reps: 5), LoggedSet(weightKg: 97.5, reps: 5)])
        let suggestion = try XCTUnwrap(CoachPlanner.suggestion(for: current, history: history(clean), audience: .adult, now: now))
        XCTAssertEqual(suggestion.actions, [.setWeight(exerciseID: current.id, setID: current.sets[0].id, kg: 102.5)])
    }

    /// Kills: workout names matched by prefix (`== wanted` -> `hasPrefix`), session names not trimmed, and a blank name that selects
    /// the sessions with a blank name.
    func testScopingMatchesTheWholeTrimmedNameAndNeverABlankOne() {
        let padded = [
            session(3, 80, name: "  Upper A "), session(10, 80, name: "Upper A"),
            session(17, 80, name: "Upper A2"), session(24, 80, name: "Push"),
        ]
        XCTAssertEqual(history(padded).scoped(toWorkoutNamed: "upper a", now: now).sessions.count, 2)

        let blanks = [session(3, 80, name: ""), session(10, 80, name: "   "), session(17, 80, name: "Push")]
        XCTAssertEqual(history(blanks).scoped(toWorkoutNamed: "  ", now: now).sessions.count, 3)
        XCTAssertEqual(history(blanks).scoped(toWorkoutNamed: "", now: now).sessions.count, 3)
    }

    // MARK: Hub note

    /// Kills: taking the first two muscles before removing the avoided ones, which names one muscle where two are due.
    func testTheReadinessSentenceFillsItsTwoPlacesAfterLeavingOutAvoidedMuscles() {
        func entry(_ exercise: Exercise) -> TemplateEntry {
            var plain = exercise
            plain.previousBestE1RM = 0
            return TemplateEntry(exercise: plain, plannedSets: [PlannedSet(weightKg: 40, reps: 8)], restSeconds: 90)
        }
        let template = WorkoutTemplate(name: "Upper", entries: [entry(bench), entry(ohp), entry(curl)])
        let message = HubNoteBuilder.message(
            template: template, exercise: { _ in nil }, recovery: { _ in 100 },
            audience: AudienceProfile(ageGroup: .adult, avoidMuscles: [.chest])
        )
        XCTAssertEqual(message, "Shoulders and arms are recovered.")
    }

    /// Kills: an avoided first exercise ending the search for a target sentence (`continue` -> `return nil`).
    func testAnAvoidedFirstExerciseLeavesTheNextOneToCarryTheSentence() throws {
        var chest = bench
        chest.previousBestE1RM = 99
        var shoulders = ohp
        shoulders.previousBestE1RM = 60
        let template = WorkoutTemplate(name: "Push", entries: [
            TemplateEntry(exercise: chest, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90),
            TemplateEntry(exercise: shoulders, plannedSets: [PlannedSet(weightKg: 40, reps: 8)], restSeconds: 90),
        ])
        let message = try XCTUnwrap(HubNoteBuilder.message(
            template: template, exercise: { _ in nil }, recovery: nil,
            audience: AudienceProfile(ageGroup: .adult, avoidMuscles: [.chest])
        ))
        XCTAssertTrue(message.hasPrefix("Aim for "), message)
        XCTAssertTrue(message.contains("× 8 on your last \(HubNoteBuilder.shortName(shoulders)) set."), message)
        XCTAssertFalse(message.contains(HubNoteBuilder.shortName(chest)), message)
    }

    /// Kills: the 2,000 kg limit of the hub sentence moved (`<=` -> `<`, or ten times higher). One-rep sets keep the arithmetic exact.
    func testTheHubSentenceStopsJustAboveTwoThousandKilograms() throws {
        func note(baseline: Double) -> String? {
            var damaged = bench
            damaged.previousBestE1RM = baseline
            let template = WorkoutTemplate(name: "T", entries: [
                TemplateEntry(exercise: damaged, plannedSets: [PlannedSet(weightKg: 80, reps: 1)], restSeconds: 90),
            ])
            return HubNoteBuilder.message(template: template, exercise: { _ in nil }, recovery: nil)
        }
        // The lowest 2.5 kg step that beats 2065 kg of estimated 1RM at one rep is exactly 2000 kg; for 2069 it is 2002.5 kg.
        XCTAssertEqual(TargetWeight.lowestBeating(baseline: 2_065, reps: 1, step: bench.weightStepKg), 2_000)
        XCTAssertEqual(TargetWeight.lowestBeating(baseline: 2_069, reps: 1, step: bench.weightStepKg), 2_002.5)
        XCTAssertEqual(note(baseline: 2_065), "Aim for \(NumberText.kg(2_000)) kg × 1 on your last bench press set.")
        XCTAssertNil(note(baseline: 2_069))
        XCTAssertNil(note(baseline: 20_000))
    }
}
