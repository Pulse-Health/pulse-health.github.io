import Foundation
import XCTest
@testable import PulseStrengthCore

final class LibraryTests: XCTestCase {

    // MARK: - Fixtures

    /// One row of the design table, reduced to the fields that are easy to compare in bulk.
    private struct Row {
        let id: String
        let muscle: MuscleGroup
        let equipment: Equipment
        let tracking: TrackingKind
        let media: String?
        let e1RM: Double
        let previousSetCount: Int
        let sets: Int
        let kg: Double
        let reps: Int
        let rest: Int
        let cueCount: Int
    }

    private func row(
        _ id: String, _ muscle: MuscleGroup, _ equipment: Equipment, _ tracking: TrackingKind, _ media: String?,
        _ e1RM: Double, _ previousSetCount: Int, _ sets: Int, _ kg: Double, _ reps: Int, _ rest: Int, _ cueCount: Int
    ) -> Row {
        Row(id: id, muscle: muscle, equipment: equipment, tracking: tracking, media: media, e1RM: e1RM,
            previousSetCount: previousSetCount, sets: sets, kg: kg, reps: reps, rest: rest, cueCount: cueCount)
    }

    /// All 36 rows of the design array `L`, in design order (id, muscle, equipment, tracking, media key,
    /// previous best e1RM, number of previous sets, default sets, kg, reps, rest, number of cues).
    private var designTable: [Row] {
        [
        row("bench", .chest, .barbell, .weightReps, "bench", 99, 5, 3, 60, 8, 150, 3),
        row("incline", .chest, .dumbbell, .weightReps, "incline", 38, 3, 3, 24, 10, 90, 3),
        row("crossover", .chest, .cable, .weightReps, "crossover", 22, 3, 3, 15, 12, 60, 3),
        row("pushup", .chest, .bodyweight, .repsOnly, "pushup", 0, 1, 3, 0, 12, 60, 3),
        row("cpress", .chest, .machine, .weightReps, nil, 0, 0, 3, 40, 10, 90, 2),
        row("dips", .chest, .bodyweight, .repsOnly, nil, 0, 0, 3, 0, 8, 90, 2),
        row("pullup", .back, .bodyweight, .repsOnly, "pullup", 0, 1, 3, 0, 8, 120, 3),
        row("pulldown", .back, .cable, .weightReps, "pulldown", 0, 1, 3, 50, 10, 90, 3),
        row("brow", .back, .barbell, .weightReps, "brow", 0, 1, 3, 50, 8, 120, 3),
        row("crow", .back, .cable, .weightReps, "crow", 0, 1, 3, 45, 10, 90, 3),
        row("dbrow", .back, .dumbbell, .weightReps, nil, 0, 0, 3, 24, 10, 90, 2),
        row("deadlift", .back, .barbell, .weightReps, "deadlift", 0, 1, 3, 80, 5, 180, 3),
        row("facepull", .shoulders, .cable, .weightReps, "facepull", 0, 1, 3, 20, 15, 60, 3),
        row("ohp", .shoulders, .barbell, .weightReps, "ohp", 58, 3, 3, 40, 8, 120, 3),
        row("dbpress", .shoulders, .dumbbell, .weightReps, nil, 0, 0, 3, 18, 10, 90, 2),
        row("lateral", .shoulders, .dumbbell, .weightReps, "lateral", 12.5, 3, 3, 8, 15, 60, 3),
        row("rdelt", .shoulders, .machine, .weightReps, nil, 0, 0, 3, 25, 12, 60, 2),
        row("curl", .arms, .barbell, .weightReps, "curl", 0, 1, 3, 30, 10, 75, 3),
        row("dbcurl", .arms, .dumbbell, .weightReps, "dbcurl", 0, 1, 3, 12, 10, 75, 3),
        row("hammer", .arms, .dumbbell, .weightReps, nil, 0, 0, 3, 12, 10, 75, 2),
        row("pushdown", .arms, .cable, .weightReps, "pushdown", 43, 3, 3, 30, 12, 60, 3),
        row("skull", .arms, .barbell, .weightReps, "skull", 0, 1, 3, 25, 10, 75, 3),
        row("ohtri", .arms, .cable, .weightReps, nil, 0, 0, 3, 20, 12, 60, 2),
        row("preacher", .arms, .machine, .weightReps, nil, 0, 0, 3, 25, 10, 75, 2),
        row("squat", .legs, .barbell, .weightReps, "squat", 0, 1, 3, 60, 6, 180, 3),
        row("legpress", .legs, .machine, .weightReps, "legpress", 0, 1, 3, 120, 10, 120, 3),
        row("rdl", .legs, .barbell, .weightReps, "rdl", 0, 1, 3, 60, 8, 120, 3),
        row("lunge", .legs, .dumbbell, .weightReps, nil, 0, 0, 3, 12, 10, 90, 2),
        row("legext", .legs, .machine, .weightReps, "legext", 0, 1, 3, 40, 12, 75, 3),
        row("legcurl", .legs, .machine, .weightReps, "legcurl", 0, 1, 3, 30, 12, 75, 3),
        row("calf", .legs, .machine, .weightReps, "calf", 0, 1, 4, 60, 12, 60, 3),
        row("hipthrust", .legs, .barbell, .weightReps, "hipthrust", 0, 1, 3, 70, 8, 90, 3),
        row("plank", .core, .bodyweight, .duration, "plank", 0, 1, 3, 0, 45, 45, 3),
        row("cablecrunch", .core, .cable, .weightReps, "cablecrunch", 0, 1, 3, 30, 15, 60, 3),
        row("hlr", .core, .bodyweight, .repsOnly, nil, 0, 0, 3, 0, 10, 60, 2),
        row("abwheel", .core, .other, .repsOnly, nil, 0, 0, 3, 0, 8, 60, 2),
        ]
    }

    /// The 25 media keys named in ARCHITECTURE.md.
    private let designMediaKeys: [String] = [
        "bench", "incline", "ohp", "lateral", "pushdown", "crossover", "pullup", "pulldown", "brow", "squat",
        "deadlift", "curl", "pushup", "legpress", "rdl", "plank", "hipthrust", "crow", "facepull", "dbcurl",
        "skull", "legcurl", "legext", "calf", "cablecrunch",
    ]

    /// The package root, found from this file: <root>/Tests/PulseStrengthCoreTests/LibraryTests.swift.
    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func ids(_ exercises: [Exercise]) -> [String] {
        exercises.map { $0.id }
    }

    private func filtered(_ query: String, _ muscle: MuscleGroup? = nil, _ equipment: Equipment? = nil) -> [String] {
        ids(ExerciseLibrary.filter(ExerciseLibrary.builtIn, query: query, muscle: muscle, equipment: equipment))
    }

    /// Asserts every field of `actual` against the hand-transcribed `expected` exercise.
    private func assertSame(
        _ actual: Exercise?, _ expected: Exercise, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let actual = actual else {
            XCTFail("exercise \(expected.id) is missing", file: file, line: line)
            return
        }
        let tag = expected.id
        XCTAssertEqual(actual.id, expected.id, "id \(tag)", file: file, line: line)
        XCTAssertEqual(actual.name, expected.name, "name \(tag)", file: file, line: line)
        XCTAssertEqual(actual.muscle, expected.muscle, "muscle \(tag)", file: file, line: line)
        XCTAssertEqual(actual.secondary, expected.secondary, "secondary \(tag)", file: file, line: line)
        XCTAssertEqual(actual.equipment, expected.equipment, "equipment \(tag)", file: file, line: line)
        XCTAssertEqual(actual.tracking, expected.tracking, "tracking \(tag)", file: file, line: line)
        XCTAssertEqual(actual.mediaKey, expected.mediaKey, "mediaKey \(tag)", file: file, line: line)
        // The library carries no history; the design's previous results are the explicit baseline of the tests (DesignBaseline).
        XCTAssertEqual(actual.previousBestE1RM, 0, "previousBestE1RM \(tag)", file: file, line: line)
        XCTAssertEqual(actual.previousSets, [], "previousSets \(tag)", file: file, line: line)
        let baseline = DesignBaseline.apply(actual)
        XCTAssertEqual(baseline.previousBestE1RM, expected.previousBestE1RM, "baseline previousBestE1RM \(tag)", file: file, line: line)
        XCTAssertEqual(baseline.previousSets, expected.previousSets, "baseline previousSets \(tag)", file: file, line: line)
        XCTAssertEqual(actual.defaults, expected.defaults, "defaults \(tag)", file: file, line: line)
        XCTAssertEqual(actual.cues, expected.cues, "cues \(tag)", file: file, line: line)
        XCTAssertEqual(actual.barKg, expected.barKg, "barKg \(tag)", file: file, line: line)
        XCTAssertEqual(actual.isCustom, expected.isCustom, "isCustom \(tag)", file: file, line: line)
    }

    private func sets(_ pairs: [(Double, Int)]) -> [PreviousSet] {
        pairs.map { PreviousSet(weightKg: $0.0, reps: $0.1) }
    }

    // MARK: - Library contents

    func testBuiltInHasExactly36Exercises() {
        XCTAssertEqual(ExerciseLibrary.builtIn.count, 36)
        XCTAssertEqual(designTable.count, 36)
    }

    func testIDsAreUnique() {
        let all = ids(ExerciseLibrary.builtIn)
        XCTAssertEqual(Set(all).count, all.count)
        XCTAssertFalse(all.contains(where: { $0.isEmpty }))
    }

    func testLibraryOrderMatchesDesign() {
        XCTAssertEqual(ids(ExerciseLibrary.builtIn), designTable.map { $0.id })
    }

    func testEveryRowMatchesDesignTable() {
        for (exercise, expected) in zip(ExerciseLibrary.builtIn, designTable) {
            let tag = expected.id
            XCTAssertEqual(exercise.id, expected.id, tag)
            XCTAssertEqual(exercise.muscle, expected.muscle, "muscle \(tag)")
            XCTAssertEqual(exercise.equipment, expected.equipment, "equipment \(tag)")
            XCTAssertEqual(exercise.tracking, expected.tracking, "tracking \(tag)")
            XCTAssertEqual(exercise.mediaKey, expected.media, "media \(tag)")
            XCTAssertEqual(exercise.previousBestE1RM, 0, "the library carries no best \(tag)")
            XCTAssertTrue(exercise.previousSets.isEmpty, "the library carries no previous sets \(tag)")
            let baseline = DesignBaseline.apply(exercise)
            XCTAssertEqual(baseline.previousBestE1RM, expected.e1RM, "baseline e1RM \(tag)")
            XCTAssertEqual(baseline.previousSets.count, expected.previousSetCount, "baseline previous sets \(tag)")
            XCTAssertEqual(exercise.defaults.sets, expected.sets, "default sets \(tag)")
            XCTAssertEqual(exercise.defaults.weightKg, expected.kg, "default kg \(tag)")
            XCTAssertEqual(exercise.defaults.reps, expected.reps, "default reps \(tag)")
            XCTAssertEqual(exercise.defaults.restSeconds, expected.rest, "default rest \(tag)")
            XCTAssertEqual(exercise.cues.count, expected.cueCount, "cue count \(tag)")
        }
    }

    func testBarWeightAndCustomFlag() {
        for exercise in ExerciseLibrary.builtIn {
            XCTAssertEqual(exercise.barKg, exercise.id == "skull" ? 10 : 20, exercise.id)
            XCTAssertFalse(exercise.isCustom, exercise.id)
        }
    }

    /// A new user starts without a PREVIOUS column and without a record to beat: the shipped library carries no history at all.
    func testTheLibraryShipsNoHistory() {
        for exercise in ExerciseLibrary.builtIn {
            XCTAssertEqual(exercise.previousBestE1RM, 0, exercise.id)
            XCTAssertTrue(exercise.previousSets.isEmpty, exercise.id)
        }
    }

    func testDataInvariants() {
        for exercise in DesignBaseline.library {
            XCTAssertFalse(exercise.name.isEmpty, exercise.id)
            XCTAssertFalse(exercise.secondary.isEmpty, exercise.id)
            XCTAssertGreaterThanOrEqual(exercise.cues.count, 2, exercise.id)
            XCTAssertFalse(exercise.cues.contains(where: { $0.isEmpty }), exercise.id)
            XCTAssertGreaterThan(exercise.defaults.sets, 0, exercise.id)
            XCTAssertGreaterThan(exercise.defaults.reps, 0, exercise.id)
            XCTAssertGreaterThanOrEqual(exercise.defaults.restSeconds, 0, exercise.id)
            if exercise.previousBestE1RM > 0 {
                XCTAssertEqual(exercise.tracking, .weightReps, exercise.id)
                XCTAssertFalse(exercise.previousSets.isEmpty, exercise.id)
            }
            if exercise.tracking != .weightReps {
                XCTAssertEqual(exercise.defaults.weightKg, 0, exercise.id)
                XCTAssertEqual(exercise.previousBestE1RM, 0, exercise.id)
            }
            if exercise.mediaKey == nil {
                XCTAssertTrue(exercise.previousSets.isEmpty, exercise.id)
            }
        }
    }

    func testExerciseLookup() {
        for exercise in ExerciseLibrary.builtIn {
            XCTAssertEqual(ExerciseLibrary.exercise(id: exercise.id), exercise)
        }
        XCTAssertEqual(ExerciseLibrary.exercise(id: "bench")?.name, "Barbell bench press")
        XCTAssertNil(ExerciseLibrary.exercise(id: "Bench"))
        XCTAssertNil(ExerciseLibrary.exercise(id: ""))
        XCTAssertNil(ExerciseLibrary.exercise(id: "custom-123"))
    }

    // MARK: - Spot checks against the prototype

    func testBenchPress() {
        assertSame(ExerciseLibrary.exercise(id: "bench"), Exercise(
            id: "bench", name: "Barbell bench press", muscle: .chest, secondary: "Shoulders · Triceps",
            equipment: .barbell, tracking: .weightReps, mediaKey: "bench", previousBestE1RM: 99,
            previousSets: sets([(50, 8), (70, 5), (80, 6), (80, 6), (80, 5)]),
            defaults: ExerciseDefaults(sets: 3, weightKg: 60, reps: 8, restSeconds: 150),
            cues: [
                "Pull your shoulder blades back and down and keep your feet planted.",
                "Lower the bar to mid-chest with your elbows about 45–60° from your body.",
                "Press up and slightly back until your arms are straight.",
            ],
            barKg: 20, isCustom: false))
    }

    func testInclineDumbbellPress() {
        assertSame(ExerciseLibrary.exercise(id: "incline"), Exercise(
            id: "incline", name: "Incline dumbbell press", muscle: .chest, secondary: "Shoulders · Triceps",
            equipment: .dumbbell, tracking: .weightReps, mediaKey: "incline", previousBestE1RM: 38,
            previousSets: sets([(26, 10), (26, 10), (26, 9)]),
            defaults: ExerciseDefaults(sets: 3, weightKg: 24, reps: 10, restSeconds: 90),
            cues: [
                "Set the bench to 30–45° and keep your back flat on the pad.",
                "Lower the dumbbells to chest level with your elbows under your wrists.",
                "Press up without letting the weights drift apart.",
            ],
            barKg: 20, isCustom: false))
    }

    func testPushUpIsRepsOnly() {
        assertSame(ExerciseLibrary.exercise(id: "pushup"), Exercise(
            id: "pushup", name: "Push-up", muscle: .chest, secondary: "Shoulders · Triceps",
            equipment: .bodyweight, tracking: .repsOnly, mediaKey: "pushup", previousBestE1RM: 0,
            previousSets: sets([(0, 15)]),
            defaults: ExerciseDefaults(sets: 3, weightKg: 0, reps: 12, restSeconds: 60),
            cues: [
                "Hands under your shoulders, body in one straight line.",
                "Lower your chest to just above the floor with your elbows about 45° out.",
                "Press back up without sagging at the hips.",
            ],
            barKg: 20, isCustom: false))
    }

    func testMachineChestPressHasNoMediaAndNoHistory() {
        assertSame(ExerciseLibrary.exercise(id: "cpress"), Exercise(
            id: "cpress", name: "Machine chest press", muscle: .chest, secondary: "Shoulders · Triceps",
            equipment: .machine, tracking: .weightReps, mediaKey: nil, previousBestE1RM: 0,
            previousSets: [],
            defaults: ExerciseDefaults(sets: 3, weightKg: 40, reps: 10, restSeconds: 90),
            cues: [
                "Set the seat so the handles line up with mid-chest.",
                "Press forward until your arms are almost straight, then return slowly.",
            ],
            barKg: 20, isCustom: false))
    }

    func testSkullCrusherUsesTenKiloBar() {
        assertSame(ExerciseLibrary.exercise(id: "skull"), Exercise(
            id: "skull", name: "Skull crusher", muscle: .arms, secondary: "Triceps · Forearms",
            equipment: .barbell, tracking: .weightReps, mediaKey: "skull", previousBestE1RM: 0,
            previousSets: sets([(25, 10)]),
            defaults: ExerciseDefaults(sets: 3, weightKg: 25, reps: 10, restSeconds: 75),
            cues: [
                "Lie on a bench holding the bar over your chest with straight arms.",
                "Bend only at the elbows to lower the bar toward your forehead.",
                "Extend back up without letting your elbows flare.",
            ],
            barKg: 10, isCustom: false))
    }

    func testPlankTracksDuration() {
        assertSame(ExerciseLibrary.exercise(id: "plank"), Exercise(
            id: "plank", name: "Plank", muscle: .core, secondary: "Abs",
            equipment: .bodyweight, tracking: .duration, mediaKey: "plank", previousBestE1RM: 0,
            previousSets: sets([(0, 45)]),
            defaults: ExerciseDefaults(sets: 3, weightKg: 0, reps: 45, restSeconds: 45),
            cues: [
                "Elbows under your shoulders, body in a straight line from head to heels.",
                "Squeeze your glutes and brace your abs.",
                "Breathe steadily and stop when your hips start to sag.",
            ],
            barKg: 20, isCustom: false))
    }

    func testStandingCalfRaiseHasFourDefaultSets() {
        assertSame(ExerciseLibrary.exercise(id: "calf"), Exercise(
            id: "calf", name: "Standing calf raise", muscle: .legs, secondary: "Calves",
            equipment: .machine, tracking: .weightReps, mediaKey: "calf", previousBestE1RM: 0,
            previousSets: sets([(60, 12)]),
            defaults: ExerciseDefaults(sets: 4, weightKg: 60, reps: 12, restSeconds: 60),
            cues: [
                "Place the balls of your feet on the platform with your heels hanging off.",
                "Rise as high as you can and pause at the top.",
                "Lower into a deep stretch before the next rep.",
            ],
            barKg: 20, isCustom: false))
    }

    func testLegExtensionKeepsApostrophes() {
        assertSame(ExerciseLibrary.exercise(id: "legext"), Exercise(
            id: "legext", name: "Leg extension", muscle: .legs, secondary: "Quads",
            equipment: .machine, tracking: .weightReps, mediaKey: "legext", previousBestE1RM: 0,
            previousSets: sets([(45, 12)]),
            defaults: ExerciseDefaults(sets: 3, weightKg: 40, reps: 12, restSeconds: 75),
            cues: [
                "Align your knees with the machine's pivot and sit back in the seat.",
                "Extend until your legs are straight and squeeze your quads.",
                "Lower under control and don't let the stack crash.",
            ],
            barKg: 20, isCustom: false))
    }

    func testLateralRaiseHasHistoryAndApostrophe() {
        assertSame(ExerciseLibrary.exercise(id: "lateral"), Exercise(
            id: "lateral", name: "Dumbbell lateral raise", muscle: .shoulders, secondary: "Side delts",
            equipment: .dumbbell, tracking: .weightReps, mediaKey: "lateral", previousBestE1RM: 12.5,
            previousSets: sets([(8, 15), (8, 15), (8, 14)]),
            defaults: ExerciseDefaults(sets: 3, weightKg: 8, reps: 15, restSeconds: 60),
            cues: [
                "Stand tall with a slight bend in your elbows.",
                "Raise the dumbbells out to the sides until they reach shoulder height.",
                "Lower slowly and don't swing your torso.",
            ],
            barKg: 20, isCustom: false))
    }

    func testAbWheelIsOtherEquipment() {
        assertSame(ExerciseLibrary.exercise(id: "abwheel"), Exercise(
            id: "abwheel", name: "Ab wheel rollout", muscle: .core, secondary: "Shoulders",
            equipment: .other, tracking: .repsOnly, mediaKey: nil, previousBestE1RM: 0,
            previousSets: [],
            defaults: ExerciseDefaults(sets: 3, weightKg: 0, reps: 8, restSeconds: 60),
            cues: [
                "Start on your knees with the wheel under your shoulders.",
                "Roll out as far as you can keep your back flat, then pull back in.",
            ],
            barKg: 20, isCustom: false))
    }

    func testPersonalBestsOfTheDesign() {
        let expected: [String: Double] = [
            "bench": 99, "incline": 38, "crossover": 22, "ohp": 58, "lateral": 12.5, "pushdown": 43,
        ]
        for exercise in ExerciseLibrary.builtIn {
            XCTAssertEqual(exercise.previousBestE1RM, 0, "the library carries no best \(exercise.id)")
        }
        for exercise in DesignBaseline.library {
            XCTAssertEqual(exercise.previousBestE1RM, expected[exercise.id] ?? 0, exercise.id)
        }
    }

    func testDerivedBehaviourOfLibraryEntries() {
        XCTAssertEqual(ExerciseLibrary.exercise(id: "bench")?.weightStepKg, 2.5)
        XCTAssertEqual(ExerciseLibrary.exercise(id: "incline")?.weightStepKg, 2)
        XCTAssertEqual(ExerciseLibrary.exercise(id: "plank")?.repsStep, 5)
        XCTAssertEqual(ExerciseLibrary.exercise(id: "bench")?.supportsPlates, true)
        XCTAssertEqual(ExerciseLibrary.exercise(id: "legpress")?.supportsPlates, false)
        XCTAssertEqual(ExerciseLibrary.exercise(id: "pullup")?.tracksWeight, false)
    }

    // MARK: - Media keys and frames

    func testExactly25DistinctMediaKeys() {
        let keys = ExerciseLibrary.builtIn.compactMap { $0.mediaKey }
        XCTAssertEqual(Set(keys).count, 25)
        XCTAssertEqual(keys.count, 25, "each media key belongs to exactly one exercise")
        XCTAssertEqual(Set(designMediaKeys).count, 25)
        XCTAssertEqual(Set(keys), Set(designMediaKeys))
    }

    func testMediaKeysMatchesBuiltIn() {
        XCTAssertEqual(ExerciseLibrary.mediaKeys, ExerciseLibrary.builtIn.compactMap { $0.mediaKey })
        XCTAssertEqual(ExerciseLibrary.mediaKeys.count, 25)
        XCTAssertEqual(Set(ExerciseLibrary.mediaKeys).count, 25)
        XCTAssertEqual(Set(ExerciseLibrary.mediaKeys), Set(designMediaKeys))
    }

    func testEveryMediaKeyHasBothFramesOnDisk() throws {
        let directory = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("PulseStrengthIOS")
            .appendingPathComponent("Resources")
            .appendingPathComponent("ExerciseMedia")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue,
            "missing directory \(directory.path)")
        for key in ExerciseLibrary.mediaKeys {
            for frame in ["a", "b"] {
                let file = directory.appendingPathComponent("\(key)-\(frame).jpg")
                XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "missing \(key)-\(frame).jpg")
                let data = try Data(contentsOf: file)
                XCTAssertGreaterThan(data.count, 1000, "\(key)-\(frame).jpg is too small")
                XCTAssertEqual(Array(data.prefix(2)), [0xFF, 0xD8], "\(key)-\(frame).jpg is not a JPEG")
            }
        }
    }

    // MARK: - Filter

    func testBlankFilterReturnsEverythingSortedByName() {
        let expected = [
            "abwheel", "squat", "bench", "curl", "brow", "crossover", "cablecrunch", "dips", "deadlift",
            "dbcurl", "lateral", "dbpress", "facepull", "hammer", "hlr", "hipthrust", "incline", "pulldown",
            "legext", "legpress", "legcurl", "cpress", "dbrow", "ohp", "ohtri", "plank", "preacher", "pullup",
            "pushup", "rdelt", "rdl", "crow", "skull", "calf", "pushdown", "lunge",
        ]
        XCTAssertEqual(expected.count, 36)
        XCTAssertEqual(filtered(""), expected)
        XCTAssertEqual(filtered("   \t\n "), expected)
        XCTAssertEqual(filtered("", nil, nil), expected)
    }

    func testSingleTokenMatchesNameMuscleEquipmentAndSecondary() {
        XCTAssertEqual(filtered("bench"), ["bench"])
        XCTAssertEqual(filtered("press"), ["bench", "dbpress", "incline", "legpress", "cpress", "ohp"])
        XCTAssertEqual(filtered("side"), ["lateral"], "secondary text is searched")
        XCTAssertEqual(filtered("calves"), ["calf"], "secondary text is searched")
        XCTAssertEqual(filtered("cable"), ["crossover", "cablecrunch", "facepull", "pulldown", "ohtri", "crow", "pushdown"])
        XCTAssertEqual(filtered("bodyweight"), ["dips", "hlr", "plank", "pullup", "pushup"], "equipment is searched")
        XCTAssertEqual(filtered("core"), ["abwheel", "cablecrunch", "hlr", "plank"], "muscle is searched")
        XCTAssertEqual(filtered("other"), ["abwheel"])
    }

    func testMuscleTextMatchesBeyondTheName() {
        // "leg" is in four names; "Legs" is the muscle of eight exercises; Hanging leg raise is the only overlap.
        XCTAssertEqual(filtered("leg").count, 9)
        XCTAssertTrue(filtered("leg").contains("hlr"))
        XCTAssertEqual(filtered("legs").count, 8)
        XCTAssertFalse(filtered("legs").contains("hlr"))
    }

    func testAllTokensMustMatchInAnyOrderAcrossFields() {
        XCTAssertEqual(filtered("press chest"), ["bench", "incline", "cpress"])
        XCTAssertEqual(filtered("chest press"), ["bench", "incline", "cpress"])
        XCTAssertEqual(filtered("triceps barbell"), ["bench", "ohp", "skull"])
        XCTAssertEqual(filtered("barbell triceps"), ["bench", "ohp", "skull"])
        XCTAssertEqual(filtered("press chest zzz"), [])
        XCTAssertEqual(filtered("zzz"), [])
        XCTAssertEqual(filtered("bench dumbbell"), [])
    }

    func testTokensAreSplitOnAnyWhitespaceAndIgnoreCase() {
        let expected = ["bench", "incline", "cpress"]
        XCTAssertEqual(filtered("  chest \t press\n"), expected)
        XCTAssertEqual(filtered("CHEST PRESS"), expected)
        XCTAssertEqual(filtered("ChEsT   pReSs"), expected)
        XCTAssertEqual(filtered("BENCH"), ["bench"])
        XCTAssertEqual(filtered("  bench  "), ["bench"])
    }

    func testPartialTokensMatchAsSubstrings() {
        XCTAssertEqual(filtered("benc"), ["bench"])
        XCTAssertEqual(filtered("ench"), ["bench"])
        XCTAssertEqual(filtered("pushd"), ["pushdown"])
        XCTAssertEqual(filtered("dumb curl"), ["dbcurl", "hammer"])
    }

    func testMuscleFilter() {
        XCTAssertEqual(filtered("", .core), ["abwheel", "cablecrunch", "hlr", "plank"])
        XCTAssertEqual(filtered("", .shoulders), ["lateral", "dbpress", "facepull", "ohp", "rdelt"])
        let counts: [(MuscleGroup, Int)] = [
            (.chest, 6), (.back, 6), (.shoulders, 5), (.arms, 7), (.legs, 8), (.core, 4),
        ]
        XCTAssertEqual(counts.reduce(0) { $0 + $1.1 }, 36)
        for (muscle, count) in counts {
            let result = ExerciseLibrary.filter(ExerciseLibrary.builtIn, query: "", muscle: muscle, equipment: nil)
            XCTAssertEqual(result.count, count, muscle.title)
            XCTAssertTrue(result.allSatisfy { $0.muscle == muscle }, muscle.title)
        }
    }

    func testEquipmentFilter() {
        XCTAssertEqual(filtered("", nil, .other), ["abwheel"])
        XCTAssertEqual(filtered("", nil, .bodyweight), ["dips", "hlr", "plank", "pullup", "pushup"])
        let counts: [(Equipment, Int)] = [
            (.barbell, 9), (.dumbbell, 7), (.cable, 7), (.machine, 7), (.bodyweight, 5), (.other, 1),
        ]
        XCTAssertEqual(counts.reduce(0) { $0 + $1.1 }, 36)
        for (equipment, count) in counts {
            let result = ExerciseLibrary.filter(ExerciseLibrary.builtIn, query: "", muscle: nil, equipment: equipment)
            XCTAssertEqual(result.count, count, equipment.title)
            XCTAssertTrue(result.allSatisfy { $0.equipment == equipment }, equipment.title)
        }
    }

    func testMuscleEquipmentAndQueryCombine() {
        XCTAssertEqual(filtered("", .arms, .barbell), ["curl", "skull"])
        XCTAssertEqual(filtered("curl", .arms), ["curl", "dbcurl", "hammer", "preacher"])
        XCTAssertEqual(filtered("curl", .legs), ["legcurl"])
        XCTAssertEqual(filtered("curl", .arms, .dumbbell), ["dbcurl", "hammer"])
        XCTAssertEqual(filtered("curl", .chest), [])
        XCTAssertEqual(filtered("", .core, .barbell), [])
        XCTAssertEqual(filtered("press", .shoulders, .barbell), ["ohp"])
    }

    func testResultsAreSortedByNameIgnoringCaseThenID() {
        func make(_ id: String, _ name: String, secondary: String = "") -> Exercise {
            Exercise.custom(name: name, muscle: .chest, equipment: .other, tracking: .weightReps, id: id)
                .withLibraryTestSecondary(secondary)
        }
        let pool = [
            make("x3", "banana"), make("x2", "apple"), make("x1", "Apple"),
            make("x4", "Cherry"), make("x0", "apple"), make("y", "Zucchini"),
        ]
        let sorted = ExerciseLibrary.filter(pool, query: "", muscle: nil, equipment: nil)
        XCTAssertEqual(ids(sorted), ["x0", "x1", "x2", "x3", "x4", "y"])
        // The input order must not matter.
        XCTAssertEqual(ids(ExerciseLibrary.filter(pool.reversed(), query: "", muscle: nil, equipment: nil)), ids(sorted))
        // Plain code unit ordering would put "Cherry" and "Zucchini" before "apple".
        XCTAssertEqual(ids(sorted).firstIndex(of: "x4"), 4)
    }

    func testIdenticalNameAndIDKeepInputOrder() {
        let first = Exercise.custom(name: "Twin", muscle: .back, equipment: .cable, tracking: .weightReps, id: "same")
            .withLibraryTestSecondary("first")
        let second = Exercise.custom(name: "Twin", muscle: .back, equipment: .cable, tracking: .weightReps, id: "same")
            .withLibraryTestSecondary("second")
        XCTAssertEqual(
            ExerciseLibrary.filter([first, second], query: "", muscle: nil, equipment: nil).map { $0.secondary },
            ["first", "second"])
        XCTAssertEqual(
            ExerciseLibrary.filter([second, first], query: "", muscle: nil, equipment: nil).map { $0.secondary },
            ["second", "first"])
    }

    func testFilterSearchesTheGivenListIncludingCustomExercises() {
        let custom = Exercise.custom(
            name: "Zercher squat", muscle: .legs, equipment: .barbell, tracking: .weightReps, id: "custom-zercher")
        let pool = ExerciseLibrary.builtIn + [custom]
        let result = ExerciseLibrary.filter(pool, query: "squat", muscle: nil, equipment: nil)
        XCTAssertEqual(ids(result), ["squat", "custom-zercher"])
        XCTAssertEqual(ids(ExerciseLibrary.filter(pool, query: "custom", muscle: nil, equipment: nil)), ["custom-zercher"],
                       "the Custom secondary text is searched")
        XCTAssertEqual(ExerciseLibrary.filter([], query: "squat", muscle: nil, equipment: nil), [])
        XCTAssertEqual(ExerciseLibrary.filter([], query: "", muscle: .legs, equipment: .barbell), [])
    }

    func testFilterIgnoresCaseOfNonASCIIText() {
        let custom = Exercise.custom(
            name: "Écarté couché", muscle: .chest, equipment: .dumbbell, tracking: .weightReps, id: "custom-ecarte")
        XCTAssertEqual(ids(ExerciseLibrary.filter([custom], query: "écarté", muscle: nil, equipment: nil)), ["custom-ecarte"])
        XCTAssertEqual(ids(ExerciseLibrary.filter([custom], query: "ÉCARTÉ COUCHÉ", muscle: nil, equipment: nil)), ["custom-ecarte"])
    }

    func testFilterDoesNotChangeTheLibrary() {
        let before = ExerciseLibrary.builtIn
        _ = filtered("press", .chest, .barbell)
        XCTAssertEqual(ExerciseLibrary.builtIn, before)
    }

    func testFilterAgreesWithAnIndependentOracleOnRandomQueries() {
        let pool = [
            "press", "bench", "curl", "cable", "dumbbell", "chest", "legs", "triceps", "·", "raise", "BAR",
            "side", "x", "e", "up", "Core", "mach", "  ", "zz",
        ]
        var rng = LibraryFuzzRNG(seed: 20251013)
        for _ in 0..<300 {
            let tokenCount = rng.next(below: 4)
            let query = (0..<tokenCount).map { _ in pool[rng.next(below: pool.count)] }.joined(separator: " ")
            let muscle: MuscleGroup? = rng.next(below: 3) == 0 ? MuscleGroup.allCases[rng.next(below: 6)] : nil
            let equipment: Equipment? = rng.next(below: 3) == 0 ? Equipment.allCases[rng.next(below: 6)] : nil
            let result = ExerciseLibrary.filter(ExerciseLibrary.builtIn, query: query, muscle: muscle, equipment: equipment)
            let tokens = query.split(whereSeparator: { $0 == " " }).map(String.init)
            var expected: [Exercise] = []
            for exercise in ExerciseLibrary.builtIn {
                if let muscle = muscle, exercise.muscle != muscle { continue }
                if let equipment = equipment, exercise.equipment != equipment { continue }
                let text = "\(exercise.name) \(exercise.muscle.rawValue) \(exercise.equipment.rawValue) \(exercise.secondary)"
                if tokens.allSatisfy({ text.range(of: $0, options: .caseInsensitive) != nil }) { expected.append(exercise) }
            }
            XCTAssertEqual(Set(ids(result)), Set(ids(expected)), "query '\(query)' \(String(describing: muscle)) \(String(describing: equipment))")
            XCTAssertEqual(result.count, expected.count)
            let names = result.map { $0.name.lowercased() }
            XCTAssertEqual(names, names.sorted(), "query '\(query)'")
        }
    }
}

// MARK: - Helpers

private extension Exercise {
    /// A copy with the given secondary text.
    func withLibraryTestSecondary(_ text: String) -> Exercise {
        var copy = self
        copy.secondary = text
        return copy
    }
}

/// Seeded linear congruential generator, so the fuzz tests are deterministic.
private struct LibraryFuzzRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 11
    }

    /// A value in 0..<bound.
    mutating func next(below bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }
}
