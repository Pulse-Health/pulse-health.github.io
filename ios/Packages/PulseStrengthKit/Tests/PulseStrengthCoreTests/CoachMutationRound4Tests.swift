import XCTest
@testable import PulseStrengthCore

/// Tests that close the gaps a fourth round of mutation testing found in the code changed by 25702d3 (the recent-run typo guard,
/// the half-day break slack, the plan-deviation gate, the Apply group and the break note). Each test fails against at least one
/// small deliberate defect in that code; the defect is named in the comment of the assertion that catches it.
///
/// The common reason the existing tests missed these: they use sessions of three identical sets. Several suspects in one session
/// "agree with each other" and are kept, so every rule that decides *which* set is a suspect never showed up. Most tests here use
/// sessions of a single set (or sets of different weights) instead.
final class CoachMutationRound4Tests: XCTestCase {
    private let now = CoachFix.now
    private let bench = CoachFix.lib("bench")
    private let squat = CoachFix.lib("squat")

    /// A minute, in days: the smallest step used to step over a boundary that is exact in binary floating point.
    private let minute = 1.0 / 1_440

    /// The failure message: the values, one after another.
    private func note(_ values: Any...) -> String { values.map { String(describing: $0) }.joined(separator: " ") }

    // MARK: Fixtures

    /// A session `daysAgo` days (fractions allowed) before `now`.
    private func session(_ daysAgo: Double, _ sets: [CompletedSet], name: String = "Workout") -> ExerciseSession {
        ExerciseSession(
            id: UUID(), date: now.addingTimeInterval(-daysAgo * 86_400), workoutName: name, sets: sets, isPersonalRecord: false
        )
    }

    /// `count` identical sets with a reps-in-reserve value.
    private func clean(_ kg: Double, reps: Int = 5, sets count: Int = 3, rir: Int = 3) -> [CompletedSet] {
        CoachFix.sets(kg, Array(repeating: reps, count: count), rir: Array(repeating: rir, count: count))
    }

    /// A session of one single set.
    private func one(_ kg: Double, reps: Int = 5, rir: Int = 3) -> [CompletedSet] { [CoachFix.set(kg, reps, rir)] }

    private func history(_ sessions: [ExerciseSession], of exercise: Exercise? = nil) -> ExerciseHistory {
        CoachFix.history(exercise ?? bench, sessions)
    }

    private func entry(_ sets: [LoggedSet], of exercise: Exercise? = nil) -> WorkoutExercise {
        WorkoutExercise(exercise: exercise ?? bench, sets: sets, restSeconds: 90)
    }

    private func template(_ name: String = "T", _ exercise: Exercise? = nil, planned: [PlannedSet]) -> WorkoutTemplate {
        WorkoutTemplate(name: name, entries: [TemplateEntry(exercise: exercise ?? bench, plannedSets: planned, restSeconds: 90)])
    }

    private func hubLines(
        _ template: WorkoutTemplate, _ history: ExerciseHistory, config: CoachConfig = CoachConfig()
    ) -> [NextTimeItem] {
        CoachPlanner.nextTime(
            for: template, exercise: { _ in nil }, history: { _ in history }, audience: .adult, config: config, now: now
        )
    }

    // MARK: The half day of slack, to the minute

    func testTheBreakAndTheRecentRunIncludeExactlyBreakDaysPlusHalfADay() {
        // The newest session is exactly 28.5 days old: not a break. A minute more: a break (mutants: break rule with ">=").
        let atLimit = CoachFix.recommend(bench, [session(28.5, clean(100)), session(35.5, clean(100)), session(42.5, clean(100))])
        XCTAssertEqual(atLimit.verdict, .progress)
        XCTAssertEqual(atLimit.targetWeightKg, 102.5)
        let over = CoachFix.recommend(
            bench, [session(28.5 + minute, clean(100)), session(35.5, clean(100)), session(42.5, clean(100))]
        )
        XCTAssertEqual(over.reasons, [.returningAfterBreak])

        // Two sessions exactly 28.5 days apart are still "the last two" (mutant: the recent loop with "<").
        let pair = CoachFix.recommend(bench, [session(3, clean(100)), session(31.5, clean(100))])
        XCTAssertEqual(pair.verdict, .progress)
        XCTAssertEqual(pair.targetWeightKg, 102.5)
        let apart = CoachFix.recommend(bench, [session(3, clean(100)), session(31.5 + minute, clean(100))])
        XCTAssertEqual(apart.reasons, [.awaitingSecondCleanSession])
    }

    func testTheTypoGuardChainsSessionsWithTheSameSlackAsTheBreak() {
        // 16 typed for 6 in the newest session. The guard needs three sessions in the recent run; the gap between the two older
        // ones is what changes (mutants: run end with ">=" and without the half day).
        func flagged(gap: Double) -> Bool {
            let typo = session(3, CoachFix.sets(80, [6, 6, 16], rir: [3, 3, 3]))
            let rows = [typo, session(10, clean(80, reps: 6)), session(10 + gap, clean(80, reps: 6))]
            return CoachFix.recommend(bench, rows).reasons.contains(.suspectSetExcluded)
        }
        XCTAssertTrue(flagged(gap: 7))
        XCTAssertTrue(flagged(gap: 28), "exactly the break length")
        XCTAssertTrue(flagged(gap: 28.25), "inside the half day")
        XCTAssertTrue(flagged(gap: 28.5), "exactly the half day")
        XCTAssertFalse(flagged(gap: 28.5 + minute), "a minute too far: only two sessions are the recent run, which cannot judge")
    }

    // MARK: Only the recent run says what is typical

    func testSessionsBeforeALongBreakAreNoReferenceForTheRecentOnes() {
        // Two single-set sessions at 100 kg; two months earlier three at 60. Judged together the 100 kg sets would be called typos
        // (mutants: the run end that never ends, the window that ignores the run).
        let rows = [
            session(3, one(100)), session(10, one(100)), session(70, one(60)), session(77, one(60)), session(84, one(60)),
        ]
        let result = CoachFix.recommend(bench, rows)
        XCTAssertEqual(result.verdict, .progress)
        XCTAssertEqual(result.targetWeightKg, 102.5)
        XCTAssertEqual(result.reasons, [.cleanSessionsWithReserve], "nothing may be excluded")
        XCTAssertEqual(result.sessionsUsed, 2)
    }

    func testASessionWithoutWorkingSetsIsNoBridgeAcrossALongBreak() {
        // The warm-up-only session sits in the middle of a 44 day gap: it must not link the two halves (mutant: the chain keeps
        // sessions without working sets). Linked, the 100 kg set would be judged against the old 60 kg sessions and dropped.
        let warmupOnly = session(25, [CoachFix.set(40, 8, type: .warmup)])
        let rows = [session(3, one(100)), warmupOnly, session(47, one(60)), session(54, one(60)), session(61, one(60))]
        let result = CoachFix.recommend(bench, rows)
        XCTAssertEqual(result.verdict, .hold)
        XCTAssertEqual(result.targetWeightKg, 100)
        XCTAssertEqual(result.reasons, [.awaitingSecondCleanSession])
        XCTAssertEqual(result.sessionsUsed, 1)
    }

    func testASessionOlderThanTheRunIsNeverJudgedAndNeverFlagged() {
        // The 200 kg set from a session 100 days ago is far above the recent 100 kg, but it is not part of the recent run:
        // nothing is excluded and no note is added (mutants: the check on one session past the run, and on all sessions).
        let rows = [session(3, clean(100)), session(10, clean(100)), session(17, clean(100)), session(100, one(200))]
        let result = CoachFix.recommend(bench, rows)
        XCTAssertEqual(result.verdict, .progress)
        XCTAssertEqual(result.reasons, [.cleanSessionsWithReserve])
        XCTAssertEqual(result.sessionsUsed, 3)
    }

    func testTheOldestSessionOfTheRunIsNotComparedWithOneBeforeTheBreak() {
        // The oldest session of the run has a single set 26 % above the typical best and nothing older in the run to compare it
        // with, so it counts as a jump; the session before the break (also 105 kg) must not excuse it.
        let rows = [session(3, clean(80)), session(10, clean(80)), session(17, one(105)), session(100, one(105))]
        let result = CoachFix.recommend(bench, rows)
        XCTAssertTrue(result.reasons.contains(.suspectSetExcluded), note(result))
        XCTAssertEqual(result.sessionsUsed, 2)
        XCTAssertEqual(result.targetWeightKg, 82.5)
    }

    // MARK: Who is a suspect

    func testALifterWhoGetsStrongerEverySessionIsNotTakenForATypo() {
        // Single-set sessions at 40, 47.5, 57.5, 70, 85, 100 kg: the newest two are far above the median of the last six, but each
        // is a normal step above the session before it (mutants: no older session; "jumped" without the ratio; a lone set that
        // "stands out").
        let tops: [Double] = [100, 85, 70, 57.5, 47.5, 40]
        let rows = tops.enumerated().map { session(3 + Double($0.offset) * 7, one($0.element)) }
        let result = CoachFix.recommend(bench, rows)
        XCTAssertEqual(result.reasons, [.awaitingSecondCleanSession], note(result))
        XCTAssertEqual(result.targetWeightKg, 100)
        XCTAssertEqual(result.sessionsUsed, 6)
    }

    func testASteppedUpTopSetIsNotATypoOfItsOwnSession() {
        // The same lifter, each session a ramp of 100 %, 90 % and 75 % of its top set. The top set is 11 % above the next one and
        // 33 % above the lightest; only a 25 % gap to the *heaviest other set* makes a set stand out (mutants: "stands out"
        // without the ratio; against the lightest other set).
        let tops: [Double] = [100, 85, 70, 57.5, 47.5, 40]
        let rows = tops.enumerated().map { index, top in
            session(3 + Double(index) * 7, [CoachFix.set(top, 5, 3), CoachFix.set(top * 0.9, 5, 3), CoachFix.set(top * 0.75, 5, 3)])
        }
        let result = CoachFix.recommend(bench, rows)
        XCTAssertEqual(result.reasons, [.awaitingSecondCleanSession], note(result))
        XCTAssertEqual(result.targetWeightKg, 100)
    }

    func testASpikeThatIsNotAJumpFromTheSessionBeforeItIsKept() {
        // Single sets of 40, 40, 60 and 50 kg, newest first. 60 kg is more than 1.25 times the median of the four (52.5 kg of
        // estimated 1RM) but only 1.2 times the session right before it, so it is not a typo (mutant: the second oldest session
        // of the run has no older session to compare with).
        let rows = [session(3, one(40)), session(10, one(40)), session(17, one(60)), session(24, one(50))]
        let result = CoachFix.recommend(bench, rows)
        XCTAssertFalse(result.reasons.contains(.suspectSetExcluded), note(result))
        XCTAssertEqual(result.sessionsUsed, 4)
        XCTAssertEqual(result.targetWeightKg, 42.5)
    }

    func testTheRecentRunAndTheTypoGuardFollowTheConfiguredBreak() {
        var short = CoachConfig()
        short.breakDays = 14
        var long = CoachConfig()
        long.breakDays = 60
        // The recent run (mutant: the engine measures it against a fixed 28 days).
        let twenty = [session(3, clean(100)), session(10, clean(100)), session(30, clean(100))]
        XCTAssertEqual(CoachFix.recommend(bench, twenty, config: short).sessionsUsed, 2)
        XCTAssertEqual(CoachFix.recommend(bench, twenty).sessionsUsed, 3)
        let forty = [session(3, clean(100)), session(10, clean(100)), session(50, clean(100))]
        XCTAssertEqual(CoachFix.recommend(bench, forty, config: long).sessionsUsed, 3)
        XCTAssertEqual(CoachFix.recommend(bench, forty).sessionsUsed, 2)

        // The reference of the typo guard (mutant: the guard chains sessions with a fixed 28 days).
        func flagged(gap: Double, config: CoachConfig) -> Bool {
            let typo = session(3, CoachFix.sets(80, [6, 6, 16], rir: [3, 3, 3]))
            let rows = [typo, session(10, clean(80, reps: 6)), session(10 + gap, clean(80, reps: 6))]
            return CoachFix.recommend(bench, rows, config: config).reasons.contains(.suspectSetExcluded)
        }
        XCTAssertFalse(flagged(gap: 20, config: short))
        XCTAssertTrue(flagged(gap: 20, config: CoachConfig()))
        XCTAssertTrue(flagged(gap: 40, config: long))
        XCTAssertFalse(flagged(gap: 40, config: CoachConfig()))
    }

    func testASetJustOverTheLimitIsStillATypo() {
        // 100.04 kg is 1.2505 times 80 kg: over the limit by far more than the 1e-9 slack (mutant: a slack of 1e-3).
        let typo = CoachFix.recommend(bench, [session(3, one(100.04)), session(10, one(80)), session(17, one(80))])
        XCTAssertTrue(typo.reasons.contains(.suspectSetExcluded), note(typo))
        XCTAssertEqual(typo.targetWeightKg, 82.5)
        // And 99.99 kg (1.249875 times) is not.
        let fine = CoachFix.recommend(bench, [session(3, one(99.99)), session(10, one(80)), session(17, one(80))])
        XCTAssertFalse(fine.reasons.contains(.suspectSetExcluded), note(fine))
        XCTAssertEqual(fine.targetWeightKg, 99.99)

        // The same two weights with only two sessions: just over the limit cannot be told from a typo, just under can (mutant: the
        // unresolved jump needs the higher best to be a whole point of estimated 1RM above the limit).
        let silent = CoachFix.recommend(bench, [session(3, one(100.04)), session(10, one(80))])
        XCTAssertEqual(silent.verdict, .insufficientData)
        XCTAssertEqual(silent.reasons, [.suspectSetExcluded])
        let heard = CoachFix.recommend(bench, [session(3, one(99.99)), session(10, one(80))])
        XCTAssertEqual(heard.verdict, .hold)
        XCTAssertEqual(heard.targetWeightKg, 99.99)
    }

    func testAnExactRatioOnPaperIsNotATypoEvenWhenFloatingPointPutsItOverTheLimit() {
        // 25 kg after 20 kg and 12.5 after 10, three reps each, are exactly 1.25 times on paper. In floating point the Epley
        // estimate of the larger one is above 1.25 times the smaller one's, so only the slack keeps it (mutants: no slack, in
        // the reference test, in the "jumped" test and in both).
        for (low, high) in [(20.0, 25.0), (10.0, 12.5)] {
            XCTAssertGreaterThan(
                Estimated1RM.epley(weightKg: high, reps: 3), 1.25 * Estimated1RM.epley(weightKg: low, reps: 3), "premise of the test"
            )
            // The older sessions climb slowly, so the median is far below the newest set and only "jumped" decides.
            let climb = [high, low, low * 0.95, low * 0.9, low * 0.85]
            let slow = CoachFix.recommend(
                bench, climb.enumerated().map { session(3 + Double($0.offset) * 7, one($0.element, reps: 3)) }
            )
            XCTAssertEqual(slow.reasons, [.awaitingSecondCleanSession], note(low, high, slow))
            XCTAssertEqual(slow.targetWeightKg, high)

            // The median is the weight before it: the reference test is on the limit and the older session is far below.
            let middle = CoachFix.recommend(
                bench, [session(3, one(high, reps: 3)), session(10, one(low * 0.6, reps: 3)), session(17, one(low, reps: 3))]
            )
            XCTAssertEqual(middle.reasons, [.awaitingSecondCleanSession], note(low, high, middle))
            XCTAssertEqual(middle.targetWeightKg, high)
        }
    }

    func testASetExactlyAtAConfiguredLimitIsNeverSuspect() {
        // A limit that is exact in binary: 15 reps make the Epley factor exactly 1.5, and this ratio times (1 + 1e-9) is exactly
        // 1.5. 60 kg x 15 is then exactly the limit above 40 kg x 15 (mutants: ">=" in the reference test, in the unresolved-jump
        // test and in the corroboration test).
        var config = CoachConfig()
        config.suspectRatio = 1.4999999984999999
        config.maximumRepsForReference = 15
        XCTAssertEqual(config.suspectRatio * (1 + 1e-9), 1.5, "premise of the test")
        XCTAssertEqual(Estimated1RM.epley(weightKg: 60, reps: 15), 90)
        XCTAssertEqual(Estimated1RM.epley(weightKg: 40, reps: 15), 60)

        // Three sessions: the median is 60 and the newest is exactly 1.5 times it, far above the session before.
        let three = CoachFix.recommend(
            bench, [session(3, one(60, reps: 15)), session(10, one(20, reps: 15)), session(17, one(40, reps: 15))], config: config
        )
        XCTAssertEqual(three.reasons, [.awaitingSecondCleanSession], note(three))
        XCTAssertEqual(three.targetWeightKg, 60)

        // Two sessions exactly at the ratio are not "far apart".
        let pair = CoachFix.recommend(bench, [session(3, one(60, reps: 15)), session(10, one(40, reps: 15))], config: config)
        XCTAssertEqual(pair.reasons, [.awaitingSecondCleanSession], note(pair))

        // Two sessions further apart, where two of the three sets of the higher one are well below its best: only the best set is
        // far above the other session and nobody agrees with it, so the engine stays silent.
        let high = session(3, [CoachFix.set(60, 15, 3), CoachFix.set(60, 15, 3), CoachFix.set(100, 15, 3)])
        let silent = CoachFix.recommend(bench, [high, session(10, one(40, reps: 15))], config: config)
        XCTAssertEqual(silent.verdict, .insufficientData)
        XCTAssertEqual(silent.reasons, [.suspectSetExcluded])
    }

    // MARK: Several suspects in one session

    func testSuspectsThatMakeUpHalfOfASessionAgreeWithEachOther() {
        func newest(_ kgs: [Double]) -> Recommendation {
            let sets = kgs.map { CoachFix.set($0, 6, 3) }
            return CoachFix.recommend(bench, [session(3, sets), session(10, clean(80, reps: 6)), session(17, clean(80, reps: 6))])
        }
        // Two of four (exactly half) and two of three: a real change of weight (mutants: corroboration needs more than half, needs
        // three suspects, needs all of them).
        for kgs in [[80.0, 80, 120, 120], [80, 120, 120], [120, 120]] {
            let result = newest(kgs)
            XCTAssertEqual(result.targetWeightKg, 120, note(kgs, result))
            XCTAssertEqual(result.reasons, [.awaitingSecondCleanSession], note(kgs, result))
        }
        // Two of six is a pair of typos, not a change of weight (mutant: a third is enough).
        let pair = newest([80, 80, 80, 80, 120, 120])
        XCTAssertTrue(pair.reasons.contains(.suspectSetExcluded), note(pair))
        XCTAssertEqual(pair.targetWeightKg, 82.5)
        // One of three is a typo (the single suspect cannot agree with itself).
        let single = newest([80, 80, 120])
        XCTAssertTrue(single.reasons.contains(.suspectSetExcluded), note(single))
        XCTAssertEqual(single.targetWeightKg, 82.5)
    }

    func testTwoSessionsFarApartAreOnlyResolvedByAgreeingSetsOverTheLimit() {
        // The higher session has two sets above the older best but under the limit, and one far above: only the last is over the
        // limit, so the jump is unresolved (mutant: corroboration counts sets above the *older best* instead of above the limit).
        let high = session(3, [CoachFix.set(90, 6, 3), CoachFix.set(90, 6, 3), CoachFix.set(140, 6, 3)])
        let result = CoachFix.recommend(bench, [high, session(10, clean(80, reps: 6))])
        XCTAssertEqual(result.verdict, .insufficientData)
        XCTAssertEqual(result.reasons, [.suspectSetExcluded])
    }

    // MARK: A streak does not cross a layoff

    func testAStreakOfIncreasesIsCountedInsideTheRecentRunOnly() {
        // Seven sessions that each use a heavier weight than the one before, but a two month layoff in the middle: the recent
        // run has three of them, so no lighter week is due (mutant: the streak is counted over the whole history).
        let loads: [Double] = [70, 67.5, 65, 62.5, 60, 57.5, 55]
        let days: [Double] = [3, 10, 17, 90, 97, 104, 111]
        let rows = zip(loads, days).map { session($1, clean($0, reps: 6, rir: 2)) }
        let result = CoachFix.recommend(bench, rows)
        XCTAssertEqual(result.verdict, .hold)
        XCTAssertEqual(result.reasons, [.awaitingSecondCleanSession])
        XCTAssertEqual(result.targetWeightKg, 70)
        XCTAssertEqual(result.sessionsUsed, 3)
        // Without the layoff it is a lighter week (so the test above does exercise the streak).
        let noBreak = zip(loads, [3, 10, 17, 24, 31, 38, 45] as [Double]).map { session($1, clean($0, reps: 6, rir: 2)) }
        XCTAssertEqual(CoachFix.recommend(bench, noBreak).reasons, [.lighterWeekDue])
    }

    // MARK: The workout name

    func testAWorkoutNameIsStaleExactlyWhenItsNewestSessionIsMoreThanBreakDaysBehind() {
        let other = session(3, clean(80), name: "B")
        /// How many sessions the history keeps when workout "A" was last trained `gapDays` before workout "B".
        func kept(gapDays: Double, breakDays: Int? = nil) -> Int {
            let a = [session(3 + gapDays, clean(80), name: "A"), session(10 + gapDays, clean(80), name: "A")]
            let all = history([other] + a)
            let result = breakDays.map { all.scoped(toWorkoutNamed: "A", now: now, breakDays: $0) } ?? all.scoped(toWorkoutNamed: "A", now: now)
            return result.sessions.count
        }
        XCTAssertEqual(kept(gapDays: 28), 2, "28 days behind is not stale")
        XCTAssertEqual(kept(gapDays: 28.5), 2, "exactly the break plus half a day of slack is not stale (mutant: stale with '>=')")
        XCTAssertEqual(kept(gapDays: 28.5 + minute), 3)
        XCTAssertEqual(kept(gapDays: 40), 3, "40 days behind is stale (mutant: a limit of twice the break)")
        XCTAssertEqual(kept(gapDays: 40, breakDays: 60), 2)
        XCTAssertEqual(kept(gapDays: 10, breakDays: 7), 3)
    }

    func testTheScopingOfTheHubAndTheCardFollowsTheConfiguredBreak() throws {
        // "Heavy" was last trained 43 days ago, the lift a lighter way 3 days ago. With a break of 60 days that is not stale.
        let heavy = [session(43, clean(100), name: "Heavy"), session(50, clean(100), name: "Heavy")]
        let all = history([session(3, clean(70, reps: 10), name: "Light")] + heavy)
        var config = CoachConfig()
        config.breakDays = 60
        let plan = template("Heavy", planned: [PlannedSet(weightKg: 100, reps: 5)])
        // Mutant: the hub scopes with the default 28 days and judges the light day.
        XCTAssertEqual(hubLines(plan, all, config: config).first?.line.headline, "102.5 kg × 5")
        let card = entry(Array(repeating: LoggedSet(weightKg: 100, reps: 5), count: 3))
        // Mutant: the card scopes with the default 28 days.
        let suggestion = try XCTUnwrap(
            CoachPlanner.suggestion(for: card, history: all, workoutName: "Heavy", audience: .adult, config: config, now: now)
        )
        XCTAssertEqual(suggestion.recommendation.targetWeightKg, 102.5)
        // With the default break the lift is judged on everything: the light day is what was done last, 30 % under the plan.
        XCTAssertTrue(hubLines(plan, all).isEmpty)
        XCTAssertNil(CoachPlanner.suggestion(for: card, history: all, workoutName: "Heavy", audience: .adult, now: now))
    }

    // MARK: The plan on the hub

    func testThePlannedWeightIsTheHeaviestNormalSetOfTheEntry() {
        let sixty = history([session(3, clean(60, reps: 8)), session(10, clean(60, reps: 8))])
        // A heavy to-failure set is not what the template plans for the working sets (mutant: every set type counts).
        let withFailure = template(planned: [PlannedSet(weightKg: 60, reps: 8), PlannedSet(type: .failure, weightKg: 100, reps: 3)])
        XCTAssertEqual(hubLines(withFailure, sixty).first?.line.headline, "62.5 kg × 8")

        // A ramp plans for its heaviest working set (mutant: the lightest).
        let eighty = history([session(3, clean(80)), session(10, clean(80))])
        let ramp = template(planned: [PlannedSet(weightKg: 60, reps: 8), PlannedSet(weightKg: 80, reps: 5)])
        XCTAssertEqual(hubLines(ramp, eighty).first?.line.headline, "82.5 kg × 5")

        // No normal set at all (only a warm-up) plans for nothing: never gated (mutant: a default plan of 1000 kg).
        let warmupOnly = template(planned: [PlannedSet(type: .warmup, weightKg: 20, reps: 10)])
        XCTAssertEqual(hubLines(warmupOnly, eighty).first?.line.headline, "82.5 kg × 5")
        XCTAssertEqual(hubLines(template(planned: []), eighty).first?.line.headline, "82.5 kg × 5")
    }

    func testALineFarFromThePlanIsSkippedButTheNextLineStillAppears() {
        let benchHistory = history([session(3, clean(80)), session(10, clean(80))])
        let squatHistory = history([session(3, clean(100)), session(10, clean(100))], of: squat)
        let plan = WorkoutTemplate(name: "T", entries: [
            TemplateEntry(exercise: bench, plannedSets: [PlannedSet(weightKg: 40, reps: 5)], restSeconds: 90),
            TemplateEntry(exercise: squat, plannedSets: [PlannedSet(weightKg: 100, reps: 5)], restSeconds: 90),
        ])
        let lines = CoachPlanner.nextTime(
            for: plan, exercise: { _ in nil }, history: { $0 == "bench" ? benchHistory : squatHistory }, audience: .adult, now: now
        )
        // Mutant: the first gated entry ends the list.
        XCTAssertEqual(lines.map { $0.recommendation.exerciseID }, ["squat"])
    }

    // MARK: The note after a long break

    func testTheBreakNoteDoesNotDependOnTheOrderOfTheReasons() throws {
        // A typo in the newest session of a lift last trained six weeks ago: the answer carries the typo note *before* the break
        // reason. The words, the missing Apply and the plan check must all look for the break anywhere in the list (mutants: the
        // break is recognised only as the first reason, in the writer, in the plan check and in the card).
        let rows = [
            session(40, CoachFix.sets(80, [6, 6, 16], rir: [3, 3, 3])), session(47, clean(80, reps: 6)), session(54, clean(80, reps: 6)),
        ]
        let rec = CoachFix.recommend(bench, rows)
        XCTAssertEqual(rec.reasons, [.suspectSetExcluded, .returningAfterBreak], "premise of the test")
        XCTAssertEqual(rec.targetWeightKg, 80)
        XCTAssertEqual(TemplateWriter.line(for: rec)?.headline, "Last time: 80 kg × 6")
        XCTAssertEqual(TemplateWriter.line(for: rec)?.detail, "It has been a while since your last session, so ease back in.")

        // The plan says 50 kg: the break is exempt from the plan check, on the hub and on the card.
        let hub = hubLines(template(planned: [PlannedSet(weightKg: 50, reps: 6)]), history(rows))
        XCTAssertEqual(hub.first?.line.headline, "Last time: 80 kg × 6")
        let card = entry(Array(repeating: LoggedSet(weightKg: 50, reps: 6), count: 3))
        let note = try XCTUnwrap(CoachPlanner.suggestion(for: card, history: history(rows), audience: .adult, now: now))
        XCTAssertEqual(note.line.headline, "Last time: 80 kg × 6")
        XCTAssertEqual(note.actions, [], "a note after a break never offers to change the plan")
    }

    // MARK: The plan on the card

    func testApplyChangesTheSetsAtTheTopWeightAndNoOthers() throws {
        let rows = history([session(3, clean(80, reps: 6)), session(10, clean(80, reps: 6))])
        // 79.5 kg is a lighter back-off set, not the top weight (mutant: a tolerance of half a kilo).
        let top1 = LoggedSet(weightKg: 80, reps: 6), top2 = LoggedSet(weightKg: 80, reps: 6), lighter = LoggedSet(weightKg: 79.5, reps: 6)
        let plan = entry([top1, top2, lighter])
        let suggestion = try XCTUnwrap(CoachPlanner.suggestion(for: plan, history: rows, audience: .adult, now: now))
        XCTAssertEqual(suggestion.actions, [
            .setWeight(exerciseID: plan.id, setID: top1.id, kg: 82.5), .setWeight(exerciseID: plan.id, setID: top2.id, kg: 82.5),
        ])

        // Weights a hair apart (the keypad's rounding) are the same weight (mutant: no tolerance at all).
        let a = LoggedSet(weightKg: 80.004, reps: 6), b = LoggedSet(weightKg: 80, reps: 6), c = LoggedSet(weightKg: 80, reps: 6)
        let hairs = entry([a, b, c])
        let again = try XCTUnwrap(CoachPlanner.suggestion(for: hairs, history: rows, audience: .adult, now: now))
        XCTAssertEqual(again.actions.count, 3)

        // A set that has no reps yet (an imported template) is part of the top group and gets both figures (mutant: skipped).
        let blank = LoggedSet(weightKg: 80, reps: 0), filled = LoggedSet(weightKg: 80, reps: 6)
        let imported = entry([blank, filled])
        let fill = try XCTUnwrap(CoachPlanner.suggestion(for: imported, history: rows, audience: .adult, now: now))
        XCTAssertEqual(fill.actions, [
            .setWeight(exerciseID: imported.id, setID: blank.id, kg: 82.5), .setReps(exerciseID: imported.id, setID: blank.id, reps: 6),
            .setWeight(exerciseID: imported.id, setID: filled.id, kg: 82.5),
        ])
    }

    func testThePlanMayDifferByExactlyTwentyPercentOfTheLargerWeightInEitherDirection() {
        func shown(history kg: Double, plan: Double, reps: Int = 6) -> Bool {
            let rows = history([session(3, clean(kg, reps: reps, rir: 1)), session(10, clean(kg, reps: reps, rir: 1))])
            let card = entry(Array(repeating: LoggedSet(weightKg: plan, reps: reps), count: 3))
            return CoachPlanner.suggestion(for: card, history: rows, audience: .adult, now: now) != nil
        }
        // The coach says "stay at 80" (hard sessions); the plan says 100: 20 kg is exactly 20 % of 100 (mutants: the share of the
        // target instead of the larger weight; strict comparison).
        XCTAssertTrue(shown(history: 80, plan: 100))
        // And the other way round: the coach says 100, the plan says 80 (the share of the plan would be 25 %).
        XCTAssertTrue(shown(history: 100, plan: 80))
        // Just over the line in each direction.
        XCTAssertFalse(shown(history: 79, plan: 100))
        XCTAssertFalse(shown(history: 100, plan: 79))
    }
}
