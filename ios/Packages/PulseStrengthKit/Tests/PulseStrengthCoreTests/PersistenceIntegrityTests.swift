import Foundation
import XCTest
@testable import PulseStrengthCore

/// A clock the tests move by hand.
private final class IntegrityClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
    }
}

/// How many times a migration ran, and whether it should fail.
private final class MigrationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var runs = 0
    private var failing: Bool

    init(failing: Bool = false) { self.failing = failing }

    var runCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return runs
    }

    func setFailing(_ value: Bool) {
        lock.lock()
        failing = value
        lock.unlock()
    }

    func recordRun() throws {
        lock.lock()
        runs += 1
        let fails = failing
        lock.unlock()
        if fails { throw CocoaError(.fileWriteUnknown) }
    }
}

/// What the previous version of the app writes, as literal JSON (the first version of every format).
enum V1Files {
    static let exercise = """
    {"barKg":20,"cues":["Keep your back flat."],"defaults":{"reps":8,"restSeconds":150,"sets":3,"weightKg":60},"equipment":"Barbell","id":"bench","isCustom":false,"mediaKey":"bench","muscle":"Chest","name":"Barbell bench press","previousBestE1RM":0,"previousSets":[],"secondary":"Shoulders · Triceps","tracking":"weightReps"}
    """

    static func template(_ number: Int, name: String) -> String {
        """
        {"entries":[{"exercise":\(exercise),"id":"0000FEED-0000-4000-8000-0000000001\(String(format: "%02d", number))","plannedSets":[{"reps":8,"type":"normal","weightKg":60}],"restSeconds":150}],"id":"0000FEED-0000-4000-8000-0000000000\(String(format: "%02d", number))","name":"\(name)"}
        """
    }

    static func workout(_ number: Int, finishedAt: String) -> String {
        """
        {"durationSeconds":3000,"exercises":[{"bestE1RM":76,"exerciseID":"bench","id":"0000FEED-0000-4000-8000-0000000002\(String(format: "%02d", number))","isPersonalRecord":false,"mediaKey":"bench","muscle":"Chest","name":"Barbell bench press","sets":[{"reps":6,"type":"normal","weightKg":63.5}],"tracking":"weightReps"}],"finishedAt":"\(finishedAt)","id":"0000FEED-0000-4000-8000-0000000003\(String(format: "%02d", number))","loggedSets":1,"muscleSets":[{"muscle":"Chest","sets":1}],"name":"Upper A","personalRecords":[],"startedAt":"2026-10-13T18:40:00.000Z","volumeKg":381}
        """
    }

    static let bests = """
    {"bench":{"date":"2026-10-13T19:30:00.000Z","estimated1RM":76.2,"exerciseID":"bench","reps":6,"weightKg":63.5}}
    """

    static let bodyWeights = """
    [{"date":"2026-10-12T07:00:00.000Z","id":"0000FEED-0000-4000-8000-000000000401","kg":82.4}]
    """

    static let preferences = """
    {"enabledAt":"2026-10-01T08:00:00.000Z","hour":7,"interval":"weekly","isEnabled":true,"minute":30}
    """

    static let acknowledged = """
    ["0000FEED-0000-4000-8000-000000000501","0000FEED-0000-4000-8000-000000000502"]
    """
}

final class PersistenceIntegrityTests: XCTestCase {
    private let epoch = SvcSyncFix.epoch

    // MARK: Helpers

    private func makeDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PulseStrength-integrity-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makePersistence(
        _ directory: URL? = nil,
        migrations: [PersistenceMigration] = [],
        clock: IntegrityClock? = nil
    ) -> FileStrengthPersistence {
        let clock = clock ?? IntegrityClock(epoch)
        return FileStrengthPersistence(directory: directory ?? makeDirectory(), migrations: migrations, clock: { clock.now })
    }

    private func write(_ text: String, _ name: String, in directory: URL) throws {
        try Data(text.utf8).write(to: directory.appendingPathComponent(name))
    }

    private func bytes(_ name: String, in directory: URL) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    private func names(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private func backups(of file: String, in directory: URL) -> [String] {
        let prefix = String(file.dropLast(5)) + ".corrupt-"
        return names(in: directory).filter { $0.hasPrefix(prefix) }
    }

    private func schemaVersionOnDisk(in directory: URL) -> Int? {
        guard let data = bytes("schema.json", in: directory),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Int]
        else { return nil }
        return object["version"]
    }

    /// Writes every data file in the first format, as an install of the previous version has them.
    private func writeVersion1Directory(_ directory: URL) throws {
        try write("[\(V1Files.template(1, name: "Push")),\(V1Files.template(2, name: "Pull"))]", "templates.json", in: directory)
        try write("[\(V1Files.workout(2, finishedAt: "2026-10-13T19:30:00.000Z")),\(V1Files.workout(1, finishedAt: "2026-10-10T19:30:00.000Z"))]", "history.json", in: directory)
        try write("[\(V1Files.exercise.replacingOccurrences(of: "\"id\":\"bench\"", with: "\"id\":\"custom-hex\"").replacingOccurrences(of: "\"isCustom\":false", with: "\"isCustom\":true"))]", "custom-exercises.json", in: directory)
        try write(V1Files.bests, "personal-bests.json", in: directory)
        try write(V1Files.bodyWeights, "body-weights.json", in: directory)
        try write(V1Files.preferences, "weigh-in-preferences.json", in: directory)
        try write(V1Files.acknowledged, "acknowledged-commands.json", in: directory)
    }

    // MARK: Schema version

    func testAFreshDirectoryGetsItsSchemaFileWithTheFirstWrite() throws {
        let directory = makeDirectory()
        let persistence = makePersistence(directory)
        XCTAssertEqual(persistence.schemaVersion, 1)
        XCTAssertEqual(persistence.currentSchemaVersion, 1)
        XCTAssertEqual(names(in: directory), [], "reading writes nothing")
        XCTAssertEqual(persistence.loadTemplates(), [])
        XCTAssertEqual(names(in: directory), [])

        try persistence.saveTemplates([])
        XCTAssertEqual(schemaVersionOnDisk(in: directory), 1)
        XCTAssertEqual(String(data: bytes("schema.json", in: directory) ?? Data(), encoding: .utf8), "{\"version\":1}")
    }

    func testADirectoryWithoutASchemaFileIsVersion1AndLoadsUnchanged() throws {
        let directory = makeDirectory()
        try writeVersion1Directory(directory)
        let before = names(in: directory)
        let persistence = makePersistence(directory)

        XCTAssertEqual(persistence.schemaVersion, 1)
        XCTAssertTrue(persistence.canWrite)
        XCTAssertEqual(persistence.loadTemplates().map { $0.name }, ["Push", "Pull"])
        XCTAssertEqual(persistence.loadTemplates().first?.entries.first?.note, "", "a template written before notes reads without one")
        XCTAssertEqual(persistence.loadHistory().map { $0.name }, ["Upper A", "Upper A"])
        XCTAssertEqual(persistence.loadHistory().first?.exercises.first?.note, "", "a workout written before notes reads without one")
        XCTAssertEqual(persistence.loadHistory().first?.exercises.first?.sets.first?.weightKg, 63.5)
        XCTAssertEqual(persistence.loadCustomExercises().map { $0.id }, ["custom-hex"])
        XCTAssertEqual(persistence.loadPersonalBests()["bench"]?.estimated1RM, 76.2)
        XCTAssertEqual(persistence.loadBodyWeights().map { $0.kg }, [82.4])
        XCTAssertEqual(persistence.loadWeighInPreferences().hour, 7)
        XCTAssertEqual(persistence.loadAcknowledgedCommands().count, 2)
        XCTAssertEqual(persistence.loadIssues, [], "nothing in a version 1 directory is damaged")
        XCTAssertEqual(names(in: directory), before, "loading writes nothing: no schema file, no backups")

        try persistence.saveTemplates(persistence.loadTemplates())
        XCTAssertEqual(schemaVersionOnDisk(in: directory), 1)
    }

    func testASchemaFileOfVersion1ChangesNothing() throws {
        let directory = makeDirectory()
        try writeVersion1Directory(directory)
        try write("{\"version\":1}", "schema.json", in: directory)
        let persistence = makePersistence(directory)
        XCTAssertEqual(persistence.loadTemplates().count, 2)
        XCTAssertEqual(persistence.loadIssues, [])
        XCTAssertTrue(persistence.canWrite)
        XCTAssertEqual(persistence.schemaVersion, 1)
    }

    func testANewerSchemaIsReadButNeverWritten() throws {
        let directory = makeDirectory()
        try writeVersion1Directory(directory)
        try write("{\"version\":7}", "schema.json", in: directory)
        let templatesBefore = bytes("templates.json", in: directory)
        let persistence = makePersistence(directory)

        XCTAssertEqual(persistence.schemaVersion, 7)
        XCTAssertFalse(persistence.canWrite)
        XCTAssertEqual(persistence.loadTemplates().count, 2, "what can be read is read")
        XCTAssertEqual(persistence.loadIssues, [PersistenceIssue(fileName: "schema.json", kind: .newerSchema)])

        let refused = PersistenceError.newerSchema(found: 7, supported: 1)
        XCTAssertThrowsError(try persistence.saveTemplates([])) { XCTAssertEqual($0 as? PersistenceError, refused) }
        XCTAssertThrowsError(try persistence.saveHistory([])) { XCTAssertEqual($0 as? PersistenceError, refused) }
        XCTAssertThrowsError(try persistence.saveActiveWorkout(SvcSyncFix.richState())) { XCTAssertEqual($0 as? PersistenceError, refused) }
        XCTAssertThrowsError(try persistence.saveActiveWorkout(nil)) { XCTAssertEqual($0 as? PersistenceError, refused) }
        XCTAssertThrowsError(try persistence.saveWeighInPreferences(WeighInPreferences())) { XCTAssertEqual($0 as? PersistenceError, refused) }

        XCTAssertEqual(bytes("templates.json", in: directory), templatesBefore)
        XCTAssertEqual(schemaVersionOnDisk(in: directory), 7, "the newer version's schema file is left alone")
        XCTAssertTrue((refused.errorDescription ?? "").contains("7"), "the message names the version that was found")
    }

    func testAnUnreadableSchemaFileIsReportedAndRepairedByTheNextSave() throws {
        let directory = makeDirectory()
        try writeVersion1Directory(directory)
        try write("{\"version\":", "schema.json", in: directory)
        let persistence = makePersistence(directory)

        XCTAssertEqual(persistence.loadTemplates().count, 2)
        XCTAssertEqual(persistence.schemaVersion, 1)
        XCTAssertTrue(persistence.canWrite)
        let issue = try XCTUnwrap(persistence.loadIssues.first { $0.fileName == "schema.json" })
        XCTAssertEqual(issue.kind, .unreadableFile)
        XCTAssertNotNil(issue.backupFileName)
        XCTAssertEqual(bytes("schema.json", in: directory), Data("{\"version\":".utf8), "reading does not repair")

        try persistence.saveTemplates(persistence.loadTemplates())
        XCTAssertEqual(schemaVersionOnDisk(in: directory), 1)
        let backup = try XCTUnwrap(issue.backupFileName)
        XCTAssertEqual(bytes(backup, in: directory), Data("{\"version\":".utf8))
    }

    func testASchemaFileWithoutAUsableVersionCountsAsUnreadable() throws {
        for text in ["{}", "{\"version\":0}", "{\"version\":-3}", "[1]", "{\"version\":\"two\"}"] {
            let directory = makeDirectory()
            try writeVersion1Directory(directory)
            try write(text, "schema.json", in: directory)
            let persistence = makePersistence(directory)
            XCTAssertEqual(persistence.schemaVersion, 1, text)
            XCTAssertEqual(persistence.loadIssues.map { $0.kind }, [.unreadableFile], text)
        }
    }

    // MARK: Migrations

    func testMigrationsRunInOrderWhenTheDirectoryIsFirstUsed() throws {
        let directory = makeDirectory()
        try writeVersion1Directory(directory)
        let probe = MigrationProbe()
        let steps = [
            // 1 -> 2: put a prefix before every template name.
            PersistenceMigration { directory in
                try probe.recordRun()
                let url = directory.appendingPathComponent("templates.json")
                let text = try String(contentsOf: url, encoding: .utf8)
                try Data(text.replacingOccurrences(of: "\"name\":\"Push\"", with: "\"name\":\"v2 Push\"").utf8).write(to: url, options: .atomic)
            },
            // 2 -> 3: must see the result of the first step.
            PersistenceMigration { directory in
                try probe.recordRun()
                let url = directory.appendingPathComponent("templates.json")
                let text = try String(contentsOf: url, encoding: .utf8)
                try Data(text.replacingOccurrences(of: "v2 Push", with: "v3 Push").utf8).write(to: url, options: .atomic)
            },
        ]
        let persistence = makePersistence(directory, migrations: steps)

        XCTAssertEqual(persistence.currentSchemaVersion, 3)
        XCTAssertEqual(persistence.loadTemplates().map { $0.name }, ["v3 Push", "Pull"])
        XCTAssertEqual(persistence.schemaVersion, 3)
        XCTAssertEqual(schemaVersionOnDisk(in: directory), 3)
        XCTAssertEqual(probe.runCount, 2)
        XCTAssertEqual(persistence.loadIssues, [])

        // The files as they were before the first step are kept.
        let saved = directory.appendingPathComponent("schema-v1-backup/templates.json")
        XCTAssertTrue(try String(contentsOf: saved, encoding: .utf8).contains("\"name\":\"Push\""))

        // A second instance finds version 3 and runs nothing.
        let again = makePersistence(directory, migrations: steps)
        XCTAssertEqual(again.loadTemplates().map { $0.name }, ["v3 Push", "Pull"])
        XCTAssertEqual(probe.runCount, 2)
    }

    func testAMigrationStartsFromTheVersionOnDisk() throws {
        let directory = makeDirectory()
        try writeVersion1Directory(directory)
        try write("{\"version\":2}", "schema.json", in: directory)
        let probe = MigrationProbe()
        let first = PersistenceMigration { _ in try probe.recordRun(); XCTFail("version 1 -> 2 must not run") }
        let second = PersistenceMigration { _ in try probe.recordRun() }
        let persistence = makePersistence(directory, migrations: [first, second])
        XCTAssertEqual(persistence.loadTemplates().count, 2)
        XCTAssertEqual(probe.runCount, 1)
        XCTAssertEqual(schemaVersionOnDisk(in: directory), 3)
    }

    func testAnEmptyDirectoryIsStampedWithTheCurrentVersionWithoutMigrating() throws {
        let directory = makeDirectory()
        let probe = MigrationProbe()
        let persistence = makePersistence(directory, migrations: [PersistenceMigration { _ in try probe.recordRun() }])
        XCTAssertEqual(persistence.loadTemplates(), [])
        XCTAssertEqual(probe.runCount, 0)
        try persistence.saveTemplates([])
        XCTAssertEqual(schemaVersionOnDisk(in: directory), 2)
    }

    func testAFailedMigrationLeavesTheFilesAloneAndRefusesWrites() throws {
        let directory = makeDirectory()
        try writeVersion1Directory(directory)
        let templatesBefore = bytes("templates.json", in: directory)
        let probe = MigrationProbe(failing: true)
        let persistence = makePersistence(directory, migrations: [PersistenceMigration { _ in try probe.recordRun() }])

        XCTAssertEqual(persistence.loadTemplates().count, 2, "the files are still read")
        XCTAssertFalse(persistence.canWrite)
        XCTAssertEqual(persistence.schemaVersion, 1)
        XCTAssertEqual(persistence.loadIssues, [PersistenceIssue(fileName: "schema.json", kind: .migrationFailed)])
        XCTAssertThrowsError(try persistence.saveTemplates([])) { XCTAssertEqual($0 as? PersistenceError, .migrationFailed(toVersion: 2)) }
        XCTAssertEqual(bytes("templates.json", in: directory), templatesBefore)
        XCTAssertEqual(probe.runCount, 1, "a failed step is not retried on every access")
        XCTAssertNil(schemaVersionOnDisk(in: directory))

        // After the cause is fixed, a rescan (the app's reload) migrates.
        probe.setFailing(false)
        persistence.rescanSchema()
        XCTAssertTrue(persistence.canWrite)
        XCTAssertEqual(schemaVersionOnDisk(in: directory), 2)
        XCTAssertEqual(persistence.schemaVersion, 2)
    }

    func testAMigrationThatStoppedHalfWayContinuesWithTheStepThatFailed() throws {
        let directory = makeDirectory()
        try writeVersion1Directory(directory)
        let first = MigrationProbe()
        let second = MigrationProbe(failing: true)
        let steps = [PersistenceMigration { _ in try first.recordRun() }, PersistenceMigration { _ in try second.recordRun() }]
        let crashed = makePersistence(directory, migrations: steps)
        XCTAssertFalse(crashed.canWrite)
        XCTAssertEqual(schemaVersionOnDisk(in: directory), 2, "the finished step is recorded")

        second.setFailing(false)
        let relaunched = makePersistence(directory, migrations: steps)
        XCTAssertTrue(relaunched.canWrite)
        XCTAssertEqual(first.runCount, 1, "version 1 -> 2 is not run again")
        XCTAssertEqual(second.runCount, 2)
        XCTAssertEqual(schemaVersionOnDisk(in: directory), 3)
    }

    func testShippedMigrationsAreEmptyBecauseVersion1IsTheCurrentFormat() {
        XCTAssertTrue(PersistenceMigration.shipped.isEmpty)
        XCTAssertEqual(FileStrengthPersistence.temporary().currentSchemaVersion, 1)
    }

    // MARK: Damaged files: every file

    private struct Case {
        var file: String
        /// A list or dictionary of three elements, the second one unreadable (nil for files that hold one value).
        var withBrokenElement: String?
        var keptCount: Int
        var load: (FileStrengthPersistence) -> Int
    }

    private func cases() -> [Case] {
        let templates = "[\(V1Files.template(1, name: "A")),{\"id\":\"oops\",\"name\":5},\(V1Files.template(2, name: "B"))]"
        let history = "[\(V1Files.workout(1, finishedAt: "2026-10-13T19:30:00.000Z")),42,\(V1Files.workout(2, finishedAt: "2026-10-12T19:30:00.000Z"))]"
        let custom = "[\(V1Files.exercise),{\"id\":3},\(V1Files.exercise.replacingOccurrences(of: "\"id\":\"bench\"", with: "\"id\":\"custom-2\""))]"
        let bests = "{\"a\":{\"date\":\"2026-10-13T19:30:00.000Z\",\"estimated1RM\":70,\"exerciseID\":\"a\",\"reps\":5,\"weightKg\":60},\"b\":\"broken\",\"c\":{\"date\":\"2026-10-13T19:30:00.000Z\",\"estimated1RM\":80,\"exerciseID\":\"c\",\"reps\":5,\"weightKg\":70}}"
        let weights = "[{\"date\":\"2026-10-12T07:00:00.000Z\",\"id\":\"0000FEED-0000-4000-8000-000000000401\",\"kg\":82.4},{\"kg\":\"x\"},{\"date\":\"2026-10-11T07:00:00.000Z\",\"id\":\"0000FEED-0000-4000-8000-000000000402\",\"kg\":82}]"
        let acknowledged = "[\"0000FEED-0000-4000-8000-000000000501\",\"not a uuid\",\"0000FEED-0000-4000-8000-000000000502\"]"
        return [
            Case(file: "templates.json", withBrokenElement: templates, keptCount: 2) { $0.loadTemplates().count },
            Case(file: "history.json", withBrokenElement: history, keptCount: 2) { $0.loadHistory().count },
            Case(file: "custom-exercises.json", withBrokenElement: custom, keptCount: 2) { $0.loadCustomExercises().count },
            Case(file: "personal-bests.json", withBrokenElement: bests, keptCount: 2) { $0.loadPersonalBests().count },
            Case(file: "body-weights.json", withBrokenElement: weights, keptCount: 2) { $0.loadBodyWeights().count },
            Case(file: "acknowledged-commands.json", withBrokenElement: acknowledged, keptCount: 2) { $0.loadAcknowledgedCommands().count },
            Case(file: "active-workout.json", withBrokenElement: nil, keptCount: 0) { $0.loadActiveWorkout() == nil ? 0 : 1 },
            Case(file: "weigh-in-preferences.json", withBrokenElement: nil, keptCount: 0) { $0.loadWeighInPreferences() == WeighInPreferences() ? 0 : 1 },
        ]
    }

    func testAnUnreadableFileIsBackedUpReportedAndLeftAlone() throws {
        for item in cases() {
            for garbage in ["not json at all", "{", "", "null", "42"] {
                let directory = makeDirectory()
                let persistence = makePersistence(directory)
                try write(garbage, item.file, in: directory)

                XCTAssertEqual(item.load(persistence), 0, "\(item.file) \(garbage)")
                let issue = try XCTUnwrap(persistence.loadIssues.first, "\(item.file) \(garbage)")
                XCTAssertEqual(persistence.loadIssues.count, 1)
                XCTAssertEqual(issue.fileName, item.file)
                XCTAssertEqual(issue.kind, .unreadableFile)
                let backup = try XCTUnwrap(issue.backupFileName, item.file)
                XCTAssertEqual(backup, String(item.file.dropLast(5)) + ".corrupt-20261013-193000.json")
                XCTAssertEqual(bytes(backup, in: directory), Data(garbage.utf8), "the original bytes are kept")
                XCTAssertEqual(bytes(item.file, in: directory), Data(garbage.utf8), "reading overwrites nothing")
                XCTAssertEqual(names(in: directory), [backup, item.file].sorted())
            }
        }
    }

    func testAnUnreadableElementIsSkippedCountedBackedUpAndTheRestKept() throws {
        for item in cases() {
            guard let text = item.withBrokenElement else { continue }
            let directory = makeDirectory()
            let persistence = makePersistence(directory)
            try write(text, item.file, in: directory)

            XCTAssertEqual(item.load(persistence), item.keptCount, item.file)
            let issue = try XCTUnwrap(persistence.loadIssues.first, item.file)
            XCTAssertEqual(issue.fileName, item.file)
            XCTAssertEqual(issue.kind, .skippedElements(1), item.file)
            let backup = try XCTUnwrap(issue.backupFileName)
            XCTAssertEqual(bytes(backup, in: directory), Data(text.utf8), "the backup holds the broken element too")
            XCTAssertEqual(bytes(item.file, in: directory), Data(text.utf8), "reading overwrites nothing")
        }
    }

    func testTheDamagedFileIsOnlyReplacedByTheNextSaveAndTheBackupSurvivesIt() throws {
        let directory = makeDirectory()
        let persistence = makePersistence(directory)
        let text = "[\(V1Files.template(1, name: "A")),{\"id\":\"oops\"},\(V1Files.template(2, name: "B"))]"
        try write(text, "templates.json", in: directory)

        let kept = persistence.loadTemplates()
        XCTAssertEqual(kept.map { $0.name }, ["A", "B"])
        XCTAssertEqual(bytes("templates.json", in: directory), Data(text.utf8))

        try persistence.saveTemplates(kept)
        XCTAssertEqual(makePersistence(directory).loadTemplates(), kept)
        XCTAssertEqual(makePersistence(directory).loadIssues, [], "the rewritten file is whole")
        let backup = try XCTUnwrap(backups(of: "templates.json", in: directory).first)
        XCTAssertEqual(bytes(backup, in: directory), Data(text.utf8))
    }

    func testACleanLoadClearsTheIssueOfThatFileAndIssuesCanBeCleared() throws {
        let directory = makeDirectory()
        let persistence = makePersistence(directory)
        try write("{", "history.json", in: directory)
        try write("{", "templates.json", in: directory)
        _ = persistence.loadHistory()
        _ = persistence.loadTemplates()
        XCTAssertEqual(persistence.loadIssues.map { $0.fileName }, ["history.json", "templates.json"], "ordered by file name")

        try persistence.saveHistory([])
        _ = persistence.loadHistory()
        XCTAssertEqual(persistence.loadIssues.map { $0.fileName }, ["templates.json"])

        persistence.clearLoadIssues()
        XCTAssertEqual(persistence.loadIssues, [])
        XCTAssertFalse(backups(of: "templates.json", in: directory).isEmpty, "clearing the issues keeps the backups")
    }

    func testAMissingFileIsNotAnIssue() {
        let persistence = makePersistence()
        _ = persistence.loadHistory()
        _ = persistence.loadActiveWorkout()
        _ = persistence.loadPersonalBests()
        XCTAssertEqual(persistence.loadIssues, [])
    }

    func testAFileThatCannotBeReadAtAllIsAnIssueWithoutABackup() throws {
        let directory = makeDirectory()
        let persistence = makePersistence(directory)
        // A directory where the file should be: reading it fails, and there are no bytes to copy.
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("history.json"), withIntermediateDirectories: true)
        XCTAssertEqual(persistence.loadHistory(), [])
        XCTAssertEqual(persistence.loadIssues, [PersistenceIssue(fileName: "history.json", kind: .unreadableFile)])
    }

    // MARK: Backups: naming, reuse, pruning

    func testBackupNamesUseUTCWithoutFormatterOrLocale() throws {
        let directory = makeDirectory()
        // 2027-01-02 03:04:05 UTC.
        let clock = IntegrityClock(Date(timeIntervalSince1970: 1_798_859_045))
        let persistence = makePersistence(directory, clock: clock)
        try write("{", "history.json", in: directory)
        _ = persistence.loadHistory()
        XCTAssertEqual(persistence.loadIssues.first?.backupFileName, "history.corrupt-20270102-030405.json")
    }

    func testTheSameDamagedFileIsBackedUpOnce() throws {
        let directory = makeDirectory()
        let clock = IntegrityClock(epoch)
        let persistence = makePersistence(directory, clock: clock)
        try write("{ broken", "history.json", in: directory)
        for _ in 0..<5 {
            _ = persistence.loadHistory()
            clock.advance(60)
        }
        XCTAssertEqual(backups(of: "history.json", in: directory), ["history.corrupt-20261013-193000.json"])
        // A new instance (the next launch) reuses the copy too.
        _ = makePersistence(directory, clock: clock).loadHistory()
        XCTAssertEqual(backups(of: "history.json", in: directory).count, 1)
    }

    func testOnlyTheNewestThreeBackupsOfAFileAreKept() throws {
        let directory = makeDirectory()
        let clock = IntegrityClock(epoch)
        let persistence = makePersistence(directory, clock: clock)
        var contents: [String] = []
        for round in 0..<5 {
            let text = "{ broken \(round)"
            contents.append(text)
            try write(text, "history.json", in: directory)
            _ = persistence.loadHistory()
            clock.advance(60)
        }
        let kept = backups(of: "history.json", in: directory)
        XCTAssertEqual(kept, [
            "history.corrupt-20261013-193200.json",
            "history.corrupt-20261013-193300.json",
            "history.corrupt-20261013-193400.json",
        ], "the two oldest are deleted")
        XCTAssertEqual(kept.map { bytes($0, in: directory) }, contents.suffix(3).map { Data($0.utf8) })
    }

    func testBackupsOfOneFileDoNotCountForAnother() throws {
        let directory = makeDirectory()
        let clock = IntegrityClock(epoch)
        let persistence = makePersistence(directory, clock: clock)
        for round in 0..<4 {
            try write("{ broken \(round)", "history.json", in: directory)
            _ = persistence.loadHistory()
            clock.advance(60)
        }
        try write("{ other", "templates.json", in: directory)
        _ = persistence.loadTemplates()
        XCTAssertEqual(backups(of: "history.json", in: directory).count, 3)
        XCTAssertEqual(backups(of: "templates.json", in: directory).count, 1)
    }

    func testTwoDifferentDamagedFilesInTheSameSecondGetDifferentBackupNames() throws {
        let directory = makeDirectory()
        let persistence = makePersistence(directory)
        try write("{ one", "history.json", in: directory)
        _ = persistence.loadHistory()
        try write("{ two", "history.json", in: directory)
        _ = persistence.loadHistory()
        XCTAssertEqual(backups(of: "history.json", in: directory), [
            "history.corrupt-20261013-193000.json",
            "history.corrupt-20261013-193001.json",
        ])
    }

    func testAClockThatWentBackwardsNeverDeletesTheNewBackup() throws {
        let directory = makeDirectory()
        let clock = IntegrityClock(epoch)
        let persistence = makePersistence(directory, clock: clock)
        for round in 0..<3 {
            try write("{ broken \(round)", "history.json", in: directory)
            _ = persistence.loadHistory()
            clock.advance(60)
        }
        clock.advance(-86_400)
        try write("{ broken from the past", "history.json", in: directory)
        _ = persistence.loadHistory()
        let issue = try XCTUnwrap(persistence.loadIssues.first)
        let name = try XCTUnwrap(issue.backupFileName)
        XCTAssertEqual(bytes(name, in: directory), Data("{ broken from the past".utf8))
        XCTAssertEqual(backups(of: "history.json", in: directory).count, 3)
    }

    func testBackupsAreNotDataFiles() throws {
        let directory = makeDirectory()
        let persistence = makePersistence(directory)
        XCTAssertFalse(persistence.hasDataFiles)
        try write("{", "history.json", in: directory)
        XCTAssertTrue(persistence.hasDataFiles)
        _ = persistence.loadHistory()
        try FileManager.default.removeItem(at: directory.appendingPathComponent("history.json"))
        XCTAssertFalse(backups(of: "history.json", in: directory).isEmpty)
        XCTAssertFalse(persistence.hasDataFiles, "a backup alone is not data")
        try persistence.saveHistory([])
        XCTAssertTrue(persistence.hasDataFiles)
    }

    func testHasDataFilesIgnoresTheSchemaFileAndSeesEveryDataFile() throws {
        for name in FileStrengthPersistence.dataFileNames {
            let directory = makeDirectory()
            let persistence = makePersistence(directory)
            try write("{\"version\":1}", "schema.json", in: directory)
            XCTAssertFalse(persistence.hasDataFiles, name)
            try write("[]", name, in: directory)
            XCTAssertTrue(persistence.hasDataFiles, name)
        }
        XCTAssertEqual(FileStrengthPersistence.dataFileNames.count, 8)
    }

    func testHasPersonalBestsFile() throws {
        let persistence = makePersistence()
        XCTAssertFalse(persistence.hasPersonalBestsFile)
        try persistence.savePersonalBests([:])
        XCTAssertTrue(persistence.hasPersonalBestsFile)
    }

    func testConcurrentLoadsOfADamagedFileMakeOneBackup() throws {
        let directory = makeDirectory()
        let persistence = makePersistence(directory)
        try write("{ broken", "history.json", in: directory)
        DispatchQueue.concurrentPerform(iterations: 40) { _ in _ = persistence.loadHistory() }
        XCTAssertEqual(backups(of: "history.json", in: directory).count, 1)
        XCTAssertEqual(persistence.loadIssues.count, 1)
    }
}

// MARK: - The model: never seed over damage, repair derived data

final class StoreIntegrityTests: XCTestCase {
    private typealias F = SvcDataFix

    private func makeDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PulseStrength-integrity-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func bytes(_ name: String, in directory: URL) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    private func write(_ text: String, _ name: String, in directory: URL) throws {
        try Data(text.utf8).write(to: directory.appendingPathComponent(name))
    }

    // MARK: Seeding

    func testDemoDataIsNeverSeededOverFilesThatExistButCannotBeRead() throws {
        let directory = makeDirectory()
        try write("{ broken", "templates.json", in: directory)
        try write("also broken", "history.json", in: directory)
        let persistence = FileStrengthPersistence(directory: directory)

        svcMain {
            let model = StrengthDataModel(persistence: persistence, seedDemoData: true, now: F.now)
            XCTAssertTrue(model.data.templates.isEmpty)
            XCTAssertTrue(model.data.history.isEmpty)
            XCTAssertEqual(model.persistenceIssues.map { $0.fileName }, ["history.json", "templates.json"])
        }
        XCTAssertEqual(bytes("templates.json", in: directory), Data("{ broken".utf8), "nothing was overwritten")
        XCTAssertEqual(bytes("history.json", in: directory), Data("also broken".utf8))
        XCTAssertNil(bytes("personal-bests.json", in: directory))
    }

    func testDemoDataIsNotSeededWhenAnyDataFileExists() throws {
        for name in FileStrengthPersistence.dataFileNames {
            let directory = makeDirectory()
            let persistence = FileStrengthPersistence(directory: directory)
            // A readable file of every kind, none of which holds templates or history.
            switch name {
            case "active-workout.json": try persistence.saveActiveWorkout(SvcSyncFix.richState())
            case "personal-bests.json", "weigh-in-preferences.json": try write("{}", name, in: directory)
            default: try write("[]", name, in: directory)
            }
            XCTAssertTrue(persistence.loadIssues.isEmpty, name)
            svcMain {
                let model = StrengthDataModel(persistence: persistence, seedDemoData: true, now: F.now)
                XCTAssertTrue(model.data.templates.isEmpty, name)
                XCTAssertTrue(model.persistenceIssues.isEmpty, name)
            }
        }
    }

    func testDemoDataIsStillSeededIntoAnEmptyDirectoryAndOneThatOnlyHoldsTheSchemaFile() throws {
        let directory = makeDirectory()
        try write("{\"version\":1}", "schema.json", in: directory)
        let persistence = FileStrengthPersistence(directory: directory)
        svcMain {
            let model = StrengthDataModel(persistence: persistence, seedDemoData: true, now: F.now)
            XCTAssertEqual(model.data.templates.count, 3)
            XCTAssertEqual(model.data.history.count, 5)
            XCTAssertTrue(model.persistenceIssues.isEmpty)
        }
        XCTAssertEqual(persistence.loadTemplates().count, 3)
    }

    func testDemoDataIsNotSeededIntoADirectoryOfANewerVersion() throws {
        let directory = makeDirectory()
        try write("{\"version\":9}", "schema.json", in: directory)
        let persistence = FileStrengthPersistence(directory: directory)
        svcMain {
            let model = StrengthDataModel(persistence: persistence, seedDemoData: true, now: F.now)
            XCTAssertTrue(model.data.templates.isEmpty)
            XCTAssertEqual(model.persistenceIssues.map { $0.kind }, [.newerSchema])
        }
        XCTAssertNil(bytes("templates.json", in: directory))
    }

    func testWithoutPersistenceDemoDataIsStillSeeded() {
        svcMain {
            XCTAssertEqual(StrengthDataModel(persistence: nil, seedDemoData: true, now: F.now).data.templates.count, 3)
        }
    }

    // MARK: Issues

    func testTheModelKeepsIssuesUntilTheyAreAcknowledged() throws {
        let directory = makeDirectory()
        try write("{\"a\":1}", "templates.json", in: directory)
        let persistence = FileStrengthPersistence(directory: directory)
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(model.persistenceIssues.first?.kind, .unreadableFile)

            // The file is rewritten by a legitimate save; a reload reads it cleanly, but the user has not seen the issue yet.
            model.saveTemplate(WorkoutTemplate(name: "Arms", entries: []))
            model.reload()
            XCTAssertEqual(model.persistenceIssues.map { $0.fileName }, ["templates.json"])

            model.acknowledgePersistenceIssues()
            XCTAssertEqual(model.persistenceIssues, [])
            XCTAssertEqual(persistence.loadIssues, [])
            model.reload()
            XCTAssertEqual(model.persistenceIssues, [])
        }
    }

    func testAnUnacknowledgedIssueReturnsWhenTheFileIsStillDamagedAfterAcknowledging() throws {
        let directory = makeDirectory()
        try write("[1,2]", "templates.json", in: directory)
        let persistence = FileStrengthPersistence(directory: directory)
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            model.acknowledgePersistenceIssues()
            model.reload()
            XCTAssertEqual(model.persistenceIssues.map { $0.fileName }, ["templates.json"], "nothing has repaired the file")
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("templates.corrupt-") }.count, 1)
    }

    // MARK: Derived data at load

    func testAMissingBestsFileIsRecomputedFromTheHistoryAndWritten() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.saveHistory([
            F.workout(1, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(100, 5)], n: 1)]),
            F.workout(2, finishedAt: F.daysAgo(5), [F.entry("bench", [F.work(90, 5)], n: 2), F.entry("squat", [F.work(120, 3)], n: 3)]),
        ])
        XCTAssertFalse(persistence.hasPersonalBestsFile)
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(model.data.personalBests["bench"]?.weightKg, 100)
            XCTAssertEqual(model.data.personalBests["squat"]?.weightKg, 120)
            XCTAssertEqual(model.data.personalBests, model.data.recomputedPersonalBests())
        }
        XCTAssertEqual(persistence.loadPersonalBests().keys.sorted(), ["bench", "squat"])
    }

    func testAnEmptyDirectoryWritesNoBestsFileAtLoad() {
        let persistence = FileStrengthPersistence(directory: makeDirectory())
        svcMain { _ = StrengthDataModel(persistence: persistence) }
        XCTAssertFalse(persistence.hasDataFiles)
    }

    func testDamagedBestsAreRecomputedInMemoryWhenTheHistoryIsWholeAndTheFileIsLeftAlone() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.saveHistory([F.workout(1, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(100, 5)], n: 1)])])
        try write("{ broken", "personal-bests.json", in: directory)
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(model.data.personalBests["bench"]?.weightKg, 100)
            XCTAssertEqual(model.persistenceIssues.map { $0.fileName }, ["personal-bests.json"])
        }
        XCTAssertEqual(bytes("personal-bests.json", in: directory), Data("{ broken".utf8), "only the next legitimate save replaces it")
    }

    func testDamagedHistoryKeepsTheBestsAsTheyWereRead() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        // The stored best (120) is higher than anything the readable history shows: it may belong to the workout that was lost.
        try persistence.saveHistory([F.workout(1, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(100, 5)], n: 1)])])
        let history = try XCTUnwrap(bytes("history.json", in: directory).flatMap { String(data: $0, encoding: .utf8) })
        try write("[" + history.dropFirst().dropLast() + ",42]", "history.json", in: directory)
        let best = "{\"date\":\"2026-10-12T19:30:00.000Z\",\"estimated1RM\":120,\"exerciseID\":\"bench\",\"reps\":6,\"weightKg\":100}"
        try write("{\"bench\":\(best),\"junk\":\"x\"}", "personal-bests.json", in: directory)
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(model.persistenceIssues.map { $0.fileName }, ["history.json", "personal-bests.json"])
            XCTAssertEqual(model.data.history.count, 1)
            XCTAssertEqual(model.data.personalBests["bench"]?.estimated1RM, 120)
        }
    }

    func testTemplateCopiesOfBuiltInExercisesFollowTheLibraryAtLoad() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        var stale = try XCTUnwrap(ExerciseLibrary.exercise(id: "bench"))
        stale.name = "Old bench name"
        stale.cues = ["An old cue."]
        stale.previousBestE1RM = 77
        stale.previousSets = [PreviousSet(weightKg: 70, reps: 5)]
        let custom = F.customExercise("Hex press")
        let template = WorkoutTemplate(name: "Mixed", entries: [
            TemplateEntry(exercise: stale, plannedSets: [PlannedSet(weightKg: 60, reps: 8)], restSeconds: 120, note: "Pause on the chest"),
            TemplateEntry(exercise: custom, plannedSets: [PlannedSet(weightKg: 20, reps: 10)], restSeconds: 90),
        ])
        try persistence.saveTemplates([template])
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let loaded = model.data.templates[0]
            let bench = ExerciseLibrary.exercise(id: "bench")!
            XCTAssertEqual(loaded.entries[0].exercise.name, bench.name)
            XCTAssertEqual(loaded.entries[0].exercise.cues, bench.cues)
            XCTAssertEqual(loaded.entries[0].exercise.mediaKey, bench.mediaKey)
            XCTAssertEqual(loaded.entries[0].exercise.previousBestE1RM, 77, "remembered results are not library data")
            XCTAssertEqual(loaded.entries[0].exercise.previousSets, [PreviousSet(weightKg: 70, reps: 5)])
            XCTAssertEqual(loaded.entries[0].note, "Pause on the chest")
            XCTAssertEqual(loaded.entries[0].plannedSets, template.entries[0].plannedSets)
            XCTAssertEqual(loaded.entries[1].exercise, custom, "a custom exercise is untouched")
        }
        XCTAssertEqual(persistence.loadTemplates()[0].entries[0].exercise.name, "Old bench name", "loading does not rewrite the file")
    }
}

#if canImport(Combine) || PULSE_COMBINE_SHIM

// MARK: - The store and the controller

final class StoreIssueWiringTests: XCTestCase {
    private func makeDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PulseStrength-wiring-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testTheStorePublishesIssuesAndAcknowledgingClearsThem() throws {
        let directory = makeDirectory()
        try Data("[".utf8).write(to: directory.appendingPathComponent("history.json"))
        let persistence = FileStrengthPersistence(directory: directory)
        svcMain {
            let store = StrengthStore(persistence: persistence, seedDemoData: true)
            XCTAssertEqual(store.persistenceIssues.map { $0.fileName }, ["history.json"])
            XCTAssertTrue(store.templates.isEmpty, "nothing is seeded over the damaged file")
            XCTAssertNil(store.lastPersistenceError)
            store.acknowledgePersistenceIssues()
            XCTAssertEqual(store.persistenceIssues, [])
            XCTAssertEqual(persistence.loadIssues, [])
        }
    }

    func testADamagedActiveWorkoutFileReachesTheStoreThroughTheControllersRestore() throws {
        let directory = makeDirectory()
        try Data("{ broken".utf8).write(to: directory.appendingPathComponent("active-workout.json"))
        let persistence = FileStrengthPersistence(directory: directory)
        svcMain {
            let store = StrengthStore(persistence: persistence)
            XCTAssertEqual(store.persistenceIssues, [], "the store does not read the active workout")
            let controller = WorkoutController(store: store, persistence: persistence, role: .authority)
            controller.restoreFromDisk()
            XCTAssertNil(controller.state)
            XCTAssertEqual(store.persistenceIssues.map { $0.fileName }, ["active-workout.json"])
            XCTAssertEqual(store.persistenceIssues.first?.kind, .unreadableFile)
        }
    }

    func testAFailedSaveIsPublishedAsTheLastPersistenceError() throws {
        let directory = makeDirectory()
        try Data("{\"version\":9}".utf8).write(to: directory.appendingPathComponent("schema.json"))
        let persistence = FileStrengthPersistence(directory: directory)
        svcMain {
            let store = StrengthStore(persistence: persistence)
            XCTAssertNil(store.lastPersistenceError)
            let template = WorkoutTemplate(name: "Arms", entries: [])
            let result = store.saveTemplate(template)
            XCTAssertEqual(store.templates, [template], "the change stays in memory")
            guard case let .failure(error) = result else { return XCTFail("a newer data format refuses the write") }
            XCTAssertEqual(error as? PersistenceError, .newerSchema(found: 9, supported: 1))
            XCTAssertEqual(store.lastPersistenceError as? PersistenceError, .newerSchema(found: 9, supported: 1))
        }
    }
}

#endif
