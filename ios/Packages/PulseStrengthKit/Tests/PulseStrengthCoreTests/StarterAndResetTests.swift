import Foundation
import XCTest
@testable import PulseStrengthCore

private func makeDirectory(_ test: XCTestCase) -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PulseStrength-reset-" + UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    test.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory
}

private func files(in directory: URL) -> Set<String> {
    Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
}

// MARK: - Starter templates

final class StarterTemplatesTests: XCTestCase {
    func testPushPullAndLegsInThatOrder() {
        XCTAssertEqual(StarterTemplates.all.map { $0.name }, ["Push", "Pull", "Legs"])
        XCTAssertEqual(StarterTemplates.all.map { $0.entries.map { $0.exercise.id } }, [
            ["bench", "ohp", "incline", "lateral", "pushdown", "ohtri"],
            ["pulldown", "brow", "crow", "facepull", "curl", "hammer"],
            ["squat", "rdl", "legpress", "legcurl", "legext", "calf"],
        ])
    }

    func testTheIDsAreFixedAndDoNotCollideWithTheSampleData() {
        XCTAssertEqual(StarterTemplates.all.map { $0.id.uuidString }, [
            "57A20001-0000-4000-8000-000000000001",
            "57A20001-0000-4000-8000-000000000002",
            "57A20001-0000-4000-8000-000000000003",
        ])
        let entryIDs = StarterTemplates.all.flatMap { $0.entries.map { $0.id } }
        XCTAssertEqual(Set(entryIDs).count, 18)
        XCTAssertEqual(entryIDs.first?.uuidString, "57A20002-0000-4000-8000-000000000101")
        let sampleIDs = Set(SampleData.templateIDs + SampleData.templates().flatMap { $0.entries.map { $0.id } })
        XCTAssertTrue(sampleIDs.isDisjoint(with: Set(StarterTemplates.all.map { $0.id } + entryIDs)))
    }

    func testEveryEntryIsABuiltInExerciseWithItsDefaultsAndNoHistory() throws {
        for template in StarterTemplates.all {
            XCTAssertTrue((5...6).contains(template.entries.count), template.name)
            XCTAssertNil(template.lastPerformed)
            XCTAssertEqual(Set(template.entries.map { $0.exercise.id }).count, template.entries.count, "no exercise twice in \(template.name)")
            for entry in template.entries {
                let library = try XCTUnwrap(ExerciseLibrary.exercise(id: entry.exercise.id), entry.exercise.id)
                XCTAssertEqual(entry.exercise, library, "the library's exercise, without any previous results")
                XCTAssertEqual(entry.exercise.previousBestE1RM, 0)
                XCTAssertEqual(entry.exercise.previousSets, [])
                XCTAssertEqual(entry.plannedSets.count, library.defaults.sets, entry.exercise.id)
                XCTAssertTrue(entry.plannedSets.allSatisfy { $0.type == .normal && $0.weightKg == library.defaults.weightKg && $0.reps == library.defaults.reps })
                XCTAssertEqual(entry.restSeconds, library.defaults.restSeconds)
                XCTAssertNil(entry.supersetGroup)
                XCTAssertEqual(entry.note, "")
            }
        }
    }

    func testEachTemplateTrainsTheMuscleGroupsOfItsName() {
        func muscles(_ index: Int) -> Set<MuscleGroup> { Set(StarterTemplates.all[index].entries.map { $0.exercise.muscle }) }
        XCTAssertEqual(muscles(0), [.chest, .shoulders, .arms])
        XCTAssertEqual(muscles(1), [.back, .shoulders, .arms])
        XCTAssertEqual(muscles(2), [.legs])
    }

    func testAWorkoutCanBeStartedFromEachTemplate() {
        for template in StarterTemplates.all {
            let state = WorkoutFactory.makeWorkout(from: template, now: SvcSyncFix.epoch)
            XCTAssertEqual(state.exercises.count, template.entries.count)
            XCTAssertEqual(state.name, template.name)
            XCTAssertTrue(state.exercises.allSatisfy { $0.sets.count >= 3 && $0.sets.allSatisfy { !$0.isDone } })
            XCTAssertGreaterThan(template.estimatedMinutes, 0)
        }
    }

    func testAddingThemTwiceNeverDuplicates() {
        var data = StrengthData()
        XCTAssertEqual(data.addStarterTemplates(), 3)
        XCTAssertEqual(data.templates.map { $0.name }, ["Push", "Pull", "Legs"])
        XCTAssertEqual(data.addStarterTemplates(), 0)
        XCTAssertEqual(data.templates.count, 3)
    }

    func testTheUsersTemplatesStayInFrontAndEditedStartersAreKept() throws {
        var data = StrengthData(templates: [WorkoutTemplate(name: "Mine", entries: [])])
        XCTAssertEqual(data.addStarterTemplates(), 3)
        XCTAssertEqual(data.templates.map { $0.name }, ["Mine", "Push", "Pull", "Legs"])
        try data.renameTemplate(id: StarterTemplates.all[0].id, to: "Heavy push").get()
        XCTAssertEqual(data.addStarterTemplates(), 0)
        XCTAssertEqual(data.templates.map { $0.name }, ["Mine", "Heavy push", "Pull", "Legs"])
    }

    func testADeletedStarterTemplateCanBeAddedAgain() throws {
        var data = StrengthData()
        data.addStarterTemplates()
        try data.deleteTemplate(id: StarterTemplates.all[1].id).get()
        XCTAssertEqual(data.addStarterTemplates(), 1)
        XCTAssertEqual(data.templates.map { $0.name }, ["Push", "Legs", "Pull"])
    }

    func testTheModelSavesThemAndReportsHowManyWereAdded() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(try model.addStarterTemplates().get(), 3)
            XCTAssertEqual(persistence.loadTemplates(), StarterTemplates.all)
            XCTAssertEqual(try model.addStarterTemplates().get(), 0)
            let reloaded = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(reloaded.data.templates, StarterTemplates.all)
            XCTAssertEqual(try reloaded.addStarterTemplates().get(), 0)
            XCTAssertEqual(reloaded.exercise(id: "bench")?.previousBestE1RM, 0, "starting values only, no history")
        }
    }

    func testNothingIsWrittenWhenAllTemplatesAreThere() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.saveTemplates(StarterTemplates.all)
        let before = try Data(contentsOf: directory.appendingPathComponent("templates.json"))
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(try model.addStarterTemplates().get(), 0)
        }
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("templates.json")), before)
    }

    func testAFailedSaveIsReportedAndTheTemplatesStayInMemory() throws {
        let directory = makeDirectory(self)
        let blocked = directory.appendingPathComponent("templates.json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: blocked.appendingPathComponent("keep"))
        svcMain {
            let model = StrengthDataModel(persistence: FileStrengthPersistence(directory: directory))
            guard case .failure = model.addStarterTemplates() else { return XCTFail("templates.json is blocked") }
            XCTAssertEqual(model.data.templates.count, 3)
            XCTAssertNotNil(model.lastPersistenceError)
        }
    }

    #if canImport(Combine) || PULSE_COMBINE_SHIM
    func testTheStorePublishesThem() throws {
        try svcMain {
            let store = StrengthStore(persistence: nil)
            XCTAssertEqual(try store.addStarterTemplates().get(), 3)
            XCTAssertEqual(store.templates.map { $0.name }, ["Push", "Pull", "Legs"])
            XCTAssertEqual(try store.addStarterTemplates().get(), 0)
        }
    }
    #endif
}

// MARK: - Reset

final class ResetDataTests: XCTestCase {
    private typealias F = SvcDataFix

    /// Templates (one performed), two user workouts with a personal best, a custom exercise, two weigh-ins and changed preferences.
    private func populated() -> StrengthData {
        var data = StrengthData()
        let custom = F.customExercise("Hex press")
        data.addCustomExercise(custom)
        var withCustom = StarterTemplates.all[0]
        withCustom.entries.append(TemplateEntry(exercise: custom, plannedSets: [PlannedSet(weightKg: 20, reps: 10)], restSeconds: 60))
        data.saveTemplate(withCustom)
        data.saveTemplate(StarterTemplates.all[1])
        data.record(
            F.workout(1, name: "Push", templateID: withCustom.id, finishedAt: F.daysAgo(3), [F.entry("bench", [F.work(80, 5)], n: 1)]),
            updateTemplate: nil
        )
        data.record(
            F.workout(2, name: "Push", templateID: withCustom.id, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(85, 5)], n: 2)]),
            updateTemplate: nil
        )
        data.recordBodyWeight(kg: 80, date: F.daysAgo(5))
        data.recordBodyWeight(kg: 79.5, date: F.daysAgo(1))
        data.weighIn = WeighInPreferences(isEnabled: true, interval: .monthly, hour: 7, minute: 30, enabledAt: F.daysAgo(9), syncWithHealth: true)
        return data
    }

    /// `populated().weighIn` with the Health exchange off: what resetting the weigh-ins leaves of the preferences.
    private func preferencesWithoutHealthSync() -> WeighInPreferences {
        var preferences = populated().weighIn
        preferences.syncWithHealth = false
        return preferences
    }

    // MARK: Each scope on its own

    func testTemplatesOnly() {
        let original = populated()
        XCTAssertNotNil(original.templates.first?.lastPerformed)
        var data = original
        data.resetData(.templates)
        XCTAssertEqual(data.templates, [])
        XCTAssertEqual(data.history, original.history, "finished workouts keep their template id and name")
        XCTAssertEqual(data.personalBests, original.personalBests)
        XCTAssertEqual(data.customExercises, original.customExercises)
        XCTAssertEqual(data.bodyWeights, original.bodyWeights)
        XCTAssertEqual(data.weighIn, original.weighIn)
    }

    func testHistoryAlsoClearsTheBestsAndTheLastPerformedDates() {
        let original = populated()
        XCTAssertEqual(original.personalBests.count, 1)
        var data = original
        data.resetData(.history)
        XCTAssertEqual(data.history, [])
        XCTAssertEqual(data.personalBests, [:])
        XCTAssertEqual(data.templates.map { $0.name }, original.templates.map { $0.name })
        XCTAssertTrue(data.templates.allSatisfy { $0.lastPerformed == nil })
        XCTAssertEqual(data.templates.map { $0.entries }, original.templates.map { $0.entries })
        XCTAssertEqual(data.customExercises, original.customExercises)
        XCTAssertEqual(data.bodyWeights, original.bodyWeights)
        XCTAssertEqual(data.weighIn, original.weighIn)
        XCTAssertEqual(data.exercise(id: "bench")?.previousBestE1RM, 0)
    }

    func testCustomExercisesOnlyKeepsTheCopiesInTemplatesAndTheNamesInHistory() throws {
        let original = populated()
        let id = try XCTUnwrap(original.customExercises.first?.id)
        var data = original
        data.resetData(.customExercises)
        XCTAssertEqual(data.customExercises, [])
        XCTAssertEqual(data.templates, original.templates)
        XCTAssertTrue(data.templates[0].entries.contains { $0.exercise.id == id }, "the template keeps its embedded copy")
        XCTAssertNil(data.exercise(id: id), "but the library no longer has the exercise")
        XCTAssertEqual(data.exercises().count, 36)
        XCTAssertEqual(data.history, original.history)
        XCTAssertEqual(data.personalBests, original.personalBests)
    }

    func testBodyWeightsOnly() {
        let original = populated()
        var data = original
        data.resetData(.bodyWeights)
        XCTAssertEqual(data.bodyWeights, [])
        XCTAssertEqual(data.weighIn, preferencesWithoutHealthSync(), "the reminder stays, the Health exchange is off")
        XCTAssertEqual(data.templates, original.templates)
        XCTAssertEqual(data.history, original.history)
    }

    func testResettingTheWeighInsSwitchesTheHealthExchangeOff() {
        var data = populated()
        XCTAssertTrue(data.weighIn.syncWithHealth)
        data.resetData(.bodyWeights)
        XCTAssertFalse(data.weighIn.syncWithHealth, "otherwise the next read from Health would bring the weigh-ins back")
        data.resetData(.bodyWeights)
        XCTAssertFalse(data.weighIn.syncWithHealth, "repeating it changes nothing")
        XCTAssertEqual(data.bodyWeights, [])
    }

    func testPreferencesOnly() {
        let original = populated()
        var data = original
        data.resetData(.preferences)
        XCTAssertEqual(data.weighIn, WeighInPreferences())
        XCTAssertEqual(data.bodyWeights, original.bodyWeights)
        XCTAssertEqual(data.templates, original.templates)
        XCTAssertEqual(data.history, original.history)
        XCTAssertEqual(data.customExercises, original.customExercises)
    }

    func testAnEmptyScopeChangesNothing() {
        var data = populated()
        let original = data
        data.resetData([])
        XCTAssertEqual(data, original)
    }

    // MARK: Combinations

    func testEverythingIsEmptyAfterAll() {
        var data = populated()
        data.historyIsIncomplete = true
        data.usesDemoPreviousResults = true
        data.resetData(.all)
        XCTAssertEqual(data, StrengthData())
        XCTAssertTrue(data.isEmpty)
    }

    func testAllWithoutPreferencesKeepsThePreferences() {
        let original = populated()
        var data = original
        data.resetData(ResetScope.all.subtracting(.preferences))
        XCTAssertEqual(data, StrengthData(weighIn: preferencesWithoutHealthSync()))
    }

    func testScopesCombine() {
        let original = populated()
        var data = original
        data.resetData([.templates, .bodyWeights])
        XCTAssertEqual(data.templates, [])
        XCTAssertEqual(data.bodyWeights, [])
        XCTAssertEqual(data.history, original.history)
        XCTAssertEqual(data.customExercises, original.customExercises)
        XCTAssertEqual(data.weighIn, preferencesWithoutHealthSync())
    }

    func testResettingTheHistoryEndsTheDemoPreviousResultsAndTheIncompleteMark() {
        var data = StrengthData.demo(now: F.now)
        data.historyIsIncomplete = true
        data.resetData(.templates)
        XCTAssertTrue(data.usesDemoPreviousResults, "other scopes leave the demo numbers")
        XCTAssertTrue(data.historyIsIncomplete)
        data.resetData(.history)
        XCTAssertFalse(data.usesDemoPreviousResults)
        XCTAssertFalse(data.historyIsIncomplete)
        XCTAssertEqual(data.exercise(id: "bench")?.previousBestE1RM, 0)
        XCTAssertEqual(data.personalBests, [:])
    }

    func testTheScopeConstants() {
        XCTAssertEqual(ResetScope.all, [.templates, .history, .customExercises, .bodyWeights, .preferences])
        XCTAssertEqual(Set([ResetScope.templates, .history, .customExercises, .bodyWeights, .preferences].map { $0.rawValue }).count, 5)
        XCTAssertTrue(ResetScope.all.contains(.history))
    }

    // MARK: Through the model and the files

    private func seedFiles(_ persistence: FileStrengthPersistence) throws {
        let data = populated()
        try persistence.saveTemplates(data.templates)
        try persistence.saveHistory(data.history)
        try persistence.saveCustomExercises(data.customExercises)
        try persistence.savePersonalBests(data.personalBests)
        try persistence.saveBodyWeights(data.bodyWeights)
        try persistence.saveWeighInPreferences(data.weighIn)
    }

    func testEachScopeIsSavedAndSurvivesARelaunch() throws {
        let scopes: [ResetScope] = [.templates, .history, .customExercises, .bodyWeights, .preferences, [.templates, .history], .all]
        for scope in scopes {
            let persistence = FileStrengthPersistence(directory: makeDirectory(self))
            try seedFiles(persistence)
            try svcMain {
                let model = StrengthDataModel(persistence: persistence)
                var expected = model.data
                expected.resetData(scope)
                XCTAssertNoThrow(try model.resetData(scope).get(), "\(scope)")
                XCTAssertEqual(model.data, expected, "\(scope)")
                XCTAssertNil(model.lastPersistenceError)

                XCTAssertEqual(persistence.loadTemplates(), expected.templates, "\(scope)")
                XCTAssertEqual(persistence.loadHistory(), expected.history, "\(scope)")
                XCTAssertEqual(persistence.loadCustomExercises(), expected.customExercises, "\(scope)")
                XCTAssertEqual(persistence.loadPersonalBests(), expected.personalBests, "\(scope)")
                XCTAssertEqual(persistence.loadBodyWeights(), expected.bodyWeights, "\(scope)")
                XCTAssertEqual(persistence.loadWeighInPreferences(), expected.weighIn, "\(scope)")

                XCTAssertEqual(StrengthDataModel(persistence: persistence).data, expected, "\(scope): a relaunch reads the same")
                XCTAssertTrue(persistence.loadIssues.isEmpty)
            }
        }
    }

    func testOnlyTheFilesOfTheScopeAreTouched() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try seedFiles(persistence)
        let history = try Data(contentsOf: directory.appendingPathComponent("history.json"))
        let templates = try Data(contentsOf: directory.appendingPathComponent("templates.json"))
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            try model.resetData(.bodyWeights).get()
        }
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("history.json")), history)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("templates.json")), templates)
        XCTAssertEqual(persistence.loadBodyWeights(), [])
        XCTAssertEqual(persistence.loadWeighInPreferences(), preferencesWithoutHealthSync(), "the Health switch is saved off")
    }

    func testAllRemovesEveryDataFileButKeepsTheSchemaAndTheBackups() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try seedFiles(persistence)
        try Data("{ broken".utf8).write(to: directory.appendingPathComponent("history.json"))
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(model.persistenceIssues.count, 1)
            let backup = try XCTUnwrap(model.persistenceIssues.first?.backupFileName)
            try persistence.saveActiveWorkout(WorkoutFactory.makeWorkout(from: StarterTemplates.all[0], now: F.now))
            try persistence.saveAcknowledgedCommands([UUID()])

            try model.resetData(.all).get()
            XCTAssertEqual(files(in: directory), ["schema.json", backup], "the schema file and the copy of the damaged file stay")
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(backup)), Data("{ broken".utf8))
            XCTAssertFalse(persistence.hasDataFiles)
            XCTAssertNil(persistence.loadActiveWorkout())
            XCTAssertEqual(model.data, StrengthData(), "all of it, also the history that could not be read")

            // Saving afterwards works as usual.
            XCTAssertNoThrow(try model.saveTemplate(StarterTemplates.all[0]).get())
            XCTAssertEqual(persistence.loadTemplates(), [StarterTemplates.all[0]])
        }
    }

    func testAResetThatIsNotAllKeepsTheActiveWorkoutFile() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try seedFiles(persistence)
        let state = WorkoutFactory.makeWorkout(from: StarterTemplates.all[0], now: F.now)
        try persistence.saveActiveWorkout(state)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            try model.resetData(ResetScope.all.subtracting(.preferences)).get()
        }
        XCTAssertEqual(persistence.loadActiveWorkout(), state)
        XCTAssertEqual(persistence.loadWeighInPreferences(), preferencesWithoutHealthSync())
    }

    func testTheModelCachesAreDroppedSoTheExercisesFollow() {
        svcMain {
            let model = StrengthDataModel(persistence: nil, seedDemoData: true, now: F.now)
            XCTAssertEqual(model.exercise(id: "deadlift")?.previousSets.count, 1)
            let custom = F.customExercise("Hex press")
            model.addCustomExercise(custom)
            XCTAssertNotNil(model.exercise(id: custom.id))
            model.resetData([.customExercises, .history])
            XCTAssertNil(model.exercise(id: custom.id))
            XCTAssertEqual(model.exercise(id: "deadlift")?.previousSets, [])
            XCTAssertEqual(model.exercises.count, 36)
        }
    }

    func testResettingWithoutPersistenceWorks() throws {
        try svcMain {
            let model = StrengthDataModel(persistence: nil, seedDemoData: true, now: F.now)
            XCTAssertNoThrow(try model.resetData(.all).get())
            XCTAssertEqual(model.data, StrengthData())
        }
    }

    func testAFailedWriteIsReportedAndTheDataStaysErasedInMemory() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try seedFiles(persistence)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let blocked = directory.appendingPathComponent("body-weights.json")
            try FileManager.default.removeItem(at: blocked)
            try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: blocked.appendingPathComponent("keep"))

            guard case .failure = model.resetData(.bodyWeights) else { return XCTFail("body-weights.json is blocked") }
            XCTAssertEqual(model.data.bodyWeights, [])
            XCTAssertNotNil(model.lastPersistenceError)
        }
    }

    func testAResetIsRefusedForAnUnreadableFileWhoseOriginalCannotBeCopied() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try seedFiles(persistence)
        let history = directory.appendingPathComponent("history.json")
        try FileManager.default.removeItem(at: history)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: history.appendingPathComponent("keep"))
        let before = files(in: directory)
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            guard case let .failure(error) = model.resetData(.all) else { return XCTFail("the original cannot be preserved") }
            XCTAssertEqual(error as? PersistenceError, .originalNotPreserved(fileName: "history.json"))
        }
        XCTAssertEqual(files(in: directory), before, "nothing was removed")
    }

    func testANewerDataFormatIsNeverErased() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try seedFiles(persistence)
        try Data("{\"version\": 9}".utf8).write(to: directory.appendingPathComponent("schema.json"))
        persistence.rescanSchema()
        let before = files(in: directory)
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            guard case let .failure(error) = model.resetData(.all) else { return XCTFail("a newer data format is read only") }
            XCTAssertEqual(error as? PersistenceError, .newerSchema(found: 9, supported: 1))
        }
        XCTAssertEqual(files(in: directory), before)
        XCTAssertEqual(persistence.loadTemplates().count, 2)
    }

    func testAfterAFailedResetOfEverythingTheNextSaveWritesTheErasedFilesEmpty() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try seedFiles(persistence)
        let history = directory.appendingPathComponent("history.json")
        try FileManager.default.removeItem(at: history)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: history.appendingPathComponent("keep"))
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            guard case .failure = model.resetData(.all) else { return XCTFail("the original of history.json cannot be preserved") }
            XCTAssertEqual(persistence.loadBodyWeights().count, 2, "the refused reset removed nothing")

            _ = model.saveTemplate(StarterTemplates.all[0])
            XCTAssertEqual(persistence.loadTemplates(), [StarterTemplates.all[0]])
            XCTAssertEqual(persistence.loadBodyWeights(), [], "the weigh-ins that were reset do not come back on the next launch")
            XCTAssertEqual(persistence.loadCustomExercises(), [])
            XCTAssertEqual(persistence.loadPersonalBests(), [:])
            XCTAssertEqual(persistence.loadWeighInPreferences(), WeighInPreferences())
        }
    }

    func testASuccessfulResetOfEverythingClearsTheEarlierPersistenceError() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try seedFiles(persistence)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let blocked = directory.appendingPathComponent("body-weights.json")
            try FileManager.default.removeItem(at: blocked)
            try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: blocked.appendingPathComponent("keep"))
            guard case .failure = model.resetData(.bodyWeights) else { return XCTFail("body-weights.json is blocked") }
            XCTAssertNotNil(model.lastPersistenceError)

            try model.resetData(.all).get()
            XCTAssertNil(model.lastPersistenceError)
        }
    }

    #if canImport(Combine) || PULSE_COMBINE_SHIM
    func testTheStorePublishesTheReset() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try seedFiles(persistence)
        try svcMain {
            let store = StrengthStore(persistence: persistence)
            XCTAssertEqual(store.history.count, 2)
            try store.resetData(.history).get()
            XCTAssertEqual(store.history, [])
            XCTAssertEqual(store.personalBests, [:])
            XCTAssertEqual(store.templates.count, 2)
            try store.resetData(.all).get()
            XCTAssertEqual(store.templates, [])
            XCTAssertEqual(store.customExercises, [])
            XCTAssertEqual(store.bodyWeights, [])
            XCTAssertEqual(store.weighIn, WeighInPreferences())
            XCTAssertEqual(store.exercises, ExerciseLibrary.builtIn)
        }
    }
    #endif
}

// MARK: - FileStrengthPersistence.deleteAll

final class DeleteAllTests: XCTestCase {
    func testItRemovesEveryDataFileAndKeepsTheSchemaFile() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.saveTemplates(StarterTemplates.all)
        try persistence.saveHistory([])
        try persistence.saveCustomExercises([])
        try persistence.savePersonalBests([:])
        try persistence.saveBodyWeights([])
        try persistence.saveWeighInPreferences(WeighInPreferences())
        try persistence.saveActiveWorkout(WorkoutFactory.makeWorkout(from: StarterTemplates.all[0], now: SvcSyncFix.epoch))
        try persistence.saveAcknowledgedCommands([UUID()])
        XCTAssertEqual(files(in: directory), Set(FileStrengthPersistence.dataFileNames + ["schema.json"]))

        XCTAssertNoThrow(try persistence.deleteAll())
        XCTAssertEqual(files(in: directory), ["schema.json"])
        XCTAssertFalse(persistence.hasDataFiles)
        XCTAssertEqual(persistence.loadTemplates(), [])
        XCTAssertEqual(persistence.schemaVersion, 1)
    }

    func testEveryFileIsAttemptedAfterOneFailsAndTheFirstErrorIsThrown() throws {
        struct Blocked: Error, Equatable { var name: String }
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.saveTemplates(StarterTemplates.all)
        try persistence.saveHistory([])
        try persistence.saveCustomExercises([])
        try persistence.savePersonalBests([:])
        try persistence.saveBodyWeights([])
        try persistence.saveWeighInPreferences(WeighInPreferences())
        try persistence.saveActiveWorkout(WorkoutFactory.makeWorkout(from: StarterTemplates.all[0], now: SvcSyncFix.epoch))
        try persistence.saveAcknowledgedCommands([UUID()])

        var attempted: [String] = []
        XCTAssertThrowsError(try persistence.deleteAll(removing: { url in
            attempted.append(url.lastPathComponent)
            if ["history.json", "body-weights.json"].contains(url.lastPathComponent) { throw Blocked(name: url.lastPathComponent) }
            try FileManager.default.removeItem(at: url)
        })) { error in
            XCTAssertEqual(error as? Blocked, Blocked(name: "history.json"), "the first failure in file order")
        }
        XCTAssertEqual(attempted, FileStrengthPersistence.dataFileNames, "the files after the failing one were attempted too")
        XCTAssertEqual(files(in: directory), ["schema.json", "history.json", "body-weights.json"])
    }

    func testItIsHarmlessOnAnEmptyDirectoryAndRepeatable() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        XCTAssertNoThrow(try persistence.deleteAll())
        try persistence.saveTemplates(StarterTemplates.all)
        XCTAssertNoThrow(try persistence.deleteAll())
        XCTAssertNoThrow(try persistence.deleteAll())
        XCTAssertEqual(files(in: directory), ["schema.json"])
    }

    func testTheCopiesOfDamagedFilesAndMigrationFoldersAreNotTouched() throws {
        let directory = makeDirectory(self)
        try Data("{ broken".utf8).write(to: directory.appendingPathComponent("templates.json"))
        let persistence = FileStrengthPersistence(directory: directory)
        XCTAssertEqual(persistence.loadTemplates(), [])
        let backup = try XCTUnwrap(persistence.loadIssues.first?.backupFileName)
        let folder = directory.appendingPathComponent("schema-v1-backup", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: folder.appendingPathComponent("history.json"))

        try persistence.deleteAll()
        XCTAssertTrue(files(in: directory).isSuperset(of: [backup, "schema-v1-backup"]))
        XCTAssertFalse(files(in: directory).contains("templates.json"))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(backup)), Data("{ broken".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("history.json").path))
    }

    func testItIsRefusedLikeAWriteWhenTheDataFormatIsNewer() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.saveTemplates(StarterTemplates.all)
        try Data("{\"version\": 4}".utf8).write(to: directory.appendingPathComponent("schema.json"))
        persistence.rescanSchema()
        XCTAssertThrowsError(try persistence.deleteAll()) {
            XCTAssertEqual($0 as? PersistenceError, .newerSchema(found: 4, supported: 1))
        }
        XCTAssertTrue(files(in: directory).contains("templates.json"))
    }

    func testAnUnreadableFileThatCannotBeCopiedStopsEverything() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.saveTemplates(StarterTemplates.all)
        let history = directory.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: history.appendingPathComponent("keep"))
        XCTAssertEqual(persistence.loadHistory(), [])
        XCTAssertThrowsError(try persistence.deleteAll()) {
            XCTAssertEqual($0 as? PersistenceError, .originalNotPreserved(fileName: "history.json"))
        }
        XCTAssertTrue(files(in: directory).contains("templates.json"), "nothing is removed when one file cannot be preserved")
        XCTAssertTrue(FileManager.default.fileExists(atPath: history.appendingPathComponent("keep").path))
    }
}
