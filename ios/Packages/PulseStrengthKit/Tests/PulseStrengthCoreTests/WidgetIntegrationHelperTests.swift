import XCTest
@testable import PulseStrengthCore

final class WidgetIntegrationHelperTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Migration-" + UUID().uuidString, isDirectory: true)
    }

    func testMigrationCopiesOnlyMissingFilesAndKeepsTheOriginals() throws {
        let legacy = temporaryDirectory()
        let target = temporaryDirectory()
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("old templates".utf8).write(to: legacy.appendingPathComponent("templates.json"))
        try Data("old history".utf8).write(to: legacy.appendingPathComponent("history.json"))
        try Data("new history".utf8).write(to: target.appendingPathComponent("history.json"))

        XCTAssertEqual(StrengthDataMigration.copyMissingFiles(from: legacy, to: target), 1)
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("templates.json")), "old templates")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("history.json")), "new history")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("templates.json").path))
        // Running it again changes nothing.
        XCTAssertEqual(StrengthDataMigration.copyMissingFiles(from: legacy, to: target), 0)
    }

    func testMigrationFromAMissingFolderOrTheSameFolderIsANoOp() {
        let folder = temporaryDirectory()
        XCTAssertEqual(StrengthDataMigration.copyMissingFiles(from: folder, to: temporaryDirectory()), 0)
        XCTAssertEqual(StrengthDataMigration.copyMissingFiles(from: folder, to: folder), 0)
    }

    /// Fails when `FileStrengthPersistence` starts writing a file that the migration to the App Group container would leave behind.
    func testMigrationKnowsEveryFileThePersistenceWrites() throws {
        let directory = temporaryDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.saveActiveWorkout(WorkoutFactory.makeEmpty(name: "Workout", now: Date()))
        try persistence.saveTemplates(SampleData.templates())
        try persistence.saveHistory(SampleData.history(now: Date()))
        try persistence.saveCustomExercises([])
        try persistence.savePersonalBests([:])
        try persistence.saveAcknowledgedCommands([UUID()])
        try persistence.saveBodyWeights([])
        try persistence.saveWeighInPreferences(WeighInPreferences())
        try persistence.savePlans([])
        let written = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".json") }
        for name in written {
            XCTAssertTrue(StrengthDataMigration.fileNames.contains(name), "\(name) is written by FileStrengthPersistence but not migrated")
        }
        XCTAssertGreaterThanOrEqual(written.count, 8)
    }
}
