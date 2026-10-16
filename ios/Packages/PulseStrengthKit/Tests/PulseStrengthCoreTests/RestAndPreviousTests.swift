import XCTest
@testable import PulseStrengthCore

// MARK: - Rest after a set, by set type

final class RestRulesTests: XCTestCase {
    private let types = SetType.allCases

    func testEveryTypeFollowedByEveryTypeAndByNothing() {
        // The expectation is written out per case: the exercise's rest is 120 s, a warm-up rests 40 % of it (48 s -> 50 s).
        let warmupRest = 50
        for current in types {
            for next in types + [nil] {
                let sets = [current] + (next.map { [$0] } ?? [])
                let expected: Int
                switch current {
                case .normal, .failure: expected = 120
                case .warmup: expected = warmupRest
                case .drop: expected = next == .drop ? 0 : 120
                }
                XCTAssertEqual(
                    RestRules.seconds(afterSetAt: 0, types: sets, exerciseRest: 120), expected,
                    "\(current) followed by \(next.map { "\($0)" } ?? "nothing")"
                )
            }
        }
    }

    func testOnlyTheNextSetOfTheSameExerciseCounts() {
        XCTAssertEqual(RestRules.seconds(afterSetAt: 0, types: [.drop, .drop, .normal], exerciseRest: 90), 0, "a drop before a drop: no rest")
        XCTAssertEqual(RestRules.seconds(afterSetAt: 1, types: [.drop, .drop, .normal], exerciseRest: 90), 90, "a drop before a normal set rests in full")
        XCTAssertEqual(RestRules.seconds(afterSetAt: 2, types: [.drop, .drop, .drop], exerciseRest: 90), 90, "the last drop set rests in full")
        XCTAssertEqual(RestRules.seconds(afterSetAt: 0, types: [.drop, .normal, .drop], exerciseRest: 90), 90)
        XCTAssertEqual(RestRules.seconds(afterSetAt: 0, types: [.drop], exerciseRest: 90), 90, "the last set of an exercise")
        XCTAssertEqual(RestRules.seconds(afterSetAt: 0, types: [.normal, .drop, .drop], exerciseRest: 90), 90, "a normal set before drops rests in full")
        XCTAssertEqual(RestRules.seconds(afterSetAt: 0, types: [.warmup, .drop], exerciseRest: 90), 35, "a warm-up keeps its own rule")
    }

    func testTheWarmUpRuleRoundsToFiveSecondsWithAFloorOfThirty() {
        func warmup(_ rest: Int) -> Int { RestRules.seconds(afterSetAt: 0, types: [.warmup], exerciseRest: rest) }
        XCTAssertEqual(warmup(150), 60)
        XCTAssertEqual(warmup(100), 40)
        XCTAssertEqual(warmup(90), 35)
        XCTAssertEqual(warmup(60), 30, "24 s is raised to 30 s")
        XCTAssertEqual(warmup(45), 30)
        XCTAssertEqual(warmup(1), 30, "any timer that is on gives a warm-up at least 30 s")
        XCTAssertEqual(warmup(600), 240)
        XCTAssertEqual(warmup(3_600), 1_440)
    }

    func testARestOfZeroTurnsTheTimerOffForEveryType() {
        for current in types {
            XCTAssertEqual(RestRules.seconds(afterSetAt: 0, types: [current, .normal], exerciseRest: 0), 0, "\(current)")
        }
    }

    func testOutOfRangeInputsNeverTrapAndCountAsTheNearestValue() {
        XCTAssertEqual(RestRules.seconds(afterSetAt: 0, types: [.normal], exerciseRest: -30), 0)
        XCTAssertEqual(RestRules.seconds(afterSetAt: 0, types: [.normal], exerciseRest: Int.max), WorkoutReducer.maximumRestSeconds)
        XCTAssertEqual(RestRules.seconds(afterSetAt: 0, types: [.warmup], exerciseRest: Int.max), 1_440)
        XCTAssertEqual(RestRules.seconds(afterSetAt: 0, types: [.normal], exerciseRest: Int.min), 0)
        XCTAssertEqual(RestRules.seconds(afterSetAt: -1, types: [.drop, .drop], exerciseRest: 60), 60, "an index outside the sets counts as a normal set")
        XCTAssertEqual(RestRules.seconds(afterSetAt: 5, types: [.drop, .drop], exerciseRest: 60), 60)
        XCTAssertEqual(RestRules.seconds(afterSetAt: Int.max, types: [], exerciseRest: 60), 60)
        XCTAssertEqual(RestRules.seconds(afterSetAt: 0, types: [], exerciseRest: 60), 60)
    }

    // MARK: Through the reducer

    private func dropWorkout(_ types: [SetType], rest: Int = 90) -> WorkoutState {
        RFix.state([RFix.entry(1, RFix.bench, types.map { ($0, 60, 8) }, rest: rest)])
    }

    func testTheReducerStartsNoRestBetweenDropSets() {
        var s = dropWorkout([.normal, .drop, .drop, .normal])
        s = RFix.reduced(s, RFix.log(s, 0, 0), at: 1)
        XCTAssertEqual(s.rest?.totalSeconds, 90, "a normal set before the drops")
        s = RFix.reduced(s, RFix.log(s, 0, 1), at: 2)
        XCTAssertNil(s.rest, "the first drop is followed by the second: the running rest ends and none starts")
        s = RFix.reduced(s, RFix.log(s, 0, 2), at: 3)
        XCTAssertEqual(s.rest, RestState(endsAt: RFix.at(93), totalSeconds: 90), "the last drop set rests in full")
    }

    func testTheLastSetOfAnExerciseRestsEvenAsADropSet() {
        var s = dropWorkout([.drop])
        s = RFix.reduced(s, RFix.log(s, 0, 0), at: 1)
        XCTAssertEqual(s.rest?.totalSeconds, 90)
    }

    func testFailureSetsRestInFull() {
        var s = dropWorkout([.failure, .failure])
        s = RFix.reduced(s, RFix.log(s, 0, 0), at: 1)
        XCTAssertEqual(s.rest?.totalSeconds, 90)
    }

    func testTheTypeAtTheMomentOfLoggingDecides() {
        var s = dropWorkout([.drop, .normal])
        s = RFix.reduced(s, .setSetType(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 1), type: .drop))
        s = RFix.reduced(s, RFix.log(s, 0, 0), at: 1)
        XCTAssertNil(s.rest)
        s = RFix.reduced(s, .setSetType(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, 1), type: .normal))
        XCTAssertNil(s.rest, "a rest that did not start does not start later")
        var late = dropWorkout([.drop, .drop])
        late = RFix.reduced(late, RFix.log(late, 0, 1), at: 1)
        XCTAssertEqual(late.rest?.totalSeconds, 90, "logging the second drop first: it is the last set")
    }

    func testTheRuleAppliesInASupersetAfterTheLastMember() {
        var s = RFix.state([
            RFix.entry(1, RFix.lateral, [(.normal, 8, 12), (.drop, 8, 12), (.drop, 6, 12)], rest: 60, group: "A"),
            RFix.entry(2, RFix.pushdown, [(.normal, 30, 12), (.normal, 30, 12), (.drop, 20, 12)], rest: 90, group: "A"),
        ])
        s = RFix.reduced(s, RFix.log(s, 0, 0), at: 1)
        XCTAssertEqual(s.currentIndex, 1)
        XCTAssertNil(s.rest)
        s = RFix.reduced(s, RFix.log(s, 1, 0), at: 2)
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertEqual(s.rest?.totalSeconds, 90, "after the last member: that exercise's rest")
        s = RFix.reduced(s, RFix.log(s, 0, 1), at: 3)       // a drop set followed by a drop set, but not the last member
        XCTAssertEqual(s.currentIndex, 1)
        XCTAssertNil(s.rest)
        s = RFix.reduced(s, RFix.log(s, 1, 1), at: 4)
        XCTAssertEqual(s.rest?.totalSeconds, 90, "the second exercise's second set is followed by a drop, but it is normal")
        s = RFix.reduced(s, RFix.log(s, 0, 2), at: 5)
        XCTAssertNil(s.rest, "not the last member")
        s = RFix.reduced(s, RFix.log(s, 1, 2), at: 6)
        XCTAssertEqual(s.rest?.totalSeconds, 90, "the last drop set of the last member rests in full")
    }

    func testAutoStartOffStartsNothing() {
        var s = dropWorkout([.normal, .normal])
        s.settings.autoStartRest = false
        s = RFix.reduced(s, RFix.log(s, 0, 0), at: 1)
        XCTAssertNil(s.rest)
    }

    func testPausedWorkoutsFreezeTheRestOfADropSet() {
        var s = dropWorkout([.drop, .normal])
        s = RFix.reduced(s, .pause, at: 1)
        s = RFix.reduced(s, RFix.log(s, 0, 0), at: 2)
        XCTAssertEqual(s.rest?.frozenRemaining, 90)
    }

    func testTheTemplateEstimateFollowsTheSameRules() {
        func minutes(_ types: [SetType], rest: Int) -> Int {
            let entry = TemplateEntry(
                id: RFix.uuid(1, 1), exercise: RFix.bench, plannedSets: types.map { PlannedSet(type: $0, weightKg: 60, reps: 8) }, restSeconds: rest
            )
            return WorkoutTemplate(id: RFix.uuid(2, 1), name: "T", entries: [entry]).estimatedMinutes
        }
        // 4 sets: 45 s of work each; with 300 s of rest after every set it is 4 x 345 s = 23 min -> 25
        XCTAssertEqual(minutes([.normal, .normal, .normal, .normal], rest: 300), 25)
        // drop sets followed by drop sets rest for nothing: 4 x 45 + 2 x 300 = 780 s = 13 min -> 15
        XCTAssertEqual(minutes([.normal, .drop, .drop, .drop], rest: 300), 15)
        XCTAssertEqual(minutes([.normal, .normal, .normal, .normal], rest: 0), 5, "no timer: 3 min of work")
    }
}

// MARK: - The PREVIOUS column

final class PreviousSetMatchingTests: XCTestCase {
    private func exercise(_ previous: [PreviousSet], tracking: TrackingKind = .weightReps, loads: Bool = false) -> Exercise {
        RedFix.exercise(
            "x", "Exercise", .chest, tracking == .weightReps ? .barbell : .bodyweight, tracking: tracking, previousSets: previous,
            kg: 0, reps: 8, rest: 60, allowsAddedWeight: loads
        )
    }

    private func entry(_ exercise: Exercise, _ types: [SetType]) -> WorkoutExercise {
        RedFix.entry(1, exercise, types.map { ($0, 60, 8) }, rest: 60)
    }

    private func texts(_ exercise: Exercise, _ types: [SetType]) throws -> [String] {
        let state = PresFix.workout([PresFix.entry(1, exercise, types.map { ($0, 60, 8) }, rest: 60)])
        return try XCTUnwrap(PresFix.present(state).card).rows.map { $0.previousText }
    }

    private let session = [
        PreviousSet(weightKg: 40, reps: 8, type: .warmup), PreviousSet(weightKg: 60, reps: 5, type: .warmup),
        PreviousSet(weightKg: 80, reps: 6), PreviousSet(weightKg: 80, reps: 6, rir: 2), PreviousSet(weightKg: 70, reps: 8, type: .drop),
    ]

    func testWarmUpsMatchWarmUpsAndWorkingSetsWorkingSetsInOrder() throws {
        let matches = PresenterSupport.matchedPreviousSets(entry(exercise(session), [.warmup, .warmup, .normal, .normal, .normal]))
        XCTAssertEqual(matches.map { $0?.weightKg }, [40, 60, 80, 80, 70])
        XCTAssertEqual(try texts(exercise(session), [.warmup, .warmup, .normal, .normal, .normal]), ["40 × 8", "60 × 5", "80 × 6", "80 × 6", "70 × 8"])
    }

    func testTheRowsDoNotNeedTheSameTypesAsLastTime() throws {
        // a workout with one warm-up and four working sets, one of them a drop set and one to failure
        XCTAssertEqual(
            try texts(exercise(session), [.warmup, .normal, .drop, .failure, .normal]),
            ["40 × 8", "80 × 6", "80 × 6", "70 × 8", "–"], "working rows take the working sets in order whatever their own type"
        )
    }

    func testWorkingSetsSkipTheWarmUpsOfLastTime() throws {
        XCTAssertEqual(try texts(exercise(session), [.normal, .normal, .normal]), ["80 × 6", "80 × 6", "70 × 8"])
    }

    func testRowsBeyondTheLastSessionShowADashAndNeverReuseTheLastSet() throws {
        XCTAssertEqual(try texts(exercise(session), [.warmup, .warmup, .warmup, .normal, .normal, .normal, .normal, .normal]),
                       ["40 × 8", "60 × 5", "–", "80 × 6", "80 × 6", "70 × 8", "–", "–"])
        XCTAssertEqual(try texts(exercise([PreviousSet(weightKg: 50, reps: 10)]), [.normal, .normal, .normal]), ["50 × 10", "–", "–"])
    }

    func testTheKeypadAsksForTheSamePreviousSetAsTheColumn() {
        // three working sets of a workout whose last session began with two warm-ups: "Use last" never offers a warm-up
        let working = entry(exercise(session), [.normal, .normal, .normal, .normal])
        XCTAssertEqual((0..<4).map { working.matchedPreviousSet(at: $0)?.weightKg }, [80, 80, 70, nil])
        let mixed = entry(exercise(session), [.warmup, .normal])
        XCTAssertEqual(mixed.matchedPreviousSet(at: 0)?.weightKg, 40)
        XCTAssertEqual(mixed.matchedPreviousSet(at: 1)?.weightKg, 80)
        XCTAssertNil(mixed.matchedPreviousSet(at: 2), "no such set")
        XCTAssertNil(mixed.matchedPreviousSet(at: -1))
    }

    func testWithoutHistoryEveryRowIsADash() throws {
        XCTAssertEqual(try texts(exercise([]), [.warmup, .normal]), ["–", "–"])
        XCTAssertTrue(PresenterSupport.matchedPreviousSets(entry(exercise([]), [.normal])).allSatisfy { $0 == nil })
    }

    func testOnlyWarmUpsLastTimeLeaveTheWorkingRowsEmpty() throws {
        let previous = [PreviousSet(weightKg: 40, reps: 8, type: .warmup)]
        XCTAssertEqual(try texts(exercise(previous), [.warmup, .normal]), ["40 × 8", "–"])
    }

    func testARowCarriesTheTypeAndTheRIROfItsPreviousSet() throws {
        let state = PresFix.workout([PresFix.entry(1, exercise(session), [(.warmup, 40, 8), (.normal, 80, 6), (.normal, 80, 6), (.drop, 70, 8)], rest: 60)])
        let rows = try XCTUnwrap(PresFix.present(state).card).rows
        XCTAssertEqual(rows.map { $0.previousSet?.type }, [.warmup, nil, nil, .drop])
        XCTAssertEqual(rows.map { $0.previousSet?.rir }, [nil, nil, 2, nil])
        XCTAssertEqual(rows[2].previousSet, PreviousSet(weightKg: 80, reps: 6, rir: 2))
    }

    func testASetWithoutATypeCountsAsAWorkingSet() {
        XCTAssertFalse(PreviousSet(weightKg: 1, reps: 1).isWarmup)
        XCTAssertFalse(PreviousSet(weightKg: 1, reps: 1, type: .failure).isWarmup)
        XCTAssertTrue(PreviousSet(weightKg: 1, reps: 1, type: .warmup).isWarmup)
    }

    func testTheSameExerciseTwiceMatchesTheSamePreviousSetsIndependently() throws {
        let bench = exercise(session)
        let state = PresFix.workout([
            PresFix.entry(1, bench, [(.warmup, 40, 8), (.normal, 80, 6)], rest: 60),
            PresFix.entry(2, PresFix.lib("incline"), PresFix.normal(1, 20, 8)),
            PresFix.entry(3, bench, [(.warmup, 40, 8), (.normal, 80, 6), (.normal, 80, 6)], rest: 60),
        ])
        var shown = state
        shown.currentIndex = 0
        let first = try XCTUnwrap(PresFix.present(shown).card).rows.map { $0.previousText }
        shown.currentIndex = 2
        let second = try XCTUnwrap(PresFix.present(shown).card).rows.map { $0.previousText }
        XCTAssertEqual(first, ["40 × 8", "80 × 6"])
        XCTAssertEqual(second, ["40 × 8", "80 × 6", "80 × 6"], "the second occurrence does not continue where the first stopped")
    }

    func testRepsOnlyAndTimedExercisesMatchTheSameWay() throws {
        let pushups = exercise([PreviousSet(weightKg: 0, reps: 15), PreviousSet(weightKg: 0, reps: 12)], tracking: .repsOnly)
        XCTAssertEqual(try texts(pushups, [.normal, .normal, .normal]), ["15 reps", "12 reps", "–"])
        let planks = exercise([PreviousSet(weightKg: 0, reps: 60)], tracking: .duration)
        XCTAssertEqual(try texts(planks, [.normal, .normal]), ["60 s", "–"])
    }

    func testPreviousSetsOfAMachineDoNotInventTheLoadOfABodyweightExercise() throws {
        // a push-up has no added load: whatever weight an old file holds is not shown
        let pushups = exercise([PreviousSet(weightKg: 20, reps: 15)], tracking: .repsOnly)
        XCTAssertEqual(try texts(pushups, [.normal]), ["15 reps"])
        let pullups = exercise([PreviousSet(weightKg: 20, reps: 15)], tracking: .repsOnly, loads: true)
        XCTAssertEqual(try texts(pullups, [.normal]), ["+20 × 15"])
    }

    // MARK: Coding

    func testPreviousSetsWrittenBeforeTheTypeAndRIRDecode() throws {
        let set = try JSONDecoder().decode(PreviousSet.self, from: Data("{\"weightKg\":80,\"reps\":6}".utf8))
        XCTAssertEqual(set, PreviousSet(weightKg: 80, reps: 6))
        XCTAssertNil(set.type)
        XCTAssertNil(set.rir)
        let full = PreviousSet(weightKg: 40, reps: 8, type: .warmup, rir: 3)
        XCTAssertEqual(try JSONDecoder().decode(PreviousSet.self, from: try JSONEncoder().encode(full)), full)
        let plain = String(decoding: try JSONEncoder().encode(PreviousSet(weightKg: 80, reps: 6)), as: UTF8.self)
        XCTAssertFalse(plain.contains("type"))
        XCTAssertFalse(plain.contains("rir"))
    }
}

// MARK: - The previous session in the history

final class PreviousSessionTests: XCTestCase {
    private typealias F = SvcDataFix

    func testThePreviousSetsAreThoseOfTheMostRecentSessionOnly() throws {
        var data = StrengthData()
        data.history = [
            F.workout(1, finishedAt: F.daysAgo(20), [F.entry("bench", [F.warmup(40, 8), F.work(70, 8), F.work(70, 8), F.work(70, 8), F.work(70, 8)], n: 1)]),
            F.workout(2, finishedAt: F.daysAgo(3), [F.entry("bench", [F.work(80, 6)], n: 2)]),
        ]
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "bench")).previousSets, [PreviousSet(weightKg: 80, reps: 6)])
        XCTAssertEqual(data.history(for: "bench", now: F.now).previousSets, [PreviousSet(weightKg: 80, reps: 6)])
    }

    func testTheTypeAndTheRIRAreCarried() throws {
        var data = StrengthData()
        let sets = [
            CompletedSet(type: .warmup, weightKg: 40, reps: 8),
            CompletedSet(type: .normal, weightKg: 80, reps: 6, rir: 3),
            CompletedSet(type: .failure, weightKg: 80, reps: 5, rir: 0),
            CompletedSet(type: .drop, weightKg: 60, reps: 10),
        ]
        data.history = [F.workout(1, finishedAt: F.daysAgo(3), [F.entry("bench", sets, n: 1)])]
        let previous = try XCTUnwrap(data.exercise(id: "bench")).previousSets
        XCTAssertEqual(previous, [
            PreviousSet(weightKg: 40, reps: 8, type: .warmup),
            PreviousSet(weightKg: 80, reps: 6, rir: 3),
            PreviousSet(weightKg: 80, reps: 5, type: .failure, rir: 0),
            PreviousSet(weightKg: 60, reps: 10, type: .drop),
        ])
    }

    func testTheSameExerciseTwiceInTheLastWorkoutUsesTheFirstEntryAndKeepsBothForTheBests() throws {
        var data = StrengthData()
        data.history = [F.workout(1, finishedAt: F.daysAgo(3), [
            F.entry("bench", [F.work(60, 10), F.work(60, 10)], n: 1), F.entry("squat", [F.work(100, 5)], n: 2), F.entry("bench", [F.work(90, 3)], n: 3),
        ])]
        let bench = try XCTUnwrap(data.exercise(id: "bench"))
        XCTAssertEqual(bench.previousSets, [PreviousSet(weightKg: 60, reps: 10), PreviousSet(weightKg: 60, reps: 10)])
        XCTAssertEqual(bench.previousBestE1RM, 90 * (1 + 3.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(bench.previousRecords.heaviestKg, 90)
    }

    func testAnEntryWithoutSetsDoesNotHideTheOneBefore() throws {
        var data = StrengthData()
        data.history = [F.workout(1, finishedAt: F.daysAgo(3), [F.entry("bench", [], n: 1), F.entry("bench", [F.work(70, 5)], n: 2)])]
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "bench")).previousSets, [PreviousSet(weightKg: 70, reps: 5)])
    }

    func testTheNextWorkoutShowsLastSessionThroughTheEngine() throws {
        try svcMain {
            let rig = SvcRig(self, seed: false)
            rig.model.addStarterTemplates()
            let push = rig.model.data.templates[0]
            rig.model.record(F.workout(70, finishedAt: F.daysAgo(0.5), [F.entry("bench", [F.warmup(40, 8), F.work(62.5, 8), F.work(62.5, 7)], n: 70)]), updateTemplate: nil)
            rig.engine.start(template: push)
            let state = try XCTUnwrap(rig.engine.state)
            let bench = try XCTUnwrap(state.exercises.first { $0.exercise.id == "bench" })
            XCTAssertEqual(bench.exercise.previousSets, [PreviousSet(weightKg: 40, reps: 8, type: .warmup), PreviousSet(weightKg: 62.5, reps: 8), PreviousSet(weightKg: 62.5, reps: 7)])
            XCTAssertEqual(bench.exercise.previousRecords.repRecords[8], 62.5, "the marks reach the exercise of a started workout too")
            var shown = state
            shown.currentIndex = state.exercises.firstIndex { $0.exercise.id == "bench" } ?? 0
            let rows = try XCTUnwrap(WorkoutPresenter.present(shown, now: rig.clock.now, recovery: DemoRecovery.provider).card).rows
            XCTAssertEqual(rows.map { $0.previousText }, ["62.5 × 8", "62.5 × 7", "–"])
        }
    }
}

// MARK: - The record marks reach a custom exercise of a template

final class CustomExerciseMarksTests: XCTestCase {
    private let hold = Exercise.custom(name: "Hollow hold", muscle: .core, equipment: .bodyweight, tracking: .duration, id: "custom-hold")

    @MainActor
    private func rig() -> (rig: SvcRig, template: WorkoutTemplate) {
        let rig = SvcRig(self, seed: false)
        _ = rig.model.addCustomExercise(hold)
        let entry = CompletedExercise(
            id: SvcSyncFix.uuid(9000), exerciseID: hold.id, name: hold.name, muscle: hold.muscle, mediaKey: nil, tracking: .duration,
            sets: [CompletedSet(type: .normal, weightKg: 0, reps: 90)], isPersonalRecord: false, bestE1RM: 0
        )
        rig.model.record(SvcDataFix.workout(80, finishedAt: SvcDataFix.daysAgo(2), [entry]), updateTemplate: nil)
        let stale = TemplateEntry(exercise: hold, plannedSets: [PlannedSet(weightKg: 0, reps: 45)], restSeconds: 60)
        return (rig, WorkoutTemplate(name: "Core", entries: [stale]))
    }

    func testStartingAWorkoutBringsTheMarksOfACustomExerciseUpToDate() throws {
        try svcMain {
            let (rig, template) = rig()
            XCTAssertEqual(template.entries[0].exercise.previousRecords.bestSeconds, 0, "the template copy is stale")
            rig.engine.start(template: template)
            let started = try XCTUnwrap(rig.engine.state?.exercises.first?.exercise)
            XCTAssertEqual(started.previousRecords.bestSeconds, 90)
            XCTAssertEqual(started.name, hold.name, "nothing else of a custom exercise changes")
        }
    }

    func testRestoringAWorkoutBringsTheMarksOfACustomExerciseUpToDate() throws {
        try svcMain {
            let (first, template) = rig()
            let saved = WorkoutFactory.makeWorkout(from: template, now: first.clock.now, preferences: first.model.data.preferences)
            try first.persistence.saveActiveWorkout(saved)
            let second = SvcRig(self, seed: false, persistence: first.persistence)
            second.engine.restore()
            XCTAssertEqual(try XCTUnwrap(second.engine.state?.exercises.first?.exercise).previousRecords.bestSeconds, 90)
        }
    }
}

// MARK: - New exercises start from the last working set

final class LastUsedDefaultsTests: XCTestCase {
    private func library(_ id: String, previous: [PreviousSet]) -> Exercise {
        var exercise = ExerciseLibrary.exercise(id: id)!
        exercise.previousSets = previous
        return exercise
    }

    private func added(_ exercise: Exercise) -> WorkoutExercise {
        var s = WorkoutState(name: "W", startedAt: RFix.t0)
        WorkoutReducer.reduce(&s, .addExercises([exercise]), now: RFix.at(1))
        return s.exercises[0]
    }

    func testTheSetsStartFromTheLastWorkingSetAndKeepTheDefaultCount() {
        let bench = library("bench", previous: [
            PreviousSet(weightKg: 40, reps: 8, type: .warmup), PreviousSet(weightKg: 80, reps: 6),
            PreviousSet(weightKg: 80, reps: 6), PreviousSet(weightKg: 82.5, reps: 5),
        ])
        let entry = added(bench)
        XCTAssertEqual(entry.sets.count, bench.defaults.sets, "the count is the default's, not last time's four")
        XCTAssertTrue(entry.sets.allSatisfy { $0.weightKg == 82.5 && $0.reps == 5 && $0.type == .normal && !$0.isDone && $0.rir == nil })
        XCTAssertEqual(entry.restSeconds, bench.defaults.restSeconds)
    }

    func testWarmUpsAreNeverCopied() {
        let onlyWarmUps = library("bench", previous: [PreviousSet(weightKg: 40, reps: 8, type: .warmup)])
        XCTAssertEqual(added(onlyWarmUps).sets.map { $0.weightKg }, Array(repeating: onlyWarmUps.defaults.weightKg, count: 3))
        let warmUpLast = library("bench", previous: [PreviousSet(weightKg: 80, reps: 6), PreviousSet(weightKg: 40, reps: 8, type: .warmup)])
        XCTAssertEqual(added(warmUpLast).sets.first?.weightKg, 80)
    }

    func testATrailingDropSetIsNotWhereTheNextSessionStarts() {
        let drops = library("bench", previous: [PreviousSet(weightKg: 100, reps: 5), PreviousSet(weightKg: 100, reps: 5), PreviousSet(weightKg: 70, reps: 8, type: .drop)])
        XCTAssertEqual(added(drops).sets.map { $0.weightKg }, [100, 100, 100])
        XCTAssertEqual(added(drops).sets.map { $0.reps }, [5, 5, 5])
        let allDrops = library("bench", previous: [PreviousSet(weightKg: 60, reps: 8, type: .drop)])
        XCTAssertEqual(added(allDrops).sets.first?.weightKg, 60, "when every working set was a drop set the last one counts")
    }

    func testWithoutPreviousWorkingSetsTheLibraryDefaultsApply() {
        let none = library("bench", previous: [])
        XCTAssertEqual(added(none).sets.map { [$0.weightKg, Double($0.reps)] }, Array(repeating: [60, 8], count: 3))
        let empty = library("bench", previous: [PreviousSet(weightKg: 80, reps: 0)])
        XCTAssertEqual(added(empty).sets.first?.weightKg, 60, "a set without reps tells nothing")
    }

    func testRepsOnlyExercisesTakeTheLastRepsAndNoWeight() {
        let pushups = library("pushup", previous: [PreviousSet(weightKg: 0, reps: 15), PreviousSet(weightKg: 35, reps: 18)])
        let entry = added(pushups)
        XCTAssertEqual(entry.sets.map { $0.reps }, [18, 18, 18])
        XCTAssertEqual(entry.sets.map { $0.weightKg }, [0, 0, 0], "a push-up has no load to copy")
    }

    func testExercisesWithAnAddedLoadCopyTheSignedLoad() {
        let pullups = library("pullup", previous: [PreviousSet(weightKg: -10, reps: 6), PreviousSet(weightKg: -5, reps: 5)])
        let entry = added(pullups)
        XCTAssertEqual(entry.sets.map { $0.weightKg }, [-5, -5, -5])
        XCTAssertEqual(entry.sets.map { $0.reps }, [5, 5, 5])
        let tooLight = library("pullup", previous: [PreviousSet(weightKg: -900, reps: 5)])
        XCTAssertEqual(added(tooLight).sets.first?.weightKg, -300)
    }

    func testTimedExercisesTakeTheLastSeconds() {
        let plank = library("plank", previous: [PreviousSet(weightKg: 0, reps: 60), PreviousSet(weightKg: 0, reps: 75)])
        XCTAssertEqual(added(plank).sets.map { $0.reps }, [75, 75, 75])
        let long = library("plank", previous: [PreviousSet(weightKg: 0, reps: 5_000)])
        XCTAssertEqual(added(long).sets.first?.reps, 5_000, "seconds up to three hours")
        let absurd = library("plank", previous: [PreviousSet(weightKg: 0, reps: Int.max)])
        XCTAssertEqual(added(absurd).sets.first?.reps, 10_800)
    }

    func testBrokenWeightsFallBackToTheDefaultWeight() {
        let broken = library("bench", previous: [PreviousSet(weightKg: .nan, reps: 6), PreviousSet(weightKg: .infinity, reps: 7)])
        let entry = added(broken)
        XCTAssertEqual(entry.sets.first?.reps, 7)
        XCTAssertEqual(entry.sets.first?.weightKg, 60)
        XCTAssertEqual(added(library("bench", previous: [PreviousSet(weightKg: -40, reps: 5)])).sets.first?.weightKg, 0)
        XCTAssertEqual(added(library("bench", previous: [PreviousSet(weightKg: 5e9, reps: 5)])).sets.first?.weightKg, WorkoutReducer.maximumWeightKg)
        XCTAssertEqual(added(library("bench", previous: [PreviousSet(weightKg: 80, reps: 50_000)])).sets.first?.reps, 999)
    }

    func testReplacingAnExerciseStartsFromItsLastWorkingSetToo() {
        var s = RFix.state([RFix.entry(1, RFix.pushup, RFix.normal(2, 0, 12), rest: 60, group: nil)])
        let bench = library("bench", previous: [PreviousSet(weightKg: 40, reps: 8, type: .warmup), PreviousSet(weightKg: 85, reps: 5)])
        s = RFix.reduced(s, .replaceExercise(exerciseID: RFix.ex(s, 0), with: bench))
        XCTAssertEqual(s.exercises[0].sets.map { $0.weightKg }, [85, 85, 85])
        XCTAssertEqual(s.exercises[0].sets.map { $0.reps }, [5, 5, 5])
    }

    func testANewSetOfAnExerciseWithoutSetsStartsFromTheLastWorkingSetToo() {
        var entry = added(library("bench", previous: [PreviousSet(weightKg: 85, reps: 5)]))
        var s = RFix.state([])
        entry.sets = []
        s.exercises = [entry]
        s = RFix.reduced(s, .addSet(exerciseID: entry.id))
        XCTAssertEqual(s.exercises[0].sets.map { [$0.weightKg, Double($0.reps)] }, [[85, 5]])
        // with sets, a new one copies the last set as before
        s = RFix.reduced(s, .setWeight(exerciseID: entry.id, setID: s.exercises[0].sets[0].id, kg: 90))
        s = RFix.reduced(s, .addSet(exerciseID: entry.id))
        XCTAssertEqual(s.exercises[0].sets.last?.weightKg, 90)
    }

    func testAWorkoutFromATemplateKeepsThePlannedSets() {
        var bench = library("bench", previous: [PreviousSet(weightKg: 99, reps: 9)])
        bench.defaults = ExerciseDefaults(sets: 2, weightKg: 50, reps: 10, restSeconds: 90)
        let template = WorkoutTemplate(id: RFix.uuid(1, 1), name: "T", entries: [
            TemplateEntry(id: RFix.uuid(2, 1), exercise: bench, plannedSets: [PlannedSet(weightKg: 70, reps: 6), PlannedSet(weightKg: 72.5, reps: 5)], restSeconds: 120),
        ])
        let state = WorkoutFactory.makeWorkout(from: template, now: RFix.t0)
        XCTAssertEqual(state.exercises[0].sets.map { $0.weightKg }, [70, 72.5], "the template's plan, not last session")
    }

    func testThroughTheStoreTheExerciseThatIsAddedCarriesLastTimesSets() throws {
        try svcMain {
            let model = StrengthDataModel(persistence: nil)
            let record = SvcDataFix.workout(1, finishedAt: SvcDataFix.daysAgo(1), [SvcDataFix.entry("bench", [SvcDataFix.warmup(40, 8), SvcDataFix.work(72.5, 6), SvcDataFix.work(72.5, 5)], n: 1)])
            model.record(record, updateTemplate: nil)
            let bench = try XCTUnwrap(model.exercise(id: "bench"))
            let entry = added(bench)
            XCTAssertEqual(entry.sets.map { [$0.weightKg, Double($0.reps)] }, [[72.5, 5], [72.5, 5], [72.5, 5]])
        }
    }
}
