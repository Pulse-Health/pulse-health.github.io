import XCTest
@testable import PulseStrengthCore

/// Regression tests for the findings of the third review, which looked at the fixes made after the second one
/// (`CoachSecondReviewTests`). Each test failed on commit c1940fe.
final class CoachThirdReviewTests: XCTestCase {
    private let now = CoachFix.now
    private let bench = CoachFix.lib("bench")
    private let squat = CoachFix.lib("squat")
    private let lateral = CoachFix.lib("lateral")

    /// One session; `parts` are (kg, [reps], [rir]) groups logged in this order.
    private func day(
        _ daysAgo: Int, _ parts: [(Double, [Int], [Int?])], name: String = "Workout", hoursEarlier: Double = 0
    ) -> ExerciseSession {
        let sets = parts.flatMap { CoachFix.sets($0.0, $0.1, rir: $0.2) }
        return ExerciseSession(
            id: UUID(), date: CoachFix.date(daysAgo: daysAgo).addingTimeInterval(-hoursEarlier * 3_600),
            workoutName: name, sets: sets, isPersonalRecord: false
        )
    }

    private func straight(_ daysAgo: Int, _ kg: Double, reps: [Int] = [6, 6, 6], rir: [Int?] = [3, 3, 3], name: String = "Workout") -> ExerciseSession {
        day(daysAgo, [(kg, reps, rir)], name: name)
    }

    private func history(_ sessions: [ExerciseSession], of exercise: Exercise? = nil) -> ExerciseHistory {
        CoachFix.history(exercise ?? bench, sessions)
    }

    // MARK: Typos that repeat

    func testAWeightTypoCopiedOntoSeveralSetsIsStillATypo() {
        // "Add set" copies the last set, so a weight typed ten times too large is easily on two sets.
        let older = [10, 17, 24].map { straight($0, 100, reps: [8, 8, 8], rir: [2, 2, 2]) }
        let newest = day(3, [(100, [8], [2]), (1_000, [8, 8], [2, 2])])
        let result = CoachFix.recommend(bench, [newest] + older)
        XCTAssertTrue(result.reasons.contains(.suspectSetExcluded), "\(result)")
        XCTAssertEqual(result.verdict, .progress)
        XCTAssertEqual(result.targetWeightKg, 102.5)
    }

    func testATypoNextToSetsThatAreFlaggedOnlyBecauseTheMedianLagsIsStillDropped() {
        // Light dumbbell work with a climbing weight: the median of the bests lags, so every set of the newest session is above 1.25x
        // of it; one set has an extra zero. The two real sets agree with each other; the typo does not agree with anything.
        let newest = day(3, [(17.5, [10], [0]), (175, [10], [0]), (17.5, [11], [0])])
        let older = [
            straight(10, 17.5, reps: [11, 11, 11], rir: [4, 4, 4]),
            day(13, [(15, [11, 10, 10, 10, 11], [2, 2, 2, 2, 2])]),
            day(17, [(12.5, [10, 11, 10, 10, 10], [3, 3, 3, 3, 3])]),
            day(22, [(12.5, [10, 10, 9, 10, 10], [2, 2, 2, 2, 2])]),
            day(26, [(12.5, [10, 10, 10, 11, 9], [2, 2, 2, 2, 2])]),
        ]
        let result = CoachFix.recommend(lateral, [newest] + older)
        XCTAssertNotEqual(result.targetWeightKg, 175, "\(result)")
        XCTAssertEqual(result.targetWeightKg, 17.5)
        XCTAssertTrue(result.reasons.contains(.suspectSetExcluded), "\(result)")
    }

    func testSetsThatAgreeAreKeptOnlyUpToThreeTimesTheTypicalBest() {
        // Three identical sets at five times the weight of the last three sessions are not a beginner's first working weight.
        let older = [10, 13, 16].map { straight($0, 20, reps: [5, 5, 5], rir: [4, 4, 4]) }
        let result = CoachFix.recommend(squat, [straight(3, 100, reps: [5, 5, 5])] + older)
        XCTAssertTrue(result.reasons.contains(.suspectSetExcluded), "\(result)")
        XCTAssertEqual(result.targetWeightKg, 20)
        // Doubling is fine (see CoachSecondReviewTests).
        let doubled = CoachFix.recommend(squat, [straight(3, 40, reps: [5, 5, 5])] + older)
        XCTAssertFalse(doubled.reasons.contains(.suspectSetExcluded), "\(doubled)")
        XCTAssertEqual(doubled.targetWeightKg, 40)
    }

    func testALightSetInTheSameSessionDoesNotMakeTheTopSetATypo() {
        // A beginner adds 5 kg every session and starts each session with a light set that is logged as a normal set.
        for count in 4...7 {
            let sessions = (0..<count).map { index -> ExerciseSession in
                let top = 20 + Double(count - 1 - index) * 5
                return day(3 + index * 3, [(20, [5], [4]), (top, [5], [3])])
            }
            let result = CoachFix.recommend(squat, sessions)
            XCTAssertFalse(result.reasons.contains(.suspectSetExcluded), "\(count): \(result)")
            XCTAssertEqual(result.targetWeightKg, 20 + Double(count - 1) * 5, "\(count)")
        }
        // A rep typo has the weight of its neighbours: that is what stands out.
        let typo = day(3, [(80, [6, 6, 16], [3, 3, 3])])
        let result = CoachFix.recommend(bench, [typo] + [10, 17, 24, 31].map { straight($0, 80) })
        XCTAssertTrue(result.reasons.contains(.suspectSetExcluded), "\(result)")
        XCTAssertEqual(result.targetReps, 6)
    }

    func testAPairWhoseSetsAllSitAtTheNewWeightIsNotSilencedByOneRep() {
        // 22.5 kg last time, 27.5 kg now on every set; only two of the five sets reach 7 reps, which puts them just over 1.25x.
        let crossover = CoachFix.lib("crossover")
        let newer = day(4, [(27.5, [7, 6, 6, 7, 6], [0, 0, 0, 0, 0])])
        let older = day(12, [(22.5, [6, 6, 6, 6], [3, 3, 3, 3])])
        for sets in [[7, 6, 6, 7, 6], [7, 7, 7, 7, 7], [6, 6, 6, 6, 6]] {
            let high = day(4, [(27.5, sets, [0, 0, 0, 0, 0])])
            let result = CoachFix.recommend(crossover, [high, older])
            XCTAssertNotEqual(result.verdict, .insufficientData, "\(sets): \(result)")
            XCTAssertEqual(result.targetWeightKg, 27.5, "\(sets)")
        }
        _ = newer
    }

    // MARK: Plan gate, record tip and scoping

    func testTheRecommendationIsHiddenWhenItsWeightIsFarFromThePlanSoTheTipIsNotHiddenForNothing() throws {
        let hard = [straight(3, 80, rir: [1, 1, 1], name: "Push"), straight(10, 80, rir: [1, 1, 1], name: "Push")]
        let far = WorkoutExercise(exercise: bench, sets: [LoggedSet(weightKg: 40, reps: 6)], restSeconds: 90)
        XCTAssertNil(CoachPlanner.suggestion(for: far, history: history(hard), workoutName: "Push", audience: .adult, now: now))
        XCTAssertNil(CoachPlanner.recommendation(for: far, history: history(hard), workoutName: "Push", audience: .adult, now: now))
        let near = WorkoutExercise(exercise: bench, sets: [LoggedSet(weightKg: 80, reps: 6)], restSeconds: 90)
        XCTAssertNotNil(CoachPlanner.recommendation(for: near, history: history(hard), workoutName: "Push", audience: .adult, now: now))
    }

    func testTheBreakNoteIsMarkedAsLookingBack() throws {
        let old = [straight(200, 140, reps: [5, 5, 5]), straight(207, 140, reps: [5, 5, 5])]
        let line = try XCTUnwrap(TemplateWriter.line(for: CoachFix.recommend(squat, old)))
        XCTAssertTrue(line.isLookingBack)
        XCTAssertEqual(line.headline, "Last time: 140 kg × 5")
        let target = try XCTUnwrap(TemplateWriter.line(for: Recommendation(exerciseID: "bench", verdict: .progress, targetWeightKg: 82.5, targetReps: 6)))
        XCTAssertFalse(target.isLookingBack)
        XCTAssertFalse(CoachLine(headline: "A").isLookingBack)
    }

    func testScopingAgreesWithTheEnginesRulesForDates() {
        let heavy = [3, 10, 17].map { straight($0, 80, reps: [5, 5, 5], name: "Heavy") }
        let light = [6, 13, 20].map { straight($0, 60, reps: [12, 12, 12], name: "Light") }
        let base = history(heavy + light)
        XCTAssertEqual(base.scoped(toWorkoutNamed: "Heavy", now: now).sessions.count, 3)

        // A session dated far in the future (a clock error) in the other workout changes nothing.
        let future = straight(-400, 60, reps: [12, 12, 12], name: "Light")
        XCTAssertEqual(history(heavy + light + [future]).scoped(toWorkoutNamed: "Heavy", now: now).sessions.count, 3)

        // A date that is not a number is ignored, wherever it sits in the list.
        let broken = ExerciseSession(
            id: UUID(), date: Date(timeIntervalSinceReferenceDate: .nan), workoutName: "Old",
            sets: CoachFix.sets(80, [5, 5, 5], rir: [3, 3, 3]), isPersonalRecord: false
        )
        let old = [60, 70, 80].map { straight($0, 80, name: "Old") }
        let other = [3, 10].map { straight($0, 60, name: "Other") }
        let front = history([broken] + old + other).scoped(toWorkoutNamed: "Old", now: now)
        let back = history(old + other + [broken]).scoped(toWorkoutNamed: "Old", now: now)
        XCTAssertEqual(front.sessions.count, back.sessions.count)
        XCTAssertEqual(front.sessions.count, 6, "stale: the whole history comes back (the engine ignores the broken date later)")

        // The staleness test has the same half day of slack as the engine: 28 days and an hour is still "the same run".
        let a = [31, 38, 45].map { straight($0, 80, name: "A") }
        let b = [3 + 0, 10].map { straight($0, 60, name: "B") }
        let shifted = a.map { row -> ExerciseSession in
            var copy = row
            copy.date = row.date.addingTimeInterval(-3_600)
            return copy
        }
        XCTAssertEqual(history(shifted + b).scoped(toWorkoutNamed: "A", now: now).sessions.count, 3)
        let wellOver = a.map { row -> ExerciseSession in
            var copy = row
            copy.date = row.date.addingTimeInterval(-13 * 3_600)
            return copy
        }
        XCTAssertEqual(history(wellOver + b).scoped(toWorkoutNamed: "A", now: now).sessions.count, 5)
    }

    func testAPlanThatIsExactlyTwentyPercentAwayIsAcceptedWhateverTheRounding() {
        let hold = [straight(3, 17.2, reps: [6, 6, 6], rir: [1, 1, 1], name: "T"), straight(10, 17.2, reps: [6, 6, 6], rir: [1, 1, 1], name: "T")]
        let template = WorkoutTemplate(name: "T", entries: [
            TemplateEntry(exercise: lateral, plannedSets: [PlannedSet(weightKg: 21.5, reps: 6)], restSeconds: 60),
        ])
        let items = CoachPlanner.nextTime(
            for: template, exercise: { _ in nil }, history: { _ in self.history(hold, of: self.lateral) }, audience: .adult, now: now
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.recommendation.targetWeightKg, 17.2)
    }

    // MARK: Apply is idempotent

    func testApplyingTwiceNeverChangesAnythingTheSecondTime() throws {
        // Lowering: a set between the target and the top is taken down with it.
        let hold = [straight(3, 52.5, reps: [5, 5, 5], rir: [1, 1, 1], name: "Push"), straight(10, 52.5, reps: [5, 5, 5], rir: [1, 1, 1], name: "Push")]
        let plan = WorkoutExercise(exercise: bench, sets: [LoggedSet(weightKg: 57.5, reps: 10), LoggedSet(weightKg: 55, reps: 10)], restSeconds: 90)
        let first = try XCTUnwrap(CoachPlanner.suggestion(for: plan, history: history(hold), workoutName: "Push", audience: .adult, now: now))
        XCTAssertEqual(first.actions.count, 4)
        var state = WorkoutState(id: UUID(), name: "Push", exercises: [plan], startedAt: now)
        for action in first.actions { WorkoutReducer.reduce(&state, action, now: now) }
        XCTAssertEqual(state.exercises[0].sets.map { $0.weightKg }, [52.5, 52.5])
        XCTAssertNil(CoachPlanner.suggestion(for: state.exercises[0], history: history(hold), workoutName: "Push", audience: .adult, now: now))
    }

    func testApplyingIsIdempotentForRandomPlans() {
        var rng = RedLCG(seed: 20_261_018)
        let histories: [(String, [ExerciseSession])] = [
            ("progress", [straight(3, 80), straight(10, 80)]),
            ("hold", [straight(3, 80, rir: [1, 1, 1]), straight(10, 80, rir: [1, 1, 1])]),
            ("reduce", [straight(3, 80, reps: [4, 4, 4], rir: [0, 0, 0]), straight(10, 80, reps: [5, 5, 5], rir: [0, 0, 0]),
                        straight(17, 80, reps: [6, 6, 6], rir: [0, 0, 0])]),
            ("hint", [straight(3, 80, rir: [nil, nil, nil]), straight(10, 80, rir: [nil, nil, nil])]),
        ]
        var applied = 0
        for _ in 0..<1_500 {
            let count = rng.int(1...6)
            let weights: [Double] = [0, 40, 60, 77.5, 80, 82.5, 100, 120]
            let types: [SetType] = [.normal, .normal, .normal, .warmup, .drop, .failure]
            let sets = (0..<count).map { _ in
                LoggedSet(type: rng.pick(types), weightKg: rng.pick(weights), reps: rng.int(1...12))
            }
            let plan = WorkoutExercise(exercise: bench, sets: sets, restSeconds: 90)
            let (label, sessions) = rng.pick(histories)
            guard let first = CoachPlanner.suggestion(for: plan, history: history(sessions), audience: .adult, now: now),
                  !first.actions.isEmpty else { continue }
            var state = WorkoutState(id: UUID(), name: "T", exercises: [plan], startedAt: now)
            for action in first.actions { WorkoutReducer.reduce(&state, action, now: now) }
            let second = CoachPlanner.suggestion(for: state.exercises[0], history: history(sessions), audience: .adult, now: now)
            XCTAssertTrue(second?.actions.isEmpty ?? true, "\(label): \(sets.map { "\($0.type) \($0.weightKg)x\($0.reps)" }) -> \(String(describing: second))")
            applied += 1
        }
        XCTAssertGreaterThan(applied, 200, "the generator must reach Apply often enough to prove anything")
    }
}
