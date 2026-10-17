import XCTest
@testable import PulseStrengthCore

// MARK: - Added and assisted loads of bodyweight exercises

final class AddedLoadReducerTests: XCTestCase {
    private func state(_ exercise: Exercise, weight: Double = 0, sets: Int = 3, reps: Int = 8) -> WorkoutState {
        RFix.state([RFix.entry(1, exercise, RFix.normal(sets, weight, reps), rest: 90)])
    }

    private func weight(_ s: WorkoutState, _ i: Int = 0) -> Double { s.exercises[0].sets[i].weightKg }

    private func setWeight(_ s: WorkoutState, _ kg: Double, _ i: Int = 0) -> WorkoutState {
        RFix.reduced(s, .setWeight(exerciseID: RFix.ex(s, 0), setID: RFix.setID(s, 0, i), kg: kg))
    }

    func testTheLimitsAreMinus300AndTheUsualMaximum() {
        XCTAssertEqual(WorkoutReducer.minimumWeightKg, -300)
        let s = state(RFix.pullup)
        XCTAssertEqual(weight(setWeight(s, -20)), -20)
        XCTAssertEqual(weight(setWeight(s, 10.004)), 10)
        XCTAssertEqual(weight(setWeight(s, -20.006)), -20.01)
        XCTAssertEqual(weight(setWeight(s, -300)), -300)
        XCTAssertEqual(weight(setWeight(s, -301)), -300)
        XCTAssertEqual(weight(setWeight(s, -1e9)), -300)
        XCTAssertEqual(weight(setWeight(s, -.infinity)), -300)
        XCTAssertEqual(weight(setWeight(s, 1e9)), WorkoutReducer.maximumWeightKg)
    }

    func testNaNAndPlusInfinityAreIgnored() {
        let s = state(RFix.pullup, weight: 12)
        XCTAssertEqual(setWeight(s, .nan), s)
        XCTAssertEqual(setWeight(s, .infinity), s)
    }

    func testAZeroIsNeverNegativeZero() {
        let s = state(RFix.pullup, weight: 10)
        let zeroed = setWeight(s, -0.004)
        XCTAssertEqual(weight(zeroed), 0)
        XCTAssertEqual(weight(zeroed).sign, .plus)
        XCTAssertEqual(weight(setWeight(state(RFix.bench), -0.004)).sign, .plus)
    }

    func testAnExerciseWithoutAnAddedLoadKeepsItsWeightAtZeroOrMore() {
        for exercise in [RFix.bench, RFix.pushup, RFix.plank] {
            let s = state(exercise, weight: 20)
            XCTAssertEqual(weight(setWeight(s, -20)), 0, exercise.id)
            XCTAssertEqual(weight(setWeight(s, -.infinity)), 0, exercise.id)
        }
        var custom = RFix.pullup
        custom.allowsAddedWeight = false
        XCTAssertEqual(weight(setWeight(state(custom), -10)), 0, "a reps-only exercise without the load flag")
        var timed = RFix.plank
        timed.allowsAddedWeight = true
        XCTAssertEqual(weight(setWeight(state(timed), -10)), 0, "the flag means nothing for a timed exercise")
        var weighted = RFix.bench
        weighted.allowsAddedWeight = true
        XCTAssertEqual(weight(setWeight(state(weighted), -10)), 0, "nor for a weight exercise")
    }

    func testNudgingStepsTheAddedLoadThroughBodyweight() {
        var s = state(RFix.pullup)
        s = RFix.reduced(s, .nudgeNextSet(weightSteps: 1, repsSteps: 0))
        XCTAssertEqual(weight(s), 1, "the step of a bodyweight exercise is 1 kg")
        s = RFix.reduced(s, .nudgeNextSet(weightSteps: -3, repsSteps: 0))
        XCTAssertEqual(weight(s), -2)
        s = RFix.reduced(s, .nudgeNextSet(weightSteps: 2, repsSteps: 0))
        XCTAssertEqual(weight(s), 0)
        XCTAssertEqual(weight(s).sign, .plus)
        s = RFix.reduced(s, .nudgeNextSet(weightSteps: -1000, repsSteps: 0))
        XCTAssertEqual(weight(s), -300, "the nudge stops at the lightest weight")
        s = RFix.reduced(s, .nudgeNextSet(weightSteps: Int.min, repsSteps: 0))
        XCTAssertEqual(weight(s), -300)
    }

    func testNudgingInPoundsReturnsToTheSameStoredWeight() {
        var s = state(RFix.pullup, weight: 10)
        s.settings.weightUnit = .lb
        let up = RFix.reduced(s, .nudgeNextSet(weightSteps: 1, repsSteps: 0))
        XCTAssertNotEqual(weight(up), 10)
        XCTAssertEqual(weight(RFix.reduced(up, .nudgeNextSet(weightSteps: -1, repsSteps: 0))), 10, "2.5 lb up and down")
        let down = RFix.reduced(state(RFix.pullup), .nudgeNextSet(weightSteps: -1, repsSteps: 0))
        XCTAssertEqual(weight(down), -1, "0 and one 1 kg step down")
    }

    func testNudgingTheWeightOfAnExerciseWithoutOneChangesNothing() {
        for exercise in [RFix.pushup, RFix.plank] {
            let s = state(exercise)
            let nudged = RFix.reduced(s, .nudgeNextSet(weightSteps: 3, repsSteps: 0))
            XCTAssertEqual(nudged.exercises, s.exercises, exercise.id)
        }
    }

    func testTheRepsOfALoadedExerciseStillClampAt999() {
        let start = state(RFix.pullup)
        let s = RFix.reduced(start, .setReps(exerciseID: RFix.ex(start, 0), setID: RFix.setID(start, 0, 0), reps: 5_000))
        XCTAssertEqual(s.exercises[0].sets[0].reps, 999)
    }

    func testANewSetOfALoadedExerciseStartsFromTheLastSet() {
        var s = state(RFix.pullup, weight: -20)
        s = RFix.reduced(s, .addSet(exerciseID: RFix.ex(s, 0)))
        XCTAssertEqual(s.exercises[0].sets.last?.weightKg, -20)
    }

    func testTheLoadIsNeverPartOfTheEstimate() {
        let entry = RFix.entry(1, RFix.pullup, [(.normal, 20, 8)], rest: 90)
        XCTAssertEqual(PresenterSupport.analyse(entry).sets.map { $0.e1RM }, [0])
    }

    func testTheFlagsOfTheLibraryAndOfCustomExercises() {
        XCTAssertEqual(Set(ExerciseLibrary.builtIn.filter { $0.allowsAddedWeight }.map { $0.id }), ["pullup", "dips"])
        XCTAssertTrue(ExerciseLibrary.builtIn.filter { $0.allowsAddedWeight }.allSatisfy { $0.tracking == .repsOnly })
        let reps = Exercise.custom(name: "Muscle-up", muscle: .back, equipment: .bodyweight, tracking: .repsOnly)
        XCTAssertTrue(reps.allowsAddedWeight)
        XCTAssertTrue(reps.carriesLoad)
        XCTAssertTrue(reps.hasEditableWeight)
        let weighted = Exercise.custom(name: "Curl", muscle: .arms, equipment: .dumbbell, tracking: .weightReps)
        XCTAssertFalse(weighted.allowsAddedWeight)
        XCTAssertTrue(weighted.hasEditableWeight)
        XCTAssertFalse(weighted.carriesLoad)
        let timed = Exercise.custom(name: "Hold", muscle: .core, equipment: .bodyweight, tracking: .duration)
        XCTAssertFalse(timed.allowsAddedWeight)
        XCTAssertFalse(timed.hasEditableWeight)
        XCTAssertFalse(ExerciseLibrary.exercise(id: "pushup")!.hasEditableWeight)
    }
}

// MARK: - Presenter, summary and history of loaded sets

final class AddedLoadPresentationTests: XCTestCase {
    private func card(_ sets: [PresFix.SetSpec], done: [Int] = [], id: String = "pullup") throws -> ActiveWorkoutPresentation.Card {
        let state = PresFix.marking(PresFix.single(PresFix.lib(id), sets), exercise: 0, done: done)
        return try XCTUnwrap(PresFix.present(state).card)
    }

    func testTheAddedColumnIsEditableAndShowsTheSignedLoad() throws {
        let card = try card([(.normal, 0, 8), (.normal, 10, 8), (.normal, -20, 8), (.normal, 12.5, 6)])
        XCTAssertEqual(card.weightColumnTitle, "Added")
        XCTAssertEqual(card.rows.map { $0.weightEditable }, [true, true, true, true])
        XCTAssertEqual(card.rows.map { $0.weightText }, ["BW", "+10", "\u{2212}20", "+12.5"])
    }

    func testOtherBodyweightExercisesStayAtBW() throws {
        let card = try card([(.normal, 0, 12)], id: "pushup")
        XCTAssertEqual(card.rows.map { $0.weightEditable }, [false])
        XCTAssertEqual(card.rows.map { $0.weightText }, ["BW"])
    }

    func testTheLoadIsShownInPoundsToo() throws {
        var state = PresFix.marking(PresFix.single(PresFix.lib("pullup"), [(.normal, 10, 8), (.normal, -20, 8)]), exercise: 0, done: [0])
        state.settings.weightUnit = .lb
        let rows = try XCTUnwrap(PresFix.present(state).card).rows
        XCTAssertEqual(rows.map { $0.weightText }, ["+22", "\u{2212}44.1"])
        XCTAssertEqual(rows[0].accessibilityLabel, "Set 1, working set, 22 pounds added, 8 reps, logged")
    }

    func testTheLabelsSayAddedAssistedOrBodyweight() throws {
        let rows = try card([(.normal, 10, 8), (.normal, -20, 8), (.normal, 0, 8), (.normal, 1, 3)]).rows
        XCTAssertEqual(rows[0].accessibilityLabel, "Set 1, working set, 10 kilograms added, 8 reps, not logged")
        XCTAssertEqual(rows[1].accessibilityLabel, "Set 2, working set, 20 kilograms assisted, 8 reps, not logged")
        XCTAssertEqual(rows[2].accessibilityLabel, "Set 3, working set, bodyweight, 8 reps, not logged")
        XCTAssertEqual(rows[3].accessibilityLabel, "Set 4, working set, 1 kilogram added, 3 reps, not logged")
        let pushup = try card([(.normal, 0, 12)], id: "pushup").rows
        XCTAssertEqual(pushup[0].accessibilityLabel, "Set 1, working set, bodyweight, 12 reps, not logged")
    }

    func testThePreviousColumnIncludesTheLoad() throws {
        var exercise = PresFix.lib("pullup")
        exercise.previousSets = [PreviousSet(weightKg: 10, reps: 8), PreviousSet(weightKg: -20, reps: 6), PreviousSet(weightKg: 0, reps: 5)]
        let state = PresFix.single(exercise, [(.normal, 10, 8), (.normal, 10, 8), (.normal, 0, 8)])
        let rows = try XCTUnwrap(PresFix.present(state).card).rows
        XCTAssertEqual(rows.map { $0.previousText }, ["+10 × 8", "\u{2212}20 × 6", "5 reps"])
    }

    func testTheNextSetAndTheDockTextsIncludeTheLoad() throws {
        var state = PresFix.single(PresFix.lib("pullup"), [(.normal, 10, 8), (.normal, 10, 8)])
        state = PresFix.reduced(state, .logNextSet, at: 5)
        let dock = try XCTUnwrap(PresFix.present(state, at: 6).dock)
        XCTAssertEqual(dock.nextSetText, "Next · Set 2 · +10 kg × 8")
        let snapshot = SnapshotBuilder.make(from: state, now: PresFix.at(6))
        XCTAssertEqual(snapshot.nextSetText, "Set 2 · +10 kg × 8")
        XCTAssertEqual(snapshot.weightText, "+10")
        XCTAssertFalse(snapshot.showsWeight, "the Watch and the Live Activity keep their reps-only layout")
    }

    func testOnlyAPositiveLoadCountsAsVolume() {
        var entry = PresFix.entry(1, PresFix.lib("pullup"), [(.normal, 10, 8), (.normal, -20, 8), (.normal, 0, 8), (.warmup, 30, 5), (.drop, 5, 10)])
        for index in entry.sets.indices { entry.sets[index].isDone = true }
        XCTAssertEqual(entry.loggedVolumeKg, 10 * 8 + 5 * 10, "the assisted set and bodyweight add nothing, the warm-up is left out")
        let state = PresFix.workout([entry])
        XCTAssertEqual(PresFix.present(state).totals.volumeKg, 130)
        let summary = SummaryBuilder.build(from: state, finishedAt: PresFix.at(600))
        XCTAssertEqual(summary.volumeKg, 130)
        XCTAssertEqual(SnapshotBuilder.make(from: state, now: PresFix.at(1)).volumeText, "130")

        var pending = entry
        pending.sets[0].isDone = false
        XCTAssertEqual(pending.loggedVolumeKg, 50, "a pending set adds nothing")
        XCTAssertEqual(PresFix.entry(1, PresFix.lib("pushup"), [(.normal, 20, 8)]).loggedVolumeKg, 0, "an exercise without an editable weight has no volume")
    }

    func testTheSummaryKeepsTheSignedWeightsAndNoEstimate() {
        var entry = PresFix.entry(1, PresFix.lib("pullup"), [(.normal, -20, 8), (.normal, 10, 6)])
        for index in entry.sets.indices { entry.sets[index].isDone = true }
        let summary = SummaryBuilder.build(from: PresFix.workout([entry]), finishedAt: PresFix.at(600))
        XCTAssertEqual(summary.exercises[0].sets.map { $0.weightKg }, [-20, 10])
        XCTAssertEqual(summary.exercises[0].bestE1RM, 0)
    }

    func testHistoryVolumeAndTheLoadedRecords() {
        typealias F = SvcDataFix
        var data = StrengthData()
        data.record(F.workout(1, finishedAt: F.daysAgo(2), [F.entry("pullup", [F.work(10, 8), F.work(-20, 8), F.work(0, 8)], n: 1)]), updateTemplate: nil)
        let history = data.history(for: "pullup", now: F.now)
        XCTAssertEqual(history.volumeLast30Days, 80, "only the +10 kg x 8")
        XCTAssertEqual(history.bestE1RM, 0)
        XCTAssertTrue(history.e1RMSeries.isEmpty)
        XCTAssertEqual(history.records.first { $0.id == "heaviest" }?.value, "+10 kg")
        XCTAssertEqual(data.personalBests["pullup"]?.heaviestKg, 10)
        XCTAssertEqual(data.personalBests["pullup"]?.bestReps, 8)
    }

    func testEditingAFinishedWorkoutKeepsAnAssistedLoadOfARepsOnlyExercise() throws {
        typealias F = SvcDataFix
        try svcMain {
            let model = StrengthDataModel(persistence: nil)
            model.record(F.workout(1, finishedAt: F.daysAgo(2), [F.entry("pullup", [F.work(-20, 8)], n: 1)]), updateTemplate: nil)
            var edited = model.data.history[0]
            edited.exercises[0].sets = [F.work(-25, 8), F.work(-500, 8), F.work(15, 8)]
            XCTAssertNoThrow(try model.updateWorkout(edited).get())
            let stored = model.data.history[0]
            XCTAssertEqual(stored.exercises[0].sets.map { $0.weightKg }, [-25, -300, 15])
            XCTAssertEqual(stored.volumeKg, 15 * 8)
        }
    }

    func testTheFlagTravelsInTheJSONOnlyWhenSet() throws {
        let encoder = StrengthJSON.makeEncoder()
        let decoder = StrengthJSON.makeDecoder()
        let pullup = ExerciseLibrary.exercise(id: "pullup")!
        let pullupText = String(decoding: try encoder.encode(pullup), as: UTF8.self)
        XCTAssertTrue(pullupText.contains("\"allowsAddedWeight\":true"))
        XCTAssertEqual(try decoder.decode(Exercise.self, from: Data(pullupText.utf8)), pullup)
        let bench = ExerciseLibrary.exercise(id: "bench")!
        let benchText = String(decoding: try encoder.encode(bench), as: UTF8.self)
        XCTAssertFalse(benchText.contains("allowsAddedWeight"))
        XCTAssertFalse(benchText.contains("previousRecords"))
        // data written before the flag (a template, a saved workout, an older Watch) reads without it
        XCTAssertFalse(try decoder.decode(Exercise.self, from: Data(benchText.utf8)).allowsAddedWeight, "data without the keys reads as before")
        var marked = bench
        marked.previousRecords = RecordMarks(heaviestKg: 100, repRecords: [5: 100])
        let markedText = String(decoding: try encoder.encode(marked), as: UTF8.self)
        XCTAssertTrue(markedText.contains("\"previousRecords\""))
        XCTAssertEqual(try decoder.decode(Exercise.self, from: Data(markedText.utf8)), marked)
    }

    func testAnExerciseWrittenByAnOlderBuildDecodes() throws {
        // the JSON of an exercise as the build before the flag wrote it: the same keys without the two new ones
        var pullup = ExerciseLibrary.exercise(id: "pullup")!
        pullup.previousSets = [PreviousSet(weightKg: 0, reps: 8)]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: try StrengthJSON.makeEncoder().encode(pullup)) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: "allowsAddedWeight"))
        object["previousRecords"] = nil
        let exercise = try StrengthJSON.makeDecoder().decode(Exercise.self, from: try JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(exercise.allowsAddedWeight, "an exercise from before the flag has no added load")
        XCTAssertEqual(exercise.previousRecords, RecordMarks())
        XCTAssertEqual(exercise.previousSets, [PreviousSet(weightKg: 0, reps: 8)])
        XCTAssertEqual(exercise.id, "pullup")
    }
}

// MARK: - Supersets: letters, moves and logging order

final class SupersetGroupTests: XCTestCase {
    private func pair(_ n: Int, group: String? = nil) -> WorkoutExercise {
        RFix.entry(n, n.isMultiple(of: 2) ? RFix.lateral : RFix.pushdown, RFix.normal(2, 10, 10), rest: 60, group: group)
    }

    private func groups(_ s: WorkoutState) -> [String?] { s.exercises.map { $0.supersetGroup } }

    private func assertContiguous(_ s: WorkoutState, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        for group in Set(s.exercises.compactMap { $0.supersetGroup }) {
            let members = s.exercises.indices.filter { s.exercises[$0].supersetGroup == group }
            XCTAssertEqual((members.last ?? 0) - (members.first ?? 0), members.count - 1, "\(group) \(message)", file: file, line: line)
            XCTAssertGreaterThanOrEqual(members.count, 2, "\(group) \(message)", file: file, line: line)
        }
    }

    // MARK: Moves

    func testMovingAMemberOutOfItsBlockTakesItOutOfTheGroup() {
        // [A1, A2, X]: A2 moves down behind X
        var s = RFix.state([pair(1, group: "A"), pair(2, group: "A"), pair(3)])
        s = RFix.reduced(s, .moveExerciseBy(exerciseID: RFix.ex(s, 1), delta: 1))
        XCTAssertEqual(s.exercises.map { $0.id }, [RFix.uuid(0x101, 0), RFix.uuid(0x103, 0), RFix.uuid(0x102, 0)])
        XCTAssertEqual(groups(s), [nil, nil, nil], "the moved exercise leaves, and the partner that is left alone leaves too")
    }

    func testMovingAMemberOutOfAGroupOfThreeKeepsTheOthersTogether() {
        var s = RFix.state([pair(1, group: "A"), pair(2, group: "A"), pair(3, group: "A"), pair(4)])
        s = RFix.reduced(s, .moveExercise(from: 2, to: 3))
        XCTAssertEqual(s.exercises.map { $0.id }.last, RFix.uuid(0x103, 0))
        XCTAssertEqual(groups(s), ["A", "A", nil, nil])
        assertContiguous(s)
        var upward = RFix.state([pair(1), pair(2, group: "A"), pair(3, group: "A"), pair(4, group: "A")])
        upward = RFix.reduced(upward, .moveExercise(from: 3, to: 0))
        XCTAssertEqual(groups(upward), [nil, nil, "A", "A"])
        assertContiguous(upward)
    }

    func testMovingAMemberWithinItsBlockKeepsTheGroup() {
        var s = RFix.state([pair(1, group: "A"), pair(2, group: "A"), pair(3, group: "A"), pair(4)])
        s = RFix.reduced(s, .moveExercise(from: 0, to: 2))
        XCTAssertEqual(s.exercises.map { $0.id }.prefix(3), [RFix.uuid(0x102, 0), RFix.uuid(0x103, 0), RFix.uuid(0x101, 0)])
        XCTAssertEqual(groups(s), ["A", "A", "A", nil])
    }

    func testMovingAnOutsiderIntoAGroupPutsItBehindTheBlockWhenMovingDown() {
        var s = RFix.state([pair(1), pair(2, group: "A"), pair(3, group: "A"), pair(4, group: "A"), pair(5)])
        s = RFix.reduced(s, .moveExercise(from: 0, to: 2))     // would land between A2 and A3
        XCTAssertEqual(s.exercises.map { $0.id }, [2, 3, 4, 1, 5].map { RFix.uuid(0x100 + $0, 0) })
        XCTAssertEqual(groups(s), ["A", "A", "A", nil, nil])
    }

    func testMovingAnOutsiderIntoAGroupPutsItBeforeTheBlockWhenMovingUp() {
        var s = RFix.state([pair(1), pair(2, group: "A"), pair(3, group: "A"), pair(4, group: "A"), pair(5)])
        s = RFix.reduced(s, .moveExercise(from: 4, to: 2))
        XCTAssertEqual(s.exercises.map { $0.id }, [1, 5, 2, 3, 4].map { RFix.uuid(0x100 + $0, 0) })
        XCTAssertEqual(groups(s), [nil, nil, "A", "A", "A"])
    }

    func testTheCurrentExerciseKeepsItsPlaceThroughAGroupRule() {
        var s = RFix.state([pair(1), pair(2, group: "A"), pair(3, group: "A"), pair(4)], index: 2)
        let current = s.exercises[2].id
        s = RFix.reduced(s, .moveExercise(from: 0, to: 1))     // the first one goes behind the block
        XCTAssertEqual(s.currentExercise?.id, current)
        s = RFix.reduced(s, .moveExerciseBy(exerciseID: RFix.ex(s, 3), delta: -1))
        XCTAssertEqual(s.currentExercise?.id, current)
        assertContiguous(s)
    }

    func testRandomMovesAndTogglesNeverSplitAGroup() {
        var rng = RedLCG(seed: 2026)
        var s = RFix.state((1...9).map { pair($0) })
        for step in 0..<600 {
            let count = s.exercises.count
            let action: WorkoutAction
            switch rng.int(0...3) {
            case 0: action = .moveExercise(from: rng.int(0...(count - 1)), to: rng.int(0...(count - 1)))
            case 1: action = .moveExerciseBy(exerciseID: RFix.ex(s, rng.int(0...(count - 1))), delta: rng.pick([-3, -1, 1, 2]))
            default: action = .toggleSuperset(exerciseID: RFix.ex(s, rng.int(0...(count - 1))))
            }
            WorkoutReducer.reduce(&s, action, now: RFix.at(Double(step)))
            assertContiguous(s, "step \(step) \(action)")
            XCTAssertEqual(Set(s.exercises.map { $0.id }).count, count)
        }
    }

    // MARK: Leaving and letters

    func testLeavingFromTheMiddleSplitsTheGroupInTwo() {
        var s = RFix.state((1...6).map { pair($0, group: $0 <= 5 ? "A" : nil) })
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 2)))
        XCTAssertEqual(groups(s), ["A", "A", nil, "B", "B", nil])
        assertContiguous(s)
    }

    // MARK: Logging through a group whose members are not next to each other

    func testALoggedSetGoesOnToTheNextMemberInOrderWhateverLiesBetween() {
        var s = RFix.state([pair(1, group: "A"), pair(2), pair(3), pair(4, group: "A"), pair(5, group: "A")])
        s = RFix.reduced(s, RFix.toggle(s, 0, 0), at: 1)
        XCTAssertEqual(s.currentIndex, 3)
        XCTAssertNil(s.rest)
        s = RFix.reduced(s, RFix.toggle(s, 3, 0), at: 2)
        XCTAssertEqual(s.currentIndex, 4)
        XCTAssertNil(s.rest)
        s = RFix.reduced(s, RFix.toggle(s, 4, 0), at: 3)
        XCTAssertEqual(s.currentIndex, 0, "after the last member the first one is current again")
        XCTAssertEqual(s.rest?.totalSeconds, 60, "and the rest starts after the last member")
    }

    func testLoggingTheLastMemberFirstStartsTheRestAtOnce() {
        var s = RFix.state([pair(1, group: "A"), pair(2), pair(3, group: "A")])
        s = RFix.reduced(s, RFix.toggle(s, 2, 0), at: 1)
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertEqual(s.rest?.totalSeconds, 60)
    }

    func testAMemberWithoutAnotherOneInItsGroupJustRests() {
        // a state with a lone member (a replay can leave one): no advance, the rest runs
        var s = RFix.state([pair(1, group: "A"), pair(2)])
        s = RFix.reduced(s, RFix.toggle(s, 0, 0), at: 1)
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertEqual(s.rest?.totalSeconds, 60)
    }

    // MARK: States that broke the rule

    func testUndoNeverBringsBackAMemberThatWouldSplitAGroup() {
        // [A1, A2, X, Y]: A1 is removed (A2 is released), then X and Y become group A (the first free letter), then A1 comes back
        var s = RFix.state([pair(1, group: "A"), pair(2, group: "A"), pair(3), pair(4)])
        s = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 0)), at: 1)
        XCTAssertEqual(groups(s), [nil, nil, nil])
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 1)), at: 2)
        XCTAssertEqual(groups(s), [nil, "B", "B"], "the letter of the removed exercise is kept back while it can come back")
        s = RFix.reduced(s, .undo, at: 3)
        XCTAssertEqual(s.exercises.count, 4)
        XCTAssertEqual(s.exercises[0].id, RFix.uuid(0x101, 0))
        assertContiguous(s)
        XCTAssertNil(s.exercises[0].supersetGroup, "it does not rejoin a group that is not next to it")
    }

    func testALetterIsHandedOutAgainOnceTheRemovalCanNoLongerBeUndone() {
        var s = RFix.state([pair(1, group: "A"), pair(2, group: "A"), pair(3), pair(4)])
        s = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 0)), at: 1)
        let afterExpiry = s.undo!.expiresAt.timeIntervalSince(RFix.at(0)) + 1
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 1)), at: afterExpiry)
        XCTAssertEqual(groups(s), [nil, "A", "A"])
    }

    func testUndoDoesNotPutAMemberIntoASupersetThatTookItsLetterOnAdjacentExercises() {
        // [a(A), b(A), c]: b is removed (a is released), then a and c become a superset, then b comes back
        var s = RFix.state([pair(1, group: "A"), pair(2, group: "A"), pair(3)])
        s = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 1)), at: 1)
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 0)), at: 2)
        s = RFix.reduced(s, .undo, at: 3)
        XCTAssertEqual(s.exercises.count, 3)
        XCTAssertEqual(groups(s).filter { $0 != nil }.count, 2, "only a and c are in a superset")
        XCTAssertNil(s.exercises.first { $0.id == RFix.uuid(0x102, 0) }?.supersetGroup)
        assertContiguous(s)
    }

    func testUndoNeverLandsInsideAnotherGroup() {
        // [X, R, Y]: R is removed, X and Y become a superset, R comes back between them
        var s = RFix.state([pair(1), pair(2), pair(3)])
        s = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 1)), at: 1)
        s = RFix.reduced(s, .toggleSuperset(exerciseID: RFix.ex(s, 0)), at: 2)
        XCTAssertEqual(groups(s), ["A", "A"])
        s = RFix.reduced(s, .undo, at: 3)
        XCTAssertEqual(s.exercises.map { $0.id }, [1, 3, 2].map { RFix.uuid(0x100 + $0, 0) })
        XCTAssertEqual(groups(s), ["A", "A", nil])
        XCTAssertEqual(s.currentExercise?.id, RFix.uuid(0x102, 0), "the restored exercise is current")
    }

    func testUndoBringsBackAMemberIntoItsOwnGroup() {
        var s = RFix.state([pair(1, group: "A"), pair(2, group: "A"), pair(3, group: "A")])
        s = RFix.reduced(s, .removeExercise(exerciseID: RFix.ex(s, 1)), at: 1)
        XCTAssertEqual(groups(s), ["A", "A"])
        s = RFix.reduced(s, .undo, at: 2)
        XCTAssertEqual(groups(s), ["A", "A", "A"])
    }

    func testReplacingAnExerciseKeepsTheGroupAndTheBlock() {
        var s = RFix.state([pair(1, group: "A"), pair(2, group: "A"), pair(3)])
        s = RFix.reduced(s, .replaceExercise(exerciseID: RFix.ex(s, 1), with: RFix.pullup))
        XCTAssertEqual(groups(s), ["A", "A", nil])
        assertContiguous(s)
    }

    func testSyncReplaysThatSplitAGroupAreRepaired() {
        // the phone moved on: a command made for an older order moves an exercise into the middle of a superset
        let base = RFix.state([pair(1), pair(2, group: "A"), pair(3, group: "A"), pair(4)])
        let workout = base.id
        let commands = [
            RemoteCommand(action: .moveExercise(from: 3, to: 2), origin: .watch, issuedAt: RFix.at(1), workoutID: workout),
            RemoteCommand(action: .moveExerciseBy(exerciseID: RFix.uuid(0x101, 0), delta: 1), origin: .watch, issuedAt: RFix.at(2), workoutID: workout),
        ]
        let shown = SyncReconciler.rebase(base, replaying: commands)
        assertContiguous(shown)
        XCTAssertEqual(Set(shown.exercises.map { $0.id }), Set(base.exercises.map { $0.id }))
    }

    func testTheReducerTakesNonContiguousGroupsWithoutTrapping() {
        // A is split by a replay; every action is applied to it and none traps or loops
        let broken = RFix.state([pair(1, group: "A"), pair(2), pair(3, group: "A"), pair(4, group: "B"), pair(5), pair(6, group: "B"), pair(7, group: "A")])
        for action in RFix.sampleActions(for: broken) + [
            .moveExercise(from: 0, to: 6), .moveExercise(from: 6, to: 0), .moveExercise(from: 3, to: 4), .moveExerciseBy(exerciseID: RFix.ex(broken, 2), delta: 2),
            .toggleSuperset(exerciseID: RFix.ex(broken, 0)), .toggleSuperset(exerciseID: RFix.ex(broken, 2)), .toggleSuperset(exerciseID: RFix.ex(broken, 6)),
            .toggleSuperset(exerciseID: RFix.ex(broken, 1)), .removeExercise(exerciseID: RFix.ex(broken, 2)),
        ] {
            var s = broken
            WorkoutReducer.reduce(&s, action, now: RFix.at(1))
            XCTAssertTrue((0..<max(1, s.exercises.count)).contains(s.currentIndex), "\(action)")
        }
        // logging walks the members in order and wraps
        var s = broken
        s = RFix.reduced(s, RFix.toggle(s, 0, 0), at: 1)
        XCTAssertEqual(s.currentIndex, 2)
        s = RFix.reduced(s, RFix.toggle(s, 2, 0), at: 2)
        XCTAssertEqual(s.currentIndex, 6)
        s = RFix.reduced(s, RFix.toggle(s, 6, 0), at: 3)
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertEqual(s.rest?.totalSeconds, 60)
    }

    func testAMovedExerciseOfABrokenStateEndsOutsideEveryBlockOrLeavesItsGroup() {
        // B is split by a replay and A sits inside it: moving A cannot loop, and nothing is lost
        var s = RFix.state([pair(1, group: "B"), pair(2, group: "A"), pair(3, group: "A"), pair(4, group: "B"), pair(5)])
        for step in 0..<10 {
            let count = s.exercises.count
            WorkoutReducer.reduce(&s, .moveExercise(from: step % count, to: (step * 3 + 1) % count), now: RFix.at(Double(step)))
            XCTAssertEqual(Set(s.exercises.map { $0.id }).count, count)
        }
    }
}
