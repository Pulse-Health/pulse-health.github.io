import Foundation
import XCTest
@testable import PulseStrengthCore

final class SampleDataTests: XCTestCase {
    private let now = SvcSyncFix.epoch
    private let day: TimeInterval = 86_400

    private func daysAgo(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * day) }

    private func template(_ name: String) throws -> WorkoutTemplate {
        try XCTUnwrap(SampleData.templates().first { $0.name == name }, name)
    }

    private func workout(_ days: Int) throws -> CompletedWorkout {
        try XCTUnwrap(SampleData.history(now: now).first { $0.finishedAt == daysAgo(days) }, "no workout \(days) days ago")
    }

    private func sets(_ workout: CompletedWorkout, _ exerciseID: String) throws -> [CompletedSet] {
        try XCTUnwrap(workout.exercises.first { $0.exerciseID == exerciseID }, exerciseID).sets
    }

    // MARK: Templates

    func testThreeTemplatesInTheDesignOrder() {
        XCTAssertEqual(SampleData.templates().map { $0.name }, ["Upper A · Push", "Lower A · Quads", "Upper B · Pull"])
        XCTAssertEqual(SampleData.templates().map { $0.entries.count }, [6, 5, 6])
    }

    func testUpperAIsTheWorkoutOfTheDesign() throws {
        let upper = try template("Upper A · Push")
        XCTAssertEqual(upper.entries.map { $0.exercise.id }, ["bench", "incline", "ohp", "lateral", "pushdown", "crossover"])
        XCTAssertEqual(upper.entries.map { $0.restSeconds }, [150, 90, 120, 60, 60, 60])
        XCTAssertEqual(upper.entries.map { $0.supersetGroup }, [nil, nil, nil, "A", "A", nil])

        let bench = upper.entries[0].plannedSets
        XCTAssertEqual(bench, [
            PlannedSet(type: .warmup, weightKg: 50, reps: 8), PlannedSet(type: .warmup, weightKg: 70, reps: 5),
            PlannedSet(type: .normal, weightKg: 82.5, reps: 6), PlannedSet(type: .normal, weightKg: 82.5, reps: 6),
            PlannedSet(type: .normal, weightKg: 85, reps: 6),
        ])
        func straight(_ count: Int, _ kg: Double, _ reps: Int) -> [PlannedSet] {
            Array(repeating: PlannedSet(type: .normal, weightKg: kg, reps: reps), count: count)
        }
        XCTAssertEqual(upper.entries[1].plannedSets, straight(3, 28, 10))
        XCTAssertEqual(upper.entries[2].plannedSets, straight(3, 45, 8))
        XCTAssertEqual(upper.entries[3].plannedSets, straight(3, 8, 15))
        XCTAssertEqual(upper.entries[4].plannedSets, straight(3, 30, 12))
        XCTAssertEqual(upper.entries[5].plannedSets, straight(3, 15, 12))
        XCTAssertEqual(upper.entries.flatMap { $0.plannedSets }.count, 20)
    }

    func testOtherTemplatesHaveTheExpectedExercises() throws {
        XCTAssertEqual(try template("Lower A · Quads").entries.map { $0.exercise.id }, ["squat", "legpress", "lunge", "legext", "calf"])
        XCTAssertEqual(try template("Upper B · Pull").entries.map { $0.exercise.id }, ["pullup", "brow", "pulldown", "crow", "facepull", "curl"])
    }

    func testEveryTemplateExerciseIsTheLibraryExercise() {
        for template in SampleData.templates() {
            for entry in template.entries {
                XCTAssertEqual(entry.exercise, ExerciseLibrary.exercise(id: entry.exercise.id), entry.exercise.id)
                XCTAssertFalse(entry.plannedSets.isEmpty)
                XCTAssertGreaterThan(entry.restSeconds, 0)
            }
        }
    }

    func testSupersetsHaveAtLeastTwoMembers() {
        for template in SampleData.templates() {
            var counts: [String: Int] = [:]
            for entry in template.entries { if let group = entry.supersetGroup { counts[group, default: 0] += 1 } }
            for (group, count) in counts { XCTAssertGreaterThanOrEqual(count, 2, group) }
        }
    }

    func testTemplatesHaveStableIdsAndNeverBeenPerformedWithoutNow() {
        XCTAssertEqual(SampleData.templates(), SampleData.templates())
        XCTAssertTrue(SampleData.templates().allSatisfy { $0.lastPerformed == nil })
        let ids = SampleData.templates().flatMap { [$0.id] + $0.entries.map { $0.id } }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testTemplatesPlanARealisticDuration() {
        for template in SampleData.templates() {
            XCTAssertGreaterThanOrEqual(template.estimatedMinutes, 30, template.name)
            XCTAssertLessThanOrEqual(template.estimatedMinutes, 90, template.name)
        }
    }

    func testLastPerformedFollowsTheHistory() throws {
        let templates = SampleData.templates(now: now)
        XCTAssertEqual(templates.map { $0.name }, ["Upper A · Push", "Lower A · Quads", "Upper B · Pull"])
        XCTAssertEqual(templates[0].lastPerformed, daysAgo(5))
        XCTAssertEqual(templates[1].lastPerformed, daysAgo(7))
        XCTAssertEqual(templates[2].lastPerformed, daysAgo(3))
        XCTAssertEqual(templates.map { $0.id }, SampleData.templates().map { $0.id })
        XCTAssertEqual(templates.map { $0.entries }, SampleData.templates().map { $0.entries })
    }

    // MARK: History

    func testHistoryIsNewestFirstWithTheDemoTimeline() {
        let history = SampleData.history(now: now)
        XCTAssertEqual(history.map { $0.name }, ["Upper B · Pull", "Upper A · Push", "Lower A · Quads", "Upper A · Push", "Upper A · Push"])
        XCTAssertEqual(history.map { $0.finishedAt }, [3, 5, 7, 10, 15].map { daysAgo($0) })
        XCTAssertEqual(history.map { $0.templateID }, [3, 1, 2, 1, 1].map { SampleData.templates()[$0 - 1].id })
        for workout in history {
            XCTAssertEqual(workout.finishedAt.timeIntervalSince(workout.startedAt), Double(workout.durationSeconds), accuracy: 0.001)
            XCTAssertGreaterThan(workout.durationSeconds, 30 * 60)
            XCTAssertLessThan(workout.finishedAt, now)
        }
    }

    func testBenchSessionsMatchTheDesign() throws {
        func warmup(_ kg: Double, _ reps: Int) -> [Double] { [1, kg, Double(reps)] }
        func shape(_ sets: [CompletedSet]) -> [[Double]] { sets.map { [$0.type == .warmup ? 1 : 0, $0.weightKg, Double($0.reps)] } }
        XCTAssertEqual(shape(try sets(try workout(5), "bench")), [warmup(50, 8), warmup(70, 5), [0, 80, 6], [0, 80, 6], [0, 80, 5]])
        XCTAssertEqual(shape(try sets(try workout(10), "bench")), [warmup(50, 8), warmup(70, 5), [0, 80, 6], [0, 82.5, 5], [0, 85, 5]])
        XCTAssertEqual(shape(try sets(try workout(15), "bench")), [warmup(50, 8), [0, 77.5, 6], [0, 77.5, 6], [0, 77.5, 6]])
    }

    func testOnlyTheTenDayBenchSessionIsAPersonalRecord() throws {
        for workout in SampleData.history(now: now) {
            let flagged = workout.exercises.filter { $0.isPersonalRecord }.map { $0.exerciseID }
            XCTAssertEqual(flagged, workout.finishedAt == daysAgo(10) ? ["bench"] : [], workout.name)
            XCTAssertEqual(workout.personalRecords.map { $0.exerciseID }, flagged)
        }
        let record = try XCTUnwrap(try workout(10).personalRecords.first)
        XCTAssertEqual(record.exerciseName, "Barbell bench press")
        XCTAssertEqual(record.weightKg, 85)
        XCTAssertEqual(record.reps, 5)
        XCTAssertEqual(record.estimated1RM, 99.1667, accuracy: 0.001)
        XCTAssertEqual(record.estimated1RM.rounded(), 99)
        XCTAssertGreaterThan(record.previousBest, 0)
        XCTAssertLessThan(record.previousBest, record.estimated1RM)
    }

    func testEntryFlagsAgreeWithTheEstimates() {
        for workout in SampleData.history(now: now) {
            for entry in workout.exercises {
                let computed = entry.sets.filter { $0.type != .warmup }
                    .map { Estimated1RM.epley(weightKg: $0.weightKg, reps: $0.reps) }.max() ?? 0
                let expected = entry.tracking == .weightReps ? computed : 0
                XCTAssertEqual(entry.bestE1RM, expected, accuracy: 1e-9, entry.name)
                XCTAssertFalse(entry.sets.isEmpty)
            }
        }
    }

    func testTotalsAreConsistentWithTheSets() throws {
        for workout in SampleData.history(now: now) {
            var volume = 0.0
            var logged = 0
            var rir: [Int] = []
            var muscles: [MuscleGroup: Int] = [:]
            for entry in workout.exercises {
                logged += entry.sets.count
                rir += entry.sets.compactMap { $0.rir }
                for set in entry.sets where set.type != .warmup {
                    if entry.tracking == .weightReps { volume += set.weightKg * Double(set.reps) }
                    muscles[entry.muscle, default: 0] += 1
                }
            }
            XCTAssertEqual(workout.volumeKg, volume, accuracy: 1e-9, workout.name)
            XCTAssertEqual(workout.loggedSets, logged, workout.name)
            XCTAssertEqual(workout.muscleSets.reduce(0) { $0 + $1.sets }, muscles.values.reduce(0, +))
            XCTAssertTrue(workout.muscleSets.allSatisfy { $0.sets > 0 })
            XCTAssertEqual(workout.muscleSets, workout.muscleSets.sorted {
                $0.sets != $1.sets ? $0.sets > $1.sets : $0.muscle.rawValue < $1.muscle.rawValue
            })
            for item in workout.muscleSets { XCTAssertEqual(muscles[item.muscle], item.sets) }
            if rir.isEmpty {
                XCTAssertNil(workout.averageRIR)
            } else {
                XCTAssertEqual(try XCTUnwrap(workout.averageRIR), Double(rir.reduce(0, +)) / Double(rir.count), accuracy: 1e-9)
            }
        }
    }

    func testUpperADayFiveNumbers() throws {
        let workout = try workout(5)
        XCTAssertEqual(workout.loggedSets, 20)
        XCTAssertEqual(workout.volumeKg, 5076, accuracy: 1e-9)
        XCTAssertEqual(workout.muscleSets.map { $0.muscle }, [.chest, .shoulders, .arms])
        XCTAssertEqual(workout.muscleSets.map { $0.sets }, [9, 6, 3])
        XCTAssertEqual(workout.averageRIR ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(workout.averageHeartRate, 126)
    }

    func testAWorkoutWithoutWatchDataHasNoHeartRate() throws {
        XCTAssertNil(try workout(15).averageHeartRate)
        XCTAssertNil(try workout(15).averageRIR)
    }

    func testEveryWorkoutFollowsItsTemplate() throws {
        for workout in SampleData.history(now: now) {
            let template = try XCTUnwrap(SampleData.templates().first { $0.id == workout.templateID })
            XCTAssertEqual(workout.exercises.map { $0.exerciseID }, template.entries.map { $0.exercise.id }, workout.name)
            for entry in workout.exercises {
                let library = try XCTUnwrap(ExerciseLibrary.exercise(id: entry.exerciseID))
                XCTAssertEqual(entry.name, library.name)
                XCTAssertEqual(entry.muscle, library.muscle)
                XCTAssertEqual(entry.mediaKey, library.mediaKey)
                XCTAssertEqual(entry.tracking, library.tracking)
            }
        }
    }

    func testHistoryIsDeterministicAndMovesWithNow() {
        XCTAssertEqual(SampleData.history(now: now), SampleData.history(now: now))
        let later = SampleData.history(now: now.addingTimeInterval(10 * day))
        let original = SampleData.history(now: now)
        XCTAssertEqual(later.count, original.count)
        for (a, b) in zip(later, original) {
            XCTAssertEqual(a.id, b.id)
            XCTAssertEqual(a.finishedAt.timeIntervalSince(b.finishedAt), 10 * day, accuracy: 0.001)
            XCTAssertEqual(a.exercises, b.exercises)
        }
    }

    func testIdsAreUniqueAcrossTheHistory() {
        let history = SampleData.history(now: now)
        let ids = history.map { $0.id } + history.flatMap { $0.exercises.map { $0.id } }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(Set(ids).isDisjoint(with: SampleData.templates().flatMap { [$0.id] + $0.entries.map { $0.id } }))
    }

    // MARK: Personal bests

    func testBenchPersonalBestIsTheTenDayRecord() throws {
        let best = try XCTUnwrap(SampleData.personalBests(now: now)["bench"])
        XCTAssertEqual(best.exerciseID, "bench")
        XCTAssertEqual(best.weightKg, 85)
        XCTAssertEqual(best.reps, 5)
        XCTAssertEqual(best.estimated1RM, 99.1667, accuracy: 0.001)
        XCTAssertEqual(best.date, daysAgo(10))
    }

    func testBestsAreTheMaximaOfTheHistory() {
        let history = SampleData.history(now: now)
        let bests = SampleData.personalBests(now: now)
        var maxima: [String: Double] = [:]
        for workout in history { for entry in workout.exercises { maxima[entry.exerciseID] = max(maxima[entry.exerciseID] ?? 0, entry.bestE1RM) } }
        let expectedIDs = Set(maxima.filter { $0.value > 0 }.keys)
        XCTAssertEqual(Set(bests.keys), expectedIDs)
        for (id, best) in bests {
            XCTAssertEqual(best.estimated1RM, maxima[id] ?? -1, accuracy: 1e-9, id)
            XCTAssertEqual(best.exerciseID, id)
            XCTAssertEqual(Estimated1RM.epley(weightKg: best.weightKg, reps: best.reps), best.estimated1RM, accuracy: 1e-9, id)
            XCTAssertTrue(history.contains { $0.finishedAt == best.date }, id)
        }
        XCTAssertNil(bests["pullup"], "bodyweight exercises have no e1RM")
    }

    func testBestsMatchTheLibraryValuesOfTheDesignExercises() throws {
        let bests = SampleData.personalBests(now: now)
        for id in ["bench", "incline", "ohp", "lateral", "pushdown", "crossover"] {
            let library = try XCTUnwrap(ExerciseLibrary.exercise(id: id)).previousBestE1RM
            XCTAssertGreaterThan(library, 0)
            XCTAssertEqual(try XCTUnwrap(bests[id]).estimated1RM, library, accuracy: 0.5, id)
        }
    }

    // MARK: Overlay

    func testSeededDataReproducesThePreviousSetsOfTheDesign() throws {
        let data = StrengthData.demo(now: now)
        for id in ["bench", "incline", "ohp", "lateral", "pushdown", "crossover"] {
            let library = try XCTUnwrap(ExerciseLibrary.exercise(id: id))
            XCTAssertEqual(try XCTUnwrap(data.exercise(id: id)).previousSets, library.previousSets, id)
        }
    }

    func testDemoDataBundlesTheSamples() {
        let data = StrengthData.demo(now: now)
        XCTAssertEqual(data.templates, SampleData.templates(now: now))
        XCTAssertEqual(data.history, SampleData.history(now: now))
        XCTAssertEqual(data.personalBests, SampleData.personalBests(now: now))
        XCTAssertTrue(data.customExercises.isEmpty)
        XCTAssertFalse(data.isEmpty)
    }

    func testTheDesignWorkoutCanBeStartedFromTheSampleTemplate() throws {
        let upper = SampleData.templates(now: now)[0]
        let state = WorkoutFactory.makeWorkout(from: upper, now: now)
        XCTAssertEqual(state.exercises.count, 6)
        XCTAssertEqual(state.exercises.flatMap { $0.sets }.count, 20)
        XCTAssertEqual(state.exercises.map { $0.supersetGroup }, [nil, nil, nil, "A", "A", nil])
        XCTAssertEqual(state.exercises[0].sets.map { $0.type }, [.warmup, .warmup, .normal, .normal, .normal])
    }
}
