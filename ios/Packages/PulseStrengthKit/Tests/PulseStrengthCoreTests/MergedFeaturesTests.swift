import Foundation
import XCTest
@testable import PulseStrengthCore

/// Features that two lines of work built independently and that now share one reducer and one state: the undo of a replaced exercise
/// next to the superset rule and timed sets, and the payloads of the builds before either.
final class MergedFeaturesTests: XCTestCase {
    private let start = SvcSyncFix.epoch

    private func state(_ ids: [String]) -> WorkoutState {
        var state = WorkoutState(id: SvcSyncFix.uuid(8800), name: "Merged", startedAt: start)
        for (index, id) in ids.enumerated() {
            let exercise = ExerciseLibrary.exercise(id: id)!
            state.exercises.append(WorkoutExercise(
                id: SvcSyncFix.uuid(8810 + index),
                exercise: exercise,
                sets: [LoggedSet(id: SvcSyncFix.uuid(8820 + index), type: .normal, weightKg: 60, reps: 8)],
                restSeconds: 90
            ))
        }
        return state
    }

    private func reduce(_ state: WorkoutState, _ action: WorkoutAction, at offset: TimeInterval = 0) -> WorkoutState {
        var copy = state
        WorkoutReducer.reduce(&copy, action, now: start.addingTimeInterval(offset))
        return copy
    }

    // MARK: Replace undo with the superset rule and timed sets

    func testReplacingAMemberOfASupersetAndUndoingKeepsTheGroupTogether() {
        var s = state(["bench", "incline", "ohp"])
        s = reduce(s, .toggleSuperset(exerciseID: s.exercises[0].id))
        XCTAssertEqual(s.exercises.map { $0.supersetGroup }, ["A", "A", nil])
        s.exercises[0].sets[0].isDone = true
        let originalID = s.exercises[0].id
        s = reduce(s, .replaceExercise(exerciseID: originalID, with: ExerciseLibrary.exercise(id: "crossover")!), at: 1)
        XCTAssertEqual(s.exercises[0].exercise.id, "crossover")
        XCTAssertEqual(s.exercises[0].supersetGroup, "A", "the entry keeps its group")
        XCTAssertEqual(s.undo?.title, "Replaced Barbell bench press")

        s = reduce(s, .undo, at: 2)
        XCTAssertEqual(s.exercises[0].exercise.id, "bench")
        XCTAssertTrue(s.exercises[0].sets[0].isDone, "the logged set comes back")
        XCTAssertEqual(s.exercises.map { $0.supersetGroup }, ["A", "A", nil])
        XCTAssertNil(s.undo)
    }

    func testTheUndoOfAReplacedExerciseFollowsTheGroupTheEntryHasNow() {
        var s = state(["bench", "incline", "ohp"])
        s = reduce(s, .toggleSuperset(exerciseID: s.exercises[0].id))
        s.exercises[0].sets[0].isDone = true
        s = reduce(s, .replaceExercise(exerciseID: s.exercises[0].id, with: ExerciseLibrary.exercise(id: "crossover")!), at: 1)
        s = reduce(s, .toggleSuperset(exerciseID: s.exercises[0].id), at: 2)   // leaves the group: the partner is released too
        XCTAssertEqual(s.exercises.map { $0.supersetGroup }, [nil, nil, nil])
        let undone = reduce(s, .undo, at: 3)
        XCTAssertEqual(undone.exercises[0].exercise.id, "bench")
        XCTAssertNil(undone.exercises[0].supersetGroup, "no group is brought back that the entry left in the meantime")
    }

    func testReplacingTheExerciseOfARunningTimedSetEndsTheTimerAndStillOffersTheUndo() {
        var s = state(["plank", "bench"])
        let setRef = SetRef(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[0].id)
        s = reduce(s, .startTimedSet(setRef))
        XCTAssertNotNil(s.timedSet)
        s.exercises[0].note = "hold still"
        s = reduce(s, .replaceExercise(exerciseID: s.exercises[0].id, with: ExerciseLibrary.exercise(id: "pushup")!), at: 5)
        XCTAssertNil(s.timedSet, "the timer belonged to the replaced exercise")
        XCTAssertEqual(s.undo?.title, "Replaced Plank")
        s = reduce(s, .undo, at: 6)
        XCTAssertEqual(s.exercises[0].exercise.id, "plank")
        XCTAssertEqual(s.exercises[0].note, "hold still")
        XCTAssertNil(s.timedSet)
    }

    func testAnUntouchedExerciseReplacedLeavesAnotherPendingUndoAlone() {
        var s = state(["bench", "incline"])
        s = reduce(s, .removeExercise(exerciseID: s.exercises[1].id))
        let pending = s.undo
        XCTAssertNotNil(pending)
        s = reduce(s, .replaceExercise(exerciseID: s.exercises[0].id, with: ExerciseLibrary.exercise(id: "squat")!), at: 1)
        XCTAssertEqual(s.undo, pending)
    }

    // MARK: Payloads of the earlier builds

    func testAStateWithAReplaceUndoRoundTripsAndOlderKeysAreOptional() throws {
        var s = state(["bench", "incline"])
        s.exercises[0].sets[0].isDone = true
        s = reduce(s, .replaceExercise(exerciseID: s.exercises[0].id, with: ExerciseLibrary.exercise(id: "crossover")!), at: 1)
        s.settings.weightUnit = .lb
        let encoder = StrengthJSON.makeEncoder()
        let decoder = StrengthJSON.makeDecoder()
        let data = try encoder.encode(s)
        XCTAssertEqual(try decoder.decode(WorkoutState.self, from: data), s)

        // The build of `main` before the units and timed sets: no `timedSet`, no `weightUnit`.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["timedSet"] = nil
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        settings["weightUnit"] = nil
        object["settings"] = settings
        let old = try JSONSerialization.data(withJSONObject: object)
        var expected = s
        expected.settings.weightUnit = .kg
        let decoded = try decoder.decode(WorkoutState.self, from: old)
        XCTAssertEqual(decoded, expected)
        XCTAssertNil(decoded.timedSet)
        if case .replaced = decoded.undo?.payload {} else { XCTFail("the replace undo survives the round trip") }
    }

    func testATemplateFromTheEarlierBuildsDecodesWithoutNoteAndRange() throws {
        let entry = TemplateEntry(exercise: ExerciseLibrary.exercise(id: "bench")!, plannedSets: [PlannedSet(weightKg: 60, reps: 8)], restSeconds: 90)
        let encoder = StrengthJSON.makeEncoder()
        let data = try encoder.encode(entry)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("\"note\""), "no note, no key")
        XCTAssertFalse(text.contains("repsMax"), "no range, no key")
        XCTAssertEqual(try StrengthJSON.makeDecoder().decode(TemplateEntry.self, from: data), entry)

        var withNote = entry
        withNote.note = "Slow eccentric"
        withNote.plannedSets[0].repsMax = 10
        XCTAssertEqual(try StrengthJSON.makeDecoder().decode(TemplateEntry.self, from: encoder.encode(withNote)), withNote)
    }

    func testTheKeepersOfBothLinesWorkTogetherInOneWorkout() throws {
        // A template with a range and a note starts a workout; the workout logs a set inside the range; the update the finish flow offers
        // keeps the range and the note, and the diff sees nothing to ask about.
        var template = WorkoutTemplate(name: "Push", entries: [
            TemplateEntry(
                exercise: ExerciseLibrary.exercise(id: "bench")!,
                plannedSets: [PlannedSet(weightKg: 60, reps: 8, repsMax: 10)],
                restSeconds: 90, note: "Pause on the chest"
            ),
        ])
        template.lastPerformed = nil
        var s = WorkoutFactory.makeWorkout(from: template, now: start)
        XCTAssertEqual(s.exercises[0].note, "Pause on the chest")
        s.exercises[0].sets[0].reps = 10
        s.exercises[0].sets[0].isDone = true
        XCTAssertTrue(TemplateDiff.compute(for: s, against: template).isEmpty)
        let completed = SummaryBuilder.build(from: s, finishedAt: start.addingTimeInterval(600))
        XCTAssertEqual(completed.exercises[0].note, "Pause on the chest")
        XCTAssertEqual(completed.personalRecords, [], "nothing in the history to beat")
        let updated = WorkoutFactory.updatedTemplate(template, from: s)
        XCTAssertEqual(updated.entries[0].note, "Pause on the chest")
    }
}
