import XCTest
@testable import PulseStrengthCore

/// One regression test per confirmed finding of the review of the first coach implementation (fuzzing, a strength-coach reading,
/// a read against the proposal, and an iOS behaviour review). Each test failed on the code the review looked at.
///
/// Findings that need a coach's decision rather than a fix (double progression, a faster pace for beginners, remembering the
/// weight before a deload, a no-RIR fallback, rep-range awareness) are listed in `ios/COACH-HARNESS-PROPOSAL.md`, not tested here.
final class CoachReviewFixTests: XCTestCase {
    private let now = CoachFix.now
    private let bench = CoachFix.lib("bench")
    private let lateral = CoachFix.lib("lateral")

    private func session(
        _ daysAgo: Int, _ kg: Double, reps: [Int] = [6, 6, 6], rir: [Int?] = [3, 3, 3],
        name: String = "Workout", id: UUID = UUID(), exercise: Exercise? = nil
    ) -> ExerciseSession {
        ExerciseSession(
            id: id, date: CoachFix.date(daysAgo: daysAgo), workoutName: name,
            sets: CoachFix.sets(kg, reps, rir: rir), isPersonalRecord: false
        )
    }

    private func entry(_ exercise: Exercise, _ sets: [LoggedSet]) -> WorkoutExercise {
        WorkoutExercise(exercise: exercise, sets: sets, restSeconds: 90)
    }

    private func history(_ sessions: [ExerciseSession], of exercise: Exercise? = nil) -> ExerciseHistory {
        CoachFix.history(exercise ?? bench, sessions)
    }

    // MARK: Apply keeps the structure of the plan

    func testApplyLeavesBackOffSetsAndRampsAlone() throws {
        let clean = [session(3, 100, reps: [5], rir: [3]), session(10, 100, reps: [5], rir: [3])]
        let topAndBackOffs = entry(bench, [
            LoggedSet(weightKg: 100, reps: 5), LoggedSet(weightKg: 80, reps: 10), LoggedSet(weightKg: 80, reps: 10),
        ])
        let suggestion = try XCTUnwrap(CoachPlanner.suggestion(for: topAndBackOffs, history: history(clean), audience: .adult, now: now))
        XCTAssertEqual(suggestion.line.headline, "102.5 kg × 5")
        XCTAssertEqual(suggestion.actions, [.setWeight(exerciseID: topAndBackOffs.id, setID: topAndBackOffs.sets[0].id, kg: 102.5)])

        // A ramp: only the heaviest pending set is the one the recommendation is about.
        let ramp = entry(bench, [
            LoggedSet(weightKg: 60, reps: 8), LoggedSet(weightKg: 70, reps: 6), LoggedSet(weightKg: 100, reps: 5),
        ])
        let rampSuggestion = try XCTUnwrap(CoachPlanner.suggestion(for: ramp, history: history(clean), audience: .adult, now: now))
        XCTAssertEqual(rampSuggestion.actions, [.setWeight(exerciseID: ramp.id, setID: ramp.sets[2].id, kg: 102.5)])

        // Straight sets (the common case) all change, including a plan of 0 kg from an imported template.
        let straight = entry(bench, Array(repeating: LoggedSet(weightKg: 0, reps: 5), count: 3).map {
            LoggedSet(weightKg: $0.weightKg, reps: $0.reps)
        })
        let all = try XCTUnwrap(CoachPlanner.suggestion(for: straight, history: history(clean), audience: .adult, now: now))
        XCTAssertEqual(all.actions.count, 3)
    }

    func testTheTopGroupIsFoundAmongPendingSetsOnly() throws {
        let clean = [session(3, 100, reps: [5], rir: [3]), session(10, 100, reps: [5], rir: [3])]
        // A warm-up at 100 kg and a drop set at 120 kg are not part of the working plan.
        let current = entry(bench, [
            LoggedSet(type: .warmup, weightKg: 100, reps: 5), LoggedSet(type: .drop, weightKg: 120, reps: 3),
            LoggedSet(weightKg: 90, reps: 5), LoggedSet(weightKg: 90, reps: 5),
        ])
        let suggestion = try XCTUnwrap(CoachPlanner.suggestion(for: current, history: history(clean), audience: .adult, now: now))
        XCTAssertEqual(suggestion.actions.count, 2)
        XCTAssertTrue(suggestion.actions.allSatisfy {
            if case let .setWeight(_, setID, _) = $0 { return setID == current.sets[2].id || setID == current.sets[3].id }
            return false
        })
    }

    // MARK: History is judged per workout

    func testAHeavyDayAndALightDayAreNotComparedWithEachOther() throws {
        // Upper A: 100 kg x 3, Upper B: 75 kg x 10, alternating. Judged together the engine only ever saw two different weights.
        var sessions: [ExerciseSession] = []
        for index in 0..<6 {
            if index % 2 == 0 {
                sessions.append(session(3 + index * 3, 100, reps: [3, 3, 3], rir: [3, 3, 3], name: "Upper A"))
            } else {
                sessions.append(session(3 + index * 3, 75, reps: [10, 10, 10], rir: [3, 3, 3], name: "Upper B"))
            }
        }
        let together = ProgressionEngine.recommend(for: bench, history: history(sessions), audience: .adult, now: now)
        XCTAssertEqual(together.verdict, .hold, "the unscoped history never progresses")

        let template = WorkoutTemplate(name: "Upper A", entries: [
            TemplateEntry(exercise: bench, plannedSets: [PlannedSet(weightKg: 100, reps: 3)], restSeconds: 150),
        ])
        let items = CoachPlanner.nextTime(
            for: template, exercise: { _ in nil }, history: { _ in self.history(sessions) }, audience: .adult, now: now
        )
        XCTAssertEqual(items.first?.recommendation.verdict, .progress)
        XCTAssertEqual(items.first?.recommendation.targetWeightKg, 102.5)
        XCTAssertEqual(items.first?.recommendation.targetReps, 3)

        // The running workout is scoped the same way.
        let current = entry(bench, [LoggedSet(weightKg: 100, reps: 3)])
        let suggestion = try XCTUnwrap(CoachPlanner.suggestion(
            for: current, history: history(sessions), workoutName: " upper a ", audience: .adult, now: now
        ))
        XCTAssertEqual(suggestion.recommendation.verdict, .progress)
    }

    func testAWorkoutNameWithTooFewSessionsFallsBackToTheWholeHistory() {
        let sessions = [session(3, 80, name: "Upper A"), session(10, 80, name: "Push day")]
        XCTAssertEqual(history(sessions).scoped(toWorkoutNamed: "Upper A", now: now).sessions.count, 2)
        XCTAssertEqual(history(sessions).scoped(toWorkoutNamed: nil, now: now).sessions.count, 2)
        XCTAssertEqual(history(sessions).scoped(toWorkoutNamed: "  ", now: now).sessions.count, 2)
        let more = sessions + [session(17, 80, name: "UPPER A")]
        XCTAssertEqual(history(more).scoped(toWorkoutNamed: "upper a", now: now).sessions.count, 2)
    }

    // MARK: Sessions must be close enough in time to count together

    func testTwoCleanSessionsSevenMonthsApartAreNotTwoCleanSessions() {
        let result = CoachFix.recommend(bench, [session(3, 80), session(210, 80)])
        XCTAssertEqual(result.verdict, .hold)
        XCTAssertEqual(result.targetWeightKg, 80)
        XCTAssertEqual(result.reasons, [.awaitingSecondCleanSession])
        XCTAssertEqual(result.sessionsUsed, 1)

        // The gap is measured between neighbours: 28 days is fine, 29 is not.
        XCTAssertEqual(CoachFix.recommend(bench, [session(3, 80), session(31, 80)]).verdict, .progress)
        XCTAssertEqual(CoachFix.recommend(bench, [session(3, 80), session(32, 80)]).verdict, .hold)
    }

    func testOnlyTheRecentRunOfSessionsDecidesTheOtherRules() {
        // Reps fell at one weight, but the three sessions are months apart: no reduce.
        let falling = [
            session(3, 80, reps: [4, 4, 4], rir: [0, 0, 0]),
            session(100, 80, reps: [5, 5, 5], rir: [0, 0, 0]),
            session(200, 80, reps: [6, 6, 6], rir: [0, 0, 0]),
        ]
        let result = CoachFix.recommend(bench, falling)
        XCTAssertEqual(result.verdict, .hold)
        XCTAssertEqual(result.reasons, [.awaitingSecondCleanSession])

        // Six increases a year apart each are not "six in a row".
        let loads: [Double] = [72.5, 70, 67.5, 65, 62.5, 60, 57.5]
        let slow = loads.enumerated().map { session(3 + $0.offset * 60, $0.element, rir: [2, 2, 2]) }
        XCTAssertEqual(CoachFix.recommend(bench, slow).verdict, .hold)
        XCTAssertFalse(CoachFix.recommend(bench, slow).reasons.contains(.lighterWeekDue))
    }

    // MARK: Dates that cannot be trusted

    func testASessionDatedInTheFutureIsIgnored() {
        // A Watch with the wrong clock logged a workout ten days from now; the real latest session is 200 days old.
        let future = session(-10, 80)
        let result = CoachFix.recommend(bench, [future, session(200, 80)])
        XCTAssertEqual(result.verdict, .insufficientData)
        XCTAssertEqual(result.reasons, [.tooFewSessions])
        XCTAssertEqual(result.sessionsUsed, 1)

        // A few hours of clock skew are tolerated.
        let skewed = ExerciseSession(
            id: UUID(), date: now.addingTimeInterval(3_600), workoutName: "Workout",
            sets: CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3]), isPersonalRecord: false
        )
        XCTAssertEqual(CoachFix.recommend(bench, [skewed, session(7, 80)]).verdict, .progress)
    }

    func testDatesThatAreNotNumbersCountAsABreakOrAreIgnored() {
        let nanNow = Date(timeIntervalSinceReferenceDate: .nan)
        let sessions = [session(3, 80), session(10, 80)]
        let result = ProgressionEngine.recommend(for: bench, history: history(sessions), audience: .adult, now: nanNow)
        XCTAssertEqual(result.verdict, .hold)
        XCTAssertEqual(result.reasons, [.returningAfterBreak])

        let brokenDate = ExerciseSession(
            id: UUID(), date: Date(timeIntervalSinceReferenceDate: .nan), workoutName: "Workout",
            sets: CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3]), isPersonalRecord: false
        )
        let ignored = CoachFix.recommend(bench, [brokenDate, session(3, 80), session(10, 80)])
        XCTAssertEqual(ignored.verdict, .progress)
        XCTAssertEqual(ignored.sessionsUsed, 2)
    }

    // MARK: Order and duplicates

    func testTheCallersOrderDoesNotMatterAndARepeatedSessionCountsOnce() {
        let newestFirst = [session(3, 80), session(10, 80), session(17, 80)]
        let forward = CoachFix.recommend(bench, newestFirst)
        XCTAssertEqual(CoachFix.recommend(bench, newestFirst.reversed()), forward)
        XCTAssertEqual(CoachFix.recommend(bench, [newestFirst[1], newestFirst[2], newestFirst[0]]), forward)

        let shared = UUID()
        let twice = [session(3, 80, id: shared), session(3, 80, id: shared)]
        let result = CoachFix.recommend(bench, twice)
        XCTAssertEqual(result.verdict, .insufficientData)
        XCTAssertEqual(result.sessionsUsed, 1)
    }

    // MARK: Effort

    func testAToFailureSetIsAtRepsInReserveZeroWhateverValueWasStored() {
        // The set was changed to "to failure" after RIR 4 was picked; the stored value must not win.
        func failureSession(_ daysAgo: Int) -> ExerciseSession {
            ExerciseSession(
                id: UUID(), date: CoachFix.date(daysAgo: daysAgo), workoutName: "Workout",
                sets: (0..<3).map { _ in CoachFix.set(80, 6, 4, type: .failure) }, isPersonalRecord: false
            )
        }
        let result = CoachFix.recommend(bench, [failureSession(3), failureSession(10)])
        XCTAssertEqual(result.verdict, .hold)
        XCTAssertEqual(result.reasons, [.lastSessionNearFailure])
    }

    func testMostSetsMustHaveRepsToSpareNotJustTheMean() {
        func verdict(_ rir: [Int?], previous: [Int?]? = nil) -> (Verdict, [ReasonCode]) {
            let result = CoachFix.recommend(bench, [session(3, 80, rir: rir), session(10, 80, rir: previous ?? rir)])
            return (result.verdict, result.reasons)
        }
        // Mean 2.0, but two of three sets at RIR 1: not comfortable.
        XCTAssertEqual(verdict([4, 1, 1]).0, .hold)
        XCTAssertEqual(verdict([4, 1, 1]).1, [.moderateEffort])
        // The usual fatigue gradient passes: two thirds of the sets have 2 or more.
        XCTAssertEqual(verdict([3, 2, 1]).0, .progress)
        // Four sets: mean 2.25, only half have 2 or more.
        XCTAssertEqual(CoachFix.recommend(bench, [
            session(3, 80, reps: [6, 6, 6, 6], rir: [4, 4, 1, 0]), session(10, 80, reps: [6, 6, 6, 6], rir: [4, 4, 1, 0]),
        ]).verdict, .hold)
        // The rule applies to the earlier session as well.
        let earlier = verdict([3, 3, 3], previous: [4, 1, 1])
        XCTAssertEqual(earlier.0, .hold)
        XCTAssertEqual(earlier.1, [.awaitingSecondCleanSession])
    }

    func testALighterWeekNeedsEffortDataBelowTheLimit() {
        let loads: [Double] = [72.5, 70, 67.5, 65, 62.5, 60, 57.5]
        func rising(rir: [Int?]) -> [ExerciseSession] {
            loads.enumerated().map { session(3 + $0.offset * 7, $0.element, rir: rir) }
        }
        XCTAssertEqual(CoachFix.recommend(bench, rising(rir: [2, 2, 2])).verdict, .reduce)
        XCTAssertEqual(CoachFix.recommend(bench, rising(rir: [3, 3, 3])).verdict, .hold)
        // No effort data: the engine asks for it instead of reducing.
        XCTAssertEqual(CoachFix.recommend(bench, rising(rir: [nil, nil, nil])).verdict, .noEffortData)
    }

    // MARK: Typos

    func testTwoSessionsFarApartInStrengthAreNotGuessedAt() {
        // The latest session has an extra "800 kg" set, a typo for 80. With two sessions there is nothing to say which is right.
        let typo = ExerciseSession(
            id: UUID(), date: CoachFix.date(daysAgo: 3), workoutName: "Workout",
            sets: CoachFix.sets(80, [6, 6, 6], rir: [3, 3, 3]) + [CoachFix.set(800, 6, 3)], isPersonalRecord: false
        )
        let result = CoachFix.recommend(bench, [typo, session(10, 80)])
        XCTAssertEqual(result.verdict, .insufficientData)
        XCTAssertEqual(result.reasons, [.suspectSetExcluded])
        XCTAssertNil(result.targetWeightKg)

        // Two sessions that are close in strength are fine.
        XCTAssertEqual(CoachFix.recommend(bench, [session(3, 82.5), session(10, 80)]).verdict, .hold)
    }

    func testSteadyProgressIsNotMistakenForATypo() {
        // +5 kg every session for six sessions: the median lags, but each session is close to the one before it.
        let loads: [Double] = [60, 55, 50, 45, 40, 35]
        let sessions = loads.enumerated().map { session(3 + $0.offset * 3, $0.element, reps: [5, 5, 5]) }
        let result = CoachFix.recommend(CoachFix.lib("squat"), sessions)
        XCTAssertEqual(result.verdict, .hold)
        XCTAssertEqual(result.targetWeightKg, 60, "the newest session is the latest, not 55")
        XCTAssertFalse(result.reasons.contains(.suspectSetExcluded))
    }

    func testASingleDoubledSetIsStillAnOutlier() {
        // Five light sessions and, right after them, one set at double the weight among normal ones: a typo, ignored.
        let typo = ExerciseSession(
            id: UUID(), date: CoachFix.date(daysAgo: 3), workoutName: "Workout",
            sets: CoachFix.sets(50, [6, 6], rir: [3, 3]) + [CoachFix.set(100, 6, 3)], isPersonalRecord: false
        )
        let sessions = [typo] + (1...5).map { session(3 + $0 * 7, 50) }
        let result = CoachFix.recommend(bench, sessions)
        XCTAssertTrue(result.reasons.contains(.suspectSetExcluded))
        XCTAssertEqual(result.verdict, .progress, "judged on the two normal sets, which match the session before")
        XCTAssertEqual(result.targetWeightKg, 52.5)
    }

    func testAWholeSessionAtADoubledWeightIsKeptBecauseItsSetsAgree() {
        // A beginner moves from the empty bar to a working weight: three sets that agree with each other are not three typos.
        let sessions = [session(3, 40, reps: [5, 5, 5])] + (1...3).map { session(3 + $0 * 3, 20, reps: [5, 5, 5], rir: [4, 4, 4]) }
        let result = CoachFix.recommend(CoachFix.lib("squat"), sessions)
        XCTAssertFalse(result.reasons.contains(.suspectSetExcluded))
        XCTAssertEqual(result.verdict, .hold)
        XCTAssertEqual(result.targetWeightKg, 40, "what the person lifted yesterday, not the light sessions before it")
        XCTAssertEqual(result.reasons, [.awaitingSecondCleanSession])
    }

    // MARK: Words

    func testTheSentenceNamesTheThresholdThatIsInForce() {
        var config = CoachConfig()
        config.progressMinimumRIR = 3
        let progress = Recommendation(exerciseID: "bench", verdict: .progress, targetWeightKg: 82.5, targetReps: 6)
        XCTAssertEqual(TemplateWriter.line(for: progress, config: config)?.detail, "Two clean sessions at RIR 3 or more.")
        XCTAssertEqual(TemplateWriter.line(for: progress)?.detail, "Two clean sessions at RIR 2 or more.")
        config.progressMinimumRIR = 2.5
        let hold = Recommendation(exerciseID: "bench", verdict: .hold, targetWeightKg: 80, targetReps: 6, reasons: [.moderateEffort])
        XCTAssertEqual(TemplateWriter.line(for: hold, config: config)?.detail, "Move up once most sets feel easier (RIR 2.5 or more).")
    }

    func testThePlannerPassesTheConfigurationToTheWriter() throws {
        var config = CoachConfig()
        config.progressMinimumRIR = 3
        let sessions = [session(3, 80), session(10, 80)]
        let current = entry(bench, [LoggedSet(weightKg: 80, reps: 6)])
        let suggestion = try XCTUnwrap(CoachPlanner.suggestion(for: current, history: history(sessions), audience: .adult, config: config, now: now))
        XCTAssertEqual(suggestion.line.detail, "Two clean sessions at RIR 3 or more.")
    }

    func testAHoldAtTheRepLimitSaysWhy() {
        // 8 kg dumbbell raises at 30 reps for two sessions: the next 2 kg step is a 25 % jump, and reps cannot go past 30.
        let sessions = [session(3, 8, reps: [30, 30, 30]), session(10, 8, reps: [30, 30, 30])]
        let result = CoachFix.recommend(lateral, sessions)
        XCTAssertEqual(result.verdict, .hold)
        XCTAssertEqual(result.reasons, [.cleanSessionsWithReserve, .stepExceedsCap])
        let line = TemplateWriter.line(for: result)
        XCTAssertEqual(line?.headline, "Stay at 8 kg × 30")
        XCTAssertNotNil(line?.detail)
    }

    // MARK: Planner limits

    func testALimitOfZeroOrLessReturnsNothingEvenWithAHint() {
        let plain = [session(3, 80, rir: [nil, nil, nil]), session(10, 80, rir: [nil, nil, nil])]
        let clean = [session(3, 80), session(10, 80)]
        let squat = CoachFix.lib("squat")
        let template = WorkoutTemplate(name: "T", entries: [
            TemplateEntry(exercise: bench, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90),
            TemplateEntry(exercise: squat, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90),
        ])
        func items(limit: Int) -> [NextTimeItem] {
            CoachPlanner.nextTime(
                for: template, exercise: { _ in nil },
                history: { $0 == "bench" ? self.history(clean) : CoachFix.history(squat, plain) },
                audience: .adult, now: now, limit: limit
            )
        }
        XCTAssertEqual(items(limit: 3).map { $0.recommendation.exerciseID }, ["bench"])
        XCTAssertEqual(items(limit: 1).map { $0.recommendation.exerciseID }, ["bench"])
        XCTAssertTrue(items(limit: 0).isEmpty)
        XCTAssertTrue(items(limit: -4).isEmpty)
    }

    func testTheTemplateIsNotScannedOnceTheLimitIsReached() {
        let ids = ["bench", "squat", "ohp", "deadlift", "curl", "row"]
        var entries: [TemplateEntry] = []
        var histories: [String: ExerciseHistory] = [:]
        for id in ids {
            guard let exercise = ExerciseLibrary.exercise(id: id) else { continue }
            entries.append(TemplateEntry(exercise: exercise, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90))
            histories[id] = CoachFix.history(exercise, [session(3, 80), session(10, 80)])
        }
        let template = WorkoutTemplate(name: "T", entries: entries)
        var lookups = 0
        let items = CoachPlanner.nextTime(
            for: template, exercise: { _ in nil }, history: { lookups += 1; return histories[$0]! }, audience: .adult, now: now, limit: 2
        )
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(lookups, 2, "the rest of the template is never looked at")
    }

    // MARK: Hub note and audience

    private func chestTemplate() -> WorkoutTemplate {
        var chest = bench
        chest.previousBestE1RM = 99
        return WorkoutTemplate(name: "Push", entries: [
            TemplateEntry(exercise: chest, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90),
        ])
    }

    func testTheHubSentenceFollowsTheAudience() {
        let template = chestTemplate()
        func note(_ audience: AudienceProfile, recovery: RecoveryProvider? = nil, includeTarget: Bool = true) -> String? {
            HubNoteBuilder.message(
                template: template, exercise: { _ in nil }, recovery: recovery, audience: audience, includeTarget: includeTarget
            )
        }
        XCTAssertEqual(note(.adult), "Aim for 85 kg × 6 on your last bench press set.")
        XCTAssertEqual(note(.unknown), "Aim for 85 kg × 6 on your last bench press set.")
        XCTAssertNil(note(AudienceProfile(ageGroup: .minor)))
        XCTAssertNil(note(AudienceProfile(ageGroup: .adult, avoidMuscles: [.chest])))
        // Another muscle being avoided changes nothing here.
        XCTAssertNotNil(note(AudienceProfile(ageGroup: .adult, avoidMuscles: [.legs])))
        // The caller turns the sentence off when the Next-time lines already say what to lift.
        XCTAssertNil(note(.adult, includeTarget: false))
    }

    func testTheReadinessSentenceDoesNotNameAnAvoidedMuscle() {
        var shoulderPress = CoachFix.lib("ohp")
        shoulderPress.previousBestE1RM = 0
        var chest = bench
        chest.previousBestE1RM = 0
        let template = WorkoutTemplate(name: "Push", entries: [
            TemplateEntry(exercise: chest, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90),
            TemplateEntry(exercise: shoulderPress, plannedSets: [PlannedSet(weightKg: 40, reps: 8)], restSeconds: 90),
        ])
        let recovered: RecoveryProvider = { _ in 100 }
        XCTAssertEqual(
            HubNoteBuilder.message(template: template, exercise: { _ in nil }, recovery: recovered, audience: .adult),
            "Chest and shoulders are recovered."
        )
        XCTAssertEqual(
            HubNoteBuilder.message(
                template: template, exercise: { _ in nil }, recovery: recovered,
                audience: AudienceProfile(ageGroup: .adult, avoidMuscles: [.chest])
            ),
            "Shoulders are recovered."
        )
        XCTAssertNil(HubNoteBuilder.message(
            template: template, exercise: { _ in nil }, recovery: recovered,
            audience: AudienceProfile(ageGroup: .adult, avoidMuscles: [.chest, .shoulders])
        ))
    }

    func testTheHubSentenceIsNotBuiltFromAbsurdFigures() {
        var damaged = bench
        damaged.previousBestE1RM = 1_000_000
        func template(reps: Int, exercise: Exercise) -> WorkoutTemplate {
            WorkoutTemplate(name: "T", entries: [
                TemplateEntry(exercise: exercise, plannedSets: [PlannedSet(weightKg: 80, reps: reps)], restSeconds: 90),
            ])
        }
        XCTAssertNil(HubNoteBuilder.message(template: template(reps: 6, exercise: damaged), exercise: { _ in nil }, recovery: nil))
        var fine = bench
        fine.previousBestE1RM = 99
        XCTAssertNil(HubNoteBuilder.message(template: template(reps: 1_000, exercise: fine), exercise: { _ in nil }, recovery: nil))
        XCTAssertNotNil(HubNoteBuilder.message(template: template(reps: 999, exercise: fine), exercise: { _ in nil }, recovery: nil))
    }

    func testAnExerciseWithoutANameStillGivesASentence() {
        var nameless = bench
        nameless.name = ""
        nameless.previousBestE1RM = 99
        let template = WorkoutTemplate(name: "T", entries: [
            TemplateEntry(exercise: nameless, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90),
        ])
        XCTAssertEqual(
            HubNoteBuilder.message(template: template, exercise: { _ in nil }, recovery: nil),
            "Aim for 85 kg × 6 on your last set."
        )
    }

    func testThePersonalRecordTipFollowsTheAudienceAndTheMuscle() {
        XCTAssertTrue(AudienceProfile.adult.allowsPersonalRecordTip(for: .chest))
        XCTAssertTrue(AudienceProfile.unknown.allowsPersonalRecordTip(for: .chest))
        XCTAssertFalse(AudienceProfile(ageGroup: .minor).allowsPersonalRecordTip(for: .chest))
        let avoiding = AudienceProfile(ageGroup: .adult, avoidMuscles: [.legs])
        XCTAssertFalse(avoiding.allowsPersonalRecordTip(for: .legs))
        XCTAssertTrue(avoiding.allowsPersonalRecordTip(for: .chest))
    }

    // MARK: Configuration

    func testTheDefaultConfigurationIsValidAndABrokenOneSilencesTheCoach() {
        XCTAssertTrue(CoachConfig().isValid)
        let sessions = [session(3, 80), session(10, 80)]
        XCTAssertEqual(CoachFix.recommend(bench, sessions).verdict, .progress)

        func broken(_ change: (inout CoachConfig) -> Void) -> Recommendation {
            var config = CoachConfig()
            change(&config)
            XCTAssertFalse(config.isValid)
            return CoachFix.recommend(bench, sessions, config: config)
        }
        let results = [
            broken { $0.maximumJumpFraction = .nan },
            broken { $0.maximumJumpFractionRestricted = 0 },
            broken { $0.reduceFraction = -0.1 },
            broken { $0.maximumReduceFraction = .infinity },
            broken { $0.effortCoverage = 1.5 },
            broken { $0.comfortableSetShare = 0 },
            broken { $0.suspectRatio = 1 },
            broken { $0.progressMinimumRIR = .nan },
            broken { $0.holdMaximumRIR = -1 },
            broken { $0.lighterWeekMaximumRIR = .nan },
            broken { $0.repsFallTolerance = -0.5 },
        ]
        for result in results {
            XCTAssertEqual(result.verdict, .insufficientData)
            XCTAssertEqual(result.reasons, [.invalidConfiguration])
        }

        // Odd but harmless values stay valid: the engine already copes with them.
        var odd = CoachConfig()
        odd.minimumSessions = Int.min
        odd.lighterWeekAfterIncreases = -3
        odd.breakDays = 0
        odd.maximumTargetReps = 0
        odd.incrementsKg = [:]
        XCTAssertTrue(odd.isValid)
    }
}
