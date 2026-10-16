import Foundation
import XCTest
@testable import PulseStrengthCore

private func makeDirectory(_ test: XCTestCase) -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PulseStrength-nofake-" + UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    test.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory
}

// MARK: - The library carries no invented history

final class LibraryWithoutInventedHistoryTests: XCTestCase {
    func testNoBuiltInExerciseHasAPreviousBestOrPreviousSets() {
        XCTAssertEqual(ExerciseLibrary.builtIn.count, 36)
        for exercise in ExerciseLibrary.builtIn {
            XCTAssertEqual(exercise.previousBestE1RM, 0, exercise.id)
            XCTAssertEqual(exercise.previousSets, [], exercise.id)
        }
        XCTAssertEqual(ExerciseLibrary.exercise(id: "bench")?.previousBestE1RM, 0)
    }

    func testTheDemoLibraryReproducesTheOldNumbersExactly() throws {
        XCTAssertEqual(ExerciseLibrary.demoBuiltIn.count, 36)
        let bests: [String: Double] = ["bench": 99, "incline": 38, "ohp": 58, "pushdown": 42, "crossover": 21]
        for exercise in ExerciseLibrary.demoBuiltIn {
            XCTAssertEqual(exercise.previousBestE1RM, bests[exercise.id] ?? 0, exercise.id)
        }
        func sets(_ id: String) throws -> [PreviousSet] {
            try XCTUnwrap(ExerciseLibrary.demoBuiltIn.first { $0.id == id }).previousSets
        }
        XCTAssertEqual(try sets("bench"), [
            PreviousSet(weightKg: 50, reps: 8, type: .warmup), PreviousSet(weightKg: 70, reps: 5, type: .warmup),
            PreviousSet(weightKg: 80, reps: 6), PreviousSet(weightKg: 80, reps: 6), PreviousSet(weightKg: 80, reps: 5),
        ])
        XCTAssertEqual(try sets("incline"), [(26.0, 10), (26, 10), (26, 9)].map { PreviousSet(weightKg: $0.0, reps: $0.1) })
        XCTAssertEqual(try sets("plank"), [PreviousSet(weightKg: 0, reps: 45)])
        XCTAssertEqual(try sets("deadlift"), [PreviousSet(weightKg: 100, reps: 5)])
        XCTAssertEqual(try sets("cpress"), [])
        XCTAssertEqual(ExerciseLibrary.demoBuiltIn.filter { !$0.previousSets.isEmpty }.count, 25)
    }

    func testTheDemoLibraryDiffersFromTheLibraryOnlyInThePreviousResults() {
        for (demo, plain) in zip(ExerciseLibrary.demoBuiltIn, ExerciseLibrary.builtIn) {
            var stripped = demo
            stripped.previousBestE1RM = 0
            stripped.previousSets = []
            XCTAssertEqual(stripped, plain, plain.id)
        }
    }

    func testTheDemoTableOnlyNamesBuiltInExercises() {
        for id in DemoPreviousResults.byExerciseID.keys {
            XCTAssertNotNil(ExerciseLibrary.exercise(id: id), id)
        }
    }

    func testApplyingTheDemoResultsLeavesOtherExercisesAlone() {
        let custom = Exercise.custom(name: "Hex press", muscle: .chest, equipment: .dumbbell, tracking: .weightReps, id: "custom-hex")
        XCTAssertEqual(DemoPreviousResults.applying(to: custom), custom)
        XCTAssertEqual(DemoPreviousResults.applying(to: [custom, ExerciseLibrary.builtIn[0]]).map { $0.previousBestE1RM }, [0, 99])
        let machinePress = ExerciseLibrary.builtIn.first { $0.id == "cpress" }!
        XCTAssertEqual(DemoPreviousResults.applying(to: machinePress), machinePress, "no demo entry, nothing changes")
    }

    func testSampleTemplatesAndHistoryAreStillTheDemoNumbers() throws {
        let upperA = try XCTUnwrap(SampleData.templates().first)
        XCTAssertEqual(upperA.entries[0].exercise.previousBestE1RM, 99)
        XCTAssertEqual(upperA.entries[0].exercise.previousSets.count, 5)
        let bench = try XCTUnwrap(SampleData.history(now: SvcSyncFix.epoch).first { $0.name == "Upper A · Push" }?.exercises.first)
        XCTAssertEqual(bench.exerciseID, "bench")
    }

    /// The ids that older builds wrote into users' files. `removeSampleData()` finds the sample data by them, so they must never change.
    func testTheSampleIDsAreTheOnesOlderBuildsWrote() {
        XCTAssertEqual(SampleData.templateIDs.map { $0.uuidString }, [
            "5EED0001-0000-4000-8000-000000000001",
            "5EED0001-0000-4000-8000-000000000002",
            "5EED0001-0000-4000-8000-000000000003",
        ])
        XCTAssertEqual(SampleData.workoutIDs.map { $0.uuidString }, [
            "5EED0003-0000-4000-8000-000000000001",
            "5EED0003-0000-4000-8000-000000000002",
            "5EED0003-0000-4000-8000-000000000003",
            "5EED0003-0000-4000-8000-000000000004",
            "5EED0003-0000-4000-8000-000000000005",
        ])
    }

    func testTheSampleIDsAreCollectedInOnePlace() {
        XCTAssertEqual(SampleData.templateIDs, SampleData.templates().map { $0.id })
        XCTAssertEqual(SampleData.workoutIDs, SampleData.history(now: SvcSyncFix.epoch).map { $0.id })
        XCTAssertEqual(SampleData.templateIDs.count, 3)
        XCTAssertEqual(SampleData.workoutIDs.count, 5)
        XCTAssertEqual(Set(SampleData.templateIDs + SampleData.workoutIDs).count, 8)
    }
}

// MARK: - The overlay with and without the demo flag

final class DemoOverlayTests: XCTestCase {
    private typealias F = SvcDataFix

    func testAnEmptyStoreHasNoPreviousResultsAtAll() {
        let data = StrengthData()
        XCTAssertFalse(data.usesDemoPreviousResults)
        XCTAssertEqual(data.exercises(), ExerciseLibrary.builtIn)
        for exercise in data.exercises() {
            XCTAssertEqual(exercise.previousBestE1RM, 0, exercise.id)
            XCTAssertTrue(exercise.previousSets.isEmpty, exercise.id)
        }
        XCTAssertEqual(data.exercise(id: "bench")?.previousBestE1RM, 0)
    }

    func testTheDemoFlagShowsTheDemoNumbersForExercisesWithoutHistory() {
        let data = StrengthData(usesDemoPreviousResults: true)
        XCTAssertEqual(data.exercises(), ExerciseLibrary.demoBuiltIn)
        XCTAssertEqual(data.exercise(id: "bench")?.previousBestE1RM, 99)
        XCTAssertEqual(data.exercise(id: "plank")?.previousSets, [PreviousSet(weightKg: 0, reps: 45)])
        XCTAssertEqual(data.overlay(ExerciseLibrary.builtIn[0]).previousBestE1RM, 99)
    }

    func testRealHistoryAlwaysWinsOverTheDemoNumbers() throws {
        for demo in [false, true] {
            var data = StrengthData(usesDemoPreviousResults: demo)
            data.history = [F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(100, 3)], n: 1)])]
            let bench = try XCTUnwrap(data.exercise(id: "bench"))
            XCTAssertEqual(bench.previousBestE1RM, 110, accuracy: 1e-9)
            XCTAssertEqual(bench.previousSets, [PreviousSet(weightKg: 100, reps: 3)])
            let incline = try XCTUnwrap(data.exercise(id: "incline"))
            XCTAssertEqual(incline.previousBestE1RM, demo ? 38 : 0)
            XCTAssertEqual(incline.previousSets.isEmpty, !demo)
        }
    }

    func testCustomExercisesNeverGetDemoNumbers() throws {
        var data = StrengthData(usesDemoPreviousResults: true)
        let custom = F.customExercise("Hex press")
        data.addCustomExercise(custom)
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: custom.id)).previousBestE1RM, 0)
        XCTAssertEqual(data.exercises().count, 37)
    }

    func testSeedingSwitchesTheFlagOnAndOnlyWhenItSeeds() {
        var empty = StrengthData()
        XCTAssertTrue(empty.seedDemoDataIfEmpty(now: SvcSyncFix.epoch))
        XCTAssertTrue(empty.usesDemoPreviousResults)
        XCTAssertTrue(StrengthData.demo(now: SvcSyncFix.epoch).usesDemoPreviousResults)

        var used = StrengthData(templates: [StarterTemplates.all[0]])
        XCTAssertFalse(used.seedDemoDataIfEmpty(now: SvcSyncFix.epoch))
        XCTAssertFalse(used.usesDemoPreviousResults)
    }

    func testTheFlagIsNeverStored() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        svcMain {
            let model = StrengthDataModel(persistence: persistence, seedDemoData: true, now: SvcSyncFix.epoch)
            XCTAssertTrue(model.data.usesDemoPreviousResults)
        }
        for name in FileStrengthPersistence.dataFileNames {
            let url = persistence.directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { continue }
            XCTAssertFalse(String(decoding: data, as: UTF8.self).lowercased().contains("demo"), name)
        }
    }

    func testAStoreSeededInThisProcessKeepsTheFlagAcrossReloads() {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        svcMain {
            let model = StrengthDataModel(persistence: persistence, seedDemoData: true, now: SvcSyncFix.epoch)
            model.reload()
            XCTAssertTrue(model.data.usesDemoPreviousResults)
            XCTAssertEqual(model.exercise(id: "deadlift")?.previousSets, [PreviousSet(weightKg: 100, reps: 5)])
        }
    }

    func testAnotherProcessOnTheSeededFilesShowsOnlyWhatTheHistoryTells() {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        svcMain {
            _ = StrengthDataModel(persistence: persistence, seedDemoData: true, now: SvcSyncFix.epoch)
            // A later launch of a build that seeded: the sample files are there, nothing is seeded again, the flag is off.
            let later = StrengthDataModel(persistence: persistence, seedDemoData: false, now: SvcSyncFix.epoch)
            XCTAssertFalse(later.data.usesDemoPreviousResults)
            XCTAssertEqual(later.exercise(id: "deadlift")?.previousSets, [], "the invented deadlift numbers are gone")
            XCTAssertEqual(later.exercise(id: "bench")?.previousBestE1RM ?? 0, 99.1667, accuracy: 0.001, "the stored sample history still counts")
        }
    }

    func testSeedingNeverHappensOverExistingFilesSoTheFlagStaysOff() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try persistence.saveTemplates([StarterTemplates.all[1]])
        svcMain {
            let model = StrengthDataModel(persistence: persistence, seedDemoData: true, now: SvcSyncFix.epoch)
            XCTAssertFalse(model.data.usesDemoPreviousResults)
            XCTAssertEqual(model.data.templates.map { $0.name }, ["Pull"])
        }
    }

    func testAStoreWithoutTheSeedFlagIsEmptyAndPlain() {
        svcMain {
            let model = StrengthDataModel(persistence: FileStrengthPersistence(directory: makeDirectory(self)))
            XCTAssertTrue(model.data.isEmpty)
            XCTAssertFalse(model.data.usesDemoPreviousResults)
            XCTAssertEqual(model.exercises, ExerciseLibrary.builtIn)
            XCTAssertFalse(model.hasSampleData)
        }
    }

    func testTheSeededMemoryStoreStaysEquivalentToTheOldBehaviour() {
        svcMain {
            let model = StrengthDataModel(persistence: nil, seedDemoData: true, now: SvcSyncFix.epoch)
            XCTAssertEqual(model.data.templates.count, 3)
            XCTAssertEqual(model.data.history.count, 5)
            XCTAssertEqual(model.exercise(id: "bench")?.previousBestE1RM ?? 0, 99.1667, accuracy: 0.001)
            XCTAssertEqual(model.exercise(id: "bench")?.previousSets.count, 5)
            XCTAssertEqual(model.exercise(id: "cpress")?.previousSets, [])
            XCTAssertEqual(model.exercise(id: "pushup")?.previousSets, [PreviousSet(weightKg: 0, reps: 15)])
            XCTAssertEqual(model.exercises.count, 36)
        }
    }
}

// MARK: - A real user's first sessions

final class FirstSessionTests: XCTestCase {
    func testAFreshStoreShowsNoPreviousColumnNoCoachTipAndNoRecordInTheFirstSession() throws {
        try svcMain {
            let rig = SvcRig(self, seed: false)
            XCTAssertNoThrow(try rig.model.addStarterTemplates().get())
            let push = rig.model.data.templates[0]
            rig.engine.start(template: push)

            let opening = try XCTUnwrap(rig.engine.presentation(now: rig.clock.now))
            let card = try XCTUnwrap(opening.card)
            XCTAssertEqual(card.exercise.id, "bench")
            XCTAssertEqual(card.exercise.previousBestE1RM, 0)
            XCTAssertEqual(card.rows.map { $0.previousText }, ["–", "–", "–"])
            XCTAssertNil(card.coachTip)

            let total = try XCTUnwrap(rig.engine.state).exercises.reduce(0) { $0 + $1.sets.count }
            XCTAssertEqual(total, 18)
            rig.logSets(total)
            let completed = try XCTUnwrap(rig.engine.finish(updateTemplate: false))
            XCTAssertEqual(completed.personalRecords, [], "nothing to beat in the very first session")
            XCTAssertFalse(completed.exercises.contains { $0.isPersonalRecord })
            XCTAssertEqual(completed.loggedSets, 18)
        }
    }

    func testTheSecondSessionHasTheFirstOneAsItsBaseline() throws {
        try svcMain {
            let rig = SvcRig(self, seed: false)
            rig.model.addStarterTemplates()
            let push = rig.model.data.templates[0]
            rig.engine.start(template: push)
            rig.logSets(18)
            XCTAssertNotNil(rig.engine.finish(updateTemplate: false))

            // Bench 60 kg x 8: estimated 1RM 76.
            let best = try XCTUnwrap(rig.model.data.personalBests["bench"])
            XCTAssertEqual(best.estimated1RM, 76, accuracy: 1e-9)

            rig.clock.advance(3 * 86_400)
            rig.engine.start(template: try XCTUnwrap(rig.model.template(id: push.id)))
            let state = try XCTUnwrap(rig.engine.state)
            let bench = state.exercises[0]
            XCTAssertEqual(bench.exercise.previousBestE1RM, 76, accuracy: 1e-9)
            XCTAssertEqual(bench.exercise.previousSets, Array(repeating: PreviousSet(weightKg: 60, reps: 8), count: 3))

            let card = try XCTUnwrap(rig.engine.presentation(now: rig.clock.now)?.card)
            XCTAssertEqual(card.rows.map { $0.previousText }, ["60 × 8", "60 × 8", "60 × 8"])
            XCTAssertEqual(card.coachTip, "62.5 kg × 8 on your last set would beat your best estimated 1RM of 76 kg.")
            XCTAssertEqual(card.rows.filter { $0.isPersonalRecord }.count, 0)

            // Repeating the weights is not a record; one more step on the last set is.
            rig.engine.send(.logSet(exerciseID: bench.id, setID: bench.sets[0].id))
            rig.engine.send(.logSet(exerciseID: bench.id, setID: bench.sets[1].id))
            rig.engine.send(.setWeight(exerciseID: bench.id, setID: bench.sets[2].id, kg: 62.5))
            rig.engine.send(.logSet(exerciseID: bench.id, setID: bench.sets[2].id))
            let after = try XCTUnwrap(rig.engine.presentation(now: rig.clock.now)?.card)
            XCTAssertEqual(after.rows.map { $0.isPersonalRecord }, [false, false, true])

            let completed = try XCTUnwrap(rig.engine.finish(updateTemplate: false))
            let record = try XCTUnwrap(completed.personalRecords.first)
            XCTAssertEqual(record.exerciseID, "bench")
            XCTAssertEqual(record.previousBest, 76, accuracy: 1e-9)
            XCTAssertEqual(record.estimated1RM, 62.5 * (1 + 8.0 / 30), accuracy: 1e-9)
            XCTAssertEqual(rig.model.data.personalBests["bench"]?.weightKg, 62.5)
        }
    }

    func testTheFirstSessionOfAnExerciseNeverComparesAgainstTheOldDemoBest() throws {
        try svcMain {
            let rig = SvcRig(self, seed: false)
            rig.engine.start(template: nil, name: "Bench only")
            let bench = try XCTUnwrap(rig.model.exercise(id: "bench"))
            rig.engine.send(.addExercises([bench]))
            let entry = try XCTUnwrap(rig.engine.state).exercises[0]
            // 80 kg x 5 is an estimated 93, below the old invented 99; with no real history it is simply the first result.
            rig.engine.send(.setWeight(exerciseID: entry.id, setID: entry.sets[0].id, kg: 80))
            rig.engine.send(.setReps(exerciseID: entry.id, setID: entry.sets[0].id, reps: 5))
            rig.engine.send(.logSet(exerciseID: entry.id, setID: entry.sets[0].id))
            let completed = try XCTUnwrap(rig.engine.finish(updateTemplate: false))
            XCTAssertEqual(completed.personalRecords, [])
            XCTAssertEqual(rig.model.data.personalBests["bench"]?.estimated1RM ?? 0, 80 * (1 + 5.0 / 30), accuracy: 1e-9)
        }
    }

    func testFinishingAWorkoutMakesTheRecoveryEstimateAvailable() {
        svcMain {
            let rig = SvcRig(self, seed: false)
            rig.model.addStarterTemplates()
            XCTAssertNil(rig.model.readinessPercent(now: rig.clock.now))
            rig.engine.start(template: rig.model.data.templates[0])
            rig.logSets(18)
            XCTAssertNotNil(rig.engine.finish(updateTemplate: false))
            let estimates = rig.model.recoveryEstimates(now: rig.clock.now)
            XCTAssertEqual(estimates[.chest], RecoveryEstimate(percent: 0, hasData: true))
            XCTAssertEqual(estimates[.legs], RecoveryEstimate(percent: 100, hasData: true))
            XCTAssertNotNil(rig.model.readinessPercent(now: rig.clock.now))
        }
    }
}

// MARK: - Removing the sample data of older installs

final class SampleDataRemovalTests: XCTestCase {
    private typealias F = SvcDataFix
    private let now = SvcSyncFix.epoch

    /// A user's workout that finished `days` ago.
    private func userWorkout(_ n: Int, days: Double, templateID: UUID? = nil, bench: CompletedSet) -> CompletedWorkout {
        F.workout(n, name: "My workout \(n)", templateID: templateID, finishedAt: F.daysAgo(days), [F.entry("bench", [bench], n: n)])
    }

    private func seededData() -> StrengthData {
        StrengthData.demo(now: now)
    }

    func testHasSampleDataLooksAtTheFixedIDs() {
        XCTAssertFalse(StrengthData().hasSampleData)
        XCTAssertTrue(seededData().hasSampleData)
        XCTAssertTrue(StrengthData(templates: [SampleData.templates()[1]]).hasSampleData)
        XCTAssertTrue(StrengthData(history: [SampleData.history(now: now)[0]]).hasSampleData)
        XCTAssertFalse(StrengthData(templates: StarterTemplates.all).hasSampleData)
        var lookalike = SampleData.templates()[0]
        lookalike.id = UUID()
        XCTAssertFalse(StrengthData(templates: [lookalike]).hasSampleData, "a copy with another id is the user's own")
    }

    func testRemovalDeletesExactlyTheSampleItemsAndKeepsTheUsersOwn() throws {
        var data = seededData()
        let mine = WorkoutTemplate(name: "My push", entries: StarterTemplates.all[0].entries)
        data.saveTemplate(mine)
        let startedFromSample = userWorkout(1, days: 1, templateID: SampleData.templateIDs[0], bench: F.work(40, 5))
        data.record(startedFromSample, updateTemplate: nil)
        let custom = F.customExercise("Hex press")
        data.addCustomExercise(custom)
        data.recordBodyWeight(kg: 80, date: F.daysAgo(1))

        let removal = data.removeSampleData()
        XCTAssertEqual(removal, SampleDataRemoval(templates: 3, workouts: 5))
        XCTAssertFalse(removal.isEmpty)
        XCTAssertEqual(data.templates.map { $0.id }, [mine.id])
        XCTAssertEqual(data.history.map { $0.id }, [startedFromSample.id], "the workout of a sample template stays, with its template id")
        XCTAssertEqual(data.history[0].templateID, SampleData.templateIDs[0])
        XCTAssertEqual(data.customExercises, [custom])
        XCTAssertEqual(data.bodyWeights.count, 1)
        XCTAssertFalse(data.hasSampleData)
        XCTAssertFalse(data.usesDemoPreviousResults)
    }

    func testThePersonalBestsAreRecomputedFromWhatIsLeft() throws {
        var data = seededData()
        data.record(userWorkout(1, days: 1, bench: F.work(40, 5)), updateTemplate: nil)
        XCTAssertEqual(try XCTUnwrap(data.personalBests["bench"]).estimated1RM, 99.1667, accuracy: 0.001, "the sample record stands before")

        _ = data.removeSampleData()
        XCTAssertEqual(Set(data.personalBests.keys), ["bench"], "the sample records of the other exercises go too")
        XCTAssertEqual(try XCTUnwrap(data.personalBests["bench"]).estimated1RM, 40 * (1 + 5.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(data.personalBests, data.recomputedPersonalBests())
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "bench")).previousBestE1RM, 40 * (1 + 5.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "incline")).previousBestE1RM, 0)
    }

    func testAUsersBetterLiftSurvivesTheRemoval() throws {
        var data = seededData()
        data.record(userWorkout(1, days: 1, bench: F.work(100, 3)), updateTemplate: nil)
        _ = data.removeSampleData()
        XCTAssertEqual(try XCTUnwrap(data.personalBests["bench"]).estimated1RM, 110, accuracy: 1e-9)
    }

    func testWithoutAnyUserDataTheStoreIsEmptyAfterwards() {
        var data = seededData()
        _ = data.removeSampleData()
        XCTAssertTrue(data.isEmpty)
        XCTAssertEqual(data.personalBests, [:])
        XCTAssertEqual(data.exercises(), ExerciseLibrary.builtIn)
    }

    func testRemovalIsIdempotentAndReportsNothingTheSecondTime() {
        var data = seededData()
        XCTAssertFalse(data.removeSampleData().isEmpty)
        XCTAssertEqual(data.removeSampleData(), SampleDataRemoval(templates: 0, workouts: 0))
        XCTAssertTrue(data.removeSampleData().isEmpty)
    }

    func testOnlyTheItemsThatAreStillThereAreCounted() {
        var data = seededData()
        _ = data.deleteTemplate(id: SampleData.templateIDs[2])
        _ = data.deleteWorkout(id: SampleData.workoutIDs[0])
        XCTAssertEqual(data.removeSampleData(), SampleDataRemoval(templates: 2, workouts: 4))
    }

    func testAnEditedSampleTemplateIsRemovedLikeTheOthers() throws {
        var data = seededData()
        try data.renameTemplate(id: SampleData.templateIDs[0], to: "Renamed").get()
        XCTAssertEqual(data.removeSampleData().templates, 3)
    }

    func testWhileTheHistoryIsIncompleteTheBestsAreOnlyRaised() {
        var data = seededData()
        data.personalBests["deadlift"] = PersonalBest(exerciseID: "deadlift", estimated1RM: 160, weightKg: 140, reps: 4, date: F.daysAgo(40))
        data.historyIsIncomplete = true
        _ = data.removeSampleData()
        XCTAssertEqual(data.personalBests["deadlift"]?.estimated1RM, 160, "a best that the readable history does not explain is kept")
    }

    // MARK: Sample personal bests

    /// An older install whose `history.json` could not be read: the bests the demo seeding wrote are still stored.
    private func damagedSeededData(bests: [String: PersonalBest]? = nil) -> StrengthData {
        StrengthData(
            templates: SampleData.templates(now: now),
            personalBests: bests ?? SampleData.personalBests(now: now),
            historyIsIncomplete: true,
            usesDemoPreviousResults: false
        )
    }

    func testTheSampleBestsOfAnInstallWithADamagedHistoryGoWithTheSampleData() throws {
        var data = damagedSeededData()
        let sampleCount = SampleData.personalBests(now: now).count
        XCTAssertGreaterThan(sampleCount, 2)
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "bench")).previousBestE1RM, 99.1667, accuracy: 0.001, "the invented best shows before")

        let removal = data.removeSampleData()
        XCTAssertEqual(removal, SampleDataRemoval(templates: 3, workouts: 0, personalBests: sampleCount))
        XCTAssertEqual(data.personalBests, [:])
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "bench")).previousBestE1RM, 0)
        XCTAssertFalse(data.hasSampleData, "the offer ends only when nothing invented is left")
        XCTAssertTrue(data.historyIsIncomplete, "the history is still damaged")
    }

    func testSampleBestsWithoutTheSampleTemplatesStillCountAsSampleData() {
        var data = damagedSeededData()
        data.templates = []
        XCTAssertTrue(data.hasSampleData)
        let removal = data.removeSampleData()
        XCTAssertEqual(removal.templates, 0)
        XCTAssertEqual(removal.personalBests, SampleData.personalBests(now: now).count)
        XCTAssertFalse(removal.isEmpty)
        XCTAssertFalse(data.hasSampleData)
        XCTAssertTrue(data.removeSampleData().isEmpty)
    }

    func testARealBestOfTheSameLiftAmongTheSampleBestsStays() throws {
        var bests = SampleData.personalBests(now: now)
        let sampleBench = try XCTUnwrap(bests["bench"])
        bests["bench"] = PersonalBest(
            exerciseID: "bench", estimated1RM: sampleBench.estimated1RM, weightKg: sampleBench.weightKg, reps: sampleBench.reps,
            date: F.daysAgo(100)
        )
        var data = damagedSeededData(bests: bests)
        let removal = data.removeSampleData()
        XCTAssertEqual(removal.personalBests, bests.count - 1)
        XCTAssertEqual(Set(data.personalBests.keys), ["bench"], "same numbers, but not from the seeding day")
        XCTAssertEqual(data.personalBests["bench"]?.date, F.daysAgo(100))
    }

    func testALoneBestThatEqualsASampleBestIsNeverTakenForOne() throws {
        let sampleBench = try XCTUnwrap(SampleData.personalBests(now: now)["bench"])
        var data = StrengthData(personalBests: ["bench": sampleBench], historyIsIncomplete: true)
        XCTAssertFalse(data.hasSampleData)
        XCTAssertTrue(data.removeSampleData().isEmpty)
        XCTAssertEqual(data.personalBests, ["bench": sampleBench])
    }

    func testABestThatARealSetBeatSinceSeedingIsTheUsersAndStays() throws {
        var bests = SampleData.personalBests(now: now)
        bests["bench"] = PersonalBest(exerciseID: "bench", estimated1RM: 120, weightKg: 100, reps: 6, date: F.daysAgo(2))
        var data = damagedSeededData(bests: bests)
        _ = data.removeSampleData()
        XCTAssertEqual(data.personalBests, ["bench": bests["bench"]!])
    }

    func testTheSampleBestsAreFoundWhenTheFilesDroppedTheFractionOfASecond() {
        let seededAt = now.addingTimeInterval(0.7)
        let stored = SampleData.personalBests(now: seededAt).mapValues { best -> PersonalBest in
            var copy = best
            copy.date = Date(timeIntervalSince1970: best.date.timeIntervalSince1970.rounded(.down))
            return copy
        }
        var data = damagedSeededData(bests: stored)
        XCTAssertTrue(data.hasSampleData)
        XCTAssertEqual(data.removeSampleData().personalBests, stored.count)
        XCTAssertEqual(data.personalBests, [:])
    }

    func testTheBestsThatTheReadableHistoryExplainsComeBackAfterTheRemoval() throws {
        var data = damagedSeededData()
        data.history = [userWorkout(1, days: 1, bench: F.work(40, 5))]
        _ = data.removeSampleData()
        XCTAssertEqual(Set(data.personalBests.keys), ["bench"])
        XCTAssertEqual(try XCTUnwrap(data.personalBests["bench"]).estimated1RM, 40 * (1 + 5.0 / 30), accuracy: 1e-9)
    }

    func testTheModelDropsTheSampleBestsFromDiskWhileTheHistoryStaysDamaged() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.saveTemplates(SampleData.templates(now: now))
        try persistence.savePersonalBests(SampleData.personalBests(now: now))
        try Data("not json".utf8).write(to: directory.appendingPathComponent("history.json"))
        try svcMain {
            let model = StrengthDataModel(persistence: FileStrengthPersistence(directory: directory), now: now)
            XCTAssertTrue(model.data.historyIsIncomplete)
            XCTAssertTrue(model.hasSampleData)

            let removal = try model.removeSampleData().get()
            XCTAssertEqual(removal.templates, 3)
            XCTAssertEqual(removal.personalBests, SampleData.personalBests(now: now).count)
            XCTAssertEqual(persistence.loadPersonalBests(), [:])
            XCTAssertEqual(persistence.loadTemplates(), [])
            XCTAssertFalse(StrengthDataModel(persistence: FileStrengthPersistence(directory: directory), now: now).hasSampleData)
        }
    }

    func testTheModelSavesWhatChangedAndReloadsClean() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try svcMain {
            _ = StrengthDataModel(persistence: persistence, seedDemoData: true, now: now)
            let model = StrengthDataModel(persistence: persistence, now: now)
            model.record(userWorkout(1, days: 1, bench: F.work(40, 5)), updateTemplate: nil)
            XCTAssertTrue(model.hasSampleData)

            let removal = try model.removeSampleData().get()
            XCTAssertEqual(removal, SampleDataRemoval(templates: 3, workouts: 5))
            XCTAssertFalse(model.hasSampleData)
            XCTAssertEqual(persistence.loadTemplates(), [])
            XCTAssertEqual(persistence.loadHistory().map { $0.name }, ["My workout 1"])
            XCTAssertEqual(Set(persistence.loadPersonalBests().keys), ["bench"])

            let reloaded = StrengthDataModel(persistence: persistence, now: now)
            XCTAssertFalse(reloaded.hasSampleData)
            XCTAssertEqual(reloaded.data.history.count, 1)

            XCTAssertEqual(try model.removeSampleData().get(), SampleDataRemoval(templates: 0, workouts: 0))
        }
    }

    func testNothingIsWrittenWhenThereIsNothingToRemove() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(try model.removeSampleData().get(), SampleDataRemoval(templates: 0, workouts: 0))
            XCTAssertFalse(persistence.hasDataFiles)
        }
    }

    func testAFailedSaveIsReportedAndTheRemovalStaysInMemory() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence, seedDemoData: true, now: now)
            let history = directory.appendingPathComponent("history.json")
            try FileManager.default.removeItem(at: history)
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: history.appendingPathComponent("keep"))

            guard case .failure = model.removeSampleData() else { return XCTFail("history.json is blocked") }
            XCTAssertFalse(model.hasSampleData)
            XCTAssertNotNil(model.lastPersistenceError)
        }
    }

    #if canImport(Combine) || PULSE_COMBINE_SHIM
    func testTheStorePublishesTheRemoval() throws {
        try svcMain {
            let store = StrengthStore(persistence: nil, seedDemoData: true)
            XCTAssertTrue(store.hasSampleData)
            XCTAssertEqual(store.templates.count, 3)
            XCTAssertEqual(store.exercise(id: "ohp")?.previousBestE1RM ?? 0, 58.3333, accuracy: 0.001)

            let removal = try store.removeSampleData().get()
            XCTAssertEqual(removal, SampleDataRemoval(templates: 3, workouts: 5))
            XCTAssertFalse(store.hasSampleData)
            XCTAssertEqual(store.templates, [])
            XCTAssertEqual(store.history, [])
            XCTAssertEqual(store.personalBests, [:])
            XCTAssertEqual(store.exercise(id: "ohp")?.previousBestE1RM, 0)
            XCTAssertEqual(store.exercises, ExerciseLibrary.builtIn)
        }
    }

    func testAPlainStoreHasNoSampleDataAndNothingToRemove() throws {
        try svcMain {
            let store = StrengthStore(persistence: nil)
            XCTAssertFalse(store.hasSampleData)
            XCTAssertEqual(store.exercises, ExerciseLibrary.builtIn)
            XCTAssertEqual(try store.removeSampleData().get(), SampleDataRemoval(templates: 0, workouts: 0))
        }
    }
    #endif
}
