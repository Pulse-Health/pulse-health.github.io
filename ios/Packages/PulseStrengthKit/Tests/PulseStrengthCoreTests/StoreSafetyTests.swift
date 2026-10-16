import Foundation
import XCTest
@testable import PulseStrengthCore

private func safetyDirectory(_ test: XCTestCase) -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PulseStrength-safety-" + UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    test.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory
}

/// Replaces `name` in the directory by a directory, so that reading it fails and the next atomic write of it fails on every platform.
private func blockWithDirectory(_ name: String, in directory: URL) throws {
    let target = directory.appendingPathComponent(name)
    try? FileManager.default.removeItem(at: target)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: target.appendingPathComponent("keep"))
}

// MARK: - Bests while the history has unreadable workouts

final class IncompleteHistoryBestsTests: XCTestCase {
    private typealias F = SvcDataFix

    /// A directory with three workouts (bench 90, squat 150, bench 100) in which the squat workout cannot be decoded.
    private func directoryWithAnUnreadableSquatWorkout() throws -> URL {
        let directory = safetyDirectory(self)
        try svcMain {
            let model = StrengthDataModel(persistence: FileStrengthPersistence(directory: directory))
            model.record(F.workout(1, name: "Bench A", finishedAt: F.daysAgo(10), [F.entry("bench", [F.work(90, 5)], n: 1)]), updateTemplate: nil)
            model.record(F.workout(2, name: "Squat day", finishedAt: F.daysAgo(5), [F.entry("squat", [F.work(150, 5)], n: 2)]), updateTemplate: nil)
            model.record(F.workout(3, name: "Bench B", finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(100, 5)], n: 3)]), updateTemplate: nil)
        }
        let url = directory.appendingPathComponent("history.json")
        var list = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        let index = try XCTUnwrap(list.firstIndex { $0["name"] as? String == "Squat day" })
        list[index]["finishedAt"] = "not a date"
        try JSONSerialization.data(withJSONObject: list).write(to: url)
        return directory
    }

    @MainActor
    private func openedModel(_ directory: URL) throws -> StrengthDataModel {
        let model = StrengthDataModel(persistence: FileStrengthPersistence(directory: directory))
        XCTAssertEqual(model.data.history.count, 2)
        XCTAssertEqual(model.persistenceIssues.map { $0.kind }, [.skippedElements(1)])
        XCTAssertEqual(model.data.personalBests["squat"]?.weightKg, 150, "the loader keeps the bests as read")
        XCTAssertTrue(model.data.historyIsIncomplete)
        return model
    }

    func testDeletingAWorkoutKeepsTheBestOfTheUnreadableOne() throws {
        let directory = try directoryWithAnUnreadableSquatWorkout()
        try svcMain {
            let model = try openedModel(directory)
            XCTAssertNoThrow(try model.deleteWorkout(id: SvcSyncFix.uuid(1)).get())
            XCTAssertEqual(model.data.personalBests.keys.sorted(), ["bench", "squat"])
            XCTAssertEqual(model.data.personalBests["squat"]?.weightKg, 150)
        }
        XCTAssertEqual(FileStrengthPersistence(directory: directory).loadPersonalBests()["squat"]?.weightKg, 150, "also on disk")
    }

    func testEditingAWorkoutKeepsTheBestOfTheUnreadableOne() throws {
        let directory = try directoryWithAnUnreadableSquatWorkout()
        try svcMain {
            let model = try openedModel(directory)
            var edited = try XCTUnwrap(model.data.history.first { $0.id == SvcSyncFix.uuid(3) })
            edited.exercises[0].sets = [F.work(110, 5)]
            XCTAssertNoThrow(try model.updateWorkout(edited).get())
            XCTAssertEqual(model.data.personalBests["bench"]?.weightKg, 110, "a better value still raises a best")
            XCTAssertEqual(model.data.personalBests["squat"]?.weightKg, 150)
        }
        XCTAssertEqual(FileStrengthPersistence(directory: directory).loadPersonalBests()["squat"]?.weightKg, 150)
    }

    func testRecordingAWorkoutAgainKeepsTheBestOfTheUnreadableOne() throws {
        let directory = try directoryWithAnUnreadableSquatWorkout()
        try svcMain {
            let model = try openedModel(directory)
            model.record(F.workout(1, name: "Bench A", finishedAt: F.daysAgo(10), [F.entry("bench", [F.work(60, 5)], n: 1)]), updateTemplate: nil)
            XCTAssertEqual(model.data.personalBests["squat"]?.weightKg, 150)
            XCTAssertNotNil(model.data.personalBests["bench"])
        }
    }

    func testTheBestsFollowTheHistoryAgainOnceTheIssuesAreAcknowledged() throws {
        let directory = try directoryWithAnUnreadableSquatWorkout()
        try svcMain {
            let model = try openedModel(directory)
            XCTAssertNoThrow(try model.deleteWorkout(id: SvcSyncFix.uuid(1)).get())
            model.reload()
            XCTAssertTrue(model.data.historyIsIncomplete, "a reload does not forget that workouts are missing")
            XCTAssertEqual(model.data.personalBests["squat"]?.weightKg, 150)

            model.acknowledgePersistenceIssues()
            XCTAssertFalse(model.data.historyIsIncomplete)
            XCTAssertNoThrow(try model.recomputePersonalBests().get())
            XCTAssertEqual(model.data.personalBests.keys.sorted(), ["bench"], "the bests are a pure function of the history again")
        }
        XCTAssertEqual(FileStrengthPersistence(directory: directory).loadPersonalBests().keys.sorted(), ["bench"])
    }

    func testAWholeHistoryRecomputesAsBefore() throws {
        try svcMain {
            let model = StrengthDataModel(persistence: FileStrengthPersistence(directory: safetyDirectory(self)))
            model.record(F.workout(1, finishedAt: F.daysAgo(5), [F.entry("bench", [F.work(90, 5)], n: 1)]), updateTemplate: nil)
            model.record(F.workout(2, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(100, 5)], n: 2)]), updateTemplate: nil)
            XCTAssertFalse(model.data.historyIsIncomplete)
            XCTAssertNoThrow(try model.deleteWorkout(id: SvcSyncFix.uuid(2)).get())
            XCTAssertEqual(model.data.personalBests["bench"]?.weightKg, 90)
        }
    }

    func testAnIncompleteHistoryOnlyRaisesBestsAndKeepsTheEarlierDateOnATie() {
        let stored = PersonalBest(exerciseID: "bench", estimated1RM: 120, weightKg: 60, reps: 30, date: F.daysAgo(2))
        var data = StrengthData(
            history: [F.workout(1, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(40, 60)], n: 1)])],
            personalBests: ["bench": stored, "squat": PersonalBest(exerciseID: "squat", estimated1RM: 150, weightKg: 130, reps: 5, date: F.daysAgo(9))],
            historyIsIncomplete: true
        )
        data.recomputePersonalBests()
        XCTAssertEqual(data.personalBests["bench"], stored, "an equal value at a later date does not replace the stored best")
        XCTAssertNotNil(data.personalBests["squat"])
        data.history = [F.workout(1, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(100, 30)], n: 1)])]
        data.recomputePersonalBests()
        XCTAssertEqual(data.personalBests["bench"]?.estimated1RM, 200)
    }
}

// MARK: - Edits and recomputation

final class WorkoutEditSafetyTests: XCTestCase {
    private typealias F = SvcDataFix

    func testANegativeWeightIsStoredAsZeroAndAddsNoNegativeVolume() throws {
        try svcMain {
            let model = StrengthDataModel(persistence: nil)
            model.record(F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(100, 5)], n: 1)]), updateTemplate: nil)
            var edited = model.data.history[0]
            edited.exercises[0].sets = [F.work(-60, 5), F.work(40, 5)]
            XCTAssertNoThrow(try model.updateWorkout(edited).get())
            let stored = model.data.history[0]
            XCTAssertEqual(stored.exercises[0].sets.map { $0.weightKg }, [0, 40])
            XCTAssertEqual(stored.volumeKg, 200, "5 x 40 kg; the clamped set adds nothing")
            XCTAssertEqual(model.data.history(for: "bench", now: F.now).volumeLast30Days, 200)
        }
    }

    func testTiedWorkoutsGiveTheSameBestIncrementallyAndWhenRecomputed() {
        // Both reach an e1RM of exactly 120 at the same instant, with a different weight and number of reps.
        let first = F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(60, 30)], n: 1)])
        let second = F.workout(2, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(40, 60)], n: 2)])
        var data = StrengthData()
        data.record(first, updateTemplate: nil)
        data.record(second, updateTemplate: nil)
        XCTAssertEqual(data.history.map { $0.id }, [second.id, first.id], "the one recorded last is listed first")
        XCTAssertEqual(data.personalBests["bench"]?.weightKg, 60, "recording keeps the first one reached")
        XCTAssertEqual(data.recomputedPersonalBests()["bench"]?.weightKg, 60, "a recompute picks the same one")
        XCTAssertEqual(data.recomputedPersonalBests()["bench"]?.reps, 30)

        var other = StrengthData()
        other.record(second, updateTemplate: nil)
        other.record(first, updateTemplate: nil)
        XCTAssertEqual(other.personalBests["bench"]?.weightKg, 40)
        XCTAssertEqual(other.recomputedPersonalBests()["bench"]?.weightKg, 40)
    }
}

// MARK: - What reaches the disk

final class ManagementWritesTests: XCTestCase {
    private typealias F = SvcDataFix

    private func template() -> WorkoutTemplate {
        WorkoutTemplate(
            id: SvcSyncFix.uuid(100),
            name: "Push",
            entries: [TemplateEntry(
                id: SvcSyncFix.uuid(200), exercise: ExerciseLibrary.exercise(id: "bench")!,
                plannedSets: [PlannedSet(weightKg: 60, reps: 8)], restSeconds: 90
            )]
        )
    }

    func testDeletingTheLatestWorkoutOfATemplateWritesTheEarlierLastPerformed() throws {
        let directory = safetyDirectory(self)
        try svcMain {
            let model = StrengthDataModel(persistence: FileStrengthPersistence(directory: directory))
            let push = template()
            model.saveTemplate(push)
            model.record(F.workout(1, templateID: push.id, finishedAt: F.daysAgo(8), [F.entry("bench", [F.work(80, 5)], n: 1)]), updateTemplate: nil)
            model.record(F.workout(2, templateID: push.id, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(85, 5)], n: 2)]), updateTemplate: nil)
            XCTAssertEqual(FileStrengthPersistence(directory: directory).loadTemplates()[0].lastPerformed, F.daysAgo(2))

            XCTAssertNoThrow(try model.deleteWorkout(id: SvcSyncFix.uuid(2)).get())
            XCTAssertEqual(FileStrengthPersistence(directory: directory).loadTemplates()[0].lastPerformed, F.daysAgo(8))
            XCTAssertNoThrow(try model.deleteWorkout(id: SvcSyncFix.uuid(1)).get())
            XCTAssertNil(FileStrengthPersistence(directory: directory).loadTemplates()[0].lastPerformed)
        }
    }

    func testARecomputeThatChangesTheBestsIsWrittenAndAnUnchangedOneIsNot() throws {
        let directory = safetyDirectory(self)
        try svcMain {
            let persistence = FileStrengthPersistence(directory: directory)
            let model = StrengthDataModel(persistence: persistence)
            model.record(F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(100, 5)], n: 1)]), updateTemplate: nil)

            var stale = model.data.personalBests
            stale["bench"]?.estimated1RM = 999
            stale["squat"] = PersonalBest(exerciseID: "squat", estimated1RM: 200, weightKg: 150, reps: 5, date: F.daysAgo(3))
            model.data.personalBests = stale
            try persistence.savePersonalBests(stale)

            XCTAssertNoThrow(try model.recomputePersonalBests().get())
            XCTAssertEqual(persistence.loadPersonalBests().keys.sorted(), ["bench"], "the lowered bests reached the disk")
            XCTAssertEqual(persistence.loadPersonalBests()["bench"]?.estimated1RM ?? 0, 100 * (1 + 5.0 / 30), accuracy: 0.001)

            try blockWithDirectory("personal-bests.json", in: directory)
            XCTAssertNoThrow(try model.recomputePersonalBests().get(), "nothing changed, so nothing was written")
        }
    }

    func testTheResultOfACallIsAboutTheFilesOfThatCallOnly() throws {
        let directory = safetyDirectory(self)
        try svcMain {
            let persistence = FileStrengthPersistence(directory: directory)
            let model = StrengthDataModel(persistence: persistence)
            model.saveTemplate(template())
            try blockWithDirectory("body-weights.json", in: directory)
            model.recordBodyWeight(kg: 80, date: F.daysAgo(1))
            XCTAssertNotNil(model.lastPersistenceError)

            XCTAssertNoThrow(try model.renameTemplate(id: SvcSyncFix.uuid(100), to: "Upper").get(), "the rename itself was saved")
            XCTAssertEqual(persistence.loadTemplates().map { $0.name }, ["Upper"])
            XCTAssertNotNil(model.lastPersistenceError, "the weigh-in that is still unsaved stays reported")

            let record = model.record(F.workout(1, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(80, 5)], n: 1)]), updateTemplate: nil)
            XCTAssertNoThrow(try record.get())

            try FileManager.default.removeItem(at: directory.appendingPathComponent("body-weights.json"))
            XCTAssertNoThrow(try model.renameTemplate(id: SvcSyncFix.uuid(100), to: "Push").get())
            XCTAssertNil(model.lastPersistenceError, "the retried file was written")
            XCTAssertEqual(persistence.loadBodyWeights().count, 1)
        }
    }

    func testACallFailsWhenItsOwnFileCannotBeWritten() throws {
        let directory = safetyDirectory(self)
        try svcMain {
            let model = StrengthDataModel(persistence: FileStrengthPersistence(directory: directory))
            model.saveTemplate(template())
            try blockWithDirectory("templates.json", in: directory)
            guard case .failure = model.renameTemplate(id: SvcSyncFix.uuid(100), to: "Upper") else { return XCTFail("the write failed") }
            XCTAssertEqual(model.data.templates[0].name, "Upper", "the change stays in memory")
        }
    }
}

// MARK: - A file whose original could not be copied

final class UnpreservedOriginalTests: XCTestCase {
    private func backups(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasPrefix("history.corrupt-") }
    }

    func testAFileThatCannotBeReadIsNotReplacedWithoutACopy() throws {
        let directory = safetyDirectory(self)
        try blockWithDirectory("history.json", in: directory)
        let persistence = FileStrengthPersistence(directory: directory)
        XCTAssertEqual(persistence.loadHistory(), [])
        XCTAssertEqual(persistence.loadIssues, [PersistenceIssue(fileName: "history.json", kind: .unreadableFile)])

        let refused = PersistenceError.originalNotPreserved(fileName: "history.json")
        XCTAssertThrowsError(try persistence.saveHistory([])) { XCTAssertEqual($0 as? PersistenceError, refused) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json/keep").path), "the original is untouched")
        XCTAssertNotNil(refused.errorDescription)
        XCTAssertNoThrow(try persistence.saveTemplates([]), "other files are not affected")
    }

    func testTheModelReportsTheRefusedSaveAndKeepsTheChangeInMemory() throws {
        let directory = safetyDirectory(self)
        try blockWithDirectory("history.json", in: directory)
        try svcMain {
            let model = StrengthDataModel(persistence: FileStrengthPersistence(directory: directory))
            let outcome = model.record(
                SvcDataFix.workout(1, finishedAt: SvcDataFix.daysAgo(1), [SvcDataFix.entry("bench", [SvcDataFix.work(80, 5)], n: 1)]),
                updateTemplate: nil
            )
            guard case let .failure(error) = outcome else { return XCTFail("the history file was not written") }
            XCTAssertEqual(error as? PersistenceError, .originalNotPreserved(fileName: "history.json"))
            XCTAssertEqual(model.data.history.count, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json/keep").path))
        }
    }

    func testTheCopyIsTriedAgainAtTheNextSave() throws {
        let directory = safetyDirectory(self)
        try blockWithDirectory("history.json", in: directory)
        let persistence = FileStrengthPersistence(directory: directory)
        _ = persistence.loadHistory()

        // The file becomes readable (as after a transient read error): the original is copied before it is replaced.
        try FileManager.default.removeItem(at: directory.appendingPathComponent("history.json"))
        try Data("{ broken".utf8).write(to: directory.appendingPathComponent("history.json"))
        XCTAssertNoThrow(try persistence.saveHistory([]))
        let copy = try XCTUnwrap(backups(in: directory).first)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(copy)), Data("{ broken".utf8))
        XCTAssertEqual(persistence.loadIssues.first?.backupFileName, copy)
        XCTAssertEqual(persistence.loadHistory(), [])
    }

    func testTheWorkoutInProgressIsNeverHeldBackByTheCheck() throws {
        let directory = safetyDirectory(self)
        try blockWithDirectory("active-workout.json", in: directory)
        let persistence = FileStrengthPersistence(directory: directory)
        XCTAssertNil(persistence.loadActiveWorkout())
        XCTAssertEqual(persistence.loadIssues.map { $0.fileName }, ["active-workout.json"])
        XCTAssertThrowsError(try persistence.saveActiveWorkout(SvcSyncFix.richState())) { error in
            XCTAssertNil(error as? PersistenceError, "the failure is the file system's, not the check")
        }
    }
}

// MARK: - A newer data format at launch

final class NewerFormatLaunchTests: XCTestCase {
    func testALaunchOverANewerFormatWithoutBestsWritesNothingAndReportsNoSaveError() throws {
        let directory = safetyDirectory(self)
        try svcMain {
            let model = StrengthDataModel(persistence: FileStrengthPersistence(directory: directory))
            model.record(SvcDataFix.workout(1, finishedAt: SvcDataFix.daysAgo(1), [SvcDataFix.entry("bench", [SvcDataFix.work(80, 5)], n: 1)]), updateTemplate: nil)
        }
        try FileManager.default.removeItem(at: directory.appendingPathComponent("personal-bests.json"))
        try Data(#"{"version": 9}"#.utf8).write(to: directory.appendingPathComponent("schema.json"))

        try svcMain {
            let model = StrengthDataModel(persistence: FileStrengthPersistence(directory: directory))
            XCTAssertEqual(model.data.history.count, 1)
            XCTAssertEqual(model.data.personalBests["bench"]?.weightKg, 80, "recomputed in memory")
            XCTAssertNil(model.lastPersistenceError, "the user did nothing, so there is no error to show")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("personal-bests.json").path))
    }
}
