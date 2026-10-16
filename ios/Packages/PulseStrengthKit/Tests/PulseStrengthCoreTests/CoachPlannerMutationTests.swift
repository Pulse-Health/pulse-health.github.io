import XCTest
@testable import PulseStrengthCore

/// Tests written after mutation-testing `CoachPlanner`, `TemplateWriter`, `HubNoteBuilder`, `TargetWeight` and the
/// `WorkoutController.isUsingDemoRecovery` flag: each one pins behaviour that a small change to the source (a dropped argument,
/// a swapped priority, a moved boundary) did not break in `CoachPlannerTests`, `HubNoteTests` or the presenter tests.
///
/// Mutants that cannot be killed because they do not change behaviour (and are therefore not tested):
/// * `CoachPlanner`: dropping the `!set.isDone` filter, because a suggestion is only built when no set is done yet, and dropping the
///   `tracksWeight` guard, because the engine already answers `insufficientData` (no line) for every other tracking kind.
/// * `HubNoteBuilder`: dropping the 0...100 clamp of the recovery value (the comparison `< 60` gives the same answer), and
///   `planned.reps >= 0` or `previousBestE1RM >= 0` (`TargetWeight` refuses reps 0 and a baseline 0 anyway).
/// * `TargetWeight`: dropping `step.isFinite` (an infinite step never beats anything), dropping the downward correction loop (the
///   upward loop and the start from the ceiling already find the lowest weight), dropping the final check or the `max(1, ...)` clamp
///   (neither can be reached with a baseline above 0).
final class CoachPlannerMutationTests: XCTestCase {
    private let now = CoachFix.now

    private func cleanHistory(_ exercise: Exercise, kg: Double, reps: Int = 6) -> ExerciseHistory {
        let sets = CoachFix.sets(kg, [reps, reps, reps], rir: [3, 3, 3])
        return CoachFix.history(exercise, [CoachFix.session(3, sets), CoachFix.session(10, sets)])
    }

    private func entry(_ exercise: Exercise, _ sets: [LoggedSet]) -> WorkoutExercise {
        WorkoutExercise(exercise: exercise, sets: sets, restSeconds: 90)
    }

    // MARK: nextTime

    func testTheDefaultLimitIsThreeLines() {
        let ids = ["bench", "squat", "ohp", "deadlift", "curl"]
        var histories: [String: ExerciseHistory] = [:]
        var entries: [TemplateEntry] = []
        for id in ids {
            let exercise = CoachFix.lib(id)
            histories[id] = cleanHistory(exercise, kg: 80)
            entries.append(TemplateEntry(exercise: exercise, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90))
        }
        let template = WorkoutTemplate(name: "Five", entries: entries)
        let items = CoachPlanner.nextTime(for: template, exercise: { _ in nil }, history: { histories[$0]! }, now: now)
        XCTAssertEqual(items.map { $0.recommendation.exerciseID }, ["bench", "squat", "ohp"])
    }

    func testTheLiveExerciseIsUsedNotTheTemplatesCopy() {
        let bench = CoachFix.lib("bench")
        var live = bench
        live.name = "Renamed bench press"
        let template = WorkoutTemplate(name: "T", entries: [
            TemplateEntry(exercise: bench, plannedSets: [PlannedSet(weightKg: 80, reps: 6)], restSeconds: 90),
        ])
        let history = cleanHistory(bench, kg: 80)
        let items = CoachPlanner.nextTime(
            for: template, exercise: { $0 == "bench" ? live : nil }, history: { _ in history }, audience: .adult, now: now
        )
        XCTAssertEqual(items.first?.exerciseName, "Renamed bench press")

        // The live definition decides which muscle is avoided, too.
        var legs = bench
        legs.muscle = .legs
        let avoided = CoachPlanner.nextTime(
            for: template, exercise: { _ in legs }, history: { _ in history },
            audience: AudienceProfile(ageGroup: .adult, avoidMuscles: [.legs]), now: now
        )
        XCTAssertTrue(avoided.isEmpty)
    }

    func testNextTimeFollowsTheAudienceTheConfigurationAndTheDate() {
        let crossover = CoachFix.lib("crossover")
        let history = cleanHistory(crossover, kg: 40, reps: 10)
        let template = WorkoutTemplate(name: "T", entries: [
            TemplateEntry(exercise: crossover, plannedSets: [PlannedSet(weightKg: 40, reps: 10)], restSeconds: 60),
        ])
        func verdict(audience: AudienceProfile = .adult, config: CoachConfig = CoachConfig(), at date: Date? = nil) -> Verdict? {
            CoachPlanner.nextTime(
                for: template, exercise: { _ in nil }, history: { _ in history },
                audience: audience, config: config, now: date ?? self.now
            ).first?.recommendation.verdict
        }
        XCTAssertEqual(verdict(), .progress)
        XCTAssertEqual(verdict(audience: .unknown), .addRep, "an unknown audience gets the smaller jump cap")

        var strict = CoachConfig()
        strict.maximumJumpFraction = 0.01
        XCTAssertEqual(verdict(config: strict), .addRep, "the configuration is passed to the engine")

        XCTAssertEqual(verdict(at: now.addingTimeInterval(60 * 86_400)), .hold, "60 days later it is a break")
    }

    // MARK: suggestion

    func testSuggestionFollowsTheAudienceTheConfigurationAndTheDate() {
        let crossover = CoachFix.lib("crossover")
        let history = cleanHistory(crossover, kg: 40, reps: 10)
        // Sets that differ from every possible target, so a suggestion always has something to apply.
        let current = entry(crossover, [LoggedSet(weightKg: 35, reps: 8), LoggedSet(weightKg: 35, reps: 8)])
        func verdict(audience: AudienceProfile = .adult, config: CoachConfig = CoachConfig(), at date: Date? = nil) -> Verdict? {
            CoachPlanner.suggestion(for: current, history: history, audience: audience, config: config, now: date ?? self.now)?
                .recommendation.verdict
        }
        XCTAssertEqual(verdict(), .progress)
        XCTAssertEqual(verdict(audience: .unknown), .addRep)

        var strict = CoachConfig()
        strict.maximumJumpFraction = 0.01
        XCTAssertEqual(verdict(config: strict), .addRep)

        XCTAssertEqual(verdict(at: now.addingTimeInterval(60 * 86_400)), .hold, "60 days later it is a break")
        // After a break the person is told what they did last time and to ease back in, whether or not the sets match: a line without
        // an Apply button, so the plan is never raised to the old weight.
        let matching = entry(crossover, [LoggedSet(weightKg: 40, reps: 10), LoggedSet(weightKg: 40, reps: 10)])
        let later = now.addingTimeInterval(60 * 86_400)
        let note = CoachPlanner.suggestion(for: matching, history: history, audience: .adult, now: later)
        XCTAssertEqual(note?.line.headline, "Last time: 40 kg × 10")
        XCTAssertEqual(note?.actions, [])
        XCTAssertEqual(CoachPlanner.suggestion(for: current, history: history, audience: .adult, now: later)?.actions, [])
    }

    func testApplyTouchesOnlyPendingNormalSetsAndNeverDropOrFailureSets() throws {
        let bench = CoachFix.lib("bench")
        let sets = [
            LoggedSet(type: .normal, weightKg: 80, reps: 6),
            LoggedSet(type: .drop, weightKg: 60, reps: 10),
            LoggedSet(type: .failure, weightKg: 80, reps: 6),
            LoggedSet(type: .normal, weightKg: 80, reps: 6),
        ]
        let suggestion = try XCTUnwrap(CoachPlanner.suggestion(for: entry(bench, sets), history: cleanHistory(bench, kg: 80), audience: .adult, now: now))
        let touched = suggestion.actions.compactMap { action -> UUID? in
            switch action {
            case let .setWeight(_, setID, _): return setID
            case let .setReps(_, setID, _): return setID
            default: return nil
            }
        }
        XCTAssertEqual(Set(touched), [sets[0].id, sets[3].id])
    }

    func testApplySetsTheWeightBeforeTheRepsOfEachSetAndTouchesBothWhenBothDiffer() throws {
        let bench = CoachFix.lib("bench")
        let only = LoggedSet(type: .normal, weightKg: 80, reps: 8)
        let current = entry(bench, [only])
        let suggestion = try XCTUnwrap(CoachPlanner.suggestion(for: current, history: cleanHistory(bench, kg: 80), audience: .adult, now: now))
        XCTAssertEqual(suggestion.actions, [
            .setWeight(exerciseID: current.id, setID: only.id, kg: 82.5),
            .setReps(exerciseID: current.id, setID: only.id, reps: 6),
        ])
    }

    func testApplyLowersTheRepsOfASetThatIsAboveTheTargetToo() throws {
        let bench = CoachFix.lib("bench")
        // Weight already right, reps above the target: the suggestion says "× 6", so Apply sets 6.
        let high = LoggedSet(type: .normal, weightKg: 82.5, reps: 10)
        let current = entry(bench, [high])
        let suggestion = try XCTUnwrap(CoachPlanner.suggestion(for: current, history: cleanHistory(bench, kg: 80), audience: .adult, now: now))
        XCTAssertEqual(suggestion.actions, [.setReps(exerciseID: current.id, setID: high.id, reps: 6)])
    }

    func testTheWeightToleranceIsHalfAHundredthOfAKilo() throws {
        let bench = CoachFix.lib("bench")
        let history = cleanHistory(bench, kg: 80)
        // 82.49 is a hundredth away from the target 82.5: a real difference, so Apply sets it.
        let off = LoggedSet(type: .normal, weightKg: 82.49, reps: 6)
        let current = entry(bench, [off])
        let suggestion = try XCTUnwrap(CoachPlanner.suggestion(for: current, history: history, audience: .adult, now: now))
        XCTAssertEqual(suggestion.actions, [.setWeight(exerciseID: current.id, setID: off.id, kg: 82.5)])

        // A billionth away is the same weight: nothing to apply, no suggestion.
        let same = entry(bench, [LoggedSet(type: .normal, weightKg: 82.5 + 1e-9, reps: 6)])
        XCTAssertNil(CoachPlanner.suggestion(for: same, history: history, audience: .adult, now: now))
    }

    func testNothingIsSuggestedOnceASetIsLoggedEvenIfMostAreStillPending() {
        let bench = CoachFix.lib("bench")
        let sets = [LoggedSet(weightKg: 80, reps: 6, isDone: true), LoggedSet(weightKg: 80, reps: 6), LoggedSet(weightKg: 80, reps: 6)]
        XCTAssertNil(CoachPlanner.suggestion(for: entry(bench, sets), history: cleanHistory(bench, kg: 80), audience: .adult, now: now))
    }

    // MARK: TemplateWriter

    func testTheNoEffortHintHasItsExplanation() {
        let line = TemplateWriter.line(for: Recommendation(exerciseID: "bench", verdict: .noEffortData))
        XCTAssertEqual(line?.detail, "Then this lift can get a suggestion.")
        XCTAssertEqual(line?.sentence, "Log RIR on your sets. Then this lift can get a suggestion.")
    }

    func testASentenceWithoutADetailIsJustTheHeadline() {
        XCTAssertEqual(CoachLine(headline: "82.5 kg × 6").sentence, "82.5 kg × 6")
        XCTAssertEqual(CoachLine(headline: "82.5 kg × 6", detail: "").sentence, "82.5 kg × 6")
        XCTAssertEqual(CoachLine(headline: "A", detail: "B").sentence, "A. B")
    }

    func testWhenSeveralReasonsApplyTheHoldTextFollowsTheDocumentedPriority() {
        func detail(_ reasons: [ReasonCode]) -> String? {
            TemplateWriter.line(for: Recommendation(
                exerciseID: "bench", verdict: .hold, targetWeightKg: 80, targetReps: 6, reasons: reasons
            ))?.detail
        }
        let breakText = "It has been a while since your last session, so ease back in."
        let failureText = "Last session ended close to failure."
        let droppingText = "Reps have been dropping at this weight."
        let waitingText = "One more clean session at this weight before moving up."
        let moderateText = "Move up once most sets feel easier (RIR 2 or more)."

        XCTAssertEqual(detail([.lastSessionNearFailure, .returningAfterBreak]), breakText)
        XCTAssertEqual(detail([.returningAfterBreak, .lastSessionNearFailure]), breakText)
        XCTAssertEqual(detail([.repsFellAtSameLoad, .lastSessionNearFailure]), failureText)
        XCTAssertEqual(detail([.awaitingSecondCleanSession, .repsFellAtSameLoad]), droppingText)
        XCTAssertEqual(detail([.moderateEffort, .awaitingSecondCleanSession]), waitingText)
        XCTAssertEqual(detail([.moderateEffort]), moderateText)
        XCTAssertNil(detail([]))
    }

    // MARK: TargetWeight limits

    func testTheLargestAnswerIsJustUnderABillionSteps() {
        // reps 30 doubles the estimate, so the answer is about (baseline + 0.05) / 2 steps of 1 kg.
        let justUnder = TargetWeight.lowestBeating(baseline: 1_999_999_996.95, reps: 30, step: 1)
        XCTAssertEqual(justUnder, 999_999_999)
        // Exactly a billion steps is already refused, and so is anything larger.
        XCTAssertNil(TargetWeight.lowestBeating(baseline: 1_999_999_998.95, reps: 30, step: 1))
        XCTAssertNil(TargetWeight.lowestBeating(baseline: 10_000_000_000, reps: 30, step: 1))
    }
}

#if canImport(Combine) || PULSE_COMBINE_SHIM
/// `WorkoutController.isUsingDemoRecovery` decides whether the hub may say "Chest is recovered". It had no test: all four
/// mutations of the flag survived. These run on Apple platforms and, with -DPULSE_COMBINE_SHIM, on Linux.
final class CoachDemoRecoveryFlagTests: XCTestCase {
    func testTheDefaultRecoveryIsDemoData() {
        svcMain {
            let controller = WorkoutController(store: StrengthStore(persistence: nil), persistence: nil)
            XCTAssertTrue(controller.isUsingDemoRecovery)
            XCTAssertEqual(controller.recovery(.chest), 88, "the demo constants")
        }
    }

    func testPassingARecoveryModelClearsTheFlag() {
        svcMain {
            let controller = WorkoutController(store: StrengthStore(persistence: nil), persistence: nil, recovery: { _ in 70 })
            XCTAssertFalse(controller.isUsingDemoRecovery)
            XCTAssertEqual(controller.recovery(.chest), 70)
        }
    }

    func testAssigningARecoveryModelLaterClearsTheFlag() {
        svcMain {
            let controller = WorkoutController(store: StrengthStore(persistence: nil), persistence: nil)
            XCTAssertTrue(controller.isUsingDemoRecovery)
            controller.recovery = { _ in 55 }
            XCTAssertFalse(controller.isUsingDemoRecovery)
            XCTAssertEqual(controller.recovery(.legs), 55)
        }
    }

    func testAMirrorControllerFollowsTheSameRule() {
        svcMain {
            let mirror = WorkoutController(store: StrengthStore(persistence: nil), persistence: nil, role: .mirror)
            XCTAssertTrue(mirror.isUsingDemoRecovery)
        }
    }
}
#endif
