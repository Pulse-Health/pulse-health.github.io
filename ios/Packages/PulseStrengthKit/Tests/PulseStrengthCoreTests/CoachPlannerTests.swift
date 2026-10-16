import XCTest
@testable import PulseStrengthCore

/// The planner and the text writer, on the demo data and on small hand-made histories.
final class CoachPlannerTests: XCTestCase {
    private let now = CoachFix.now

    private var demo: StrengthData {
        StrengthData(
            templates: SampleData.templates(now: now),
            history: SampleData.history(now: now),
            personalBests: SampleData.personalBests(now: now)
        )
    }

    private func nextTime(_ template: WorkoutTemplate, data: StrengthData, audience: AudienceProfile = .adult, limit: Int = 3) -> [NextTimeItem] {
        CoachPlanner.nextTime(
            for: template,
            exercise: { data.exercise(id: $0) },
            history: { data.history(for: $0, now: self.now) },
            audience: audience, now: now, limit: limit
        )
    }

    // MARK: Next time

    func testDemoUpperPushShowsOnlyBenchBecauseTheOthersHaveNoRepsInReserve() {
        let data = demo
        let items = nextTime(data.templates[0], data: data)
        // Bench is the only demo lift with RIR: 80 kg last time, 85 kg before, so the weight changed and one more session is needed.
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.recommendation.verdict, .hold)
        XCTAssertEqual(items.first?.line.headline, "Stay at 80 kg × 6")
        XCTAssertEqual(items.first?.line.detail, "One more clean session at this weight before moving up.")
        XCTAssertEqual(items.first?.exerciseName, "Barbell bench press")
    }

    func testLiftsWithOneSessionSayNothing() {
        let data = demo
        XCTAssertTrue(nextTime(data.templates[1], data: data).isEmpty)
        XCTAssertTrue(nextTime(data.templates[2], data: data).isEmpty)
    }

    func testTheLogRIRHintAppearsOnlyWhenThereIsNothingElse() {
        let data = demo
        // Same template without bench: every remaining lift lacks RIR, so one hint (for the first of them) is returned.
        var template = data.templates[0]
        template.entries.removeFirst()
        let items = nextTime(template, data: data)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.recommendation.verdict, .noEffortData)
        XCTAssertEqual(items.first?.line.headline, "Log RIR on your sets")
        XCTAssertEqual(items.first?.exerciseName, "Incline dumbbell press")
    }

    func testTheLimitAndTheOrderOfTheTemplateAreKept() {
        let clean = CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3])
        let ids = ["bench", "squat", "ohp", "deadlift"]
        let sessions = [CoachFix.session(3, clean), CoachFix.session(10, clean)]
        var histories: [String: ExerciseHistory] = [:]
        var entries: [TemplateEntry] = []
        for id in ids {
            let exercise = CoachFix.lib(id)
            histories[id] = CoachFix.history(exercise, sessions)
            entries.append(TemplateEntry(exercise: exercise, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90))
        }
        let template = WorkoutTemplate(name: "Test", entries: entries)
        let items = CoachPlanner.nextTime(
            for: template, exercise: { _ in nil }, history: { histories[$0]! }, audience: .adult, now: now, limit: 2
        )
        XCTAssertEqual(items.map { $0.recommendation.exerciseID }, ["bench", "squat"])
        XCTAssertTrue(items.allSatisfy { $0.recommendation.verdict == .progress })
        // Limit 0 returns nothing rather than crashing.
        XCTAssertTrue(CoachPlanner.nextTime(
            for: template, exercise: { _ in nil }, history: { histories[$0]! }, audience: .adult, now: now, limit: 0
        ).isEmpty)
    }

    func testAnExerciseThatAppearsTwiceIsListedOnce() {
        let clean = CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3])
        let bench = CoachFix.lib("bench")
        let history = CoachFix.history(bench, [CoachFix.session(3, clean), CoachFix.session(10, clean)])
        let entry = TemplateEntry(exercise: bench, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90)
        let template = WorkoutTemplate(name: "Twice", entries: [entry, entry])
        let items = CoachPlanner.nextTime(for: template, exercise: { _ in nil }, history: { _ in history }, now: now)
        XCTAssertEqual(items.count, 1)
    }

    // MARK: Text

    func testEveryVerdictHasItsWords() {
        func line(_ verdict: Verdict, _ reasons: [ReasonCode], weight: Double? = 82.5, reps: Int? = 6) -> CoachLine? {
            TemplateWriter.line(for: Recommendation(
                exerciseID: "bench", verdict: verdict, targetWeightKg: weight, targetReps: reps, reasons: reasons
            ))
        }
        XCTAssertEqual(line(.progress, [])?.sentence, "82.5 kg × 6. Two clean sessions at RIR 2 or more.")
        XCTAssertEqual(line(.addRep, [], weight: 8, reps: 16)?.sentence, "8 kg × 16. A heavier step would be a big jump, so add a rep instead.")
        XCTAssertEqual(line(.reduce, [.repsFellAtSameLoad], weight: 77.5, reps: 5)?.sentence, "77.5 kg × 5. Reps fell at the same weight twice.")
        XCTAssertEqual(line(.reduce, [.lighterWeekDue], weight: 70)?.detail, "A lighter week after several increases in a row.")
        XCTAssertEqual(line(.hold, [.lastSessionNearFailure], weight: 80)?.sentence, "Stay at 80 kg × 6. Last session ended close to failure.")
        XCTAssertEqual(line(.hold, [.returningAfterBreak])?.headline, "Last time: 82.5 kg × 6")
        XCTAssertEqual(line(.hold, [.returningAfterBreak])?.detail, "It has been a while since your last session, so ease back in.")
        XCTAssertEqual(line(.hold, [.repsFellAtSameLoad])?.detail, "Reps have been dropping at this weight.")
        XCTAssertEqual(line(.hold, [.moderateEffort])?.detail, "Move up once most sets feel easier (RIR 2 or more).")
        XCTAssertEqual(line(.hold, [.stepExceedsCap])?.detail, "The next step up is a big jump, so choose your own weight.")
        XCTAssertEqual(
            line(.hold, [.repsFellAtSameLoad, .reduceExceedsCap])?.detail,
            "Reps have been dropping, but the smallest step down is a big change, so choose your own weight."
        )
        XCTAssertEqual(line(.hold, [.lighterWeekDue, .reduceExceedsCap])?.detail, "A lighter week is due, but the smallest step down is a big change, so choose your own weight.")
        XCTAssertEqual(line(.hold, [.reduceExceedsCap])?.detail, "The smallest step down is a big change, so choose your own weight.")
        XCTAssertNil(line(.hold, [.suspectSetExcluded])?.detail)
        XCTAssertEqual(line(.noEffortData, [], weight: nil, reps: nil)?.headline, "Log RIR on your sets")
        XCTAssertNil(line(.insufficientData, [.tooFewSessions], weight: nil, reps: nil))
    }

    func testATargetVerdictWithoutFiguresSaysNothingInsteadOfInventingThem() {
        for verdict in [Verdict.progress, .hold, .reduce, .addRep] {
            XCTAssertNil(TemplateWriter.line(for: Recommendation(exerciseID: "x", verdict: verdict)), "\(verdict)")
        }
    }

    // MARK: Suggestion in the workout

    private func benchEntry(sets: [LoggedSet]) -> WorkoutExercise {
        WorkoutExercise(exercise: CoachFix.lib("bench"), sets: sets, restSeconds: 150)
    }

    private var progressHistory: ExerciseHistory {
        let clean = CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3])
        return CoachFix.history(CoachFix.lib("bench"), [CoachFix.session(3, clean), CoachFix.session(10, clean)])
    }

    func testApplyChangesOnlyPendingNormalSetsAndReachesTheSuggestedState() throws {
        let entry = benchEntry(sets: [
            LoggedSet(type: .warmup, weightKg: 50, reps: 8),
            LoggedSet(type: .normal, weightKg: 80, reps: 6),
            LoggedSet(type: .normal, weightKg: 80, reps: 6),
            LoggedSet(type: .failure, weightKg: 80, reps: 6),
        ])
        let suggestion = try XCTUnwrap(CoachPlanner.suggestion(for: entry, history: progressHistory, audience: .adult, now: now))
        XCTAssertEqual(suggestion.line.headline, "82.5 kg × 6")
        // Two weight changes, no rep changes, nothing for the warm-up or the failure set.
        XCTAssertEqual(suggestion.actions.count, 2)

        var state = WorkoutState(id: UUID(), name: "Test", exercises: [entry], startedAt: now)
        for action in suggestion.actions { WorkoutReducer.reduce(&state, action, now: now) }
        XCTAssertEqual(state.exercises[0].sets.map { $0.weightKg }, [50, 82.5, 82.5, 80])
        XCTAssertEqual(state.exercises[0].sets.map { $0.reps }, [8, 6, 6, 6])
    }

    func testApplyAlsoSetsTheRepsOfAnAddRepSuggestion() throws {
        let lateral = CoachFix.lib("lateral")
        let clean = CoachFix.sets(8, [15, 15, 15], rir: [3, 3, 3])
        let history = CoachFix.history(lateral, [CoachFix.session(3, clean), CoachFix.session(10, clean)])
        let entry = WorkoutExercise(exercise: lateral, sets: [LoggedSet(weightKg: 8, reps: 15), LoggedSet(weightKg: 8, reps: 15)], restSeconds: 60)
        let suggestion = try XCTUnwrap(CoachPlanner.suggestion(for: entry, history: history, audience: .adult, now: now))
        XCTAssertEqual(suggestion.recommendation.verdict, .addRep)
        var state = WorkoutState(id: UUID(), name: "Test", exercises: [entry], startedAt: now)
        for action in suggestion.actions { WorkoutReducer.reduce(&state, action, now: now) }
        XCTAssertEqual(state.exercises[0].sets.map { $0.reps }, [16, 16])
        XCTAssertEqual(state.exercises[0].sets.map { $0.weightKg }, [8, 8])
    }

    func testNoSuggestionOnceASetIsLoggedOrWhenThePlanAlreadyMatches() {
        var logged = benchEntry(sets: [LoggedSet(weightKg: 80, reps: 6, isDone: true), LoggedSet(weightKg: 80, reps: 6)])
        XCTAssertNil(CoachPlanner.suggestion(for: logged, history: progressHistory, audience: .adult, now: now))
        logged.sets[0].isDone = false
        XCTAssertNotNil(CoachPlanner.suggestion(for: logged, history: progressHistory, audience: .adult, now: now))

        let matching = benchEntry(sets: [LoggedSet(weightKg: 82.5, reps: 6), LoggedSet(weightKg: 82.5, reps: 6)])
        XCTAssertNil(CoachPlanner.suggestion(for: matching, history: progressHistory, audience: .adult, now: now))
    }

    func testNoSuggestionForExercisesWithoutAWeight() {
        let pushup = WorkoutExercise(exercise: CoachFix.lib("pushup"), sets: [LoggedSet(weightKg: 0, reps: 12)], restSeconds: 60)
        XCTAssertNil(CoachPlanner.suggestion(for: pushup, history: CoachFix.history(pushup.exercise, []), now: now))
    }

    func testTheHintHasNoActions() throws {
        let plain = CoachFix.sets(80, [6, 6, 6])
        let history = CoachFix.history(CoachFix.lib("bench"), [CoachFix.session(3, plain), CoachFix.session(10, plain)])
        let entry = benchEntry(sets: [LoggedSet(weightKg: 80, reps: 6)])
        let suggestion = try XCTUnwrap(CoachPlanner.suggestion(for: entry, history: history, audience: .adult, now: now))
        XCTAssertEqual(suggestion.recommendation.verdict, .noEffortData)
        XCTAssertTrue(suggestion.actions.isEmpty)
    }

    // MARK: Audience

    func testOnlyKnownMinorsLoseTheRecordTip() {
        XCTAssertTrue(AudienceProfile.adult.showsPersonalRecordTips)
        XCTAssertTrue(AudienceProfile.unknown.showsPersonalRecordTips)
        XCTAssertFalse(AudienceProfile(ageGroup: .minor).showsPersonalRecordTips)
        XCTAssertFalse(AudienceProfile.adult.isRestricted)
        XCTAssertTrue(AudienceProfile.unknown.isRestricted)
        XCTAssertTrue(AudienceProfile(ageGroup: .minor).isRestricted)
    }

    func testRecommendationRoundTripsThroughJSON() throws {
        let original = Recommendation(
            exerciseID: "bench", verdict: .addRep, targetWeightKg: 8, targetReps: 16,
            reasons: [.cleanSessionsWithReserve, .stepExceedsCap], sessionsUsed: 3
        )
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(Recommendation.self, from: data), original)
    }
}
