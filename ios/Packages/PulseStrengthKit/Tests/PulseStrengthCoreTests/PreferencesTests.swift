import Foundation
import XCTest
@testable import PulseStrengthCore

// User preferences: the value type, `preferences.json`, the model that owns them, what a new workout takes from them and how
// the engine and the controller keep them and the running workout in step. Locales are always explicit.

private let enUS = Locale(identifier: "en_US")
private let deDE = Locale(identifier: "de_DE")
private let epoch = SvcSyncFix.epoch

private func makeDirectory(_ test: XCTestCase) -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PulseStrength-prefs-" + UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    test.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory
}

private func files(in directory: URL) -> Set<String> {
    Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
}

private func decode(_ text: String) throws -> StrengthPreferences {
    try StrengthJSON.makeDecoder().decode(StrengthPreferences.self, from: Data(text.utf8))
}

/// Preferences that differ from the defaults in every field.
private func changedPreferences() -> StrengthPreferences {
    StrengthPreferences(
        weightUnit: .lb, autoStartRest: false, alertWhenRestEnds: false, soundWhenRestEnds: false, hapticsEnabled: false,
        weeklyGoalSessions: 6, keepScreenAwake: false, saveWorkoutsToHealth: false, estimateCalories: false,
        askToUpdateTemplate: .structureOnly, defaultRestSeconds: 120
    )
}

// MARK: - The value

final class StrengthPreferencesTests: XCTestCase {
    func testTheDefaults() {
        let defaults = StrengthPreferences()
        XCTAssertEqual(defaults.weightUnit, .kg)
        XCTAssertTrue(defaults.autoStartRest)
        XCTAssertTrue(defaults.alertWhenRestEnds)
        XCTAssertTrue(defaults.soundWhenRestEnds)
        XCTAssertTrue(defaults.hapticsEnabled)
        XCTAssertEqual(defaults.weeklyGoalSessions, 4)
        XCTAssertTrue(defaults.keepScreenAwake)
        XCTAssertTrue(defaults.saveWorkoutsToHealth)
        XCTAssertTrue(defaults.estimateCalories)
        XCTAssertEqual(defaults.askToUpdateTemplate, .whenChanged)
        XCTAssertEqual(defaults.defaultRestSeconds, 90)
        XCTAssertEqual(StrengthPreferences.standardRestSeconds, 90)
        XCTAssertEqual(StrengthPreferences.weeklyGoalRange, 1...14)
    }

    func testTheFirstCreationPicksTheUnitByRegion() {
        XCTAssertEqual(StrengthPreferences(locale: enUS).weightUnit, .lb)
        XCTAssertEqual(StrengthPreferences(locale: Locale(identifier: "en_LR")).weightUnit, .lb)
        XCTAssertEqual(StrengthPreferences(locale: Locale(identifier: "my_MM")).weightUnit, .lb)
        XCTAssertEqual(StrengthPreferences(locale: deDE).weightUnit, .kg)
        XCTAssertEqual(StrengthPreferences(locale: Locale(identifier: "en_GB")).weightUnit, .kg)
        var expected = StrengthPreferences()
        expected.weightUnit = .lb
        XCTAssertEqual(StrengthPreferences(locale: enUS), expected, "only the unit differs from the defaults")
    }

    func testTheWeeklyGoalIsKeptBetweenOneAndFourteen() {
        for (given, kept) in [(-3, 1), (0, 1), (1, 1), (4, 4), (14, 14), (15, 14), (99, 14), (Int.max, 14), (Int.min, 1)] {
            XCTAssertEqual(StrengthPreferences(weeklyGoalSessions: given).weeklyGoalSessions, kept, "init \(given)")
            var preferences = StrengthPreferences()
            preferences.weeklyGoalSessions = given
            XCTAssertEqual(preferences.weeklyGoalSessions, kept, "assigned \(given)")
        }
    }

    func testTheDefaultRestIsKeptBetweenZeroAndTheLongestRest() {
        let longest = WorkoutReducer.maximumRestSeconds
        XCTAssertEqual(longest, 3_600)
        for (given, kept) in [(-5, 0), (0, 0), (1, 1), (90, 90), (3_600, 3_600), (3_601, 3_600), (Int.max, 3_600), (Int.min, 0)] {
            XCTAssertEqual(StrengthPreferences(defaultRestSeconds: given).defaultRestSeconds, kept, "init \(given)")
            var preferences = StrengthPreferences()
            preferences.defaultRestSeconds = given
            XCTAssertEqual(preferences.defaultRestSeconds, kept, "assigned \(given)")
        }
    }

    func testRoundTrip() throws {
        for preferences in [StrengthPreferences(), changedPreferences(), StrengthPreferences(locale: enUS)] {
            let data = try StrengthJSON.makeEncoder().encode(preferences)
            XCTAssertEqual(try StrengthJSON.makeDecoder().decode(StrengthPreferences.self, from: data), preferences)
        }
        let text = String(decoding: try StrengthJSON.makeEncoder().encode(changedPreferences()), as: UTF8.self)
        XCTAssertEqual(
            text,
            "{\"alertWhenRestEnds\":false,\"askToUpdateTemplate\":\"structureOnly\",\"autoStartRest\":false,\"defaultRestSeconds\":120,"
                + "\"estimateCalories\":false,\"hapticsEnabled\":false,\"keepScreenAwake\":false,\"saveWorkoutsToHealth\":false,"
                + "\"soundWhenRestEnds\":false,\"weeklyGoalSessions\":6,\"weightUnit\":\"lb\"}"
        )
    }

    func testPartialJSONFillsTheRestWithDefaults() throws {
        XCTAssertEqual(try decode("{}"), StrengthPreferences())
        var expected = StrengthPreferences()
        expected.weightUnit = .lb
        expected.autoStartRest = false
        XCTAssertEqual(try decode("{\"weightUnit\":\"lb\",\"autoStartRest\":false}"), expected)
        expected = StrengthPreferences()
        expected.weeklyGoalSessions = 5
        expected.askToUpdateTemplate = .never
        XCTAssertEqual(try decode("{\"weeklyGoalSessions\":5,\"askToUpdateTemplate\":\"never\"}"), expected)
    }

    func testAFileOfAnotherVersionLoads() throws {
        // Fields a newer version added are ignored; values of cases it added read as the default.
        let future = try decode(
            "{\"weightUnit\":\"stone\",\"askToUpdateTemplate\":\"always\",\"hapticsEnabled\":false,\"newestSetting\":{\"a\":[1,2]},\"zoom\":3}"
        )
        var expected = StrengthPreferences()
        expected.hapticsEnabled = false
        XCTAssertEqual(future, expected)
    }

    func testOutOfRangeNumbersInAFileAreKeptInRange() throws {
        let loaded = try decode("{\"weeklyGoalSessions\":99,\"defaultRestSeconds\":-4}")
        XCTAssertEqual(loaded.weeklyGoalSessions, 14)
        XCTAssertEqual(loaded.defaultRestSeconds, 0)
        let low = try decode("{\"weeklyGoalSessions\":0,\"defaultRestSeconds\":99999}")
        XCTAssertEqual(low.weeklyGoalSessions, 1)
        XCTAssertEqual(low.defaultRestSeconds, 3_600)
    }

    func testAFieldOfTheWrongTypeMakesTheFileUnreadable() {
        XCTAssertThrowsError(try decode("{\"hapticsEnabled\":\"yes\"}"))
        XCTAssertThrowsError(try decode("{\"weeklyGoalSessions\":\"four\"}"))
        XCTAssertThrowsError(try decode("[]"))
        XCTAssertThrowsError(try decode("{ broken"))
    }

    func testTheTemplatePromptCases() {
        XCTAssertEqual(TemplateUpdatePrompt.allCases, [.whenChanged, .structureOnly, .never])
        XCTAssertEqual(TemplateUpdatePrompt.structureOnly.id, "structureOnly")
        XCTAssertEqual(TemplateUpdatePrompt(rawValue: "never"), .never)
    }

    func testPreferencesAreEquatable() {
        XCTAssertEqual(StrengthPreferences(), StrengthPreferences())
        XCTAssertNotEqual(StrengthPreferences(), changedPreferences())
        var other = StrengthPreferences()
        other.estimateCalories = false
        XCTAssertNotEqual(StrengthPreferences(), other)
    }

    func testANewCustomExerciseTakesItsRestFromTheCaller() {
        func custom(_ rest: Int?) -> Exercise {
            rest.map { Exercise.custom(name: "Row", muscle: .back, equipment: .cable, tracking: .weightReps, restSeconds: $0) }
                ?? Exercise.custom(name: "Row", muscle: .back, equipment: .cable, tracking: .weightReps)
        }
        XCTAssertEqual(custom(nil).defaults.restSeconds, 90)
        XCTAssertEqual(custom(120).defaults.restSeconds, 120)
        XCTAssertEqual(custom(0).defaults.restSeconds, 0, "0 means the timer is off")
        XCTAssertEqual(custom(-5).defaults.restSeconds, 0)
        XCTAssertEqual(custom(99_999).defaults.restSeconds, 3_600)
        XCTAssertEqual(custom(StrengthPreferences(defaultRestSeconds: 75).defaultRestSeconds).defaults.restSeconds, 75)
        XCTAssertEqual(custom(nil).defaults.sets, 3)
    }

    func testStrengthDataCarriesThePreferences() {
        XCTAssertEqual(StrengthData().preferences, StrengthPreferences())
        XCTAssertEqual(StrengthData(preferences: changedPreferences()).preferences, changedPreferences())
        XCTAssertNotEqual(StrengthData(preferences: changedPreferences()), StrengthData())
    }
}

// MARK: - The file

final class PreferencesFileTests: XCTestCase {
    func testAMissingFileLoadsNilWithoutAnIssue() {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        XCTAssertNil(persistence.loadPreferences())
        XCTAssertFalse(persistence.hasPreferencesFile)
        XCTAssertTrue(persistence.loadIssues.isEmpty)
    }

    func testSaveAndLoad() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.savePreferences(changedPreferences())
        XCTAssertTrue(persistence.hasPreferencesFile)
        XCTAssertEqual(files(in: directory), ["preferences.json", "schema.json"])
        XCTAssertEqual(persistence.loadPreferences(), changedPreferences())
        XCTAssertEqual(FileStrengthPersistence(directory: directory).loadPreferences(), changedPreferences())
        XCTAssertTrue(persistence.hasDataFiles)
    }

    func testItIsAProtectedDataFile() {
        XCTAssertTrue(FileStrengthPersistence.dataFileNames.contains("preferences.json"))
        XCTAssertTrue(FileStrengthPersistence.protectedFileNames.contains("preferences.json"))
    }

    func testADamagedFileIsBackedUpAndLoadsNil() throws {
        let directory = makeDirectory(self)
        try Data("{ broken".utf8).write(to: directory.appendingPathComponent("preferences.json"))
        let persistence = FileStrengthPersistence(directory: directory)
        XCTAssertNil(persistence.loadPreferences())
        let issue = try XCTUnwrap(persistence.loadIssues.first)
        XCTAssertEqual(issue.fileName, "preferences.json")
        XCTAssertEqual(issue.kind, .unreadableFile)
        let backup = try XCTUnwrap(issue.backupFileName)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(backup)), Data("{ broken".utf8))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("preferences.json")), Data("{ broken".utf8), "loading changes nothing")
    }

    func testAPartialFileLoadsWithoutAnIssue() throws {
        let directory = makeDirectory(self)
        try Data("{\"weightUnit\":\"lb\"}".utf8).write(to: directory.appendingPathComponent("preferences.json"))
        let persistence = FileStrengthPersistence(directory: directory)
        var expected = StrengthPreferences()
        expected.weightUnit = .lb
        XCTAssertEqual(persistence.loadPreferences(), expected)
        XCTAssertTrue(persistence.loadIssues.isEmpty)
    }

    func testDeleteAllRemovesIt() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.savePreferences(changedPreferences())
        try persistence.deleteAll()
        XCTAssertFalse(persistence.hasPreferencesFile)
        XCTAssertEqual(files(in: directory), ["schema.json"])
    }
}

// MARK: - The model

final class PreferencesModelTests: XCTestCase {
    func testWithoutALocaleANewInstallUsesKilograms() {
        svcMain {
            XCTAssertEqual(StrengthDataModel(persistence: nil).preferences, StrengthPreferences())
            XCTAssertEqual(StrengthDataModel(persistence: nil, deviceLocale: deDE).preferences.weightUnit, .kg)
            XCTAssertEqual(StrengthDataModel(persistence: nil, deviceLocale: enUS).preferences.weightUnit, .lb)
        }
    }

    func testLoadingWritesNothing() {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        svcMain {
            let model = StrengthDataModel(persistence: persistence, deviceLocale: enUS)
            XCTAssertEqual(model.preferences.weightUnit, .lb)
        }
        XCTAssertEqual(files(in: directory), [])
        XCTAssertFalse(persistence.hasDataFiles)
        XCTAssertFalse(persistence.hasPreferencesFile)
    }

    func testTheFirstSaveOfAnythingKeepsTheUnitThatTheRegionPicked() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence, deviceLocale: enUS)
            try model.saveTemplate(StarterTemplates.all[0]).get()
        }
        XCTAssertEqual(persistence.loadPreferences()?.weightUnit, .lb)
        // The person moves to Germany: the unit they started with stays.
        svcMain {
            XCTAssertEqual(StrengthDataModel(persistence: persistence, deviceLocale: deDE).preferences.weightUnit, .lb)
        }
    }

    func testADataDirectoryOfAnOlderBuildKeepsKilogramsInAPoundRegion() throws {
        for (name, write): (String, (FileStrengthPersistence) throws -> Void) in [
            ("templates", { try $0.saveTemplates([StarterTemplates.all[0]]) }),
            ("history", { try $0.saveHistory([]) }),
            ("custom exercises", { try $0.saveCustomExercises([]) }),
            ("body weights", { try $0.saveBodyWeights([]) }),
        ] {
            let directory = makeDirectory(self)
            let persistence = FileStrengthPersistence(directory: directory)
            try write(persistence)
            XCTAssertFalse(persistence.hasPreferencesFile, name)
            try svcMain {
                for locale in [enUS, Locale(identifier: "en_LR"), Locale(identifier: "my_MM")] {
                    let model = StrengthDataModel(persistence: persistence, deviceLocale: locale)
                    XCTAssertEqual(model.preferences, StrengthPreferences(), "\(name), \(locale.identifier)")
                }
                let model = StrengthDataModel(persistence: persistence, deviceLocale: enUS)
                try model.saveTemplate(StarterTemplates.all[1]).get()
            }
            XCTAssertEqual(persistence.loadPreferences(), StrengthPreferences(), "\(name): the kilograms are stored with the next save")
        }
    }

    func testTheUpgradedUserCanStillChooseThePounds() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try persistence.saveTemplates([StarterTemplates.all[0]])
        try svcMain {
            let model = StrengthDataModel(persistence: persistence, deviceLocale: enUS)
            var preferences = model.preferences
            preferences.weightUnit = .lb
            try model.updatePreferences(preferences).get()
        }
        svcMain {
            XCTAssertEqual(StrengthDataModel(persistence: persistence, deviceLocale: deDE).preferences.weightUnit, .lb)
        }
    }

    func testOnlyTransientFilesDoNotMakeAnInstallAnOlderOne() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try Data("[]".utf8).write(to: directory.appendingPathComponent("acknowledged-commands.json"))
        try Data("{}".utf8).write(to: directory.appendingPathComponent("active-workout.json"))
        XCTAssertTrue(persistence.hasDataFiles)
        svcMain {
            XCTAssertEqual(StrengthDataModel(persistence: persistence, deviceLocale: enUS).preferences.weightUnit, .lb)
        }
    }

    func testStoredPreferencesAreNeverReplacedByTheFirstCreationOrALaterSave() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.savePreferences(changedPreferences())
        try svcMain {
            let model = StrengthDataModel(persistence: persistence, deviceLocale: deDE)
            XCTAssertEqual(model.preferences, changedPreferences())
            try model.saveTemplate(StarterTemplates.all[0]).get()
        }
        XCTAssertEqual(persistence.loadPreferences(), changedPreferences())
    }

    func testUpdatePreferencesSavesThemAndKeepsTheCountsInRange() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            var preferences = changedPreferences()
            try model.updatePreferences(preferences).get()
            XCTAssertEqual(model.preferences, preferences)
            XCTAssertEqual(persistence.loadPreferences(), preferences)
            XCTAssertNil(model.lastPersistenceError)

            preferences.weeklyGoalSessions = 99
            preferences.defaultRestSeconds = 99_999
            try model.updatePreferences(preferences).get()
            XCTAssertEqual(model.preferences.weeklyGoalSessions, 14)
            XCTAssertEqual(persistence.loadPreferences()?.weeklyGoalSessions, 14)
            XCTAssertEqual(persistence.loadPreferences()?.defaultRestSeconds, 3_600)
        }
    }

    func testAnUnchangedUpdateWritesNothingOnceTheyAreStored() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            try model.updatePreferences(changedPreferences()).get()
            let file = directory.appendingPathComponent("preferences.json")
            try FileManager.default.removeItem(at: file)
            try model.updatePreferences(changedPreferences()).get()
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "nothing changed, so nothing is written")
        }
    }

    func testSavingTheDefaultsOfAFreshInstallStoresThem() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence, deviceLocale: enUS)
            try model.updatePreferences(model.preferences).get()
        }
        XCTAssertEqual(persistence.loadPreferences()?.weightUnit, .lb)
    }

    func testAFailedWriteIsReportedAndTheChangeStaysInMemory() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let blocked = directory.appendingPathComponent("preferences.json")
            try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: blocked.appendingPathComponent("keep"))
            guard case .failure = model.updatePreferences(changedPreferences()) else { return XCTFail("preferences.json is blocked") }
            XCTAssertEqual(model.preferences, changedPreferences())
            XCTAssertNotNil(model.lastPersistenceError)
        }
    }

    func testADamagedFileIsLeftAloneUntilThePersonSavesNewPreferences() throws {
        let directory = makeDirectory(self)
        let broken = Data("{ broken".utf8)
        try broken.write(to: directory.appendingPathComponent("preferences.json"))
        let persistence = FileStrengthPersistence(directory: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence, deviceLocale: enUS)
            XCTAssertEqual(model.preferences, StrengthPreferences(locale: enUS), "the defaults of a new install")
            let issue = try XCTUnwrap(model.persistenceIssues.first { $0.fileName == "preferences.json" })
            XCTAssertEqual(issue.kind, .unreadableFile)
            let backup = try XCTUnwrap(issue.backupFileName)

            try model.saveTemplate(StarterTemplates.all[0]).get()
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("preferences.json")), broken, "another save leaves it alone")

            try model.updatePreferences(changedPreferences()).get()
            XCTAssertEqual(persistence.loadPreferences(), changedPreferences())
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(backup)), broken, "the original is kept")
        }
    }

    func testReloadReadsTheFileAgain() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(model.preferences, StrengthPreferences())
            try persistence.savePreferences(changedPreferences())
            model.reload()
            XCTAssertEqual(model.preferences, changedPreferences())
        }
    }

    func testResettingThePreferencesRestoresTheDefaultsOfANewInstall() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.savePreferences(changedPreferences())
        try persistence.saveWeighInPreferences(WeighInPreferences(isEnabled: true))
        try persistence.saveTemplates([StarterTemplates.all[0]])
        try svcMain {
            let model = StrengthDataModel(persistence: persistence, deviceLocale: enUS)
            try model.resetData(.preferences).get()
            XCTAssertEqual(model.preferences, StrengthPreferences(locale: enUS))
            XCTAssertEqual(model.data.weighIn, WeighInPreferences())
            XCTAssertEqual(model.data.templates.count, 1, "the templates stay")
        }
        XCTAssertEqual(persistence.loadPreferences(), StrengthPreferences(locale: enUS))
        XCTAssertEqual(persistence.loadWeighInPreferences(), WeighInPreferences())
        XCTAssertEqual(persistence.loadTemplates().count, 1)
    }

    func testResettingThePreferencesWithoutALocaleGivesKilograms() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try persistence.savePreferences(changedPreferences())
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            try model.resetData(.preferences).get()
            XCTAssertEqual(model.preferences, StrengthPreferences())
        }
        XCTAssertEqual(persistence.loadPreferences(), StrengthPreferences())
    }

    func testTheOtherResetScopesLeaveThePreferencesAlone() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try persistence.savePreferences(changedPreferences())
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            for scope: ResetScope in [.templates, .history, .customExercises, .bodyWeights] {
                try model.resetData(scope).get()
                XCTAssertEqual(model.preferences, changedPreferences(), "\(scope)")
            }
        }
        XCTAssertEqual(persistence.loadPreferences(), changedPreferences())
    }

    func testResettingEverythingRemovesTheFileAndTheNextSaveStoresTheDefaultsAgain() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.savePreferences(changedPreferences())
        try svcMain {
            let model = StrengthDataModel(persistence: persistence, deviceLocale: deDE)
            try model.resetData(.all).get()
            XCTAssertEqual(model.preferences, StrengthPreferences(locale: deDE))
            XCTAssertFalse(persistence.hasPreferencesFile)
            XCTAssertEqual(model.data, StrengthData(preferences: StrengthPreferences(locale: deDE)))

            try model.saveTemplate(StarterTemplates.all[1]).get()
            XCTAssertEqual(persistence.loadPreferences(), StrengthPreferences(locale: deDE))
        }
    }

    func testTheResetOfTheDataReachesThePureValue() {
        var data = StrengthData(preferences: changedPreferences())
        data.resetData(.templates)
        XCTAssertEqual(data.preferences, changedPreferences())
        data.resetData(.preferences, deviceLocale: enUS)
        XCTAssertEqual(data.preferences, StrengthPreferences(locale: enUS))
        data.preferences = changedPreferences()
        data.resetData(.preferences)
        XCTAssertEqual(data.preferences, StrengthPreferences())
        data.preferences = changedPreferences()
        data.resetData(.all, deviceLocale: deDE)
        XCTAssertEqual(data.preferences, StrengthPreferences(locale: deDE))
        XCTAssertTrue(ResetScope.all.contains(.preferences))
    }

    func testTheUnitOfTheModelDecidesTheTextsOfTheHistory() {
        let workout = SvcDataFix.workout(1, finishedAt: SvcDataFix.daysAgo(3), [SvcDataFix.entry("bench", [SvcDataFix.work(85, 5)], n: 1)])
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            model.data.history = [workout]
            XCTAssertEqual(model.history(for: "bench", now: SvcDataFix.now).bestSetText, "85 kg × 5")
            model.updatePreferences(StrengthPreferences(weightUnit: .lb))
            XCTAssertEqual(model.history(for: "bench", now: SvcDataFix.now).bestSetText, "187.4 lb × 5")
            XCTAssertEqual(model.history(for: "bench", now: SvcDataFix.now, locale: deDE).bestSetText, "187,4 lb × 5")
        }
    }
}

// MARK: - Workouts and the engine

final class PreferencesWorkoutTests: XCTestCase {
    func testTheFactoryTakesTheSettingsFromThePreferences() {
        let preferences = StrengthPreferences(weightUnit: .lb, autoStartRest: false, alertWhenRestEnds: false)
        let expected = WorkoutSettings(autoStartRest: false, alertWhenRestEnds: false, weightUnit: .lb)
        XCTAssertEqual(WorkoutFactory.makeEmpty(name: "Quick", now: epoch, preferences: preferences).settings, expected)
        XCTAssertEqual(WorkoutFactory.makeWorkout(from: StarterTemplates.all[0], now: epoch, preferences: preferences).settings, expected)
    }

    func testWithoutPreferencesTheSettingsAreTheOldDefaults() {
        XCTAssertEqual(WorkoutFactory.makeEmpty(name: "Quick", now: epoch).settings, WorkoutSettings())
        XCTAssertEqual(WorkoutFactory.makeWorkout(from: StarterTemplates.all[0], now: epoch).settings, WorkoutSettings())
        XCTAssertEqual(WorkoutSettings(), WorkoutSettings(autoStartRest: true, alertWhenRestEnds: true, weightUnit: .kg))
    }

    func testThePreferencesDoNotChangeTheRestOfAWorkout() {
        let plain = WorkoutFactory.makeWorkout(from: StarterTemplates.all[0], now: epoch, id: SvcSyncFix.uuid(1))
        var withPreferences = WorkoutFactory.makeWorkout(
            from: StarterTemplates.all[0], now: epoch, id: SvcSyncFix.uuid(1), preferences: changedPreferences()
        )
        withPreferences.settings = plain.settings
        XCTAssertEqual(withPreferences.exercises.map { $0.exercise }, plain.exercises.map { $0.exercise })
        XCTAssertEqual(withPreferences.exercises.map { $0.sets.map { $0.weightKg } }, plain.exercises.map { $0.sets.map { $0.weightKg } })
        XCTAssertEqual(withPreferences.exercises.map { $0.restSeconds }, plain.exercises.map { $0.restSeconds })
    }

    func testTheEngineStartsWorkoutsWithTheCurrentPreferences() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let engine = WorkoutEngine(role: .authority, persistence: persistence, data: model, clock: { epoch })
            try model.updatePreferences(StrengthPreferences(weightUnit: .lb, autoStartRest: false, alertWhenRestEnds: false)).get()

            XCTAssertTrue(engine.start(template: StarterTemplates.all[0]))
            XCTAssertEqual(engine.state?.settings, WorkoutSettings(autoStartRest: false, alertWhenRestEnds: false, weightUnit: .lb))
            engine.discard()

            XCTAssertTrue(engine.start(template: nil, name: "Open"))
            XCTAssertEqual(engine.state?.settings, WorkoutSettings(autoStartRest: false, alertWhenRestEnds: false, weightUnit: .lb))
            engine.discard()

            try model.updatePreferences(StrengthPreferences()).get()
            XCTAssertTrue(engine.start(template: nil))
            XCTAssertEqual(engine.state?.settings, WorkoutSettings())
        }
    }

    func testARestChoiceMadeDuringAWorkoutIsTheNextWorkoutsToo() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let engine = WorkoutEngine(role: .authority, persistence: persistence, data: model, clock: { epoch })
            engine.start(template: StarterTemplates.all[0])
            engine.send(.setAutoStartRest(false))
            XCTAssertFalse(model.preferences.autoStartRest)
            XCTAssertTrue(model.preferences.alertWhenRestEnds)
            XCTAssertEqual(persistence.loadPreferences()?.autoStartRest, false, "saved, not only remembered")
            engine.send(.setAlertWhenRestEnds(false))
            XCTAssertFalse(model.preferences.alertWhenRestEnds)
            engine.discard()

            engine.start(template: StarterTemplates.all[1])
            XCTAssertEqual(engine.state?.settings, WorkoutSettings(autoStartRest: false, alertWhenRestEnds: false))
            engine.send(.setAutoStartRest(true))
            XCTAssertTrue(model.preferences.autoStartRest)
            XCTAssertEqual(persistence.loadPreferences(), StrengthPreferences(autoStartRest: true, alertWhenRestEnds: false))
        }
    }

    func testARestChoiceWritesBackOnlyItsOwnToggleNotTheWorkoutsStaleOne() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let engine = WorkoutEngine(role: .authority, persistence: persistence, data: model, clock: { epoch })
            engine.start(template: StarterTemplates.all[0])
            XCTAssertEqual(engine.state?.settings, WorkoutSettings(), "the workout starts with both toggles on")

            // Settings turn the alert off while the workout runs; the workout keeps its own toggles.
            try model.updatePreferences(StrengthPreferences(autoStartRest: true, alertWhenRestEnds: false)).get()
            engine.send(.setAutoStartRest(false))
            XCTAssertEqual(model.preferences, StrengthPreferences(autoStartRest: false, alertWhenRestEnds: false), "the alert choice survives")
            XCTAssertEqual(persistence.loadPreferences(), StrengthPreferences(autoStartRest: false, alertWhenRestEnds: false))

            // Settings turn auto-start back on; the workout still has it off and the alert on.
            try model.updatePreferences(StrengthPreferences(autoStartRest: true, alertWhenRestEnds: false)).get()
            engine.send(.setAlertWhenRestEnds(false))
            XCTAssertEqual(model.preferences, StrengthPreferences(autoStartRest: true, alertWhenRestEnds: false), "the auto-start choice survives")
            XCTAssertEqual(persistence.loadPreferences(), StrengthPreferences(autoStartRest: true, alertWhenRestEnds: false))
        }
    }

    func testEachRestChoiceCopiesItsOwnToggleWhateverTheOtherOneIs() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let engine = WorkoutEngine(role: .authority, persistence: persistence, data: model, clock: { epoch })
            engine.start(template: StarterTemplates.all[0])
            XCTAssertEqual(engine.state?.settings, WorkoutSettings(autoStartRest: true, alertWhenRestEnds: true))

            // Each action is sent while the other toggle of the workout has the opposite value, in both directions.
            let steps: [(WorkoutAction, StrengthPreferences)] = [
                (.setAlertWhenRestEnds(false), StrengthPreferences(autoStartRest: true, alertWhenRestEnds: false)),
                (.setAutoStartRest(false), StrengthPreferences(autoStartRest: false, alertWhenRestEnds: false)),
                (.setAlertWhenRestEnds(true), StrengthPreferences(autoStartRest: false, alertWhenRestEnds: true)),
                (.setAutoStartRest(true), StrengthPreferences(autoStartRest: true, alertWhenRestEnds: true)),
                (.setAutoStartRest(false), StrengthPreferences(autoStartRest: false, alertWhenRestEnds: true)),
                (.setAlertWhenRestEnds(false), StrengthPreferences(autoStartRest: false, alertWhenRestEnds: false)),
                (.setAutoStartRest(true), StrengthPreferences(autoStartRest: true, alertWhenRestEnds: false)),
                (.setAlertWhenRestEnds(true), StrengthPreferences(autoStartRest: true, alertWhenRestEnds: true)),
            ]
            for (action, expected) in steps {
                engine.send(action)
                XCTAssertEqual(model.preferences, expected, "\(action)")
                XCTAssertEqual(persistence.loadPreferences(), expected, "\(action) is saved")
            }
        }
    }

    func testARestChoiceFromTheWatchIsRememberedByThePhone() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let engine = WorkoutEngine(role: .authority, persistence: persistence, data: model, clock: { epoch })
            engine.start(template: StarterTemplates.all[0])
            let command = RemoteCommand(action: .setAutoStartRest(false), origin: .watch, issuedAt: epoch, workoutID: engine.state?.id)
            engine.receive(command)
            XCTAssertFalse(model.preferences.autoStartRest)
        }
    }

    func testOnlyTheRestChoicesAreWrittenBackNotTheUnitNorOtherEdits() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let engine = WorkoutEngine(role: .authority, persistence: persistence, data: model, clock: { epoch })
            engine.start(template: StarterTemplates.all[0])
            engine.send(.setWeightUnit(.lb))
            engine.send(.rename("Push (heavy)"))
            engine.send(.nextExercise)
            XCTAssertEqual(model.preferences, StrengthPreferences(), "a unit chosen for one workout is not the preference")
            XCTAssertFalse(persistence.hasPreferencesFile)
        }
    }

    func testAMirrorNeverWritesPreferences() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let engine = WorkoutEngine(role: .mirror, persistence: nil, data: model, clock: { epoch })
            engine.receive(SyncEnvelope(state: WorkoutFactory.makeWorkout(from: StarterTemplates.all[0], now: epoch, id: SvcSyncFix.uuid(1)), sentAt: epoch))
            engine.send(.setAutoStartRest(false), origin: .watch)
            XCTAssertEqual(engine.state?.settings.autoStartRest, false)
            XCTAssertEqual(model.preferences, StrengthPreferences())
        }
    }

    func testAProviderWithoutPreferencesGivesTheDefaults() throws {
        @MainActor final class Bare: WorkoutDataProviding {
            func exercise(id: String) -> Exercise? { ExerciseLibrary.exercise(id: id) }
            func template(id: UUID) -> WorkoutTemplate? { nil }
            func record(_ completed: CompletedWorkout, updateTemplate: WorkoutTemplate?) -> Result<Void, Error> { .success(()) }
            func recoveryProvider(now: Date) -> RecoveryProvider { DemoRecovery.provider }
        }
        try svcMain {
            let bare = Bare()
            XCTAssertEqual(bare.preferences, StrengthPreferences())
            XCTAssertTrue(bare.recoveryHasData(now: epoch), "a provider that says nothing about its data has data")
            try bare.updatePreferences(changedPreferences()).get()
            XCTAssertEqual(bare.preferences, StrengthPreferences(), "it keeps none")
            let engine = WorkoutEngine(role: .authority, persistence: nil, data: bare, clock: { epoch })
            engine.start(template: nil)
            engine.send(.setAutoStartRest(false))
            XCTAssertEqual(engine.state?.settings.autoStartRest, false)
        }
    }

    func testTheDisplayLocaleDecidesTheSeparatorsOfPresentationAndSnapshot() throws {
        try svcMain {
            let engine = WorkoutEngine(role: .authority, persistence: nil, data: StrengthDataModel(persistence: nil), clock: { epoch })
            XCTAssertEqual(engine.displayLocale.identifier, "en_US", "the default is reproducible English")
            engine.start(template: StarterTemplates.all[0])
            let benchSet = try XCTUnwrap(engine.state?.exercises[0].sets[0])
            engine.send(.setWeight(exerciseID: engine.state!.exercises[0].id, setID: benchSet.id, kg: 82.5))
            XCTAssertEqual(engine.presentation(now: epoch)?.card?.rows[0].weightText, "82.5")
            XCTAssertEqual(engine.snapshot(now: epoch)?.weightText, "82.5")

            engine.displayLocale = deDE
            XCTAssertEqual(engine.presentation(now: epoch)?.card?.rows[0].weightText, "82,5")
            XCTAssertEqual(engine.snapshot(now: epoch)?.weightText, "82,5")
            XCTAssertEqual(engine.snapshot(now: epoch)?.weightUnit, .kg)

            engine.send(.setWeightUnit(.lb))
            XCTAssertEqual(engine.presentation(now: epoch)?.card?.rows[0].weightText, "181,9")
            XCTAssertEqual(engine.presentation(now: epoch)?.card?.weightColumnTitle, "lb")
            XCTAssertEqual(engine.snapshot(now: epoch)?.weightText, "181,9")
            XCTAssertEqual(engine.snapshot(now: epoch)?.weightUnit, .lb)
        }
    }
}

// MARK: - Store and controller

#if canImport(Combine) || PULSE_COMBINE_SHIM
final class PreferencesStoreAndControllerTests: XCTestCase {
    @MainActor private func makeController(
        _ persistence: FileStrengthPersistence?, role: WorkoutRole = .authority, deviceLocale: Locale? = nil
    ) -> (store: StrengthStore, controller: WorkoutController) {
        let store = StrengthStore(persistence: persistence, deviceLocale: deviceLocale)
        return (store, WorkoutController(store: store, persistence: persistence, role: role, recovery: DemoRecovery.provider, clock: { epoch }))
    }

    func testAnOlderBuildsTemplateStartsAWorkoutInKilogramsInTheUnitedStates() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try persistence.saveTemplates([StarterTemplates.all[0]])
        svcMain {
            let (store, controller) = makeController(persistence, deviceLocale: enUS)
            XCTAssertEqual(store.preferences.weightUnit, .kg)
            controller.startWorkout(template: StarterTemplates.all[0])
            XCTAssertEqual(controller.state?.settings.weightUnit, .kg)
        }
    }

    func testTheStorePublishesAndSavesThePreferences() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try svcMain {
            let store = StrengthStore(persistence: persistence, deviceLocale: enUS)
            XCTAssertEqual(store.preferences, StrengthPreferences(locale: enUS))
            try store.updatePreferences(changedPreferences()).get()
            XCTAssertEqual(store.preferences, changedPreferences())
            XCTAssertEqual(persistence.loadPreferences(), changedPreferences())
            XCTAssertEqual(StrengthStore(persistence: persistence).preferences, changedPreferences(), "it comes back at the next launch")
            try store.resetData(.preferences).get()
            XCTAssertEqual(store.preferences, StrengthPreferences(locale: enUS))
        }
    }

    func testTheStoreWithoutALocaleUsesKilogramsAndReportsAFailedSave() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try svcMain {
            let store = StrengthStore(persistence: persistence)
            XCTAssertEqual(store.preferences.weightUnit, .kg)
            let blocked = directory.appendingPathComponent("preferences.json")
            try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: blocked.appendingPathComponent("keep"))
            guard case .failure = store.updatePreferences(changedPreferences()) else { return XCTFail("preferences.json is blocked") }
            XCTAssertEqual(store.preferences, changedPreferences(), "the change stays in memory")
            XCTAssertNotNil(store.lastPersistenceError)
        }
    }

    func testTheStoresHistoryFollowsThePreferredUnit() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        let workout = SvcDataFix.workout(1, finishedAt: SvcDataFix.daysAgo(3), [SvcDataFix.entry("bench", [SvcDataFix.work(85, 5)], n: 1)])
        try persistence.saveHistory([workout])
        try svcMain {
            let store = StrengthStore(persistence: persistence)
            XCTAssertEqual(store.history(for: "bench", now: SvcDataFix.now).bestSetText, "85 kg × 5")
            try store.updatePreferences(StrengthPreferences(weightUnit: .lb)).get()
            XCTAssertEqual(store.history(for: "bench", now: SvcDataFix.now).bestSetText, "187.4 lb × 5")
            XCTAssertEqual(store.history(for: "bench", now: SvcDataFix.now, locale: deDE).bestSetText, "187,4 lb × 5")
        }
    }

    func testAWorkoutStartsWithThePreferences() throws {
        try svcMain {
            let (store, controller) = makeController(nil)
            try store.updatePreferences(StrengthPreferences(weightUnit: .lb, autoStartRest: false)).get()
            controller.startWorkout(template: StarterTemplates.all[0])
            XCTAssertEqual(controller.state?.settings, WorkoutSettings(autoStartRest: false, alertWhenRestEnds: true, weightUnit: .lb))
            XCTAssertEqual(controller.presentation(now: epoch)?.card?.weightColumnTitle, "lb")
            XCTAssertEqual(controller.snapshot(now: epoch)?.weightUnit, .lb)
        }
    }

    func testChangingTheUnitDuringAWorkoutSwitchesTheWorkoutAtOnce() throws {
        try svcMain {
            let (store, controller) = makeController(nil)
            controller.startWorkout(template: StarterTemplates.all[0])
            let before = try XCTUnwrap(controller.state)
            XCTAssertEqual(before.settings.weightUnit, .kg)
            XCTAssertEqual(controller.presentation(now: epoch)?.card?.weightColumnTitle, "kg")

            var preferences = store.preferences
            preferences.weightUnit = .lb
            try controller.updatePreferences(preferences).get()
            let after = try XCTUnwrap(controller.state)
            XCTAssertEqual(after.settings.weightUnit, .lb)
            XCTAssertEqual(after.revision, before.revision + 1, "one change, so the Watch and the Live Activity follow")
            XCTAssertEqual(after.exercises, before.exercises, "stored weights do not change")
            XCTAssertEqual(store.preferences.weightUnit, .lb)
            XCTAssertEqual(controller.presentation(now: epoch)?.card?.weightColumnTitle, "lb")
            XCTAssertEqual(controller.makeEnvelope(now: epoch).state?.settings.weightUnit, .lb, "it reaches the Watch with the state")

            preferences.weightUnit = .kg
            try controller.updatePreferences(preferences).get()
            XCTAssertEqual(controller.state?.settings.weightUnit, .kg)
            XCTAssertEqual(controller.state?.revision, before.revision + 2)
        }
    }

    func testTheEffectsAreToldAboutTheUnitChange() throws {
        @MainActor final class Recorder: WorkoutSideEffect {
            var actions: [WorkoutAction] = []
            func workoutChanged(from old: WorkoutState, to new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
                actions.append(action)
            }
        }
        try svcMain {
            let (_, controller) = makeController(nil)
            let recorder = Recorder()
            controller.addEffect(recorder)
            controller.startWorkout(template: StarterTemplates.all[0])
            try controller.updatePreferences(StrengthPreferences(weightUnit: .lb)).get()
            XCTAssertEqual(recorder.actions, [.setWeightUnit(.lb)])
        }
    }

    func testNothingIsSentWhenTheUnitIsTheSameOrThereIsNoWorkout() throws {
        try svcMain {
            let (store, controller) = makeController(nil)
            try controller.updatePreferences(StrengthPreferences(weightUnit: .lb)).get()
            XCTAssertNil(controller.state)
            XCTAssertEqual(store.preferences.weightUnit, .lb)

            controller.startWorkout(template: StarterTemplates.all[0])
            let started = try XCTUnwrap(controller.state)
            XCTAssertEqual(started.settings.weightUnit, .lb)
            var preferences = store.preferences
            preferences.weeklyGoalSessions = 6
            try controller.updatePreferences(preferences).get()
            XCTAssertEqual(controller.state, started, "a preference that is not the unit changes nothing in the workout")
        }
    }

    func testTheRunningWorkoutKeepsItsOwnRestToggles() throws {
        try svcMain {
            let (store, controller) = makeController(nil)
            controller.startWorkout(template: StarterTemplates.all[0])
            controller.send(.setAutoStartRest(false))
            XCTAssertFalse(store.preferences.autoStartRest, "turning it off in the workout is the new preference")
            var preferences = store.preferences
            preferences.autoStartRest = true
            preferences.alertWhenRestEnds = false
            try controller.updatePreferences(preferences).get()
            XCTAssertEqual(controller.state?.settings.autoStartRest, false, "the settings screen does not reach into the workout")
            XCTAssertEqual(controller.state?.settings.alertWhenRestEnds, true)
            XCTAssertTrue(store.preferences.autoStartRest)
            XCTAssertFalse(store.preferences.alertWhenRestEnds)
        }
    }

    func testARestToggleOfTheWorkoutScreenIsRememberedForTheNextWorkout() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        svcMain {
            let (store, controller) = makeController(persistence)
            controller.startWorkout(template: StarterTemplates.all[0])
            controller.send(.setAutoStartRest(false))
            controller.send(.setAlertWhenRestEnds(false))
            XCTAssertEqual(store.preferences.autoStartRest, false)
            XCTAssertEqual(store.preferences.alertWhenRestEnds, false)
            controller.discard()
            controller.startWorkout(template: StarterTemplates.all[1])
            XCTAssertEqual(controller.state?.settings, WorkoutSettings(autoStartRest: false, alertWhenRestEnds: false))

            let relaunched = StrengthStore(persistence: persistence)
            XCTAssertEqual(relaunched.preferences.autoStartRest, false, "it survives a relaunch")
        }
    }

    func testAMirrorControllerDoesNotChangeThePreferences() throws {
        svcMain {
            let (store, controller) = makeController(nil, role: .mirror)
            let phone = WorkoutFactory.makeWorkout(from: StarterTemplates.all[0], now: epoch, id: SvcSyncFix.uuid(2))
            controller.receive(SyncEnvelope(state: phone, sentAt: epoch))
            controller.send(.setAutoStartRest(false), origin: .watch)
            XCTAssertEqual(controller.state?.settings.autoStartRest, false)
            XCTAssertEqual(store.preferences, StrengthPreferences())
        }
    }

    func testTheDisplayLocaleOfTheController() throws {
        try svcMain {
            let (_, controller) = makeController(nil)
            XCTAssertEqual(controller.displayLocale.identifier, "en_US")
            controller.startWorkout(template: StarterTemplates.all[0])
            let state = try XCTUnwrap(controller.state)
            controller.send(.setWeight(exerciseID: state.exercises[0].id, setID: state.exercises[0].sets[0].id, kg: 82.5))
            XCTAssertEqual(controller.presentation(now: epoch)?.card?.rows[0].weightText, "82.5")
            controller.displayLocale = deDE
            XCTAssertEqual(controller.displayLocale, deDE)
            XCTAssertEqual(controller.presentation(now: epoch)?.card?.rows[0].weightText, "82,5")
            XCTAssertEqual(controller.snapshot(now: epoch)?.weightText, "82,5")
        }
    }
}
#endif
