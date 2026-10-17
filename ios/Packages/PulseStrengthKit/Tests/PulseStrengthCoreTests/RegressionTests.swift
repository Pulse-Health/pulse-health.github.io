import Foundation
import XCTest
@testable import PulseStrengthCore

/// One test per verified bug, named after its id. Each test uses only the documented bounds (as literals), so it states the
/// contract in ARCHITECTURE.md and not the name of a constant.
final class RegressionTests: XCTestCase {
    // MARK: B1: an unbounded weight traps the presenter

    /// The reducer used to accept any finite weight (1e20, 1e300). Logged as a personal record, it made
    /// `WorkoutPresenter` convert an enormous Double to Int and trap, and because the active workout is saved after every change
    /// the same state trapped again on every launch.
    func testB1_AnAbsurdWeightIsBoundedAndNeverTrapsThePresenter() throws {
        let maximumKg = 1_000_000.0   // ARCHITECTURE 3.2 rule 3

        // The reducer bounds the weight (and still keeps what the keypad can type: at most 6 characters, so 999999).
        let design = RedFix.designState()
        let exercise = design.exercises[0]
        let setID = exercise.sets[2].id
        func weight(after kg: Double) -> Double {
            var s = design
            WorkoutReducer.reduce(&s, .setWeight(exerciseID: exercise.id, setID: setID, kg: kg), now: RedFix.t0)
            return s.exercises[0].sets[2].weightKg
        }
        XCTAssertEqual(weight(after: 999_999), 999_999, "a value the keypad can produce is kept")
        XCTAssertEqual(weight(after: 1e20), maximumKg)
        XCTAssertEqual(weight(after: 1e300), maximumKg)
        XCTAssertEqual(weight(after: Double.greatestFiniteMagnitude), maximumKg)
        XCTAssertEqual(weight(after: -1e20), 0)
        XCTAssertEqual(weight(after: .infinity), 82.5, "not representable: still ignored")
        XCTAssertEqual(weight(after: .nan), 82.5, "still ignored")

        // The reported scenario: a record set with the absurd weight, then present (this trapped).
        var s = design
        WorkoutReducer.reduce(&s, .setWeight(exerciseID: exercise.id, setID: setID, kg: 1e20), now: RedFix.t0)
        WorkoutReducer.reduce(&s, .logSet(exerciseID: exercise.id, setID: setID), now: RedFix.at(1))
        let view = WorkoutPresenter.present(s, now: RedFix.at(2), recovery: DemoRecovery.provider)
        let row = try XCTUnwrap(view.card?.rows[2])
        XCTAssertTrue(row.isPersonalRecord)
        XCTAssertNotNil(row.estimated1RM)

        // A state that did not come through the reducer (a file saved by an older build, a corrupt file, a decoded sync message)
        // must not crash the presenter either. The weights below are what an older build could have saved.
        for kg in [1e20, 1e300, Double.greatestFiniteMagnitude] {
            var raw = design
            raw.exercises[0].sets[2].weightKg = kg
            raw.exercises[0].sets[2].isDone = true

            let persistence = FileStrengthPersistence.temporary()
            let directory = persistence.directory
            addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
            try persistence.saveActiveWorkout(raw)
            let reloaded = try XCTUnwrap(persistence.loadActiveWorkout(), "the file round trips")

            let shown = WorkoutPresenter.present(reloaded, now: RedFix.at(2), recovery: DemoRecovery.provider)
            XCTAssertEqual(shown.card?.rows.count, 5)
            _ = SnapshotBuilder.make(from: reloaded, now: RedFix.at(2))
            let summary = SummaryBuilder.build(from: reloaded, finishedAt: RedFix.at(3))
            XCTAssertEqual(summary.loggedSets, 1)
            XCTAssertTrue(summary.exercises.allSatisfy { $0.bestE1RM.isFinite }, "an estimate that overflowed is not stored")
            XCTAssertTrue(summary.personalRecords.allSatisfy { $0.estimated1RM.isFinite })
        }
    }

    // MARK: B2: an unbounded rest overflows the template estimate

    /// `setRest(Int.max)` was accepted, copied into a saved template and `WorkoutTemplate.estimatedMinutes` (shown on the hub)
    /// overflowed its integer arithmetic.
    func testB2_AnAbsurdRestIsBoundedAndTheTemplateEstimateNeverTraps() {
        let maximumRest = 3_600   // ARCHITECTURE 3.2 rule 7

        let design = RedFix.designState()
        let exerciseID = design.exercises[0].id
        func rest(after seconds: Int) -> Int {
            var s = design
            WorkoutReducer.reduce(&s, .setRest(exerciseID: exerciseID, seconds: seconds), now: RedFix.t0)
            return s.exercises[0].restSeconds
        }
        XCTAssertEqual(rest(after: 0), 0)
        XCTAssertEqual(rest(after: 105), 105)
        XCTAssertEqual(rest(after: 3_600), 3_600, "the bound itself is allowed")
        XCTAssertEqual(rest(after: 3_601), maximumRest)
        XCTAssertEqual(rest(after: Int.max), maximumRest)
        XCTAssertEqual(rest(after: -5), 0)
        XCTAssertEqual(rest(after: Int.min), 0)

        // The reported scenario: the huge rest reaches a template, whose estimate is shown on the hub.
        var s = design
        WorkoutReducer.reduce(&s, .setRest(exerciseID: exerciseID, seconds: Int.max), now: RedFix.t0)
        let template = WorkoutFactory.template(from: s, name: "Mine")
        XCTAssertEqual(template.entries[0].restSeconds, maximumRest)
        XCTAssertGreaterThanOrEqual(template.estimatedMinutes, 5)

        // A template that did not come through the reducer (a corrupt file) must not trap either.
        var corrupt = template
        corrupt.entries[0].restSeconds = Int.max
        corrupt.entries[1].restSeconds = Int.min
        XCTAssertGreaterThanOrEqual(corrupt.estimatedMinutes, 5)
        XCTAssertGreaterThan(corrupt.estimatedMinutes, SampleData.templates()[0].estimatedMinutes, "an hour of rest still counts")

        // The estimate of every normal template is unchanged (the original integer arithmetic, rests of 0...3600 s).
        func reference(_ template: WorkoutTemplate) -> Int {
            var seconds = 0
            for entry in template.entries {
                for set in entry.plannedSets {
                    seconds += 45 + (set.type == .warmup ? max(30, entry.restSeconds * 2 / 5) : entry.restSeconds)
                }
            }
            return max(5, Int((Double(seconds) / 60.0 / 5.0).rounded()) * 5)
        }
        for sample in SampleData.templates() {
            XCTAssertEqual(sample.estimatedMinutes, reference(sample), sample.name)
        }
    }

    // MARK: SVC-1: finish deletes the only copy of the workout when the history cannot be saved

    /// `StrengthDataModel.persist` swallowed write errors and `WorkoutEngine.finish` then deleted `active-workout.json`
    /// unconditionally, so a failed `history.json` write lost the whole workout at the next launch.
    func testSVC1_FinishKeepsTheActiveWorkoutFileWhenTheHistoryCouldNotBeSaved() throws {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        // history.json can no longer be replaced (stands in for a full disk / I/O error: the atomic write throws).
        let blocker = directory.appendingPathComponent("history.json", isDirectory: true)
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: blocker.appendingPathComponent("keep"))

        let workoutID: UUID = svcMain {
            let rig = SvcRig(self, persistence: persistence)
            // The unreadable history.json stops the demo seeding, so the template comes from the sample data directly.
            rig.engine.start(template: SampleData.templates()[0])
            rig.logSets(2)
            let loggedBefore = rig.engine.state?.exercises.reduce(0) { $0 + $1.doneCount }
            XCTAssertEqual(loggedBefore, 2)
            let id = rig.engine.state!.id

            let completed = rig.engine.finish(updateTemplate: false)
            XCTAssertEqual(completed?.loggedSets, 2, "the user still gets the finished workout (summary screen)")
            XCTAssertNil(rig.engine.state)
            XCTAssertEqual(rig.model.data.history.first?.id, id, "the workout is in memory")
            XCTAssertNotNil(rig.engine.lastPersistenceError, "the failed save is reported, not swallowed")

            // What a relaunch would find on disk.
            XCTAssertTrue(persistence.loadHistory().isEmpty, "precondition: nothing could be written to history.json")
            XCTAssertNotNil(persistence.loadActiveWorkout(), "the two logged sets exist nowhere on disk any more")
            return id
        }

        // The relaunch: the unsaved workout comes back with every logged set, and finishing it again saves it once the disk works.
        try FileManager.default.removeItem(at: blocker)
        svcMain {
            let rig = SvcRig(self, seed: false, persistence: persistence)
            rig.engine.restore()
            XCTAssertEqual(rig.engine.state?.id, workoutID)
            XCTAssertEqual(rig.engine.state?.exercises.reduce(0) { $0 + $1.doneCount }, 2)
            XCTAssertNotNil(rig.engine.finish(updateTemplate: false))
            XCTAssertNil(rig.engine.lastPersistenceError)
            XCTAssertEqual(persistence.loadHistory().map { $0.id }, [workoutID], "saved exactly once")
            XCTAssertNil(persistence.loadActiveWorkout(), "now that the history is safe the active file is removed")
        }
    }
}
