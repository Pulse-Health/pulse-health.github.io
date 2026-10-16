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
}
