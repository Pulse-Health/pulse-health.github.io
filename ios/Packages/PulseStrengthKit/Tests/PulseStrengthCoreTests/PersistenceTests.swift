import Foundation
import XCTest
@testable import PulseStrengthCore

final class PersistenceTests: XCTestCase {
    private let now = SvcSyncFix.epoch

    /// A fresh persistence in a temporary directory that is removed when the test ends.
    private func makePersistence() -> FileStrengthPersistence {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return persistence
    }

    /// The names of the data files (`schema.json` is checked by its own tests).
    private func fileNames(_ persistence: FileStrengthPersistence) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: persistence.directory.path)) ?? []).filter { $0 != "schema.json" }.sorted()
    }

    private func text(_ persistence: FileStrengthPersistence, _ name: String) -> String {
        (try? String(contentsOf: persistence.directory.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }

    // MARK: Empty and missing

    func testEverythingReadsAsEmptyBeforeAnythingWasSaved() {
        let persistence = makePersistence()
        XCTAssertNil(persistence.loadActiveWorkout())
        XCTAssertEqual(persistence.loadTemplates(), [])
        XCTAssertEqual(persistence.loadHistory(), [])
        XCTAssertEqual(persistence.loadCustomExercises(), [])
        XCTAssertEqual(persistence.loadPersonalBests(), [:])
    }

    func testTemporaryPersistenceUsesADistinctDirectoryEachTime() {
        let first = makePersistence()
        let second = makePersistence()
        XCTAssertNotEqual(first.directory, second.directory)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.directory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testAppGroupIsOnlyAvailableOnApplePlatforms() {
        #if canImport(Darwin)
        // macOS hands out a group container path even without the entitlement, iOS returns nil: both are valid.
        // When a container exists, the persistence lives in its "PulseStrength" subdirectory.
        if let persistence = FileStrengthPersistence.appGroup(identifier: "group.invalid.\(UUID().uuidString)") {
            XCTAssertEqual(persistence.directory.lastPathComponent, "PulseStrength")
        }
        #else
        XCTAssertNil(FileStrengthPersistence.appGroup(identifier: StrengthConfig.appGroupID))
        #endif
    }

    // MARK: Round trips

    func testActiveWorkoutRoundTrip() throws {
        let persistence = makePersistence()
        let state = SvcSyncFix.richState()
        try persistence.saveActiveWorkout(state)
        XCTAssertEqual(persistence.loadActiveWorkout(), state)
        XCTAssertEqual(fileNames(persistence), ["active-workout.json"])
    }

    func testSavingNilDeletesTheActiveWorkoutAndDeletingTwiceIsFine() throws {
        let persistence = makePersistence()
        try persistence.saveActiveWorkout(SvcSyncFix.richState())
        try persistence.saveActiveWorkout(nil)
        XCTAssertNil(persistence.loadActiveWorkout())
        XCTAssertEqual(fileNames(persistence), [])
        XCTAssertNoThrow(try persistence.saveActiveWorkout(nil))
    }

    func testTemplatesRoundTripKeepsOrderAndDates() throws {
        let persistence = makePersistence()
        let templates = SampleData.templates(now: now)
        try persistence.saveTemplates(templates)
        XCTAssertEqual(persistence.loadTemplates(), templates)
    }

    func testHistoryRoundTrip() throws {
        let persistence = makePersistence()
        let history = SampleData.history(now: now)
        try persistence.saveHistory(history)
        XCTAssertEqual(persistence.loadHistory(), history)
    }

    func testCustomExercisesRoundTrip() throws {
        let persistence = makePersistence()
        let exercises = [
            Exercise.custom(name: "Zercher squat", muscle: .legs, equipment: .barbell, tracking: .weightReps, id: "custom-1"),
            Exercise.custom(name: "Dead hang", muscle: .back, equipment: .bodyweight, tracking: .duration, id: "custom-2"),
        ]
        try persistence.saveCustomExercises(exercises)
        XCTAssertEqual(persistence.loadCustomExercises(), exercises)
    }

    func testPersonalBestsRoundTrip() throws {
        let persistence = makePersistence()
        let bests = SampleData.personalBests(now: now)
        XCTAssertFalse(bests.isEmpty)
        try persistence.savePersonalBests(bests)
        XCTAssertEqual(persistence.loadPersonalBests(), bests)
    }

    func testSavingEmptyCollectionsReadsBackEmpty() throws {
        let persistence = makePersistence()
        try persistence.saveTemplates(SampleData.templates())
        try persistence.saveTemplates([])
        XCTAssertEqual(persistence.loadTemplates(), [])
        try persistence.savePersonalBests(["bench": PersonalBest(exerciseID: "bench", estimated1RM: 99, weightKg: 85, reps: 5, date: now)])
        try persistence.savePersonalBests([:])
        XCTAssertEqual(persistence.loadPersonalBests(), [:])
    }

    func testASecondInstanceOnTheSameDirectorySeesTheData() throws {
        let persistence = makePersistence()
        try persistence.saveHistory(SampleData.history(now: now))
        let other = FileStrengthPersistence(directory: persistence.directory)
        XCTAssertEqual(other.loadHistory(), SampleData.history(now: now))
    }

    // MARK: File format

    func testFilesUseSortedKeysAndISO8601Dates() throws {
        let persistence = makePersistence()
        let bench = PersonalBest(exerciseID: "bench", estimated1RM: 99.5, weightKg: 85, reps: 5, date: now)
        let squat = PersonalBest(exerciseID: "squat", estimated1RM: 96, weightKg: 80, reps: 6, date: now)
        let calf = PersonalBest(exerciseID: "calf", estimated1RM: 84, weightKg: 60, reps: 12, date: now)
        try persistence.savePersonalBests(["squat": squat, "bench": bench, "calf": calf])
        let first = text(persistence, "personal-bests.json")
        XCTAssertTrue(first.contains("\"2026-10-13T19:30:00.000Z\""), first)
        let positions = ["bench", "calf", "squat"].map { first.range(of: "\"\($0)\":{")?.lowerBound }
        XCTAssertFalse(positions.contains { $0 == nil }, first)
        XCTAssertLessThan(positions[0]!, positions[1]!)
        XCTAssertLessThan(positions[1]!, positions[2]!)
        // Writing the same value again gives identical bytes.
        try persistence.savePersonalBests(["calf": calf, "bench": bench, "squat": squat])
        XCTAssertEqual(text(persistence, "personal-bests.json"), first)
    }

    func testFilesAreReadableJSON() throws {
        let persistence = makePersistence()
        try persistence.saveActiveWorkout(SvcSyncFix.richState())
        try persistence.saveTemplates(SampleData.templates())
        try persistence.saveHistory(SampleData.history(now: now))
        for name in ["active-workout.json", "templates.json", "history.json"] {
            let data = try Data(contentsOf: persistence.directory.appendingPathComponent(name))
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data), name)
        }
    }

    func testFilesWrittenWithTheStandardISO8601StrategyStillLoad() throws {
        let persistence = makePersistence()
        let json = "{\"bench\":{\"exerciseID\":\"bench\",\"estimated1RM\":99,\"weightKg\":85,\"reps\":5,\"date\":\"2026-10-13T19:30:00Z\"}}"
        try Data(json.utf8).write(to: persistence.directory.appendingPathComponent("personal-bests.json"))
        XCTAssertEqual(persistence.loadPersonalBests()["bench"]?.date, now)
    }

    // MARK: Atomic writes and robustness

    func testWritesLeaveNoTemporaryFilesBehind() throws {
        let persistence = makePersistence()
        for round in 0..<5 {
            try persistence.saveHistory(Array(SampleData.history(now: now).prefix(round)))
            try persistence.saveActiveWorkout(SvcSyncFix.richState())
            try persistence.saveTemplates(SampleData.templates())
        }
        XCTAssertEqual(fileNames(persistence), ["active-workout.json", "history.json", "templates.json"])
    }

    func testAShorterSaveFullyReplacesALongerOne() throws {
        let persistence = makePersistence()
        try persistence.saveHistory(SampleData.history(now: now))
        try persistence.saveHistory([])
        XCTAssertEqual(persistence.loadHistory(), [])
        XCTAssertEqual(text(persistence, "history.json"), "[]")
    }

    func testCorruptFilesReadAsEmptyValues() throws {
        let persistence = makePersistence()
        let garbage: [Data] = [Data(), Data("not json at all".utf8), Data("{".utf8), Data([0xFF, 0xFE, 0x00, 0x01]), Data("null".utf8), Data("42".utf8)]
        for data in garbage {
            for name in ["active-workout.json", "templates.json", "history.json", "custom-exercises.json", "personal-bests.json"] {
                try data.write(to: persistence.directory.appendingPathComponent(name))
            }
            XCTAssertNil(persistence.loadActiveWorkout())
            XCTAssertEqual(persistence.loadTemplates(), [])
            XCTAssertEqual(persistence.loadHistory(), [])
            XCTAssertEqual(persistence.loadCustomExercises(), [])
            XCTAssertEqual(persistence.loadPersonalBests(), [:])
        }
    }

    func testWrongShapeFilesReadAsEmpty() throws {
        let persistence = makePersistence()
        try Data("{\"a\":1}".utf8).write(to: persistence.directory.appendingPathComponent("templates.json"))
        try Data("[1,2,3]".utf8).write(to: persistence.directory.appendingPathComponent("personal-bests.json"))
        XCTAssertEqual(persistence.loadTemplates(), [])
        XCTAssertEqual(persistence.loadPersonalBests(), [:])
    }

    func testAnUnreadableElementIsSkippedAndTheRestIsKept() throws {
        let persistence = makePersistence()
        let templates = SampleData.templates()
        try persistence.saveTemplates(templates)
        let original = text(persistence, "templates.json")
        // Insert a broken element between the first and second template.
        let broken = "{\"id\":\"oops\",\"name\":5}"
        var parts = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(original.utf8)) as? [Any])
        parts.insert(try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(broken.utf8))), at: 1)
        try JSONSerialization.data(withJSONObject: parts).write(to: persistence.directory.appendingPathComponent("templates.json"))
        XCTAssertEqual(persistence.loadTemplates(), templates)

        try persistence.savePersonalBests(SampleData.personalBests(now: now))
        var bests = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text(persistence, "personal-bests.json").utf8)) as? [String: Any])
        let count = bests.count
        bests["broken"] = "not a personal best"
        try JSONSerialization.data(withJSONObject: bests).write(to: persistence.directory.appendingPathComponent("personal-bests.json"))
        XCTAssertEqual(persistence.loadPersonalBests().count, count)
        XCTAssertNil(persistence.loadPersonalBests()["broken"])
    }

    func testSavingRecreatesAMissingDirectory() throws {
        let persistence = makePersistence()
        try FileManager.default.removeItem(at: persistence.directory)
        try persistence.saveTemplates(SampleData.templates())
        XCTAssertEqual(persistence.loadTemplates(), SampleData.templates())
    }

    func testSavingFailsWithAnErrorWhenTheDirectoryCannotBeCreated() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("PulseStrength-blocker-" + UUID().uuidString)
        try Data("file".utf8).write(to: blocker)
        addTeardownBlock { try? FileManager.default.removeItem(at: blocker) }
        let persistence = FileStrengthPersistence(directory: blocker.appendingPathComponent("inner"))
        XCTAssertThrowsError(try persistence.saveHistory([]))
        XCTAssertEqual(persistence.loadHistory(), [])
        XCTAssertNil(persistence.loadActiveWorkout())
    }

    func testConcurrentSavesNeverCorruptTheFile() throws {
        let persistence = makePersistence()
        let histories = (0..<6).map { Array(SampleData.history(now: now).prefix($0)) }
        DispatchQueue.concurrentPerform(iterations: 60) { index in
            try? persistence.saveHistory(histories[index % histories.count])
            _ = persistence.loadHistory()
        }
        let loaded = persistence.loadHistory()
        XCTAssertTrue(histories.contains(loaded), "loaded \(loaded.count) workouts")
    }

    func testPersistenceIsSendable() {
        func requireSendable<T: Sendable>(_ value: T) {}
        requireSendable(makePersistence())
    }
}
