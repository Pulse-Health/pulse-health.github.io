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

    func testRotationFollowsTheMostRecentlyPerformedTemplate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func template(_ name: String, daysAgo: Double?) -> WorkoutTemplate {
            WorkoutTemplate(name: name, entries: [], lastPerformed: daysAgo.map { now.addingTimeInterval(-$0 * 86_400) })
        }
        XCTAssertNil(TemplateRotation.next(in: []))
        XCTAssertEqual(TemplateRotation.next(in: [template("A", daysAgo: nil), template("B", daysAgo: nil)])?.name, "A")
        XCTAssertEqual(TemplateRotation.next(in: [template("A", daysAgo: 5), template("B", daysAgo: 7), template("C", daysAgo: 3)])?.name, "A")
        XCTAssertEqual(TemplateRotation.next(in: [template("A", daysAgo: 5), template("B", daysAgo: 1), template("C", daysAgo: 3)])?.name, "C")
        XCTAssertEqual(TemplateRotation.next(in: [template("Only", daysAgo: 2)])?.name, "Only")
        // Equal dates: the earlier template counts as the latest.
        XCTAssertEqual(TemplateRotation.next(in: [template("A", daysAgo: 2), template("B", daysAgo: 2), template("C", daysAgo: nil)])?.name, "B")
    }
}
