import Foundation
import XCTest
@testable import PulseStrengthCore

/// Builders for finished workouts with deterministic ids.
enum SvcDataFix {
    static let now = SvcSyncFix.epoch

    static func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    static func work(_ kg: Double, _ reps: Int, rir: Int? = nil) -> CompletedSet {
        CompletedSet(type: .normal, weightKg: kg, reps: reps, rir: rir)
    }

    static func warmup(_ kg: Double, _ reps: Int) -> CompletedSet {
        CompletedSet(type: .warmup, weightKg: kg, reps: reps)
    }

    /// An entry for a built-in exercise; `best` overrides the recorded e1RM (nil = the real best of the working sets).
    static func entry(_ exerciseID: String, _ sets: [CompletedSet], best: Double? = nil, pr: Bool = false, n: Int = 0) -> CompletedExercise {
        let exercise = ExerciseLibrary.exercise(id: exerciseID)!
        let computed = exercise.tracksWeight
            ? sets.filter { $0.type != .warmup }.map { Estimated1RM.epley(weightKg: $0.weightKg, reps: $0.reps) }.max() ?? 0
            : 0
        return CompletedExercise(
            id: SvcSyncFix.uuid(5000 + n), exerciseID: exerciseID, name: exercise.name, muscle: exercise.muscle,
            mediaKey: exercise.mediaKey, tracking: exercise.tracking, sets: sets, isPersonalRecord: pr, bestE1RM: best ?? computed
        )
    }

    static func workout(
        _ n: Int, name: String = "Upper A · Push", templateID: UUID? = nil, finishedAt: Date, _ entries: [CompletedExercise]
    ) -> CompletedWorkout {
        CompletedWorkout(
            id: SvcSyncFix.uuid(n), name: name, templateID: templateID, startedAt: finishedAt.addingTimeInterval(-3000), finishedAt: finishedAt,
            durationSeconds: 3000, volumeKg: 0, loggedSets: entries.reduce(0) { $0 + $1.sets.count }, averageHeartRate: nil,
            averageRIR: nil, exercises: entries, personalRecords: [], muscleSets: []
        )
    }

    static func customExercise(_ name: String, _ tracking: TrackingKind = .weightReps) -> Exercise {
        Exercise.custom(name: name, muscle: .arms, equipment: .dumbbell, tracking: tracking, id: "custom-" + name.lowercased())
    }
}

final class StrengthDataTests: XCTestCase {
    private typealias F = SvcDataFix

    // MARK: Exercises and overlay

    func testWithoutResultsTheLibraryIsReturnedUnchanged() {
        let data = StrengthData()
        XCTAssertEqual(data.exercises(), ExerciseLibrary.builtIn)
        XCTAssertEqual(data.exercises().count, 36)
        XCTAssertEqual(data.exercise(id: "bench"), ExerciseLibrary.exercise(id: "bench"))
        XCTAssertNil(data.exercise(id: "nope"))
        XCTAssertTrue(data.isEmpty)
    }

    func testAPersonalBestOverridesThePreviousBest() throws {
        var data = StrengthData()
        data.personalBests["bench"] = PersonalBest(exerciseID: "bench", estimated1RM: 120, weightKg: 100, reps: 6, date: F.now)
        data.personalBests["incline"] = PersonalBest(exerciseID: "incline", estimated1RM: 10, weightKg: 8, reps: 8, date: F.now)
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "bench")).previousBestE1RM, 120)
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "incline")).previousBestE1RM, 10, "what is remembered wins")
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "ohp")).previousBestE1RM, 0, "untouched exercises have no previous best: the library carries no history")
        var expected = try XCTUnwrap(ExerciseLibrary.exercise(id: "bench"))
        expected.previousBestE1RM = 120
        XCTAssertEqual(data.exercise(id: "bench"), expected)
    }

    func testHistoryProvidesTheBestAndThePreviousSets() throws {
        var data = StrengthData()
        data.history = [F.workout(1, name: "Lower", finishedAt: F.daysAgo(2), [F.entry("squat", [F.warmup(40, 8), F.work(80, 6), F.work(90, 4)], n: 1)])]
        let squat = try XCTUnwrap(data.exercise(id: "squat"))
        XCTAssertEqual(squat.previousSets, [PreviousSet(weightKg: 40, reps: 8), PreviousSet(weightKg: 80, reps: 6), PreviousSet(weightKg: 90, reps: 4)])
        XCTAssertEqual(squat.previousBestE1RM, 102, accuracy: 1e-9)       // 90 x 4 (102) beats 80 x 6 (96); the warm-up is ignored
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "legpress")), ExerciseLibrary.exercise(id: "legpress"))
    }

    func testThePreviousSetsComeFromTheNewestSessionWhateverTheArrayOrder() throws {
        var data = StrengthData()
        let older = F.workout(1, finishedAt: F.daysAgo(9), [F.entry("bench", [F.work(70, 8)], n: 1)])
        let newer = F.workout(2, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(75, 6)], n: 2)])
        data.history = [older, newer]
        XCTAssertEqual(data.exercise(id: "bench")?.previousSets, [PreviousSet(weightKg: 75, reps: 6)])
        data.history = [newer, older]
        XCTAssertEqual(data.exercise(id: "bench")?.previousSets, [PreviousSet(weightKg: 75, reps: 6)])
        // The best comes from every session: 75 x 6 = 90 beats 70 x 8 = 88.67.
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "bench")).previousBestE1RM, 90, accuracy: 1e-9)
        // What the user did replaces whatever the exercise carried, even a higher value (here the design's baseline of 99).
        let carried = try XCTUnwrap(DesignBaseline.exercise(id: "bench"))
        XCTAssertEqual(carried.previousBestE1RM, 99)
        let overlaid = data.overlay(carried)
        XCTAssertEqual(overlaid.previousBestE1RM, 90, accuracy: 1e-9)
        XCTAssertEqual(overlaid.previousSets, [PreviousSet(weightKg: 75, reps: 6)])
    }

    func testTheHistoryBestWinsOverALowerPersonalBestAndViceVersa() throws {
        var data = StrengthData()
        data.history = [F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(100, 3)], n: 1)])]   // 110
        data.personalBests["bench"] = PersonalBest(exerciseID: "bench", estimated1RM: 105, weightKg: 100, reps: 1, date: F.daysAgo(40))
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "bench")).previousBestE1RM, 110, accuracy: 1e-9)
        data.personalBests["bench"] = PersonalBest(exerciseID: "bench", estimated1RM: 130, weightKg: 110, reps: 1, date: F.daysAgo(40))
        XCTAssertEqual(try XCTUnwrap(data.exercise(id: "bench")).previousBestE1RM, 130, accuracy: 1e-9)
    }

    func testEntriesWithoutSetsDoNotReplaceThePreviousSets() throws {
        var data = StrengthData()
        data.history = [F.workout(1, finishedAt: F.daysAgo(1), [F.entry("bench", [], n: 1)])]
        // An exercise that carries previous sets (the design's baseline here) keeps them when the only session has no sets.
        let carried = try XCTUnwrap(DesignBaseline.exercise(id: "bench"))
        XCTAssertFalse(carried.previousSets.isEmpty)
        XCTAssertEqual(data.overlay(carried).previousSets, carried.previousSets)
        XCTAssertEqual(data.exercise(id: "bench")?.previousSets, [], "the library itself carries none")
    }

    func testTheSameExerciseTwiceInOneWorkoutIsMerged() throws {
        var data = StrengthData()
        data.history = [F.workout(1, finishedAt: F.daysAgo(1), [
            F.entry("bench", [F.work(60, 10)], n: 1), F.entry("incline", [F.work(20, 10)], n: 2), F.entry("bench", [F.work(65, 8)], n: 3),
        ])]
        XCTAssertEqual(data.exercise(id: "bench")?.previousSets, [PreviousSet(weightKg: 60, reps: 10), PreviousSet(weightKg: 65, reps: 8)])
    }

    func testCustomExercisesFollowTheLibraryAndGetTheOverlayToo() throws {
        var data = StrengthData()
        let curl = F.customExercise("Zottman curl")
        data.addCustomExercise(curl)
        data.history = [F.workout(1, finishedAt: F.daysAgo(1), [
            CompletedExercise(exerciseID: curl.id, name: curl.name, muscle: .arms, mediaKey: nil, tracking: .weightReps,
                              sets: [F.work(14, 10)], isPersonalRecord: false, bestE1RM: 0),
        ])]
        let all = data.exercises()
        XCTAssertEqual(all.count, 37)
        XCTAssertEqual(all.last?.id, curl.id)
        let overlaid = try XCTUnwrap(data.exercise(id: curl.id))
        XCTAssertEqual(overlaid.previousSets, [PreviousSet(weightKg: 14, reps: 10)])
        XCTAssertEqual(overlaid.previousBestE1RM, 14 * (1 + 10.0 / 30), accuracy: 1e-9, "computed from the sets when the entry recorded none")
        XCTAssertTrue(overlaid.isCustom)
    }

    func testCustomExercisesMustNotShadowBuiltInIds() {
        var data = StrengthData()
        var impostor = F.customExercise("Fake bench")
        impostor.id = "bench"
        data.addCustomExercise(impostor)
        XCTAssertTrue(data.customExercises.isEmpty)
        data.customExercises = [impostor]          // e.g. loaded from a damaged file
        XCTAssertEqual(data.exercises().count, 36)
        XCTAssertEqual(data.exercise(id: "bench"), ExerciseLibrary.exercise(id: "bench"))
    }

    func testAddingACustomExerciseMarksItCustomAndReplacesById() {
        var data = StrengthData()
        var first = F.customExercise("Landmine press")
        first.isCustom = false
        data.addCustomExercise(first)
        XCTAssertEqual(data.customExercises.map { $0.isCustom }, [true])
        var renamed = first
        renamed.name = "Landmine press (heavy)"
        data.addCustomExercise(renamed)
        data.addCustomExercise(F.customExercise("Sled push"))
        XCTAssertEqual(data.customExercises.map { $0.name }, ["Landmine press (heavy)", "Sled push"])
    }

    // MARK: Templates

    func testSaveTemplateInsertsThenReplacesInPlace() {
        var data = StrengthData(templates: SampleData.templates())
        var edited = data.templates[1]
        edited.name = "Lower A · Quads (new)"
        data.saveTemplate(edited)
        XCTAssertEqual(data.templates.map { $0.name }, ["Upper A · Push", "Lower A · Quads (new)", "Upper B · Pull"])
        let extra = WorkoutTemplate(id: SvcSyncFix.uuid(77), name: "Arms", entries: [])
        data.saveTemplate(extra)
        XCTAssertEqual(data.templates.count, 4)
        XCTAssertEqual(data.templates.last, extra)
        XCTAssertEqual(data.template(id: extra.id), extra)
        XCTAssertNil(data.template(id: SvcSyncFix.uuid(78)))
    }

    // MARK: Recording

    func testRecordInsertsNewestFirst() {
        var data = StrengthData()
        let a = F.workout(1, finishedAt: F.daysAgo(5), [F.entry("bench", [F.work(80, 5)], n: 1)])
        let b = F.workout(2, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(80, 5)], n: 2)])
        let c = F.workout(3, finishedAt: F.daysAgo(3), [F.entry("bench", [F.work(80, 5)], n: 3)])
        for workout in [a, b, c] { data.record(workout, updateTemplate: nil) }
        XCTAssertEqual(data.history.map { $0.id }, [b.id, c.id, a.id])
    }

    func testRecordingTheSameWorkoutTwiceReplacesIt() {
        var data = StrengthData()
        let first = F.workout(1, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(80, 5)], n: 1)])
        var edited = first
        edited.name = "Edited"
        data.record(first, updateTemplate: nil)
        data.record(edited, updateTemplate: nil)
        XCTAssertEqual(data.history, [edited])
    }

    func testPersonalBestIsCreatedAndOnlyRaisedWhenBeaten() throws {
        var data = StrengthData()
        data.record(F.workout(1, finishedAt: F.daysAgo(10), [F.entry("bench", [F.warmup(120, 3), F.work(80, 6), F.work(85, 5)], n: 1)]), updateTemplate: nil)
        var best = try XCTUnwrap(data.personalBests["bench"])
        XCTAssertEqual(best.exerciseID, "bench")
        XCTAssertEqual(best.estimated1RM, 85 * (1 + 5.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(best.weightKg, 85, "the warm-up with more weight is not the best set")
        XCTAssertEqual(best.reps, 5)
        XCTAssertEqual(best.date, F.daysAgo(10))

        // Equal estimate: unchanged (strictly greater is required).
        data.record(F.workout(2, finishedAt: F.daysAgo(5), [F.entry("bench", [F.work(85, 5)], n: 2)]), updateTemplate: nil)
        XCTAssertEqual(data.personalBests["bench"], best)
        // Lower: unchanged.
        data.record(F.workout(3, finishedAt: F.daysAgo(4), [F.entry("bench", [F.work(80, 6)], n: 3)]), updateTemplate: nil)
        XCTAssertEqual(data.personalBests["bench"], best)
        // Higher: raised, with the new set and date.
        data.record(F.workout(4, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(87.5, 5)], n: 4)]), updateTemplate: nil)
        best = try XCTUnwrap(data.personalBests["bench"])
        XCTAssertEqual(best.estimated1RM, 87.5 * (1 + 5.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(best.weightKg, 87.5)
        XCTAssertEqual(best.date, F.daysAgo(1))
    }

    func testEveryExerciseOfAWorkoutIsConsidered() {
        var data = StrengthData()
        data.record(F.workout(1, finishedAt: F.daysAgo(1), [
            F.entry("bench", [F.work(80, 5)], n: 1), F.entry("squat", [F.work(100, 5)], n: 2),
            F.entry("pullup", [F.work(0, 12)], n: 3), F.entry("plank", [F.work(0, 60)], n: 4),
        ]), updateTemplate: nil)
        XCTAssertEqual(Set(data.personalBests.keys), ["bench", "squat"], "bodyweight and duration exercises have no e1RM")
    }

    func testTheRecordedEstimateIsUsedAndAZeroOneIsComputedFromTheSets() throws {
        var data = StrengthData()
        data.record(F.workout(1, finishedAt: F.daysAgo(2), [F.entry("bench", [F.work(80, 5)], best: 120, n: 1)]), updateTemplate: nil)
        XCTAssertEqual(try XCTUnwrap(data.personalBests["bench"]).estimated1RM, 120)
        data.record(F.workout(2, finishedAt: F.daysAgo(1), [F.entry("squat", [F.warmup(60, 5), F.work(100, 3)], best: 0, n: 2)]), updateTemplate: nil)
        XCTAssertEqual(try XCTUnwrap(data.personalBests["squat"]).estimated1RM, 110, accuracy: 1e-9)
        data.record(F.workout(3, finishedAt: F.daysAgo(1), [F.entry("deadlift", [F.warmup(100, 5)], best: 0, n: 3)]), updateTemplate: nil)
        XCTAssertNil(data.personalBests["deadlift"], "warm-ups alone never set a best")
    }

    func testRecordSetsLastPerformedOfTheWorkoutsTemplate() throws {
        var data = StrengthData(templates: SampleData.templates(now: F.now))
        let upper = data.templates[0]
        XCTAssertEqual(upper.lastPerformed, F.daysAgo(5))
        data.record(F.workout(1, templateID: upper.id, finishedAt: F.daysAgo(0.5), [F.entry("bench", [F.work(80, 5)], n: 1)]), updateTemplate: nil)
        XCTAssertEqual(data.templates[0].lastPerformed, F.daysAgo(0.5))
        XCTAssertEqual(data.templates[1].lastPerformed, F.daysAgo(7), "other templates are untouched")
        // An older workout never moves lastPerformed backwards.
        data.record(F.workout(2, templateID: upper.id, finishedAt: F.daysAgo(30), [F.entry("bench", [F.work(60, 5)], n: 2)]), updateTemplate: nil)
        XCTAssertEqual(data.templates[0].lastPerformed, F.daysAgo(0.5))
        // A workout of an unknown template changes no template.
        let before = data.templates
        data.record(F.workout(3, templateID: SvcSyncFix.uuid(999), finishedAt: F.daysAgo(0.1), [F.entry("bench", [F.work(60, 5)], n: 3)]), updateTemplate: nil)
        XCTAssertEqual(data.templates, before)
    }

    func testRecordWithAnUpdatedTemplateReplacesTheStoredOne() throws {
        var data = StrengthData(templates: SampleData.templates())
        var updated = data.templates[0]
        updated.entries.removeLast()
        XCTAssertEqual(updated.lastPerformed, nil)
        data.record(F.workout(1, templateID: updated.id, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(80, 5)], n: 1)]), updateTemplate: updated)
        XCTAssertEqual(data.templates.count, 3)
        XCTAssertEqual(data.templates[0].id, updated.id)
        XCTAssertEqual(data.templates[0].entries, updated.entries)
        XCTAssertEqual(data.templates[0].lastPerformed, F.daysAgo(1))
        XCTAssertEqual(data.templates.map { $0.name }, ["Upper A · Push", "Lower A · Quads", "Upper B · Pull"], "position is kept")
    }

    func testRecordWithATemplateThatIsNotStoredYetAddsIt() {
        var data = StrengthData()
        let template = SampleData.templates()[2]
        data.record(F.workout(1, finishedAt: F.daysAgo(1), [F.entry("bench", [F.work(80, 5)], n: 1)]), updateTemplate: template)
        XCTAssertEqual(data.templates.map { $0.id }, [template.id])
        XCTAssertEqual(data.templates[0].lastPerformed, F.daysAgo(1))
    }

    // MARK: Seeding

    func testSeedingFillsAnEmptyStoreOnce() {
        var data = StrengthData()
        XCTAssertTrue(data.seedDemoDataIfEmpty(now: F.now))
        XCTAssertEqual(data.templates.count, 3)
        XCTAssertEqual(data.history.count, 5)
        XCTAssertFalse(data.personalBests.isEmpty)
        XCTAssertFalse(data.isEmpty)
        let seeded = data
        XCTAssertFalse(data.seedDemoDataIfEmpty(now: F.now.addingTimeInterval(86_400)))
        XCTAssertEqual(data, seeded)
    }

    func testSeedingKeepsExistingBestsAndRefusesANonEmptyStore() {
        let mine = PersonalBest(exerciseID: "bench", estimated1RM: 140, weightKg: 120, reps: 5, date: F.now)
        var onlyBests = StrengthData(personalBests: ["bench": mine])
        XCTAssertTrue(onlyBests.seedDemoDataIfEmpty(now: F.now))
        XCTAssertEqual(onlyBests.personalBests, ["bench": mine])

        var withTemplate = StrengthData(templates: [WorkoutTemplate(name: "Mine", entries: [])])
        XCTAssertFalse(withTemplate.seedDemoDataIfEmpty(now: F.now))
        XCTAssertEqual(withTemplate.templates.map { $0.name }, ["Mine"])
        XCTAssertTrue(withTemplate.history.isEmpty)

        var withHistory = StrengthData(history: [F.workout(1, finishedAt: F.daysAgo(1), [])])
        XCTAssertFalse(withHistory.seedDemoDataIfEmpty(now: F.now))
        XCTAssertTrue(withHistory.templates.isEmpty)
    }

    // MARK: Exercise history

    private func demoHistory(_ exerciseID: String, now: Date = F.now) -> ExerciseHistory {
        StrengthData.demo(now: F.now).history(for: exerciseID, now: now)
    }

    func testBenchHistoryOfTheDemo() throws {
        let history = demoHistory("bench")
        XCTAssertEqual(history.exerciseID, "bench")
        XCTAssertEqual(history.sessions.map { $0.date }, [5, 10, 15].map { F.daysAgo(Double($0)) })
        XCTAssertEqual(history.sessions.map { $0.workoutName }, Array(repeating: "Upper A · Push", count: 3))
        XCTAssertEqual(history.sessions.map { $0.isPersonalRecord }, [false, true, false])
        XCTAssertEqual(history.sessions[1].sets.map { $0.weightKg }, [50, 70, 80, 82.5, 85])
        XCTAssertEqual(history.sessions[1].sets.map { $0.type }, [.warmup, .warmup, .normal, .normal, .normal])
        XCTAssertEqual(history.e1RMSeries.map { $0.date }, [15, 10, 5].map { F.daysAgo(Double($0)) }, "oldest first")
        let expectedSeries = [93, 85 * (1 + 5.0 / 30), 96]
        XCTAssertEqual(history.e1RMSeries.count, 3)
        for (point, expected) in zip(history.e1RMSeries, expectedSeries) { XCTAssertEqual(point.value, expected, accuracy: 1e-9) }
        XCTAssertEqual(history.bestE1RM, 85 * (1 + 5.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(history.bestSetText, "85 kg × 5")
        XCTAssertEqual(history.bestSetDate, F.daysAgo(10))
    }

    func testThirtyDayTotalsAndTheirWindow() throws {
        let all = demoHistory("bench")
        let volume = 1360.0 + (480 + 412.5 + 425) + (3 * 77.5 * 6)
        XCTAssertEqual(all.volumeLast30Days, volume, accuracy: 1e-9)
        XCTAssertEqual(all.sessionsLast30Days, 3)

        let later = demoHistory("bench", now: F.now.addingTimeInterval(21 * 86_400))     // only the 5 day old session (26 days) remains... 10 d = 31 d
        XCTAssertEqual(later.sessionsLast30Days, 1)
        XCTAssertEqual(later.volumeLast30Days, 1360, accuracy: 1e-9)
        XCTAssertEqual(later.sessions.count, 3, "the list keeps every session")

        let muchLater = demoHistory("bench", now: F.now.addingTimeInterval(200 * 86_400))
        XCTAssertEqual(muchLater.sessionsLast30Days, 0)
        XCTAssertEqual(muchLater.volumeLast30Days, 0)
    }

    func testBenchRecordRows() throws {
        let history = demoHistory("bench")
        XCTAssertEqual(history.records.map { $0.id }, ["e1rm", "bestSet", "repsAtWeight", "bestVolume"])
        XCTAssertEqual(history.records.map { $0.label }, ["Estimated 1RM", "Best set", "Most reps at 80 kg", "Best session volume"])
        XCTAssertEqual(history.records[0].value, "99 kg")
        XCTAssertEqual(history.records[0].date, F.daysAgo(10))
        XCTAssertEqual(history.records[1].value, "85 kg × 5")
        XCTAssertEqual(history.records[1].date, F.daysAgo(10))
        XCTAssertEqual(history.records[2].value, "6")
        XCTAssertEqual(history.records[2].date, F.daysAgo(5), "the newest session that reached the maximum")
        XCTAssertEqual(history.records[3].value, "1,395 kg", "3 x 77.5 x 6 beats the two heavier but shorter sessions")
        XCTAssertEqual(history.records[3].date, F.daysAgo(15))
    }

    func testAnExerciseWithoutSessionsHasAnEmptyHistory() {
        let history = demoHistory("dips")
        XCTAssertTrue(history.sessions.isEmpty)
        XCTAssertTrue(history.e1RMSeries.isEmpty)
        XCTAssertEqual(history.bestE1RM, 0)
        XCTAssertNil(history.bestSetText)
        XCTAssertNil(history.bestSetDate)
        XCTAssertEqual(history.volumeLast30Days, 0)
        XCTAssertEqual(history.sessionsLast30Days, 0)
        XCTAssertTrue(history.records.isEmpty)
        XCTAssertEqual(StrengthData().history(for: "bench", now: F.now).sessions.count, 0)
    }

    func testAStoredPersonalBestBeyondTheHistoryIsShown() throws {
        var data = StrengthData.demo(now: F.now)
        data.personalBests["bench"] = PersonalBest(exerciseID: "bench", estimated1RM: 120, weightKg: 100, reps: 6, date: F.daysAgo(100))
        let history = data.history(for: "bench", now: F.now)
        XCTAssertEqual(history.bestE1RM, 120)
        XCTAssertEqual(history.bestSetText, "100 kg × 6")
        XCTAssertEqual(history.bestSetDate, F.daysAgo(100))
        XCTAssertEqual(history.records.first?.value, "120 kg")
    }

    func testBodyweightAndDurationRecords() throws {
        var data = StrengthData()
        data.history = [
            F.workout(1, finishedAt: F.daysAgo(2), [
                F.entry("pullup", [F.work(0, 8), F.work(0, 9), F.work(0, 7)], n: 1), F.entry("plank", [F.work(0, 45), F.work(0, 60)], n: 2),
            ]),
            F.workout(2, finishedAt: F.daysAgo(9), [
                F.entry("pullup", [F.work(0, 10), F.work(0, 6)], n: 3), F.entry("plank", [F.work(0, 50)], n: 4),
            ]),
        ]
        let pullups = data.history(for: "pullup", now: F.now)
        XCTAssertEqual(pullups.bestE1RM, 0)
        XCTAssertEqual(pullups.bestSetText, "10 reps")
        XCTAssertEqual(pullups.bestSetDate, F.daysAgo(9))
        XCTAssertEqual(pullups.records.map { $0.id }, ["mostReps", "bestSessionReps"])
        XCTAssertEqual(pullups.records.map { $0.value }, ["10", "24"])
        XCTAssertEqual(pullups.records.map { $0.date }, [F.daysAgo(9), F.daysAgo(2)])
        XCTAssertTrue(pullups.e1RMSeries.isEmpty)
        XCTAssertEqual(pullups.volumeLast30Days, 0)
        XCTAssertEqual(pullups.sessionsLast30Days, 2)

        let planks = data.history(for: "plank", now: F.now)
        XCTAssertEqual(planks.bestSetText, "60 s")
        XCTAssertEqual(planks.records.map { $0.id }, ["longest", "bestSessionTime"])
        XCTAssertEqual(planks.records.map { $0.value }, ["60 s", "1:45"])
    }

    func testTwoEntriesOfOneExerciseFormOneSession() throws {
        var data = StrengthData()
        data.history = [F.workout(1, finishedAt: F.daysAgo(2), [
            F.entry("bench", [F.work(60, 10)], pr: false, n: 1), F.entry("bench", [F.work(80, 5)], pr: true, n: 2),
        ])]
        let history = data.history(for: "bench", now: F.now)
        XCTAssertEqual(history.sessions.count, 1)
        XCTAssertEqual(history.sessions[0].sets.map { $0.weightKg }, [60, 80])
        XCTAssertTrue(history.sessions[0].isPersonalRecord)
        XCTAssertEqual(history.e1RMSeries.count, 1)
    }

    func testSessionsWithTheSameDateKeepTheStoredOrder() {
        var data = StrengthData()
        let when = F.daysAgo(1)
        data.history = [
            F.workout(1, name: "First", finishedAt: when, [F.entry("bench", [F.work(60, 5)], n: 1)]),
            F.workout(2, name: "Second", finishedAt: when, [F.entry("bench", [F.work(61, 5)], n: 2)]),
        ]
        XCTAssertEqual(data.history(for: "bench", now: F.now).sessions.map { $0.workoutName }, ["First", "Second"])
    }
}

// MARK: - StrengthDataModel (data + files)

final class StrengthDataModelTests: XCTestCase {
    private typealias F = SvcDataFix

    private func makePersistence() -> FileStrengthPersistence {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return persistence
    }

    func testWithoutPersistenceEverythingStaysInMemory() {
        svcMain {
            let model = StrengthDataModel(persistence: nil, seedDemoData: true, now: F.now)
            XCTAssertEqual(model.data.templates.count, 3)
            model.record(F.workout(1, finishedAt: F.daysAgo(0.1), [F.entry("bench", [F.work(100, 5)], n: 1)]), updateTemplate: nil)
            XCTAssertEqual(model.data.history.count, 6)
            model.reload()                                  // nothing to reload from
            XCTAssertEqual(model.data.history.count, 6)
        }
    }

    func testSeedingIsPersistedAndNotRepeated() {
        let persistence = makePersistence()
        let first = svcMain { () -> StrengthData in
            StrengthDataModel(persistence: persistence, seedDemoData: true, now: F.now).data
        }
        XCTAssertEqual(first.templates.count, 3)
        XCTAssertEqual(persistence.loadTemplates(), first.templates)
        XCTAssertEqual(persistence.loadHistory(), first.history)
        XCTAssertEqual(persistence.loadPersonalBests(), first.personalBests)

        let second = svcMain { () -> StrengthData in
            StrengthDataModel(persistence: persistence, seedDemoData: true, now: F.now.addingTimeInterval(86_400 * 3)).data
        }
        XCTAssertEqual(second, first, "an existing store is neither reseeded nor shifted")
    }

    func testNoSeedingWithoutTheFlag() {
        let persistence = makePersistence()
        let data = svcMain { StrengthDataModel(persistence: persistence, now: F.now).data }
        XCTAssertTrue(data.isEmpty)
        XCTAssertEqual(persistence.loadTemplates(), [])
    }

    func testRecordPersistsHistoryBestsAndTemplates() {
        let persistence = makePersistence()
        svcMain {
            let model = StrengthDataModel(persistence: persistence, seedDemoData: true, now: F.now)
            let upper = model.data.templates[0]
            let workout = F.workout(50, templateID: upper.id, finishedAt: F.daysAgo(0.1), [F.entry("bench", [F.work(90, 5)], n: 50)])
            model.record(workout, updateTemplate: nil)

            XCTAssertEqual(persistence.loadHistory().first, workout)
            XCTAssertEqual(persistence.loadHistory().count, 6)
            XCTAssertEqual(persistence.loadPersonalBests()["bench"]?.estimated1RM ?? 0, 105, accuracy: 1e-9)
            XCTAssertEqual(persistence.loadTemplates().first?.lastPerformed, F.daysAgo(0.1))
            XCTAssertEqual(persistence.loadHistory(), model.data.history)
        }
    }

    func testTheExerciseOverlayRefreshesAfterRecording() throws {
        svcMain {
            let model = StrengthDataModel(persistence: nil, seedDemoData: true, now: F.now)
            XCTAssertEqual(model.exercise(id: "bench")?.previousBestE1RM ?? 0, 99.1667, accuracy: 0.001)
            XCTAssertEqual(model.exercises.first { $0.id == "bench" }?.previousBestE1RM ?? 0, 99.1667, accuracy: 0.001)
            model.record(F.workout(60, finishedAt: F.daysAgo(0.1), [F.entry("bench", [F.work(100, 3)], n: 60)]), updateTemplate: nil)
            XCTAssertEqual(model.exercise(id: "bench")?.previousBestE1RM ?? 0, 110, accuracy: 1e-9)
            XCTAssertEqual(model.exercises.first { $0.id == "bench" }?.previousSets, [PreviousSet(weightKg: 100, reps: 3)])
            XCTAssertNil(model.exercise(id: "unknown"))
            XCTAssertEqual(model.exercises.count, 36)
        }
    }

    func testCustomExercisesAndTemplatesArePersisted() {
        let persistence = makePersistence()
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            let curl = F.customExercise("Spider curl")
            model.addCustomExercise(curl)
            model.addCustomExercise(curl)                                      // duplicate: still one
            XCTAssertEqual(persistence.loadCustomExercises(), [curl])
            XCTAssertEqual(model.exercise(id: curl.id)?.name, "Spider curl")
            XCTAssertEqual(model.exercises.count, 37)

            let template = WorkoutTemplate(id: SvcSyncFix.uuid(40), name: "Arms", entries: [])
            model.saveTemplate(template)
            XCTAssertEqual(persistence.loadTemplates(), [template])
            XCTAssertEqual(model.template(id: template.id), template)
        }
        // A new model sees everything.
        svcMain {
            let reopened = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(reopened.data.customExercises.map { $0.name }, ["Spider curl"])
            XCTAssertEqual(reopened.data.templates.map { $0.name }, ["Arms"])
            XCTAssertEqual(reopened.exercises.count, 37)
        }
    }

    func testReloadPicksUpChangesMadeElsewhere() throws {
        let persistence = makePersistence()
        try svcMain {
            let model = StrengthDataModel(persistence: persistence)
            XCTAssertTrue(model.data.isEmpty)
            XCTAssertNoThrow(try persistence.saveTemplates(SampleData.templates()))
            XCTAssertNoThrow(try persistence.saveHistory(SampleData.history(now: F.now)))
            XCTAssertNoThrow(try persistence.savePersonalBests(SampleData.personalBests(now: F.now)))
            XCTAssertNoThrow(try persistence.saveCustomExercises([F.customExercise("Hex press")]))
            model.reload()
            XCTAssertEqual(model.data.templates.count, 3)
            XCTAssertEqual(model.data.history.count, 5)
            XCTAssertEqual(model.data.customExercises.count, 1)
            XCTAssertEqual(model.exercises.count, 37, "the cached exercise list is refreshed too")
            XCTAssertEqual(model.exercise(id: "bench")?.previousBestE1RM ?? 0, 99.1667, accuracy: 0.001)
        }
    }

    func testHistoryForAnExerciseDelegatesToTheData() {
        svcMain {
            let model = StrengthDataModel(persistence: nil, seedDemoData: true, now: F.now)
            XCTAssertEqual(model.history(for: "bench", now: F.now), model.data.history(for: "bench", now: F.now))
            XCTAssertEqual(model.history(for: "bench", now: F.now).sessions.count, 3)
        }
    }
}

// MARK: - StrengthStore (Combine wrapper; runs on Apple platforms and, with -DPULSE_COMBINE_SHIM, on Linux)

#if canImport(Combine) || PULSE_COMBINE_SHIM
#if canImport(Combine)
import Combine
#endif

final class StrengthStoreWrapperTests: XCTestCase {
    private typealias F = SvcDataFix

    private func makePersistence() -> FileStrengthPersistence {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return persistence
    }

    func testAnEmptyStoreHasTheLibraryOnly() {
        svcMain {
            let store = StrengthStore(persistence: nil)
            XCTAssertTrue(store.templates.isEmpty)
            XCTAssertTrue(store.history.isEmpty)
            XCTAssertTrue(store.customExercises.isEmpty)
            XCTAssertTrue(store.personalBests.isEmpty)
            XCTAssertEqual(store.exercises, ExerciseLibrary.builtIn)
            XCTAssertEqual(store.exercise(id: "bench"), ExerciseLibrary.exercise(id: "bench"))
            XCTAssertNil(store.exercise(id: "nope"))
        }
    }

    func testSeedingFillsTemplatesHistoryAndBests() {
        svcMain {
            let store = StrengthStore(persistence: nil, seedDemoData: true)
            XCTAssertEqual(store.templates.map { $0.name }, ["Upper A · Push", "Lower A · Quads", "Upper B · Pull"])
            XCTAssertEqual(store.history.count, 5)
            XCTAssertEqual(store.history.map { $0.finishedAt }, store.history.map { $0.finishedAt }.sorted(by: >))
            XCTAssertEqual(store.personalBests["bench"]?.weightKg, 85)
            XCTAssertEqual(store.exercise(id: "bench")?.previousBestE1RM ?? 0, 99.1667, accuracy: 0.001)
            XCTAssertEqual(store.history(for: "bench", now: F.now).sessions.count, 3)
        }
    }

    func testSeedingHappensOnlyOnceWithPersistence() {
        let persistence = makePersistence()
        let first = svcMain { () -> [UUID] in
            StrengthStore(persistence: persistence, seedDemoData: true).history.map { $0.id }
        }
        let second = svcMain { () -> [UUID] in
            StrengthStore(persistence: persistence, seedDemoData: true).history.map { $0.id }
        }
        XCTAssertEqual(first.count, 5)
        XCTAssertEqual(first, second)
        XCTAssertEqual(persistence.loadHistory().map { $0.id }, first)
    }

    func testChangesAreVisibleThroughThePublishedValuesAndPersisted() {
        let persistence = makePersistence()
        svcMain {
            let store = StrengthStore(persistence: persistence)
            let curl = F.customExercise("Cable curl")
            store.addCustomExercise(curl)
            XCTAssertEqual(store.customExercises, [curl])
            XCTAssertEqual(store.exercises.count, 37)
            XCTAssertEqual(store.exercise(id: curl.id), curl)

            let template = WorkoutTemplate(id: SvcSyncFix.uuid(90), name: "Arms", entries: [])
            store.saveTemplate(template)
            XCTAssertEqual(store.templates, [template])

            let workout = F.workout(91, templateID: template.id, finishedAt: F.now, [F.entry("bench", [F.work(100, 5)], n: 91)])
            store.record(workout, updateTemplate: nil)
            XCTAssertEqual(store.history, [workout])
            XCTAssertEqual(store.personalBests["bench"]?.weightKg, 100)
            XCTAssertEqual(store.templates[0].lastPerformed, workout.finishedAt)
            XCTAssertEqual(store.exercise(id: "bench")?.previousSets, [PreviousSet(weightKg: 100, reps: 5)])
        }
        XCTAssertEqual(persistence.loadCustomExercises().count, 1)
        XCTAssertEqual(persistence.loadTemplates().count, 1)
        XCTAssertEqual(persistence.loadHistory().count, 1)
        XCTAssertEqual(persistence.loadPersonalBests().count, 1)
    }

    func testReloadReadsWhatWasWrittenElsewhere() throws {
        let persistence = makePersistence()
        try svcMain {
            let store = StrengthStore(persistence: persistence)
            XCTAssertTrue(store.templates.isEmpty)
            try persistence.saveTemplates(SampleData.templates())
            try persistence.saveHistory(SampleData.history(now: F.now))
            try persistence.savePersonalBests(SampleData.personalBests(now: F.now))
            try persistence.saveCustomExercises([F.customExercise("Hex press")])
            store.reload()
            XCTAssertEqual(store.templates.count, 3)
            XCTAssertEqual(store.history.count, 5)
            XCTAssertEqual(store.customExercises.count, 1)
            XCTAssertFalse(store.personalBests.isEmpty)
            XCTAssertEqual(store.exercises.count, 37)
        }
    }

    #if canImport(Combine)
    func testObjectWillChangeFiresOnlyWhenSomethingChanges() {
        svcMain {
            let store = StrengthStore(persistence: nil)
            var count = 0
            let subscription = store.objectWillChange.sink { count += 1 }
            store.reload()
            XCTAssertEqual(count, 0, "nothing changed")
            store.saveTemplate(WorkoutTemplate(name: "Arms", entries: []))
            XCTAssertGreaterThan(count, 0)
            subscription.cancel()
        }
    }
    #endif
}

#endif
