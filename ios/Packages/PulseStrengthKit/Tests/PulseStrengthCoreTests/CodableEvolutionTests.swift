import Foundation
import XCTest
@testable import PulseStrengthCore

/// Files written by the previous version of the app still load, and the raw values that double as storage keys never change.
final class CodableEvolutionTests: XCTestCase {
    private let decoder = StrengthJSON.makeDecoder()
    private let encoder = StrengthJSON.makeEncoder()

    // MARK: Fixtures of the previous format

    func testAWorkoutWrittenBeforeNotesDecodesWithEmptyNotes() throws {
        let json = V1Files.workout(7, finishedAt: "2026-10-13T19:30:00.000Z")
        let workout = try decoder.decode(CompletedWorkout.self, from: Data(json.utf8))
        XCTAssertEqual(workout.name, "Upper A")
        XCTAssertEqual(workout.finishedAt, SvcSyncFix.epoch)
        XCTAssertEqual(workout.exercises.count, 1)
        XCTAssertEqual(workout.exercises[0].note, "")
        XCTAssertEqual(workout.exercises[0].sets, [CompletedSet(type: .normal, weightKg: 63.5, reps: 6)])
        XCTAssertEqual(workout.exercises[0].bestE1RM, 76)
        XCTAssertEqual(workout.volumeKg, 381)
        XCTAssertNil(workout.templateID)
        XCTAssertNil(workout.averageHeartRate)

        // Written again it carries the note, and reads back equal.
        let rewritten = try encoder.encode(workout)
        XCTAssertTrue(String(decoding: rewritten, as: UTF8.self).contains("\"note\":\"\""))
        XCTAssertEqual(try decoder.decode(CompletedWorkout.self, from: rewritten), workout)
    }

    func testATemplateWrittenBeforeNotesDecodesWithoutANote() throws {
        let template = try decoder.decode(WorkoutTemplate.self, from: Data(V1Files.template(3, name: "Push").utf8))
        XCTAssertEqual(template.name, "Push")
        XCTAssertEqual(template.entries.count, 1)
        XCTAssertNil(template.entries[0].note)
        XCTAssertEqual(template.entries[0].plannedSets, [PlannedSet(weightKg: 60, reps: 8)])
        XCTAssertEqual(template.entries[0].restSeconds, 150)
        XCTAssertNil(template.entries[0].supersetGroup)
        XCTAssertNil(template.lastPerformed)
        XCTAssertEqual(try decoder.decode(WorkoutTemplate.self, from: encoder.encode(template)), template)
    }

    func testANewFileWithNotesStillReadsInTheOldWayWhenTheNoteIsIgnored() throws {
        // What an older build does: it ignores the key it does not know. Here: the same JSON minus its note decodes to the same value.
        var entry = CompletedExercise(exerciseID: "bench", name: "Bench", muscle: .chest, mediaKey: nil, tracking: .weightReps, sets: [], isPersonalRecord: false, bestE1RM: 0)
        entry.note = "Paused reps"
        let text = String(decoding: try encoder.encode(entry), as: UTF8.self)
        let stripped = text.replacingOccurrences(of: ",\"note\":\"Paused reps\"", with: "")
        XCTAssertNotEqual(text, stripped)
        var expected = entry
        expected.note = ""
        XCTAssertEqual(try decoder.decode(CompletedExercise.self, from: Data(stripped.utf8)), expected)
    }

    func testUnknownKeysOfALaterVersionAreIgnored() throws {
        let json = """
        {"bestE1RM":0,"exerciseID":"bench","futureField":{"a":[1,2]},"id":"0000FEED-0000-4000-8000-000000000001","isPersonalRecord":false,"muscle":"Chest","name":"Bench","note":"x","sets":[],"tracking":"weightReps"}
        """
        let entry = try decoder.decode(CompletedExercise.self, from: Data(json.utf8))
        XCTAssertEqual(entry.note, "x")
    }

    func testAVersion1DirectoryLoadsIntoTheModelUnchanged() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PulseStrength-v1-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        func write(_ text: String, _ name: String) throws { try Data(text.utf8).write(to: directory.appendingPathComponent(name)) }
        try write("[\(V1Files.template(1, name: "Push"))]", "templates.json")
        try write("[\(V1Files.workout(2, finishedAt: "2026-10-13T19:30:00.000Z")),\(V1Files.workout(1, finishedAt: "2026-10-10T19:30:00.000Z"))]", "history.json")
        try write(V1Files.bests, "personal-bests.json")
        try write(V1Files.bodyWeights, "body-weights.json")
        try write(V1Files.preferences, "weigh-in-preferences.json")
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let persistence = FileStrengthPersistence(directory: directory)

        svcMain {
            let model = StrengthDataModel(persistence: persistence, seedDemoData: true)
            XCTAssertEqual(model.data.templates.map { $0.name }, ["Push"])
            XCTAssertEqual(model.data.history.count, 2)
            XCTAssertEqual(model.data.personalBests["bench"]?.estimated1RM, 76.2, "the stored bests are used as they are")
            XCTAssertEqual(model.data.bodyWeights.map { $0.kg }, [82.4])
            XCTAssertEqual(model.data.weighIn.hour, 7)
            XCTAssertTrue(model.data.weighIn.isEnabled)
            XCTAssertTrue(model.persistenceIssues.isEmpty)
            XCTAssertNil(model.lastPersistenceError)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), before, "opening a version 1 directory writes nothing")
    }

    // MARK: Storage keys

    func testEnumRawValuesAreStorageKeysAndStayAsTheyAre() {
        XCTAssertEqual(MuscleGroup.allCases.map { $0.rawValue }, ["Chest", "Back", "Shoulders", "Arms", "Legs", "Core"])
        XCTAssertEqual(Equipment.allCases.map { $0.rawValue }, ["Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight", "Other"])
        XCTAssertEqual(TrackingKind.allCases.map { $0.rawValue }, ["weightReps", "repsOnly", "duration"])
        XCTAssertEqual(SetType.allCases.map { $0.rawValue }, ["normal", "warmup", "drop", "failure"])
        XCTAssertEqual(WeighInInterval.allCases.map { $0.rawValue }, ["weekly", "everyTwoWeeks", "monthly"])
        XCTAssertEqual([BodyWeightSource.app, .health].map { $0.rawValue }, ["app", "health"])
    }

    func testEnumsAreWrittenAndReadByTheirRawValues() throws {
        for muscle in MuscleGroup.allCases {
            XCTAssertEqual(try decoder.decode(MuscleGroup.self, from: Data("\"\(muscle.rawValue)\"".utf8)), muscle)
            XCTAssertEqual(String(decoding: try encoder.encode([muscle]), as: UTF8.self), "[\"\(muscle.rawValue)\"]")
        }
        for equipment in Equipment.allCases {
            XCTAssertEqual(try decoder.decode(Equipment.self, from: Data("\"\(equipment.rawValue)\"".utf8)), equipment)
        }
        for tracking in TrackingKind.allCases {
            XCTAssertEqual(try decoder.decode(TrackingKind.self, from: Data("\"\(tracking.rawValue)\"".utf8)), tracking)
        }
        for type in SetType.allCases {
            XCTAssertEqual(try decoder.decode(SetType.self, from: Data("\"\(type.rawValue)\"".utf8)), type)
        }
    }

    func testAnExerciseIsWrittenWithTheStorageKeys() throws {
        let bench = try XCTUnwrap(ExerciseLibrary.exercise(id: "bench"))
        let text = String(decoding: try encoder.encode(bench), as: UTF8.self)
        for fragment in ["\"muscle\":\"Chest\"", "\"equipment\":\"Barbell\"", "\"tracking\":\"weightReps\""] {
            XCTAssertTrue(text.contains(fragment), fragment)
        }
        let set = String(decoding: try encoder.encode(CompletedSet(type: .warmup, weightKg: 20, reps: 5)), as: UTF8.self)
        XCTAssertTrue(set.contains("\"type\":\"warmup\""))
    }

    func testDisplayTextComesFromTitleNotFromTheRawValue() {
        // Today the titles equal the raw values for the muscle groups and the equipment; a localisation pass changes `title` only.
        XCTAssertEqual(MuscleGroup.chest.title, "Chest")
        XCTAssertEqual(Equipment.bodyweight.title, "Bodyweight")
        XCTAssertEqual(TrackingKind.weightReps.title, "Weight × reps")
        XCTAssertNotEqual(TrackingKind.weightReps.title, TrackingKind.weightReps.rawValue)
        XCTAssertEqual(SetType.warmup.title, "Warm-up")
        XCTAssertNotEqual(SetType.warmup.title, SetType.warmup.rawValue)
    }
}
