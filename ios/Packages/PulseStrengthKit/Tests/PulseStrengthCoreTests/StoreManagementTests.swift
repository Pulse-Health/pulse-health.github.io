import Foundation
import XCTest
@testable import PulseStrengthCore

/// Shared builders for the management tests.
private enum M {
    typealias F = SvcDataFix

    static func template(_ n: Int, _ name: String, exercises: [String] = ["bench"], superset: Bool = false, lastPerformed: Date? = nil) -> WorkoutTemplate {
        WorkoutTemplate(
            id: SvcSyncFix.uuid(100 + n),
            name: name,
            entries: exercises.enumerated().map { index, id in
                TemplateEntry(
                    id: SvcSyncFix.uuid(200 + n * 10 + index),
                    exercise: ExerciseLibrary.exercise(id: id)!,
                    plannedSets: [PlannedSet(weightKg: 60, reps: 8), PlannedSet(type: .warmup, weightKg: 30, reps: 10)],
                    restSeconds: 90,
                    supersetGroup: superset && index > 0 ? "A" : nil,
                    note: "note \(index)"
                )
            },
            lastPerformed: lastPerformed
        )
    }

    static func names(_ templates: [WorkoutTemplate]) -> [String] { templates.map { $0.name } }

    /// A custom exercise entry in a template.
    static func entry(of exercise: Exercise, n: Int) -> TemplateEntry {
        TemplateEntry(
            id: SvcSyncFix.uuid(300 + n),
            exercise: exercise,
            plannedSets: [PlannedSet(weightKg: 20, reps: 10)],
            restSeconds: 60,
            note: "keep the elbows in"
        )
    }
}

private func makeDirectory(_ test: XCTestCase) -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PulseStrength-management-" + UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    test.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory
}

/// Replaces `name` in the directory by a directory, so that the next atomic write of that file fails on every platform (also as root).
private func block(_ name: String, in directory: URL) throws {
    let target = directory.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: target)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: target.appendingPathComponent("keep"))
}

private func unblock(_ name: String, in directory: URL) throws {
    try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
}

// MARK: - Templates

final class TemplateManagementTests: XCTestCase {
    private typealias F = SvcDataFix

    func testRenameTrimsPersistsAndKeepsThePosition() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            model.saveTemplate(M.template(1, "Push"))
            model.saveTemplate(M.template(2, "Pull"))
            model.saveTemplate(M.template(3, "Legs"))
            XCTAssertNoThrow(try model.renameTemplate(id: SvcSyncFix.uuid(102), to: "  Pull day \n").get())
            XCTAssertEqual(M.names(model.data.templates), ["Push", "Pull day", "Legs"])
        }
        XCTAssertEqual(M.names(persistence.loadTemplates()), ["Push", "Pull day", "Legs"])
    }

    func testRenameRejectsABlankNameAndAnUnknownIdWithoutWriting() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            model.saveTemplate(M.template(1, "Push"))
            let before = try Data(contentsOf: directory.appendingPathComponent("templates.json"))
            try FileManager.default.removeItem(at: directory.appendingPathComponent("templates.json"))

            guard case let .failure(blank) = model.renameTemplate(id: SvcSyncFix.uuid(101), to: " \t ") else { return XCTFail("blank names are refused") }
            XCTAssertEqual(blank as? StrengthStoreError, .invalidName)
            guard case let .failure(unknown) = model.renameTemplate(id: SvcSyncFix.uuid(999), to: "X") else { return XCTFail("unknown ids are refused") }
            XCTAssertEqual(unknown as? StrengthStoreError, .notFound)
            XCTAssertEqual(M.names(model.data.templates), ["Push"])
            XCTAssertNil(model.lastPersistenceError, "a refused change is not a persistence error")
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("templates.json").path), "nothing was written")
            XCTAssertFalse(before.isEmpty)
        }
    }

    func testDeleteRemovesTheTemplateAndKeepsTheWorkoutsDoneFromIt() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let push = M.template(1, "Push")
            model.saveTemplate(push)
            model.saveTemplate(M.template(2, "Pull"))
            model.record(F.workout(1, name: "Push", templateID: push.id, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(80, 5)], n: 1)]), updateTemplate: nil)
            XCTAssertNoThrow(try model.deleteTemplate(id: push.id).get())
            XCTAssertEqual(M.names(model.data.templates), ["Pull"])
            XCTAssertEqual(model.data.history.count, 1)
            XCTAssertEqual(model.data.history[0].templateID, push.id, "the workout keeps its template id and name")
            guard case let .failure(error) = model.deleteTemplate(id: push.id) else { return XCTFail("deleting twice is refused") }
            XCTAssertEqual(error as? StrengthStoreError, .notFound)
        }
        XCTAssertEqual(M.names(persistence.loadTemplates()), ["Pull"])
        XCTAssertEqual(persistence.loadHistory().count, 1)
    }

    func testDuplicateMakesAnIndependentCopyRightAfterTheOriginal() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        let stamp = F.daysAgo(2)
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let original = M.template(1, "Push", exercises: ["bench", "ohp"], superset: true, lastPerformed: stamp)
            model.saveTemplate(original)
            model.saveTemplate(M.template(2, "Pull"))

            let copy = try? model.duplicateTemplate(id: original.id, name: "  Push (heavy) ").get()
            XCTAssertNotNil(copy)
            guard let copy else { return }
            XCTAssertEqual(M.names(model.data.templates), ["Push", "Push (heavy)", "Pull"])
            XCTAssertNotEqual(copy.id, original.id)
            XCTAssertNil(copy.lastPerformed)
            XCTAssertEqual(copy.name, "Push (heavy)")
            XCTAssertEqual(copy.entries.count, 2)
            XCTAssertTrue(Set(copy.entries.map { $0.id }).isDisjoint(with: original.entries.map { $0.id }), "new entry ids")
            XCTAssertEqual(Set(copy.entries.map { $0.id }).count, 2)
            XCTAssertEqual(copy.entries.map { $0.exercise }, original.entries.map { $0.exercise })
            XCTAssertEqual(copy.entries.map { $0.plannedSets }, original.entries.map { $0.plannedSets })
            XCTAssertEqual(copy.entries.map { $0.note }, ["note 0", "note 1"], "notes come along")
            XCTAssertEqual(copy.entries.map { $0.supersetGroup }, [nil, "A"])
            XCTAssertEqual(model.data.template(id: original.id), original, "the original is untouched")

            guard case let .failure(blank) = model.duplicateTemplate(id: original.id, name: "  ") else { return XCTFail("a copy needs a name") }
            XCTAssertEqual(blank as? StrengthStoreError, .invalidName)
            guard case let .failure(unknown) = model.duplicateTemplate(id: SvcSyncFix.uuid(999), name: "X") else { return XCTFail("unknown id") }
            XCTAssertEqual(unknown as? StrengthStoreError, .notFound)
            XCTAssertEqual(model.data.templates.count, 3)
        }
        XCTAssertEqual(M.names(persistence.loadTemplates()), ["Push", "Push (heavy)", "Pull"])
    }

    func testMovingFollowsTheMeaningOfSwiftUIOnMove() {
        func moved(_ source: [Int], to destination: Int) -> [String] {
            var data = StrengthData(templates: ["A", "B", "C", "D"].enumerated().map { M.template($0.offset, $0.element) })
            data.moveTemplates(fromOffsets: IndexSet(source), toOffset: destination)
            return M.names(data.templates)
        }
        XCTAssertEqual(moved([0], to: 3), ["B", "C", "A", "D"])
        XCTAssertEqual(moved([0], to: 4), ["B", "C", "D", "A"])
        XCTAssertEqual(moved([3], to: 0), ["D", "A", "B", "C"])
        XCTAssertEqual(moved([0, 1], to: 4), ["C", "D", "A", "B"])
        XCTAssertEqual(moved([1, 2], to: 0), ["B", "C", "A", "D"])
        XCTAssertEqual(moved([0, 3], to: 2), ["B", "A", "D", "C"])
        XCTAssertEqual(moved([2], to: 2), ["A", "B", "C", "D"], "dropping an item where it is changes nothing")
        XCTAssertEqual(moved([2], to: 3), ["A", "B", "C", "D"])
        XCTAssertEqual(moved([1], to: 99), ["A", "C", "D", "B"], "a destination past the end means the end")
        XCTAssertEqual(moved([1], to: -5), ["B", "A", "C", "D"], "a destination before the start means the start")
        XCTAssertEqual(moved([9], to: 0), ["A", "B", "C", "D"], "offsets outside the list are ignored")
        XCTAssertEqual(moved([], to: 1), ["A", "B", "C", "D"])
        XCTAssertEqual(moved([0, 9], to: 4), ["B", "C", "D", "A"])
    }

    func testTheOrderIsSetByIdsAndTolerantOfMistakes() {
        func ordered(_ order: [Int]) -> [String] {
            var data = StrengthData(templates: ["A", "B", "C", "D"].enumerated().map { M.template($0.offset, $0.element) })
            data.setTemplateOrder(order.map { SvcSyncFix.uuid(100 + $0) })
            return M.names(data.templates)
        }
        XCTAssertEqual(ordered([3, 2, 1, 0]), ["D", "C", "B", "A"])
        XCTAssertEqual(ordered([2, 0]), ["C", "A", "B", "D"], "unlisted templates follow in their old order")
        XCTAssertEqual(ordered([9, 1, 8]), ["B", "A", "C", "D"], "unknown ids are ignored")
        XCTAssertEqual(ordered([1, 1, 1]), ["B", "A", "C", "D"], "a repeated id counts once")
        XCTAssertEqual(ordered([]), ["A", "B", "C", "D"])
    }

    func testTemplatesKeepTheirOrderAcrossSavesAndReloads() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            for (index, name) in ["A", "B", "C"].enumerated() { model.saveTemplate(M.template(index, name)) }
            XCTAssertEqual(M.names(model.data.templates), ["A", "B", "C"], "a new template is appended")

            var changed = M.template(1, "B edited")
            changed.entries = []
            model.saveTemplate(changed)
            XCTAssertEqual(M.names(model.data.templates), ["A", "B edited", "C"], "saving an existing id keeps its position")

            XCTAssertNoThrow(try model.moveTemplates(fromOffsets: IndexSet(integer: 2), toOffset: 0).get())
            XCTAssertEqual(M.names(model.data.templates), ["C", "A", "B edited"])
            model.saveTemplate(M.template(0, "A again"))
            XCTAssertEqual(M.names(model.data.templates), ["C", "A again", "B edited"])
            model.saveTemplate(M.template(7, "New"))
            XCTAssertEqual(M.names(model.data.templates), ["C", "A again", "B edited", "New"])

            XCTAssertNoThrow(try model.setTemplateOrder([SvcSyncFix.uuid(107), SvcSyncFix.uuid(101)]).get())
            XCTAssertEqual(M.names(model.data.templates), ["New", "B edited", "C", "A again"])

            let reloaded = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(M.names(reloaded.data.templates), ["New", "B edited", "C", "A again"], "the file order is the user's order")
        }
        XCTAssertEqual(M.names(persistence.loadTemplates()), ["New", "B edited", "C", "A again"])
    }
}

// MARK: - Finished workouts and personal bests

final class WorkoutManagementTests: XCTestCase {
    private typealias F = SvcDataFix

    private func bench(_ n: Int, _ sets: [CompletedSet], note: String = "") -> CompletedExercise {
        var entry = F.entry("bench", sets, n: n)
        entry.note = note
        return entry
    }

    func testDeletingTheWorkoutThatSetABestLowersIt() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            model.record(F.workout(1, finishedAt: F.daysAgo(10), [bench(1, [F.work(90, 5)])]), updateTemplate: nil)
            model.record(F.workout(2, finishedAt: F.daysAgo(5), [bench(2, [F.work(100, 5)]), F.entry("squat", [F.work(120, 3)], n: 21)]), updateTemplate: nil)
            XCTAssertEqual(model.data.personalBests["bench"]?.weightKg, 100)
            XCTAssertEqual(model.exercise(id: "bench")?.previousBestE1RM ?? 0, 100 * (1 + 5.0 / 30), accuracy: 0.001)

            XCTAssertNoThrow(try model.deleteWorkout(id: SvcSyncFix.uuid(2)).get())
            XCTAssertEqual(model.data.personalBests["bench"]?.weightKg, 90, "the best falls back to the older workout")
            XCTAssertNil(model.data.personalBests["squat"], "an exercise without history has no best")
            XCTAssertEqual(model.exercise(id: "bench")?.previousBestE1RM ?? 0, 90 * (1 + 5.0 / 30), accuracy: 0.001, "the overlay follows")
            XCTAssertEqual(model.data.history.map { $0.id }, [SvcSyncFix.uuid(1)])

            XCTAssertNoThrow(try model.deleteWorkout(id: SvcSyncFix.uuid(1)).get())
            XCTAssertEqual(model.data.personalBests, [:])
            guard case let .failure(error) = model.deleteWorkout(id: SvcSyncFix.uuid(1)) else { return XCTFail("already deleted") }
            XCTAssertEqual(error as? StrengthStoreError, .notFound)
        }
        XCTAssertEqual(persistence.loadHistory(), [])
        XCTAssertEqual(persistence.loadPersonalBests(), [:])
    }

    func testATypoWeightNoLongerBlocksRecordsOnceTheWorkoutIsCorrected() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            model.record(F.workout(1, finishedAt: F.daysAgo(3), [bench(1, [F.work(1000, 5)])]), updateTemplate: nil)
            XCTAssertEqual(model.data.personalBests["bench"]?.weightKg, 1000)

            var fixed = model.data.history[0]
            fixed.exercises[0].sets[0].weightKg = 100
            XCTAssertNoThrow(try model.updateWorkout(fixed).get())
            XCTAssertEqual(model.data.personalBests["bench"]?.weightKg, 100)
            XCTAssertEqual(model.data.personalBests["bench"]?.estimated1RM ?? 0, 100 * (1 + 5.0 / 30), accuracy: 0.001)
            XCTAssertEqual(model.exercise(id: "bench")?.previousBestE1RM ?? 0, 100 * (1 + 5.0 / 30), accuracy: 0.001)
        }
        XCTAssertEqual(persistence.loadPersonalBests()["bench"]?.weightKg, 100)
    }

    func testDeletingAWorkoutGivesItsTemplateTheEarlierLastPerformed() {
        svcMain {
            let model = StrengthDataModel(persistence: nil)
            let push = M.template(1, "Push")
            model.saveTemplate(push)
            model.record(F.workout(1, templateID: push.id, finishedAt: F.daysAgo(8), [bench(1, [F.work(80, 5)])]), updateTemplate: nil)
            model.record(F.workout(2, templateID: push.id, finishedAt: F.daysAgo(2), [bench(2, [F.work(85, 5)])]), updateTemplate: nil)
            XCTAssertEqual(model.data.templates[0].lastPerformed, F.daysAgo(2))
            model.deleteWorkout(id: SvcSyncFix.uuid(2))
            XCTAssertEqual(model.data.templates[0].lastPerformed, F.daysAgo(8))
            model.deleteWorkout(id: SvcSyncFix.uuid(1))
            XCTAssertNil(model.data.templates[0].lastPerformed)
        }
    }

    func testDeletingAnOlderWorkoutLeavesTheTemplatesLastPerformedAlone() {
        svcMain {
            let model = StrengthDataModel(persistence: nil)
            let push = M.template(1, "Push")
            model.saveTemplate(push)
            model.record(F.workout(1, templateID: push.id, finishedAt: F.daysAgo(8), [bench(1, [F.work(80, 5)])]), updateTemplate: nil)
            model.record(F.workout(2, templateID: push.id, finishedAt: F.daysAgo(2), [bench(2, [F.work(85, 5)])]), updateTemplate: nil)
            model.deleteWorkout(id: SvcSyncFix.uuid(1))
            XCTAssertEqual(model.data.templates[0].lastPerformed, F.daysAgo(2))
        }
    }

    func testUpdatingAWorkoutRecomputesEveryDerivedField() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let older = F.workout(1, finishedAt: F.daysAgo(10), [bench(1, [F.work(90, 5)])])           // e1RM 105
            var edited = F.workout(2, name: "Push", templateID: SvcSyncFix.uuid(55), finishedAt: F.daysAgo(5), [
                bench(2, [F.warmup(60, 8), F.work(100, 5)]),
                F.entry("squat", [F.work(120, 3)], n: 22),
            ])
            edited.averageHeartRate = 131
            let newer = F.workout(3, finishedAt: F.daysAgo(1), [bench(3, [F.work(95, 5)])])
            model.record(older, updateTemplate: nil)
            model.record(edited, updateTemplate: nil)
            model.record(newer, updateTemplate: nil)
            let stored = try XCTUnwrap(model.data.history.first { $0.id == edited.id })

            // The user fixes the weights, drops the squat, deletes the warm-up, adds RIR and a note, and renames the workout.
            var change = stored
            change.name = "  Heavy push  "
            change.exercises[0].sets = [
                CompletedSet(type: .normal, weightKg: 100, reps: 5, rir: 2),
                CompletedSet(type: .drop, weightKg: 95, reps: 8, rir: 4),
            ]
            change.exercises[0].note = "Paused reps"
            change.exercises.remove(at: 1)
            change.startedAt = F.daysAgo(99)       // not editable: ignored
            change.averageHeartRate = 40           // not editable: ignored
            XCTAssertNoThrow(try model.updateWorkout(change).get())

            let updated = try XCTUnwrap(model.data.history.first { $0.id == edited.id })
            XCTAssertEqual(model.data.history.map { $0.id }, [newer.id, edited.id, older.id], "the position is kept")
            XCTAssertEqual(updated.name, "Heavy push")
            XCTAssertEqual(updated.exercises.count, 1)
            XCTAssertEqual(updated.exercises[0].id, stored.exercises[0].id, "the entry keeps its id")
            XCTAssertEqual(updated.exercises[0].note, "Paused reps")
            XCTAssertEqual(updated.loggedSets, 2)
            XCTAssertEqual(updated.volumeKg, 100 * 5 + 95 * 8, accuracy: 1e-9)
            XCTAssertEqual(updated.averageRIR ?? -1, 3, accuracy: 1e-9)
            XCTAssertEqual(updated.muscleSets, [MuscleSets(muscle: .chest, sets: 2)])
            XCTAssertEqual(updated.exercises[0].bestE1RM, 95 * (1 + 8.0 / 30), accuracy: 1e-9, "the 95 kg x 8 drop set has the higher estimate")
            XCTAssertTrue(updated.exercises[0].isPersonalRecord, "beats the 105 of the workout before it")
            XCTAssertEqual(updated.personalRecords.count, 1)
            XCTAssertEqual(updated.personalRecords[0].exerciseID, "bench")
            XCTAssertEqual(updated.personalRecords[0].previousBest, 105, accuracy: 1e-9)
            XCTAssertEqual(updated.personalRecords[0].weightKg, 95)
            XCTAssertEqual(updated.personalRecords[0].reps, 8)
            XCTAssertEqual(updated.startedAt, stored.startedAt)
            XCTAssertEqual(updated.finishedAt, stored.finishedAt)
            XCTAssertEqual(updated.durationSeconds, stored.durationSeconds)
            XCTAssertEqual(updated.averageHeartRate, 131)
            XCTAssertEqual(updated.templateID, SvcSyncFix.uuid(55))
            XCTAssertEqual(model.data.history.first { $0.id == newer.id }, newer, "later workouts are not touched")
            XCTAssertNil(model.data.personalBests["squat"], "the squat went with the exercise")
            XCTAssertEqual(model.data.personalBests["bench"]?.weightKg, 95)

            // A smaller edit loses the record.
            var smaller = updated
            smaller.exercises[0].sets = [CompletedSet(type: .normal, weightKg: 85, reps: 5)]
            XCTAssertNoThrow(try model.updateWorkout(smaller).get())
            let flat = try XCTUnwrap(model.data.history.first { $0.id == edited.id })
            XCTAssertFalse(flat.exercises[0].isPersonalRecord)
            XCTAssertEqual(flat.personalRecords, [])
            XCTAssertEqual(flat.averageRIR, nil)
            XCTAssertEqual(model.data.personalBests["bench"]?.weightKg, 95, "the newest workout now holds the best")
            XCTAssertEqual(model.data.personalBests["bench"]?.date, newer.finishedAt)
        }
        let onDisk = persistence.loadHistory()
        XCTAssertEqual(onDisk.first { $0.id == SvcSyncFix.uuid(2) }?.exercises.first?.sets, [CompletedSet(type: .normal, weightKg: 85, reps: 5)])
    }

    func testTheOldestWorkoutHasNoHistoryToBeARecordAgainst() throws {
        try svcMain {
            let model = StrengthDataModel(persistence: nil)
            model.record(F.workout(1, finishedAt: F.daysAgo(10), [bench(1, [F.work(90, 5)])]), updateTemplate: nil)
            var change = model.data.history[0]
            change.exercises[0].sets = [F.work(150, 5)]
            XCTAssertNoThrow(try model.updateWorkout(change).get())
            XCTAssertFalse(model.data.history[0].exercises[0].isPersonalRecord)
            XCTAssertEqual(model.data.history[0].personalRecords, [])
            XCTAssertEqual(model.data.personalBests["bench"]?.weightKg, 150)
        }
    }

    func testAnEditCanRemoveAllSetsOfAnExerciseAndKeepsOtherEntries() throws {
        try svcMain {
            let model = StrengthDataModel(persistence: nil)
            model.record(F.workout(1, finishedAt: F.daysAgo(1), [bench(1, [F.work(90, 5)]), F.entry("squat", [F.work(120, 3)], n: 2)]), updateTemplate: nil)
            var change = model.data.history[0]
            change.exercises[0].sets = []
            XCTAssertNoThrow(try model.updateWorkout(change).get())
            XCTAssertEqual(model.data.history[0].exercises.map { $0.exerciseID }, ["squat"])
            XCTAssertEqual(model.data.history[0].loggedSets, 1)
            XCTAssertEqual(model.data.personalBests.keys.sorted(), ["squat"])
        }
    }

    func testAnEditKeepsValuesInRangeAndANonBlankName() throws {
        try svcMain {
            let model = StrengthDataModel(persistence: nil)
            model.record(F.workout(1, name: "Original", finishedAt: F.daysAgo(1), [bench(1, [F.work(90, 5)])]), updateTemplate: nil)
            var change = model.data.history[0]
            change.name = "   "
            change.exercises[0].sets = [
                CompletedSet(type: .normal, weightKg: .nan, reps: -4, rir: 9),
                CompletedSet(type: .normal, weightKg: .infinity, reps: 50_000, rir: -2),
                CompletedSet(type: .normal, weightKg: 82.5049, reps: 3),
            ]
            XCTAssertNoThrow(try model.updateWorkout(change).get())
            let sets = model.data.history[0].exercises[0].sets
            XCTAssertEqual(model.data.history[0].name, "Original")
            XCTAssertEqual(sets[0], CompletedSet(type: .normal, weightKg: 0, reps: 0, rir: 4))
            XCTAssertEqual(sets[1], CompletedSet(type: .normal, weightKg: WorkoutReducer.maximumWeightKg, reps: 10_800, rir: 0))
            XCTAssertEqual(sets[2].weightKg, 82.5)
            XCTAssertTrue(model.data.history[0].volumeKg.isFinite)
        }
    }

    func testUpdatingAnUnknownWorkoutFails() {
        svcMain {
            let model = StrengthDataModel(persistence: nil)
            guard case let .failure(error) = model.updateWorkout(F.workout(1, finishedAt: F.now, [])) else { return XCTFail("unknown id") }
            XCTAssertEqual(error as? StrengthStoreError, .notFound)
        }
    }

    func testReRecordingAWorkoutWithTheSameIdRecomputesTheBests() {
        svcMain {
            let model = StrengthDataModel(persistence: nil)
            model.record(F.workout(1, finishedAt: F.daysAgo(3), [bench(1, [F.work(1000, 1)])]), updateTemplate: nil)
            model.record(F.workout(1, finishedAt: F.daysAgo(3), [bench(1, [F.work(100, 5)])]), updateTemplate: nil)
            XCTAssertEqual(model.data.personalBests["bench"]?.weightKg, 100)
            XCTAssertEqual(model.data.history.count, 1)
        }
    }

    func testRecomputeSkipsWarmUpsPrefersTheEarliestOnATieAndIgnoresExercisesWithoutAnEstimate() {
        var data = StrengthData(history: [
            F.workout(3, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(100, 5)], n: 3), F.entry("pushup", [F.work(0, 20)], n: 4)]),
            F.workout(2, finishedAt: F.daysAgo(5), [F.entry("bench", [F.warmup(200, 5), F.work(100, 5)], n: 2)]),
            F.workout(1, finishedAt: F.daysAgo(9), [F.entry("bench", [F.work(80, 5)], n: 1), F.entry("plank", [F.work(0, 60)], n: 5)]),
        ], personalBests: ["bench": PersonalBest(exerciseID: "bench", estimated1RM: 9999, weightKg: 999, reps: 1, date: F.now), "ghost": PersonalBest(exerciseID: "ghost", estimated1RM: 1, weightKg: 1, reps: 1, date: F.now)])
        data.recomputePersonalBests()
        XCTAssertEqual(data.personalBests.keys.sorted(), ["bench", "plank", "pushup"], "stale and invented bests go, reps-only and timed exercises keep only their marks")
        XCTAssertEqual(data.personalBests["bench"], PersonalBest(
            exerciseID: "bench", estimated1RM: 100 * (1 + 5.0 / 30), weightKg: 100, reps: 5, date: F.daysAgo(5),
            heaviestKg: 100, repRecords: [1: 100, 2: 100, 3: 100, 4: 100, 5: 100]
        ))
        XCTAssertEqual(data.personalBests["pushup"], PersonalBest(
            exerciseID: "pushup", estimated1RM: 0, weightKg: 0, reps: 0, date: F.daysAgo(1), bestReps: 20
        ))
        XCTAssertEqual(data.personalBests["plank"], PersonalBest(
            exerciseID: "plank", estimated1RM: 0, weightKg: 0, reps: 0, date: F.daysAgo(9), bestSeconds: 60
        ))
        XCTAssertEqual(StrengthData().recomputedPersonalBests(), [:])
    }

    func testRecomputeUsesTheRecordedEstimateWhenThereIsOne() {
        let data = StrengthData(history: [F.workout(1, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(100, 5)], best: 130, n: 1)])])
        XCTAssertEqual(data.recomputedPersonalBests()["bench"]?.estimated1RM, 130)
        XCTAssertEqual(data.recomputedPersonalBests()["bench"]?.weightKg, 100)
    }

    // MARK: Incremental record against a full recompute

    func testRecordAgreesWithAFullRecomputeForRandomHistories() {
        let exerciseIDs = ["bench", "squat", "ohp", "pushup", "plank"]
        var generator = SvcLCG(seed: 20_261_016)
        for trial in 0..<300 {
            var data = StrengthData()
            let workoutCount = generator.int(in: 1...14)
            var usedIDs: [Int] = []
            for step in 0..<workoutCount {
                // Reuse an earlier id now and then (a replaced workout); finish times collide on purpose.
                let reuse = !usedIDs.isEmpty && generator.int(6) == 0
                let number = reuse ? usedIDs[generator.int(usedIDs.count)] : 1000 * trial + step + 1
                usedIDs.append(number)
                let finishedAt = F.daysAgo(Double(generator.int(8)))
                var entries: [CompletedExercise] = []
                for slot in 0..<generator.int(in: 0...3) {
                    let id = exerciseIDs[generator.int(exerciseIDs.count)]
                    var sets: [CompletedSet] = []
                    for _ in 0..<generator.int(in: 0...4) {
                        let type: SetType = [.normal, .normal, .warmup, .drop, .failure][generator.int(5)]
                        // Coarse weights so that equal estimates (ties) occur.
                        sets.append(CompletedSet(type: type, weightKg: Double(generator.int(in: 0...6) * 20), reps: generator.int(in: 1...8)))
                    }
                    var entry = F.entry(id, sets, n: 100 * trial + 10 * step + slot)
                    if generator.int(8) == 0 { entry.bestE1RM = Double(generator.int(in: 0...160)) }
                    entries.append(entry)
                }
                data.record(F.workout(number, finishedAt: finishedAt, entries), updateTemplate: nil)
                XCTAssertEqual(data.personalBests, data.recomputedPersonalBests(), "trial \(trial) step \(step)")
            }
        }
    }

    func testRecomputeIsADeterministicFunctionOfTheHistoryOrder() {
        let tie = [
            F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(100, 5)], n: 1)]),
            F.workout(2, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(100, 5)], n: 2)]),
        ]
        var data = StrengthData()
        data.record(tie[0], updateTemplate: nil)
        data.record(tie[1], updateTemplate: nil)
        XCTAssertEqual(data.personalBests, data.recomputedPersonalBests())
        XCTAssertEqual(data.recomputedPersonalBests(), data.recomputedPersonalBests())
    }
}

// MARK: - Custom exercises

final class CustomExerciseManagementTests: XCTestCase {
    private typealias F = SvcDataFix

    @MainActor
    private func makeModel(_ persistence: FileStrengthPersistence?) -> (StrengthDataModel, Exercise) {
        let model = StrengthDataModel(persistence: persistence)
        let custom = F.customExercise("Hex press")
        model.addCustomExercise(custom)
        var other = M.template(1, "Push")
        other.entries.append(M.entry(of: custom, n: 1))
        model.saveTemplate(other)
        model.saveTemplate(M.template(2, "Pull"))
        var third = M.template(3, "Arms", exercises: [])
        third.entries = [M.entry(of: custom, n: 2), M.entry(of: ExerciseLibrary.exercise(id: "bench")!, n: 3)]
        model.saveTemplate(third)
        model.record(F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(80, 5)], n: 1), {
            var entry = F.entry("bench", [F.work(20, 10)], n: 9)
            entry.exerciseID = custom.id
            entry.name = custom.name
            return entry
        }()]), updateTemplate: nil)
        return (model, custom)
    }

    func testDeletingARemovesItFromTheLibraryAndTheTemplatesButNotFromTheHistory() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try svcMain {
            let (model, custom) = makeModel(persistence)
            XCTAssertEqual(model.exercises.count, 37)
            let changed = try model.deleteCustomExercise(id: custom.id).get()
            XCTAssertEqual(changed, 2, "Push and Arms held it, Pull did not")
            XCTAssertEqual(model.exercises.count, 36)
            XCTAssertNil(model.exercise(id: custom.id))
            XCTAssertEqual(model.data.customExercises, [])
            XCTAssertEqual(model.data.templates.map { $0.entries.map { $0.exercise.id } }, [["bench"], ["bench"], ["bench"]])
            XCTAssertEqual(model.data.history[0].exercises.map { $0.name }, ["Barbell bench press", custom.name], "the workout keeps the name")
            guard case let .failure(error) = model.deleteCustomExercise(id: custom.id) else { return XCTFail("already deleted") }
            XCTAssertEqual(error as? StrengthStoreError, .notFound)
            guard case let .failure(builtIn) = model.deleteCustomExercise(id: "bench") else { return XCTFail("built-in exercises cannot be deleted") }
            XCTAssertEqual(builtIn as? StrengthStoreError, .notFound)
        }
        XCTAssertEqual(persistence.loadCustomExercises(), [])
        XCTAssertEqual(persistence.loadTemplates().map { $0.entries.count }, [1, 1, 1])
        XCTAssertEqual(persistence.loadHistory()[0].exercises.count, 2)
    }

    func testDeletingAnExerciseNobodyUsesReportsZeroTemplatesChanged() throws {
        try svcMain {
            let model = StrengthDataModel(persistence: nil)
            let custom = F.customExercise("Unused")
            model.addCustomExercise(custom)
            model.saveTemplate(M.template(1, "Push"))
            XCTAssertEqual(try model.deleteCustomExercise(id: custom.id).get(), 0)
            XCTAssertEqual(model.data.templates.count, 1)
        }
    }

    func testUpdatingReplacesTheLibraryEntryAndRefreshesTheTemplateCopies() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try svcMain {
            let (model, custom) = makeModel(persistence)
            // The copy in a template carries remembered results; they must survive.
            var push = model.data.templates[0]
            push.entries[1].exercise.previousBestE1RM = 41
            push.entries[1].exercise.previousSets = [PreviousSet(weightKg: 22, reps: 9)]
            model.saveTemplate(push)

            let historyBefore = model.data.history
            var edited = custom
            edited.name = "  Neutral-grip press "
            edited.muscle = .chest
            edited.equipment = .machine
            edited.tracking = .repsOnly
            edited.secondary = "Triceps"
            edited.cues = ["Squeeze at the top."]
            edited.isCustom = false
            XCTAssertNoThrow(try model.updateCustomExercise(edited).get())

            let stored = try XCTUnwrap(model.data.customExercises.first)
            XCTAssertEqual(stored.name, "Neutral-grip press")
            XCTAssertEqual(stored.muscle, .chest)
            XCTAssertEqual(stored.equipment, .machine)
            XCTAssertEqual(stored.tracking, .repsOnly)
            XCTAssertEqual(stored.secondary, "Triceps")
            XCTAssertEqual(stored.cues, ["Squeeze at the top."])
            XCTAssertTrue(stored.isCustom)
            XCTAssertEqual(model.exercise(id: custom.id)?.name, "Neutral-grip press", "the exercise lookup is refreshed")
            XCTAssertEqual(model.exercises.count, 37)

            let copies = model.data.templates.flatMap { $0.entries }.filter { $0.exercise.id == custom.id }
            XCTAssertEqual(copies.count, 2)
            for copy in copies {
                XCTAssertEqual(copy.exercise.name, "Neutral-grip press")
                XCTAssertEqual(copy.exercise.muscle, .chest)
                XCTAssertEqual(copy.exercise.equipment, .machine)
                XCTAssertEqual(copy.exercise.tracking, .repsOnly)
                XCTAssertEqual(copy.exercise.secondary, "Triceps")
                XCTAssertEqual(copy.exercise.cues, ["Squeeze at the top."])
                XCTAssertEqual(copy.note, "keep the elbows in", "the entry's own data stays")
                XCTAssertEqual(copy.plannedSets, [PlannedSet(weightKg: 20, reps: 10)])
            }
            let pushCopy = try XCTUnwrap(model.data.templates[0].entries.first { $0.exercise.id == custom.id })
            XCTAssertEqual(pushCopy.exercise.previousBestE1RM, 41)
            XCTAssertEqual(pushCopy.exercise.previousSets, [PreviousSet(weightKg: 22, reps: 9)])
            XCTAssertEqual(model.data.templates[2].entries.last?.exercise, ExerciseLibrary.exercise(id: "bench"), "other entries are untouched")

            XCTAssertEqual(model.data.history, historyBefore, "the history keeps the old name and muscle")
            XCTAssertEqual(model.data.history[0].exercises.map { $0.name }, ["Barbell bench press", custom.name])
        }
        XCTAssertEqual(persistence.loadCustomExercises().first?.name, "Neutral-grip press")
        XCTAssertEqual(persistence.loadTemplates()[0].entries[1].exercise.name, "Neutral-grip press")
    }

    func testUpdatingACustomExerciseKeepsItsRecordMarksAndThoseOfItsTemplateCopies() throws {
        try svcMain {
            let (model, custom) = makeModel(nil)
            let storedMarks = RecordMarks(heaviestKg: 30, repRecords: [8: 30], bestReps: 0, bestSeconds: 0)
            let copyMarks = RecordMarks(heaviestKg: 25, repRecords: [5: 25], bestReps: 3, bestSeconds: 45)
            model.data.customExercises[0].previousRecords = storedMarks
            var push = model.data.templates[0]
            let copyIndex = try XCTUnwrap(push.entries.firstIndex { $0.exercise.id == custom.id })
            push.entries[copyIndex].exercise.previousRecords = copyMarks
            model.saveTemplate(push)

            var edited = custom
            edited.name = "Hex press 2"
            XCTAssertNoThrow(try model.updateCustomExercise(edited).get())

            XCTAssertEqual(model.data.customExercises[0].previousRecords, storedMarks, "the edit does not wipe the stored marks")
            let copy = try XCTUnwrap(model.data.templates[0].entries.first { $0.exercise.id == custom.id })
            XCTAssertEqual(copy.exercise.previousRecords, copyMarks, "nor the marks of a template copy")
        }
    }

    func testRefreshingTheTemplateCopiesKeepsTheirMarksAndReportsNoChangeOnAnUnchangedStore() {
        var data = StrengthData()
        var bench = ExerciseLibrary.exercise(id: "bench")!
        bench.previousRecords = RecordMarks(heaviestKg: 100, repRecords: [5: 100], bestReps: 0, bestSeconds: 0)
        data.templates = [WorkoutTemplate(name: "Push", entries: [
            TemplateEntry(exercise: bench, plannedSets: [PlannedSet(weightKg: 60, reps: 8)], restSeconds: 90),
        ])]
        XCTAssertFalse(data.refreshTemplateExercises(), "a copy with marks equals the library entry plus its results")
        XCTAssertEqual(data.templates[0].entries[0].exercise.previousRecords, bench.previousRecords)
        data.templates[0].entries[0].exercise.name = "Old name"
        XCTAssertTrue(data.refreshTemplateExercises())
        XCTAssertEqual(data.templates[0].entries[0].exercise.name, bench.name)
        XCTAssertEqual(data.templates[0].entries[0].exercise.previousRecords, bench.previousRecords, "the marks of the copy stay")
    }

    func testEditingAWorkoutKeepsItsRecordsOfEveryKind() throws {
        try svcMain {
            let model = StrengthDataModel(persistence: nil)
            let hold = { (n: Int, seconds: Int) in F.entry("plank", [F.work(0, seconds)], n: n) }
            model.record(F.workout(1, finishedAt: F.daysAgo(20), [
                F.entry("pullup", [F.work(0, 5), F.work(10, 6)], n: 1), F.entry("bench", [F.work(100, 5)], n: 2), hold(3, 60),
            ]), updateTemplate: nil)
            model.record(F.workout(2, finishedAt: F.daysAgo(5), [
                F.entry("pullup", [F.work(0, 9)], n: 4), F.entry("bench", [F.work(110, 1)], n: 5), hold(6, 90),
            ]), updateTemplate: nil)
            var edited = model.data.history[0]
            edited.name = "Edited name"
            XCTAssertNoThrow(try model.updateWorkout(edited).get())

            let after = model.data.history[0]
            XCTAssertEqual(after.exercises.map { $0.sets.first?.prKind }, [.reps, .heaviest, .duration], "judged against the older workout's marks")
            XCTAssertEqual(after.personalRecords.map { $0.kind }.sorted { $0.rank > $1.rank }, [.heaviest, .reps, .duration])
        }
    }

    func testUpdatingRefusesUnknownIdsBuiltInExercisesAndBlankNames() {
        svcMain {
            let (model, custom) = makeModel(nil)
            var ghost = custom
            ghost.id = "custom-ghost"
            guard case let .failure(unknown) = model.updateCustomExercise(ghost) else { return XCTFail("unknown id") }
            XCTAssertEqual(unknown as? StrengthStoreError, .notFound)
            guard case let .failure(builtIn) = model.updateCustomExercise(ExerciseLibrary.exercise(id: "bench")!) else { return XCTFail("built-in") }
            XCTAssertEqual(builtIn as? StrengthStoreError, .notFound)
            var blank = custom
            blank.name = "  "
            guard case let .failure(invalid) = model.updateCustomExercise(blank) else { return XCTFail("blank") }
            XCTAssertEqual(invalid as? StrengthStoreError, .invalidName)
            XCTAssertEqual(model.data.customExercises.first?.name, custom.name)
        }
    }

    func testAddingAnExerciseWithABuiltInIdIsRefusedAndReported() throws {
        try svcMain {
            let model = StrengthDataModel(persistence: nil)
            var clash = F.customExercise("Bench")
            clash.id = "bench"
            guard case let .failure(error) = model.addCustomExercise(clash) else { return XCTFail("built-in ids are reserved") }
            XCTAssertEqual(error as? StrengthStoreError, .reservedExerciseID)
            XCTAssertEqual(model.data.customExercises, [])
            XCTAssertNoThrow(try model.addCustomExercise(F.customExercise("Hex press")).get())
            XCTAssertNoThrow(try model.addCustomExercise(F.customExercise("Hex press")).get(), "adding the same exercise again is not an error")
        }
    }

    func testTheEngineStartsATemplateWithTheCurrentLibraryForBuiltInExercises() throws {
        try svcMain {
            let rig = SvcRig(self, seed: false)
            var stale = try XCTUnwrap(ExerciseLibrary.exercise(id: "bench"))
            stale.name = "Old name"
            stale.cues = ["Old cue"]
            stale.mediaKey = nil
            let custom = F.customExercise("Hex press")
            rig.model.addCustomExercise(custom)
            var renamedCustom = custom
            renamedCustom.name = "Stale custom copy"
            let template = WorkoutTemplate(name: "Mixed", entries: [
                TemplateEntry(exercise: stale, plannedSets: [PlannedSet(weightKg: 60, reps: 8)], restSeconds: 120),
                TemplateEntry(exercise: renamedCustom, plannedSets: [PlannedSet(weightKg: 20, reps: 10)], restSeconds: 90),
            ])
            rig.engine.start(template: template)
            let started = try XCTUnwrap(rig.engine.state)
            let bench = try XCTUnwrap(ExerciseLibrary.exercise(id: "bench"))
            XCTAssertEqual(started.exercises[0].exercise.name, bench.name)
            XCTAssertEqual(started.exercises[0].exercise.cues, bench.cues)
            XCTAssertEqual(started.exercises[0].exercise.mediaKey, bench.mediaKey)
            XCTAssertEqual(started.exercises[1].exercise.name, "Stale custom copy", "a custom copy is refreshed by editing the exercise, not at start")
        }
    }
}

// MARK: - Notes

final class ExerciseNoteTests: XCTestCase {
    private typealias F = SvcDataFix

    func testATemplatesNotesStartTheWorkoutAndComeBackWhenItIsSavedAsATemplate() {
        let template = M.template(1, "Push", exercises: ["bench", "ohp"])
        let state = WorkoutFactory.makeWorkout(from: template, now: F.now)
        XCTAssertEqual(state.exercises.map { $0.note }, ["note 0", "note 1"])

        var edited = state
        edited.exercises[0].note = "Changed during the workout"
        let updated = WorkoutFactory.updatedTemplate(template, from: edited)
        XCTAssertEqual(updated.entries.map { $0.note }, ["Changed during the workout", "note 1"])
        XCTAssertEqual(updated.entries.map { $0.id }, template.entries.map { $0.id })

        let saved = WorkoutFactory.template(from: edited, name: "Copy")
        XCTAssertEqual(saved.entries.map { $0.note }, ["Changed during the workout", "note 1"])
    }

    func testNotesSurviveFinishingAWorkoutAndTheTripToDisk() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        let completed: CompletedWorkout = try svcMain {
            let rig = SvcRig(self, seed: false, persistence: persistence)
            rig.model.saveTemplate(M.template(1, "Push", exercises: ["bench", "ohp", "squat"]))
            rig.engine.start(template: rig.model.data.templates[0])
            let state = try XCTUnwrap(rig.engine.state)
            XCTAssertEqual(state.exercises[0].note, "note 0", "a workout starts with the template's notes")
            rig.engine.send(.setNote(exerciseID: state.exercises[1].id, note: "Felt a twinge — \"ease off\""))
            rig.engine.send(.setNote(exerciseID: state.exercises[2].id, note: "Never logged, so never saved"))
            for (exercise, set) in [(0, 0), (0, 1), (1, 0)] {
                rig.engine.send(.logSet(exerciseID: state.exercises[exercise].id, setID: state.exercises[exercise].sets[set].id))
            }
            let done = try XCTUnwrap(rig.engine.finish(updateTemplate: false))
            XCTAssertEqual(done.exercises.map { $0.exerciseID }, ["bench", "ohp"])
            XCTAssertEqual(done.exercises.map { $0.note }, ["note 0", "Felt a twinge — \"ease off\""])
            XCTAssertEqual(rig.model.data.history[0].exercises.map { $0.note }, done.exercises.map { $0.note })
            return done
        }
        XCTAssertEqual(persistence.loadHistory()[0].exercises.map { $0.note }, completed.exercises.map { $0.note })
    }

    func testFinishingWithTheTemplateUpdateStoresTheEditedNote() throws {
        try svcMain {
            let rig = SvcRig(self, seed: false)
            rig.model.saveTemplate(M.template(1, "Push", exercises: ["bench"]))
            rig.engine.start(template: rig.model.data.templates[0])
            let state = try XCTUnwrap(rig.engine.state)
            rig.engine.send(.setNote(exerciseID: state.exercises[0].id, note: "Use the 2 kg plates"))
            rig.logSets(1)
            XCTAssertNotNil(rig.engine.finish(updateTemplate: true))
            XCTAssertEqual(rig.model.data.templates[0].entries[0].note, "Use the 2 kg plates")
        }
    }

    func testSummaryBuilderCopiesTheNote() {
        var state = WorkoutFactory.makeWorkout(from: M.template(1, "Push"), now: F.now)
        state.exercises[0].sets[0].isDone = true
        state.exercises[0].note = "Slow eccentric"
        XCTAssertEqual(SummaryBuilder.build(from: state, finishedAt: F.now.addingTimeInterval(600)).exercises[0].note, "Slow eccentric")
    }

    func testNoteDefaultsAndTheEncodedForm() throws {
        let entry = CompletedExercise(exerciseID: "bench", name: "Bench", muscle: .chest, mediaKey: nil, tracking: .weightReps, sets: [], isPersonalRecord: false, bestE1RM: 0)
        XCTAssertEqual(entry.note, "")
        XCTAssertNil(TemplateEntry(exercise: ExerciseLibrary.exercise(id: "bench")!, plannedSets: [], restSeconds: 60).note)

        let encoder = StrengthJSON.makeEncoder()
        let decoder = StrengthJSON.makeDecoder()
        var withNote = entry
        withNote.note = "Paused reps"
        XCTAssertTrue(String(decoding: try encoder.encode(withNote), as: UTF8.self).contains("\"note\":\"Paused reps\""))
        XCTAssertEqual(try decoder.decode(CompletedExercise.self, from: encoder.encode(withNote)), withNote)
        let templateEntry = M.template(1, "Push").entries[0]
        XCTAssertEqual(try decoder.decode(TemplateEntry.self, from: encoder.encode(templateEntry)), templateEntry)
    }
}

// MARK: - Failing writes

final class FailedSaveTests: XCTestCase {
    private typealias F = SvcDataFix

    func testAFailedTemplateSaveIsReportedAndKeptInMemory() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try block("templates.json", in: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let result = model.saveTemplate(M.template(1, "Push"))
            guard case .failure = result else { return XCTFail("the file cannot be replaced") }
            XCTAssertNotNil(model.lastPersistenceError)
            XCTAssertEqual(M.names(model.data.templates), ["Push"], "the change stays in memory")

            // Once the disk works again, the next save of anything writes the template too.
            try unblock("templates.json", in: directory)
            XCTAssertNoThrow(try model.addCustomExercise(F.customExercise("Hex press")).get())
            XCTAssertNil(model.lastPersistenceError)
        }
        XCTAssertEqual(M.names(persistence.loadTemplates()), ["Push"])
    }

    func testEveryManagementCallReportsAFailedWriteAndKeepsTheChange() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let custom = F.customExercise("Hex press")
            model.addCustomExercise(custom)
            var push = M.template(1, "Push")
            push.entries.append(M.entry(of: custom, n: 1))
            model.saveTemplate(push)
            model.saveTemplate(M.template(2, "Pull"))
            model.record(F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(80, 5)], n: 1)]), updateTemplate: nil)
            model.record(F.workout(2, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(90, 5)], n: 2)]), updateTemplate: nil)

            for name in ["templates.json", "history.json", "custom-exercises.json", "personal-bests.json"] { try block(name, in: directory) }
            @MainActor func failed<T>(_ label: String, _ result: Result<T, Error>) {
                guard case let .failure(error) = result else { return XCTFail("\(label) should report the failed write") }
                XCTAssertFalse(error is StrengthStoreError, "\(label): a write error, not a refusal")
                XCTAssertNotNil(model.lastPersistenceError, label)
            }
            failed("rename", model.renameTemplate(id: SvcSyncFix.uuid(102), to: "Pull day"))
            XCTAssertEqual(model.data.templates[1].name, "Pull day")
            failed("duplicate", model.duplicateTemplate(id: SvcSyncFix.uuid(101), name: "Push 2"))
            XCTAssertEqual(model.data.templates.count, 3)
            failed("move", model.moveTemplates(fromOffsets: IndexSet(integer: 0), toOffset: 3))
            XCTAssertEqual(M.names(model.data.templates), ["Push 2", "Pull day", "Push"])
            failed("order", model.setTemplateOrder([SvcSyncFix.uuid(101)]))
            failed("delete template", model.deleteTemplate(id: SvcSyncFix.uuid(102)))
            XCTAssertEqual(model.data.templates.count, 2)
            var edited = model.data.history[0]
            edited.exercises[0].sets = [F.work(95, 5)]
            failed("update workout", model.updateWorkout(edited))
            XCTAssertEqual(model.data.history[0].exercises[0].sets[0].weightKg, 95)
            failed("delete workout", model.deleteWorkout(id: SvcSyncFix.uuid(1)))
            XCTAssertEqual(model.data.history.count, 1)
            var renamed = custom
            renamed.name = "Hex press 2"
            failed("update exercise", model.updateCustomExercise(renamed))
            XCTAssertEqual(model.data.customExercises.first?.name, "Hex press 2")
            failed("delete exercise", model.deleteCustomExercise(id: custom.id))
            XCTAssertEqual(model.data.customExercises, [])
            failed("add exercise", model.addCustomExercise(custom))
        }
    }

    func testRecordReportsOnlyAFailedHistoryWriteAsAFailure() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let push = M.template(1, "Push")
            model.saveTemplate(push)

            // The bests and the template cannot be written, the history can: the workout is safe, so the result is a success.
            try block("personal-bests.json", in: directory)
            try block("templates.json", in: directory)
            let first = model.record(F.workout(1, templateID: push.id, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(80, 5)], n: 1)]), updateTemplate: nil)
            XCTAssertNoThrow(try first.get())
            XCTAssertNotNil(model.lastPersistenceError, "the secondary failure is still reported")
            XCTAssertEqual(persistence.loadHistory().count, 1, "the history is written first, whatever happens to the other files")

            // A failing history write is the failure the caller must see.
            try block("history.json", in: directory)
            let second = model.record(F.workout(2, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(85, 5)], n: 2)]), updateTemplate: nil)
            guard case .failure = second else { return XCTFail("the workout could not be saved") }
            XCTAssertEqual(model.data.history.count, 2, "it is in memory")

            // Everything that failed is written again by the next save once the disk works.
            for name in ["personal-bests.json", "templates.json", "history.json"] { try unblock(name, in: directory) }
            XCTAssertNoThrow(try model.record(F.workout(3, finishedAt: F.now, [F.entry("bench", [F.work(88, 5)], n: 3)]), updateTemplate: nil).get())
            XCTAssertNil(model.lastPersistenceError)
        }
        XCTAssertEqual(persistence.loadHistory().count, 3)
        XCTAssertEqual(persistence.loadPersonalBests()["bench"]?.weightKg, 88)
        XCTAssertEqual(persistence.loadTemplates().count, 1)
        XCTAssertNotNil(persistence.loadTemplates().first?.lastPerformed, "the template write that failed earlier was made up")
    }

    func testAFailedHistoryWriteDoesNotStopTheOtherFiles() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try block("history.json", in: directory)
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let result = model.record(F.workout(1, finishedAt: F.now, [F.entry("bench", [F.work(80, 5)], n: 1)]), updateTemplate: nil)
            guard case .failure = result else { return XCTFail("history cannot be written") }
        }
        XCTAssertEqual(persistence.loadPersonalBests()["bench"]?.weightKg, 80, "every file is attempted even when the first one fails")
    }
}

// MARK: - Only the files that changed are written

final class WrittenFilesTests: XCTestCase {
    private typealias F = SvcDataFix

    /// Runs `change` on a model whose directory was emptied first and returns the data files that exist afterwards.
    @MainActor
    private func written(_ directory: URL, _ model: StrengthDataModel, _ change: @MainActor () -> Void) -> [String] {
        for name in FileStrengthPersistence.dataFileNames {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
        change()
        return FileStrengthPersistence.dataFileNames.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }.sorted()
    }

    func testEachOperationWritesOnlyWhatItChanged() {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let custom = F.customExercise("Hex press")
            var push = M.template(1, "Push", lastPerformed: nil)
            push.entries.append(M.entry(of: custom, n: 1))
            model.addCustomExercise(custom)
            model.saveTemplate(push)
            model.saveTemplate(M.template(2, "Pull"))
            model.record(F.workout(1, templateID: push.id, finishedAt: F.daysAgo(10), [F.entry("bench", [F.work(100, 5)], n: 1)]), updateTemplate: nil)
            model.record(F.workout(2, finishedAt: F.daysAgo(5), [F.entry("bench", [F.work(90, 5)], n: 2)]), updateTemplate: nil)

            XCTAssertEqual(written(directory, model) {
                model.saveTemplate(M.template(3, "Legs"))
            }, ["templates.json"])
            XCTAssertEqual(written(directory, model) {
                model.addCustomExercise(F.customExercise("Cable fly"))
            }, ["custom-exercises.json"])
            XCTAssertEqual(written(directory, model) {
                model.record(F.workout(3, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(80, 5)], n: 3)]), updateTemplate: nil)
            }, ["history.json"], "no template and no new best: only the history")
            XCTAssertEqual(written(directory, model) {
                model.record(F.workout(4, templateID: push.id, finishedAt: F.daysAgo(0.5), [F.entry("bench", [F.work(70, 5)], n: 4)]), updateTemplate: nil)
            }, ["history.json", "templates.json"], "the template's last performed date changed")
            XCTAssertEqual(written(directory, model) {
                model.record(F.workout(5, finishedAt: F.daysAgo(0.2), [F.entry("bench", [F.work(110, 5)], n: 5)]), updateTemplate: nil)
            }, ["history.json", "personal-bests.json"], "a new best")
            XCTAssertEqual(written(directory, model) {
                model.renameTemplate(id: SvcSyncFix.uuid(102), to: "Pull day")
            }, ["templates.json"])
            XCTAssertEqual(written(directory, model) {
                model.moveTemplates(fromOffsets: IndexSet(integer: 0), toOffset: 0)
                model.setTemplateOrder([])
                model.recomputePersonalBests()
            }, [], "a change that changes nothing writes nothing")
            XCTAssertEqual(written(directory, model) {
                model.deleteWorkout(id: SvcSyncFix.uuid(3))
            }, ["history.json"], "the deleted workout held no best and no template date")
            XCTAssertEqual(written(directory, model) {
                model.deleteWorkout(id: SvcSyncFix.uuid(5))
            }, ["history.json", "personal-bests.json"])
            XCTAssertEqual(written(directory, model) {
                var edited = model.data.history[0]
                edited.exercises[0].note = "Just a note"
                model.updateWorkout(edited)
            }, ["history.json"])
            XCTAssertEqual(written(directory, model) {
                var renamed = custom
                renamed.name = "Hex press 2"
                model.updateCustomExercise(renamed)
            }, ["custom-exercises.json", "templates.json"], "the copy in the Push template changed")
            XCTAssertEqual(written(directory, model) {
                model.deleteCustomExercise(id: "custom-cable fly")
            }, ["custom-exercises.json"], "no template held it")
            XCTAssertEqual(written(directory, model) {
                model.recordBodyWeight(kg: 80, date: F.now)
            }, ["body-weights.json"])
            XCTAssertEqual(written(directory, model) {
                model.setWeighInPreferences(WeighInPreferences(isEnabled: true))
            }, ["weigh-in-preferences.json"])
        }
    }
}

#if canImport(Combine) || PULSE_COMBINE_SHIM

// MARK: - The store forwards, publishes and reports

final class StoreManagementForwardingTests: XCTestCase {
    private typealias F = SvcDataFix

    func testTheStorePublishesEveryManagementChange() throws {
        let persistence = FileStrengthPersistence(directory: makeDirectory(self))
        try svcMain {
            let store = StrengthStore(persistence: persistence)
            let custom = F.customExercise("Hex press")
            XCTAssertNoThrow(try store.addCustomExercise(custom).get())
            var push = M.template(1, "Push")
            push.entries.append(M.entry(of: custom, n: 1))
            XCTAssertNoThrow(try store.saveTemplate(push).get())
            XCTAssertNoThrow(try store.saveTemplate(M.template(2, "Pull")).get())
            let copy = try store.duplicateTemplate(id: push.id, name: "Push B").get()
            XCTAssertEqual(M.names(store.templates), ["Push", "Push B", "Pull"])
            XCTAssertNoThrow(try store.renameTemplate(id: copy.id, to: "Push C").get())
            XCTAssertNoThrow(try store.moveTemplates(fromOffsets: IndexSet(integer: 2), toOffset: 0).get())
            XCTAssertEqual(M.names(store.templates), ["Pull", "Push", "Push C"])
            XCTAssertNoThrow(try store.setTemplateOrder([copy.id]).get())
            XCTAssertEqual(M.names(store.templates), ["Push C", "Pull", "Push"])
            XCTAssertNoThrow(try store.deleteTemplate(id: copy.id).get())
            XCTAssertEqual(M.names(store.templates), ["Pull", "Push"])

            store.record(F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(100, 5)], n: 1)]), updateTemplate: nil)
            store.record(F.workout(2, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(80, 5)], n: 2)]), updateTemplate: nil)
            XCTAssertEqual(store.personalBests["bench"]?.weightKg, 100)
            var edited = store.history.first { $0.id == SvcSyncFix.uuid(2) }!
            edited.exercises[0].sets = [F.work(90, 5)]
            XCTAssertNoThrow(try store.updateWorkout(edited).get())
            XCTAssertEqual(store.history[0].exercises[0].sets[0].weightKg, 90)
            XCTAssertNoThrow(try store.deleteWorkout(id: SvcSyncFix.uuid(1)).get())
            XCTAssertEqual(store.personalBests["bench"]?.weightKg, 90, "the published bests follow")
            XCTAssertNoThrow(try store.recomputePersonalBests().get())

            var renamed = custom
            renamed.name = "Neutral press"
            XCTAssertNoThrow(try store.updateCustomExercise(renamed).get())
            XCTAssertEqual(store.customExercises.first?.name, "Neutral press")
            XCTAssertEqual(store.templates.flatMap { $0.entries }.last { $0.exercise.id == custom.id }?.exercise.name, "Neutral press")
            XCTAssertEqual(try store.deleteCustomExercise(id: custom.id).get(), 1)
            XCTAssertEqual(store.customExercises, [])
            XCTAssertEqual(store.exercises.count, 36)
        }
        XCTAssertEqual(persistence.loadHistory().count, 1)
        XCTAssertEqual(M.names(persistence.loadTemplates()), ["Pull", "Push"])
    }

    func testTheLastPersistenceErrorIsPublishedAndClearedAgain() throws {
        let directory = makeDirectory(self)
        let persistence = FileStrengthPersistence(directory: directory)
        try block("templates.json", in: directory)
        try svcMain {
            let store = StrengthStore(persistence: persistence)
            XCTAssertNil(store.lastPersistenceError)
            guard case .failure = store.saveTemplate(M.template(1, "Push")) else { return XCTFail("blocked") }
            XCTAssertNotNil(store.lastPersistenceError)
            try unblock("templates.json", in: directory)
            XCTAssertNoThrow(try store.saveTemplate(M.template(2, "Pull")).get())
            XCTAssertNil(store.lastPersistenceError)
            XCTAssertEqual(M.names(store.templates), ["Push", "Pull"])
        }
    }

    func testSourceCompatibilityOfTheOldCallSites() {
        svcMain {
            let store = StrengthStore(persistence: nil)
            store.addCustomExercise(F.customExercise("Hex press"))
            store.saveTemplate(WorkoutTemplate(name: "Arms", entries: []))
            let onCreate: (Exercise) -> Void = { exercise in store.addCustomExercise(exercise) }
            onCreate(F.customExercise("Cable fly"))
            XCTAssertEqual(store.customExercises.count, 2)
        }
    }
}

#endif
