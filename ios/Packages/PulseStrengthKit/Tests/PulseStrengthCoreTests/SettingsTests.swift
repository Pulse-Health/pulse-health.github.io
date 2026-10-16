import Foundation
import XCTest
@testable import PulseStrengthCore

/// `StrengthSettings` (the weekly goal), its file `settings.json`, and the model and store that carry it.
final class StrengthSettingsTests: XCTestCase {
    private func makePersistence() -> FileStrengthPersistence {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return persistence
    }

    private func decode(_ json: String) throws -> StrengthSettings {
        try StrengthJSON.makeDecoder().decode(StrengthSettings.self, from: Data(json.utf8))
    }

    private func fileNames(_ persistence: FileStrengthPersistence) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: persistence.directory.path)) ?? []).sorted()
    }

    // MARK: The value

    func testTheWeeklyGoalDefaultsToTheWidgetDefault() {
        XCTAssertEqual(StrengthSettings().weeklyGoal, WidgetContext.defaultWeeklyGoal)
        XCTAssertEqual(StrengthSettings().weeklyGoal, 4)
        XCTAssertEqual(StrengthSettings.weeklyGoalRange, 1...7)
    }

    func testTheGoalIsBroughtIntoOneToSevenWhenCreatedAndWhenChanged() {
        XCTAssertEqual(StrengthSettings(weeklyGoal: 0).weeklyGoal, 1)
        XCTAssertEqual(StrengthSettings(weeklyGoal: -5).weeklyGoal, 1)
        XCTAssertEqual(StrengthSettings(weeklyGoal: 12).weeklyGoal, 7)
        XCTAssertEqual(StrengthSettings(weeklyGoal: 1).weeklyGoal, 1)
        XCTAssertEqual(StrengthSettings(weeklyGoal: 7).weeklyGoal, 7)
        var settings = StrengthSettings()
        settings.weeklyGoal = 9
        XCTAssertEqual(settings.weeklyGoal, 7)
        settings.weeklyGoal = 0
        XCTAssertEqual(settings.weeklyGoal, 1)
        settings.weeklyGoal = 5
        XCTAssertEqual(settings.weeklyGoal, 5)
    }

    func testSettingsRoundTripThroughJSON() throws {
        let settings = StrengthSettings(weeklyGoal: 6)
        let data = try StrengthJSON.makeEncoder().encode(settings)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"weeklyGoal":6}"#)
        XCTAssertEqual(try StrengthJSON.makeDecoder().decode(StrengthSettings.self, from: data), settings)
    }

    func testAMissingOrWronglyTypedGoalReadsAsTheDefaultAndOutOfRangeNumbersAreClamped() throws {
        XCTAssertEqual(try decode("{}").weeklyGoal, 4)
        XCTAssertEqual(try decode(#"{"weeklyGoal":"six"}"#).weeklyGoal, 4)
        XCTAssertEqual(try decode(#"{"weeklyGoal":null}"#).weeklyGoal, 4)
        XCTAssertEqual(try decode(#"{"weeklyGoal":99}"#).weeklyGoal, 7)
        XCTAssertEqual(try decode(#"{"weeklyGoal":0}"#).weeklyGoal, 1)
        XCTAssertEqual(try decode(#"{"weeklyGoal":-3}"#).weeklyGoal, 1)
        XCTAssertEqual(try decode(#"{"weeklyGoal":5,"someFutureSetting":true}"#).weeklyGoal, 5, "unknown keys are ignored")
        XCTAssertThrowsError(try decode("[1, 2]"), "a file that is not an object is not settings")
    }

    // MARK: The file

    func testWithoutAFileTheDefaultsAreRead() {
        let persistence = makePersistence()
        XCTAssertEqual(persistence.loadSettings(), StrengthSettings())
        XCTAssertEqual(fileNames(persistence), [])
    }

    func testSavingWritesOneAtomicSortedFileAndLoadingReadsItBack() throws {
        let persistence = makePersistence()
        try persistence.saveSettings(StrengthSettings(weeklyGoal: 3))
        XCTAssertEqual(fileNames(persistence), ["settings.json"], "an atomic write leaves no temporary file behind")
        XCTAssertEqual(persistence.loadSettings().weeklyGoal, 3)
        let text = try String(contentsOf: persistence.directory.appendingPathComponent("settings.json"), encoding: .utf8)
        XCTAssertEqual(text, #"{"weeklyGoal":3}"#)
        try persistence.saveSettings(StrengthSettings(weeklyGoal: 5))
        XCTAssertEqual(persistence.loadSettings().weeklyGoal, 5, "a later save replaces the file")
    }

    func testACorruptFileReadsAsTheDefaults() throws {
        let persistence = makePersistence()
        let url = persistence.directory.appendingPathComponent("settings.json")
        for garbage in ["not json", "{", "[]", "null", ""] {
            try Data(garbage.utf8).write(to: url)
            XCTAssertEqual(persistence.loadSettings(), StrengthSettings(), "\(garbage.debugDescription)")
        }
    }

    func testTheMigrationToTheAppGroupKnowsTheFile() throws {
        XCTAssertTrue(StrengthDataMigration.fileNames.contains("settings.json"))
        let persistence = makePersistence()
        try persistence.saveSettings(StrengthSettings(weeklyGoal: 2))
        let written = try FileManager.default.contentsOfDirectory(atPath: persistence.directory.path).filter { $0.hasSuffix(".json") }
        XCTAssertEqual(written, ["settings.json"])
        for name in written { XCTAssertTrue(StrengthDataMigration.fileNames.contains(name), name) }

        let target = FileManager.default.temporaryDirectory.appendingPathComponent("Settings-" + UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: target) }
        XCTAssertEqual(StrengthDataMigration.copyMissingFiles(from: persistence.directory, to: target), 1)
        XCTAssertEqual(FileStrengthPersistence(directory: target).loadSettings().weeklyGoal, 2)
    }

    // MARK: The model

    func testTheModelStartsWithTheDefaultGoalAndSavesAChange() {
        let persistence = makePersistence()
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(model.weeklyGoal, 4)
            XCTAssertEqual(model.settings, StrengthSettings())
            model.setWeeklyGoal(6)
            XCTAssertEqual(model.weeklyGoal, 6)
            XCTAssertEqual(model.settings.weeklyGoal, 6)
            XCTAssertEqual(persistence.loadSettings().weeklyGoal, 6)
            XCTAssertNil(model.lastPersistenceError)
        }
        svcMain {
            XCTAssertEqual(StrengthDataModel(persistence: persistence).weeklyGoal, 6, "a new model sees the saved goal")
        }
    }

    func testTheModelBringsTheGoalIntoRange() {
        let persistence = makePersistence()
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            model.setWeeklyGoal(0)
            XCTAssertEqual(model.weeklyGoal, 1)
            model.setWeeklyGoal(100)
            XCTAssertEqual(model.weeklyGoal, 7)
            XCTAssertEqual(persistence.loadSettings().weeklyGoal, 7)
        }
    }

    func testSettingTheSameGoalWritesNothing() {
        let persistence = makePersistence()
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            model.setWeeklyGoal(4)
            XCTAssertEqual(fileNames(persistence), [], "the default is not written")
            model.setWeeklyGoal(5)
            let url = persistence.directory.appendingPathComponent("settings.json")
            try? FileManager.default.removeItem(at: url)
            model.setWeeklyGoal(5)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "an unchanged goal is not written again")
        }
    }

    func testTheGoalDoesNotTouchTheWorkoutFiles() {
        let persistence = makePersistence()
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            model.setWeeklyGoal(3)
            XCTAssertEqual(fileNames(persistence), ["settings.json"])
        }
    }

    func testReloadReadsTheGoalFromDisk() throws {
        let persistence = makePersistence()
        try persistence.saveSettings(StrengthSettings(weeklyGoal: 2))
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(model.weeklyGoal, 2)
            try persistence.saveSettings(StrengthSettings(weeklyGoal: 5))
            model.reload()
            XCTAssertEqual(model.weeklyGoal, 5)
        }
    }

    func testADamagedSettingsFileDoesNotStopTheRestOfTheDataFromLoading() throws {
        let persistence = makePersistence()
        try persistence.saveTemplates(SampleData.templates())
        try Data("{ broken".utf8).write(to: persistence.directory.appendingPathComponent("settings.json"))
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(model.data.templates.count, 3)
            XCTAssertEqual(model.weeklyGoal, 4)
        }
    }

    func testAFailedSaveIsReportedAndTheGoalStillChangesInMemory() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("PulseStrength-settings-blocker-" + UUID().uuidString)
        try Data("file".utf8).write(to: blocker)
        addTeardownBlock { try? FileManager.default.removeItem(at: blocker) }
        svcMain {
            let broken = FileStrengthPersistence(directory: blocker.appendingPathComponent("inner"))
            let model = StrengthDataModel(persistence: broken)
            model.setWeeklyGoal(6)
            XCTAssertEqual(model.weeklyGoal, 6)
            XCTAssertNotNil(model.lastPersistenceError)
        }
    }

    func testAModelWithoutPersistenceKeepsTheGoalInMemory() {
        svcMain {
            let model = StrengthDataModel(persistence: nil)
            model.setWeeklyGoal(5)
            XCTAssertEqual(model.weeklyGoal, 5)
            XCTAssertNil(model.lastPersistenceError)
            model.reload()
            XCTAssertEqual(model.weeklyGoal, 5, "there is nothing on disk to reload")
        }
    }

    // MARK: The store

#if canImport(Combine) || PULSE_COMBINE_SHIM
    func testTheStorePublishesTheGoalAndTheNextStoreSeesIt() {
        let persistence = makePersistence()
        svcMain {
            let store = StrengthStore(persistence: persistence)
            XCTAssertEqual(store.weeklyGoal, 4)
            store.setWeeklyGoal(6)
            XCTAssertEqual(store.weeklyGoal, 6)
            store.setWeeklyGoal(50)
            XCTAssertEqual(store.weeklyGoal, 7)
            XCTAssertEqual(persistence.loadSettings().weeklyGoal, 7)
            XCTAssertEqual(StrengthStore(persistence: persistence).weeklyGoal, 7)
            store.setWeeklyGoal(3)
            store.reload()
            XCTAssertEqual(store.weeklyGoal, 3)
        }
    }

    func testTheStoreWithoutPersistenceKeepsTheGoal() {
        svcMain {
            let store = StrengthStore(persistence: nil)
            store.setWeeklyGoal(2)
            XCTAssertEqual(store.weeklyGoal, 2)
        }
    }
#endif
}
