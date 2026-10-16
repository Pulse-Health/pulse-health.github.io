import XCTest
@testable import PulseStrengthCore

/// Regression tests for the findings of the second review, which looked at the fixes made after the first one (`CoachReviewFixTests`).
/// Each test failed on commit 9cdda14.
///
/// Still open on purpose (a coach's decision or low value): two workouts logged on the same day count as two sessions, a typo in the
/// reps of a lift done above 10 reps cannot be seen by the typo guard (the plan check below stops it from reaching Apply), and a
/// restart weight after a long layoff is not suggested (the note says to ease back in and offers no Apply).
final class CoachSecondReviewTests: XCTestCase {
    private let now = CoachFix.now
    private let bench = CoachFix.lib("bench")
    private let squat = CoachFix.lib("squat")

    private func session(
        _ daysAgo: Int, _ kg: Double, reps: [Int] = [6, 6, 6], rir: [Int?] = [3, 3, 3], name: String = "Workout", hoursEarlier: Double = 0
    ) -> ExerciseSession {
        ExerciseSession(
            id: UUID(), date: CoachFix.date(daysAgo: daysAgo).addingTimeInterval(-hoursEarlier * 3_600), workoutName: name,
            sets: CoachFix.sets(kg, reps, rir: rir), isPersonalRecord: false
        )
    }

    private func entry(_ exercise: Exercise, _ sets: [LoggedSet]) -> WorkoutExercise {
        WorkoutExercise(exercise: exercise, sets: sets, restSeconds: 90)
    }

    private func history(_ sessions: [ExerciseSession], of exercise: Exercise? = nil) -> ExerciseHistory {
        CoachFix.history(exercise ?? bench, sessions)
    }

    private func template(_ name: String, _ exercise: Exercise, kg: Double, reps: Int) -> WorkoutTemplate {
        WorkoutTemplate(name: name, entries: [
            TemplateEntry(exercise: exercise, plannedSets: [PlannedSet(weightKg: kg, reps: reps)], restSeconds: 90),
        ])
    }

    // MARK: Apply and to-failure sets

    func testApplyNeverReachesBackOffSetsBehindAHeavierToFailureSet() {
        // Top set to failure at 100 kg, then two back-off sets: the history says "100 kg x 5", which is about the failure set.
        let failureTop = [
            ExerciseSession(
                id: UUID(), date: CoachFix.date(daysAgo: 3), workoutName: "Workout",
                sets: [CoachFix.set(100, 5, 2, type: .failure)] + CoachFix.sets(80, [10, 10], rir: [2, 2]), isPersonalRecord: false
            ),
            ExerciseSession(
                id: UUID(), date: CoachFix.date(daysAgo: 10), workoutName: "Workout",
                sets: [CoachFix.set(100, 5, 2, type: .failure)] + CoachFix.sets(80, [10, 10], rir: [2, 2]), isPersonalRecord: false
            ),
        ]
        let plan = entry(bench, [
            LoggedSet(type: .failure, weightKg: 100, reps: 5), LoggedSet(weightKg: 80, reps: 10), LoggedSet(weightKg: 80, reps: 10),
        ])
        let suggestion = CoachPlanner.suggestion(for: plan, history: history(failureTop), audience: .adult, now: now)
        XCTAssertNil(suggestion, "nothing in the top group is a normal set, so there is nothing to apply")

        // A ramp ending in a to-failure set: the three normal sets below it are not touched either.
        let ramp = [
            ExerciseSession(
                id: UUID(), date: CoachFix.date(daysAgo: 3), workoutName: "Workout",
                sets: CoachFix.sets(100, [5, 5, 5], rir: [3, 3, 3]) + [CoachFix.set(105, 8, 0, type: .failure)], isPersonalRecord: false
            ),
        ]
        let rampPlan = entry(bench, [
            LoggedSet(weightKg: 100, reps: 5), LoggedSet(weightKg: 100, reps: 5), LoggedSet(weightKg: 100, reps: 5),
            LoggedSet(type: .failure, weightKg: 105, reps: 8),
        ])
        XCTAssertNil(CoachPlanner.suggestion(for: rampPlan, history: history(ramp + ramp.map {
            ExerciseSession(id: UUID(), date: CoachFix.date(daysAgo: 10), workoutName: $0.workoutName, sets: $0.sets, isPersonalRecord: false)
        }), audience: .adult, now: now))
    }

    // MARK: The record tip and the coach

    func testTheRecommendationIsAvailableWhenThereIsNothingToApply() throws {
        // The plan already says what the coach says ("stay at 80"): no suggestion, but the card still has to know the coach named a weight.
        let hard = [session(3, 80, rir: [1, 1, 1]), session(10, 80, rir: [1, 1, 1])]
        let plan = entry(bench, [LoggedSet(weightKg: 80, reps: 6), LoggedSet(weightKg: 80, reps: 6), LoggedSet(weightKg: 80, reps: 6)])
        XCTAssertNil(CoachPlanner.suggestion(for: plan, history: history(hard), audience: .adult, now: now))
        let recommendation = try XCTUnwrap(CoachPlanner.recommendation(for: plan, history: history(hard), audience: .adult, now: now))
        XCTAssertEqual(recommendation.verdict, .hold)
        XCTAssertTrue(recommendation.verdict.hasTarget)

        // It is also there after sets were logged, and it is nil for an exercise without a weight.
        var started = plan
        started.sets[0].isDone = true
        XCTAssertNotNil(CoachPlanner.recommendation(for: started, history: history(hard), audience: .adult, now: now))
        let pushUp = entry(CoachFix.lib("pushup"), [LoggedSet(weightKg: 0, reps: 12)])
        XCTAssertNil(CoachPlanner.recommendation(for: pushUp, history: CoachFix.history(pushUp.exercise, []), now: now))
    }

    // MARK: Typo guard

    func testARepTypoIsCaughtEvenWhenTheOlderSessionWasStronger() {
        // 16 typed for 6 in the newest session; the session before it was a heavier 85 kg.
        let typo = ExerciseSession(
            id: UUID(), date: CoachFix.date(daysAgo: 3), workoutName: "Workout",
            sets: CoachFix.sets(80, [6, 6, 16], rir: [3, 3, 3]), isPersonalRecord: false
        )
        let sessions = [typo, session(7, 85), session(11, 80), session(15, 80), session(19, 80)]
        let result = CoachFix.recommend(bench, sessions)
        XCTAssertTrue(result.reasons.contains(.suspectSetExcluded), "\(result)")
        XCTAssertEqual(result.targetWeightKg, 80)
        XCTAssertEqual(result.targetReps, 6)
    }

    func testRatiosThatAreExactlyTheLimitOnPaperAreOnTheSameSideWhateverTheNumbers() {
        // 50 kg after 40 kg is exactly 1.25 times. It must not be called a typo, for any of these weights.
        for (low, high) in [(40.0, 50.0), (20, 25), (80, 100), (160, 200), (8, 10), (10, 12.5)] {
            for reps in [3, 5, 8] {
                let rows = [session(3, high, reps: [reps, reps, reps]), session(10, low, reps: [reps, reps, reps]),
                            session(17, low, reps: [reps, reps, reps])]
                let three = CoachFix.recommend(bench, rows)
                XCTAssertFalse(three.reasons.contains(.suspectSetExcluded), "\(low)->\(high) x\(reps): \(three)")
                XCTAssertEqual(three.targetWeightKg, high, "\(low)->\(high) x\(reps)")
                let pair = CoachFix.recommend(bench, Array(rows.prefix(2)))
                XCTAssertNotEqual(pair.verdict, .insufficientData, "\(low)->\(high) x\(reps): \(pair)")
            }
        }
    }

    func testOnlyTheRecentRunSaysWhatIsTypical() {
        // Two clean 3x12 sessions at 60 kg, and two much older 8-rep sessions at 30 and 45 kg.
        let recent = [session(3, 60, reps: [12, 12, 12]), session(10, 60, reps: [12, 12, 12])]
        let old = [session(510, 45, reps: [8, 8, 8]), session(517, 30, reps: [8, 8, 8])]
        let result = CoachFix.recommend(bench, recent + old)
        XCTAssertEqual(result.verdict, .progress)
        XCTAssertEqual(result.targetWeightKg, 62.5)
        XCTAssertEqual(result.targetReps, 12)

        // The same with a third old session: the old ones must not turn the recent ones into "typos".
        let moreOld = old + [session(524, 45, reps: [8, 8, 8])]
        XCTAssertEqual(CoachFix.recommend(bench, recent + moreOld).targetWeightKg, 62.5)

        // A returning lifter who is stronger than he was a year ago is not corrected back to the old weight.
        let stronger = [session(10, 85, reps: [5, 5, 5])] + (0..<5).map { session(400 + $0 * 7, 60, reps: [5, 5, 5]) }
        let comeback = CoachFix.recommend(bench, stronger)
        XCTAssertEqual(comeback.verdict, .hold)
        XCTAssertEqual(comeback.targetWeightKg, 85)
        XCTAssertEqual(comeback.reasons, [.awaitingSecondCleanSession])
    }

    func testASessionThatDoublesTheWeightWithAllItsSetsIsNotSilencedAsAJump() {
        // Novice: 20 kg x 8 last week, 30 kg x 8 (all three sets) now. Not a typo; wait for a second session at 30.
        let result = CoachFix.recommend(squat, [session(3, 30, reps: [8, 8, 8]), session(10, 20, reps: [8, 8, 8])])
        XCTAssertEqual(result.verdict, .hold)
        XCTAssertEqual(result.targetWeightKg, 30)
        XCTAssertEqual(result.reasons, [.awaitingSecondCleanSession])

        // One set far above its two neighbours in the same pair of sessions is still unresolvable.
        let oneSet = ExerciseSession(
            id: UUID(), date: CoachFix.date(daysAgo: 3), workoutName: "Workout",
            sets: CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3]) + [CoachFix.set(800, 6, 3)], isPersonalRecord: false
        )
        let silent = CoachFix.recommend(bench, [oneSet, session(10, 80)])
        XCTAssertEqual(silent.verdict, .insufficientData)
        XCTAssertEqual(silent.reasons, [.suspectSetExcluded])
    }

    // MARK: Workout names, the plan, and long breaks

    func testAStaleWorkoutNameCannotHideRecentTrainingOfTheLift() {
        // Eight recent "Push A" sessions, and two sessions of "Chest day" seven months ago.
        let recent = (0..<8).map { session(3 + $0 * 7, 90 - Double($0) * 2.5, name: "Push A") }
        let stale = [session(210, 60, name: "Chest day"), session(217, 60, name: "Chest day")]
        let all = history(recent + stale)
        XCTAssertEqual(all.scoped(toWorkoutNamed: "Chest day", now: now).sessions.count, 10, "falls back to everything")
        XCTAssertEqual(all.scoped(toWorkoutNamed: "Push A", now: now).sessions.count, 8)

        let plan = entry(bench, [LoggedSet(weightKg: 90, reps: 6), LoggedSet(weightKg: 90, reps: 6)])
        let note = CoachPlanner.suggestion(for: plan, history: all, workoutName: "Chest day", audience: .adult, now: now)
        XCTAssertNil(note, "unscoped, the engine says: stay at 90, which is the plan")
    }

    func testAFarAwayTargetIsNeverOfferedAgainstThePlan() {
        // Upper A plans 100 x 3, Upper B plans 75 x 10; Upper A has only one session so far, so the history is not scoped.
        let mixed = [session(3, 75, reps: [10, 10, 10], name: "Upper B"), session(7, 100, reps: [3, 3, 3], name: "Upper A")]
        let upperA = template("Upper A", bench, kg: 100, reps: 3)
        XCTAssertEqual(
            CoachPlanner.nextTime(for: upperA, exercise: { _ in nil }, history: { _ in self.history(mixed) }, audience: .adult, now: now)
                .count, 0
        )
        let plan = entry(bench, [LoggedSet(weightKg: 100, reps: 3), LoggedSet(weightKg: 100, reps: 3), LoggedSet(weightKg: 100, reps: 3)])
        XCTAssertNil(CoachPlanner.suggestion(for: plan, history: history(mixed), workoutName: "Upper A", audience: .adult, now: now))

        // A new template with the same lift at a very different weight: no +37 % Apply.
        let fullBody = [session(3, 80, reps: [5, 5, 5], name: "Full body"), session(10, 80, reps: [5, 5, 5], name: "Full body")]
        let push = entry(bench, [LoggedSet(weightKg: 60, reps: 10), LoggedSet(weightKg: 60, reps: 10)])
        XCTAssertNil(CoachPlanner.suggestion(for: push, history: history(fullBody), workoutName: "Push", audience: .adult, now: now))

        // Within the deviation the suggestion appears as before; a plan of 0 kg (imported template) is never gated.
        let close = entry(bench, [LoggedSet(weightKg: 75, reps: 6), LoggedSet(weightKg: 75, reps: 6)])
        XCTAssertNotNil(CoachPlanner.suggestion(for: close, history: history([session(3, 80), session(10, 80)]), audience: .adult, now: now))
        let imported = entry(bench, [LoggedSet(weightKg: 0, reps: 6), LoggedSet(weightKg: 0, reps: 6)])
        XCTAssertNotNil(CoachPlanner.suggestion(for: imported, history: history(fullBody), workoutName: "Push", audience: .adult, now: now))

        // The limit is the configuration's.
        var strict = CoachConfig()
        strict.maximumPlanDeviation = 0.01
        XCTAssertNil(CoachPlanner.suggestion(for: close, history: history([session(3, 80), session(10, 80)]), audience: .adult, config: strict, now: now))
    }

    func testAfterALongBreakTheCoachSaysWhatWasDoneAndNeverRaisesThePlan() throws {
        let old = [session(200, 140, reps: [5, 5, 5]), session(207, 140, reps: [5, 5, 5]), session(214, 140, reps: [5, 5, 5])]
        let comeback = entry(squat, [LoggedSet(weightKg: 100, reps: 5), LoggedSet(weightKg: 100, reps: 5)])
        let note = try XCTUnwrap(CoachPlanner.suggestion(for: comeback, history: history(old, of: squat), audience: .adult, now: now))
        XCTAssertEqual(note.line.headline, "Last time: 140 kg × 5")
        XCTAssertEqual(note.line.detail, "It has been a while since your last session, so ease back in.")
        XCTAssertEqual(note.actions, [])

        // Also when the plan still holds the old weight: this is exactly when a warning is needed.
        let unchanged = entry(squat, [LoggedSet(weightKg: 140, reps: 5), LoggedSet(weightKg: 140, reps: 5)])
        XCTAssertNotNil(CoachPlanner.suggestion(for: unchanged, history: history(old, of: squat), audience: .adult, now: now))

        // The hub card shows it too, whatever the plan is.
        let hub = CoachPlanner.nextTime(
            for: template("Legs", squat, kg: 100, reps: 5), exercise: { _ in nil }, history: { _ in self.history(old, of: self.squat) },
            audience: .adult, now: now
        )
        XCTAssertEqual(hub.first?.line.headline, "Last time: 140 kg × 5")
    }

    func testFourWeeksToTheHourIsStillFourWeeks() {
        let weekly = (0..<4).map { 28 + $0 * 7 }.map { session($0, 100, reps: [5, 5, 5]) }
        func verdict(extraHours: Double) -> Recommendation {
            // The newest session is 28 days and `extraHours` hours old.
            let shifted = weekly.enumerated().map { index, row -> ExerciseSession in
                var copy = row
                copy.date = row.date.addingTimeInterval(-extraHours * 3_600)
                _ = index
                return copy
            }
            return CoachFix.recommend(bench, shifted)
        }
        XCTAssertEqual(verdict(extraHours: 0).verdict, .progress)
        XCTAssertEqual(verdict(extraHours: 1).verdict, .progress, "an hour later in the day is the same four weeks")
        XCTAssertEqual(verdict(extraHours: 11).verdict, .progress)
        XCTAssertEqual(verdict(extraHours: 13).reasons, [.returningAfterBreak])
        // And the same slack applies between the two sessions that must count together.
        let closePair = [session(3, 100, reps: [5, 5, 5]), session(31, 100, reps: [5, 5, 5], hoursEarlier: 11)]
        XCTAssertEqual(CoachFix.recommend(bench, closePair).verdict, .progress)
        let farPair = [session(3, 100, reps: [5, 5, 5]), session(31, 100, reps: [5, 5, 5], hoursEarlier: 13)]
        XCTAssertEqual(CoachFix.recommend(bench, farPair).reasons, [.awaitingSecondCleanSession])
    }

    // MARK: Lighter week and words

    func testALighterWeekNeedsRepsInReserveOfAtMostTwoOnAverage() {
        let loads: [Double] = [72.5, 70, 67.5, 65, 62.5, 60, 57.5]
        func rising(rir: [Int?]) -> Recommendation {
            CoachFix.recommend(bench, loads.enumerated().map { session(3 + $0.offset * 7, $0.element, rir: rir) })
        }
        XCTAssertEqual(rising(rir: [2, 2, 2]).verdict, .reduce)
        XCTAssertEqual(rising(rir: [3, 2, 2]).verdict, .hold, "mean 2.33: not tired enough")
        XCTAssertEqual(rising(rir: [3, 3, 2]).verdict, .hold, "the typical beginner")
        XCTAssertEqual(rising(rir: [2, 2, 3]).verdict, .hold)
    }

    func testAReduceThatIsTooBigSaysSoInTheSentence() {
        let lateral = CoachFix.lib("lateral")
        let sessions = [
            session(3, 8, reps: [10, 10, 9], rir: [0, 0, 0]),
            session(10, 8, reps: [12, 11, 11], rir: [0, 0, 0]),
            session(17, 8, reps: [13, 13, 13], rir: [0, 0, 0]),
        ]
        let result = CoachFix.recommend(lateral, sessions)
        XCTAssertEqual(result.reasons, [.repsFellAtSameLoad, .reduceExceedsCap])
        XCTAssertEqual(
            TemplateWriter.line(for: result)?.sentence,
            "Stay at 8 kg × 10. Reps have been dropping, but the smallest step down is a big change, so choose your own weight."
        )
    }

    func testTheShareRuleHasItsOwnWords() {
        let result = CoachFix.recommend(bench, [session(3, 80, rir: [4, 1, 1]), session(10, 80, rir: [4, 1, 1])])
        XCTAssertEqual(result.reasons, [.moderateEffort])
        XCTAssertEqual(TemplateWriter.line(for: result)?.detail, "Move up once most sets feel easier (RIR 2 or more).")
    }

    func testThePlanDeviationIsPartOfTheConfigurationCheck() {
        XCTAssertEqual(CoachConfig().maximumPlanDeviation, 0.2)
        for bad in [0.0, -0.1, 1.5, Double.nan, Double.infinity] {
            var config = CoachConfig()
            config.maximumPlanDeviation = bad
            XCTAssertFalse(config.isValid, "\(bad)")
        }
        var wide = CoachConfig()
        wide.maximumPlanDeviation = 1
        XCTAssertTrue(wide.isValid)
    }
}
