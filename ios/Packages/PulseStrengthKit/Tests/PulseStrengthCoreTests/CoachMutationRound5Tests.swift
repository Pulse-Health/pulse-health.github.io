import XCTest
@testable import PulseStrengthCore

/// Closes the gaps a fifth round of mutation testing found in the typo guard's agreement rule, the same-weight comparison of
/// the "stands out" test, the scoping clock rule and the plan used for the recommendation. Each test names the defect it catches.
///
/// Survivors that are equivalent and therefore not tested: dropping `isFinite` of the scoping dates (NaN already fails the `<=`),
/// `<=` for `<` in the agreement test (`within` carries a 1e-9 slack, so the exact ratio is never decided by it), and `>` for `>=`
/// in the cluster around a session's best (the same slack).
final class CoachMutationRound5Tests: XCTestCase {
    private let now = CoachFix.now
    private let bench = CoachFix.lib("bench")

    private func day(_ daysAgo: Double, _ parts: [(Double, Int, Int?)], name: String = "Workout") -> ExerciseSession {
        ExerciseSession(
            id: UUID(), date: now.addingTimeInterval(-daysAgo * 86_400), workoutName: name,
            sets: parts.map { CoachFix.set($0.0, $0.1, $0.2) }, isPersonalRecord: false
        )
    }

    private func straight(_ daysAgo: Double, _ kg: Double, reps: Int = 5, count: Int = 3, rir: Int? = 3, name: String = "Workout") -> ExerciseSession {
        day(daysAgo, Array(repeating: (kg, reps, rir), count: count), name: name)
    }

    private func history(_ sessions: [ExerciseSession]) -> ExerciseHistory { CoachFix.history(bench, sessions) }

    /// Three older sessions of 80 kg x 5 to make a typical best, and `newest` on top.
    private func withBase(_ newest: ExerciseSession) -> [ExerciseSession] {
        [newest] + [10.0, 17, 24].map { straight($0, 80) }
    }

    // MARK: Agreement between suspects

    /// Kills: the agreeing limit changed to 2 (a beginner may more than double the weight) or to 30 (a factor of ten is a typo).
    func testSuspectsAgreeUpToThreeTimesTheTypicalBestAndNoFurther() {
        // 80 kg typical; 200 kg is 2.5 times: three sets that agree are kept. 260 kg is 3.25 times: dropped.
        let kept = CoachFix.recommend(bench, withBase(straight(3, 200)))
        XCTAssertFalse(kept.reasons.contains(.suspectSetExcluded), "\(kept)")
        XCTAssertEqual(kept.targetWeightKg, 200)
        let dropped = CoachFix.recommend(bench, withBase(straight(3, 260)))
        XCTAssertTrue(dropped.reasons.contains(.suspectSetExcluded), "\(dropped)")
        XCTAssertEqual(dropped.targetWeightKg, 82.5, "the newest session has nothing left: the clean sessions before it decide")
    }

    /// Kills: the agreeing limit compared with `<` (exactly three times the typical best is still fine). 15 reps make the Epley factor
    /// exactly 1.5, so 60 kg is exactly three times 20 kg in floating point as well.
    func testExactlyThreeTimesTheTypicalBestStillAgrees() {
        var config = CoachConfig()
        config.maximumRepsForReference = 15
        let older = [10.0, 17, 24].map { straight($0, 20, reps: 15, rir: 4) }
        let result = CoachFix.recommend(bench, [straight(3, 60, reps: 15)] + older, config: config)
        XCTAssertFalse(result.reasons.contains(.suspectSetExcluded), "\(result)")
        XCTAssertEqual(result.targetWeightKg, 60)
    }

    /// Kills: no agreement test, and a set that agrees with itself, and `within` against the larger value. Two suspects of very
    /// different size do not agree with each other, however many they are.
    func testSuspectsThatDoNotAgreeWithEachOtherAreAllDropped() {
        let result = CoachFix.recommend(bench, withBase(day(3, [(80, 5, 3), (120, 5, 3), (220, 5, 3)])))
        XCTAssertTrue(result.reasons.contains(.suspectSetExcluded), "\(result)")
        XCTAssertEqual(result.targetWeightKg, 82.5, "the 80 kg set is the session, and it matches the clean ones before it")
        XCTAssertEqual(result.targetReps, 5)
    }

    /// Kills: one agreeing suspect being enough. Here 235 kg has a partner (260 kg) but the partner is beyond the limit, so only one
    /// suspect could be kept, and a single suspect is never corroborated.
    func testALoneSuspectWhoseOnlyPartnerIsOutOfBoundsIsDropped() {
        // Two sets, so that one kept set would already be "half of the session".
        let result = CoachFix.recommend(bench, withBase(day(3, [(235, 5, 3), (260, 5, 3)])))
        XCTAssertTrue(result.reasons.contains(.suspectSetExcluded), "\(result)")
        XCTAssertEqual(result.targetWeightKg, 82.5)
    }

    /// Kills: the two-session check measuring the limit against the higher session's own best instead of the lower session's. A
    /// beginner cannot go from 20 kg to 100 kg: with two sessions nothing can tell which one is right, so the engine stays silent.
    func testTwoSessionsFiveTimesApartStaySilentEvenWhenTheHigherOneAgreesWithItself() {
        let result = CoachFix.recommend(bench, [straight(3, 100), straight(10, 20, rir: 4)])
        XCTAssertEqual(result.verdict, .insufficientData)
        XCTAssertEqual(result.reasons, [.suspectSetExcluded])
        // Doubling is a real step.
        XCTAssertEqual(CoachFix.recommend(bench, [straight(3, 40), straight(10, 20, rir: 4)]).verdict, .hold)
    }

    // MARK: Standing out from the sets at the same weight

    /// Kills: "same weight" meaning within a kilogram. 80.5 kg is not the weight of the 80 kg sets, so the 16-rep set is compared with
    /// nothing and is no rep typo of its own session (it is not a jump from the session before either).
    func testSetsHalfAKilogramApartAreNotTheSameWeight() {
        // A climbing lifter: the median of the bests lags (88 kg-ish), so the 16-rep set is far above it; but it is no more than 1.25
        // times the session before (90 kg), and it is the only set at 80.5 kg, so it stands out from nothing.
        let older = [90.0, 80, 70, 60, 50].enumerated().map { straight(Double($0.offset) * 7 + 10, $0.element) }
        let newest = day(3, [(80, 6, 3), (80, 6, 3), (80.5, 16, 3)])
        let result = CoachFix.recommend(bench, [newest] + older)
        XCTAssertFalse(result.reasons.contains(.suspectSetExcluded), "\(result)")
    }

    /// Kills: standing out without the ratio (any set a little above its neighbours would count), and against the smallest other set
    /// instead of the largest. The sets are all far above the lagging median, but each is within 1.25 times the best of the others.
    func testASetOnlyALittleAboveItsNeighboursIsNoTypo() {
        // A lifter who climbs 10 kg every session; the median of the six bests lags well behind the newest session.
        let climbing = [100.0, 90, 80, 70, 60, 50]
        func rows(_ newest: ExerciseSession) -> [ExerciseSession] {
            [newest] + climbing.dropFirst().enumerated().map { straight(Double($0.offset + 1) * 7 + 3, $0.element) }
        }
        let a = CoachFix.recommend(bench, rows(day(3, [(100, 6, 3), (100, 7, 3), (100, 6, 3)])))
        XCTAssertFalse(a.reasons.contains(.suspectSetExcluded), "\(a)")
        // Reps 3, 10 and 16 at one weight: the 16-rep set is above the best of the others (10 reps) by only 15 %, though it is 40 %
        // above the smallest one. The session before is strong enough (107.5 kg) for it not to be a jump either.
        let older = [107.5, 100, 90, 80, 70].enumerated().map { straight(Double($0.offset) * 7 + 10, $0.element) }
        let b = CoachFix.recommend(bench, [day(3, [(100, 3, 3), (100, 10, 3), (100, 16, 3)])] + older)
        XCTAssertFalse(b.reasons.contains(.suspectSetExcluded), "\(b)")
    }

    // MARK: The clock rule of the scoping

    /// Kills: a session exactly one day ahead being ignored by the scoping, though the engine keeps it.
    func testASessionExactlyOneDayAheadStillCountsAsTheNewestOne() {
        let a = [straight(30, 80, name: "A"), straight(37, 80, name: "A")]
        let b = [day(-1, [(60, 12, 3)], name: "B"), straight(60, 60, reps: 12, name: "B")]
        // The newest session of the lift is the one a day ahead, 31 days after A's newest: A is stale, so everything comes back.
        XCTAssertEqual(history(a + b).scoped(toWorkoutNamed: "A", now: now).sessions.count, 4)
    }

    // MARK: The plan that gates the recommendation

    /// Kills: the plan ignoring to-failure sets, counting every set type, or taking the lightest set.
    func testThePlanForTheRecommendationIsTheHeaviestWorkingSet() {
        let hard = [straight(3, 100, rir: 1, name: "T"), straight(10, 100, rir: 1, name: "T")]
        func recommendation(_ sets: [LoggedSet]) -> Recommendation? {
            CoachPlanner.recommendation(
                for: WorkoutExercise(exercise: bench, sets: sets, restSeconds: 90), history: history(hard), workoutName: "T",
                audience: .adult, now: now
            )
        }
        // The top set is a to-failure set at 100 kg, the back-offs 60 kg: the plan is 100 kg, which fits.
        XCTAssertNotNil(recommendation([LoggedSet(type: .failure, weightKg: 100, reps: 5), LoggedSet(weightKg: 60, reps: 5)]))
        // A heavy warm-up or drop set is not the plan; the working sets at 100 kg are.
        XCTAssertNotNil(recommendation([LoggedSet(type: .warmup, weightKg: 200, reps: 5), LoggedSet(weightKg: 100, reps: 5)]))
        XCTAssertNotNil(recommendation([LoggedSet(type: .drop, weightKg: 200, reps: 5), LoggedSet(weightKg: 100, reps: 5)]))
        // Heaviest, not lightest: 100 kg and 60 kg normal sets are a plan of 100 kg.
        XCTAssertNotNil(recommendation([LoggedSet(weightKg: 60, reps: 5), LoggedSet(weightKg: 100, reps: 5)]))
        // And a plan far from the history is still gated.
        XCTAssertNil(recommendation([LoggedSet(weightKg: 60, reps: 5)]))
    }
}
