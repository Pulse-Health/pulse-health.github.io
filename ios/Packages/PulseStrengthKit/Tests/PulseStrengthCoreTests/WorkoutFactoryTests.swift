import XCTest
@testable import PulseStrengthCore

/// Template fixtures with deterministic ids for the factory tests.
enum RedTemplateFix {
    static func entry(_ n: Int, _ exercise: Exercise, _ planned: [PlannedSet], rest: Int, group: String? = nil) -> TemplateEntry {
        TemplateEntry(id: RedFix.uuid(0x200 + n, 0), exercise: exercise, plannedSets: planned, restSeconds: rest, supersetGroup: group)
    }

    static func planned(_ count: Int, _ kg: Double, _ reps: Int) -> [PlannedSet] {
        Array(repeating: PlannedSet(type: .normal, weightKg: kg, reps: reps), count: count)
    }

    /// "Upper A · Push": the design's workout.
    static func upperA(lastPerformed: Date? = RedFix.at(-432_000)) -> WorkoutTemplate {
        WorkoutTemplate(
            id: RedFix.uuid(0x2FF, 1),
            name: "Upper A · Push",
            entries: [
                entry(1, RedFix.bench, [
                    PlannedSet(type: .warmup, weightKg: 50, reps: 8), PlannedSet(type: .warmup, weightKg: 70, reps: 5),
                    PlannedSet(weightKg: 82.5, reps: 6), PlannedSet(weightKg: 82.5, reps: 6), PlannedSet(weightKg: 85, reps: 6),
                ], rest: 150),
                entry(2, RedFix.incline, planned(3, 28, 10), rest: 90),
                entry(3, RedFix.ohp, planned(3, 45, 8), rest: 120),
                entry(4, RedFix.lateral, planned(3, 8, 15), rest: 60, group: "A"),
                entry(5, RedFix.pushdown, planned(3, 30, 12), rest: 60, group: "A"),
                entry(6, RedFix.crossover, planned(3, 15, 12), rest: 60),
            ],
            lastPerformed: lastPerformed
        )
    }
}

final class WorkoutFactoryTests: XCTestCase {
    /// What a template stores about an exercise entry (without the entry id).
    private struct Shape: Equatable {
        var exerciseID: String
        var rest: Int
        var group: String?
        var sets: [PlannedSet]
    }

    private func shapes(_ template: WorkoutTemplate) -> [Shape] {
        template.entries.map { Shape(exerciseID: $0.exercise.id, rest: $0.restSeconds, group: $0.supersetGroup, sets: $0.plannedSets) }
    }

    private func shapes(_ state: WorkoutState) -> [Shape] {
        state.exercises.map { entry in
            Shape(
                exerciseID: entry.exercise.id, rest: entry.restSeconds, group: entry.supersetGroup,
                sets: entry.sets.map { PlannedSet(type: $0.type, weightKg: $0.weightKg, reps: $0.reps) }
            )
        }
    }

    // MARK: makeEmpty

    func testMakeEmptyCreatesAnEmptyRunningWorkout() {
        let id = RedFix.uuid(9, 9)
        let s = WorkoutFactory.makeEmpty(name: "Quick session", now: RedFix.t0, id: id)
        XCTAssertEqual(s.id, id)
        XCTAssertEqual(s.name, "Quick session")
        XCTAssertEqual(s.startedAt, RedFix.t0)
        XCTAssertTrue(s.exercises.isEmpty)
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertEqual(s.revision, 0)
        XCTAssertNil(s.templateID)
        XCTAssertTrue(s.templateBaseline.isEmpty)
        XCTAssertNil(s.rest)
        XCTAssertNil(s.pausedAt)
        XCTAssertNil(s.lastLogged)
        XCTAssertNil(s.undo)
        XCTAssertNil(s.finishedAt)
        XCTAssertEqual(s.settings, WorkoutSettings())
        XCTAssertEqual(s.heartRateCount, 0)
        XCTAssertFalse(s.usedWatch)
    }

    func testMakeEmptyUsesFreshIDsByDefault() {
        let a = WorkoutFactory.makeEmpty(name: "A", now: RedFix.t0)
        let b = WorkoutFactory.makeEmpty(name: "A", now: RedFix.t0)
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: makeWorkout

    func testMakeWorkoutCopiesTheTemplate() {
        let template = RedTemplateFix.upperA()
        let id = RedFix.uuid(9, 1)
        let s = WorkoutFactory.makeWorkout(from: template, now: RedFix.at(10), id: id)
        XCTAssertEqual(s.id, id)
        XCTAssertEqual(s.name, "Upper A · Push")
        XCTAssertEqual(s.templateID, template.id)
        XCTAssertEqual(s.startedAt, RedFix.at(10))
        XCTAssertEqual(s.templateBaseline, template.entries.map { $0.id })
        XCTAssertEqual(s.currentIndex, 0)
        XCTAssertEqual(s.revision, 0)
        XCTAssertNil(s.rest)
        XCTAssertNil(s.lastLogged)
        XCTAssertNil(s.undo)
        XCTAssertNil(s.pausedAt)
        XCTAssertEqual(s.exercises.count, 6)
        XCTAssertEqual(shapes(s), shapes(template))
        for (workoutExercise, entry) in zip(s.exercises, template.entries) {
            XCTAssertEqual(workoutExercise.templateEntryID, entry.id)
            XCTAssertNotEqual(workoutExercise.id, entry.id)
            XCTAssertEqual(workoutExercise.exercise, entry.exercise)
            XCTAssertEqual(workoutExercise.note, "")
            XCTAssertTrue(workoutExercise.sets.allSatisfy { !$0.isDone && $0.rir == nil })
        }
    }

    func testMakeWorkoutGivesEveryExerciseAndSetAFreshID() {
        let template = RedTemplateFix.upperA()
        let a = WorkoutFactory.makeWorkout(from: template, now: RedFix.t0)
        let b = WorkoutFactory.makeWorkout(from: template, now: RedFix.t0)
        let aIDs = a.exercises.map { $0.id } + a.exercises.flatMap { $0.sets.map { $0.id } }
        let bIDs = b.exercises.map { $0.id } + b.exercises.flatMap { $0.sets.map { $0.id } }
        XCTAssertEqual(Set(aIDs).count, aIDs.count)
        XCTAssertTrue(Set(aIDs).isDisjoint(with: bIDs))
        XCTAssertNotEqual(a.id, b.id)
    }

    func testMakeWorkoutKeepsTheSameExerciseTwice() {
        let twice = WorkoutTemplate(name: "Doubles", entries: [
            RedTemplateFix.entry(1, RedFix.bench, RedTemplateFix.planned(2, 80, 5), rest: 150),
            RedTemplateFix.entry(2, RedFix.bench, RedTemplateFix.planned(2, 60, 8), rest: 120),
        ])
        let s = WorkoutFactory.makeWorkout(from: twice, now: RedFix.t0)
        XCTAssertEqual(s.exercises.count, 2)
        XCTAssertNotEqual(s.exercises[0].id, s.exercises[1].id)
        XCTAssertEqual(s.exercises[0].templateEntryID, twice.entries[0].id)
        XCTAssertEqual(s.exercises[1].templateEntryID, twice.entries[1].id)
    }

    func testMakeWorkoutDropsALoneSupersetLetter() {
        let template = WorkoutTemplate(name: "Odd", entries: [
            RedTemplateFix.entry(1, RedFix.lateral, RedTemplateFix.planned(2, 8, 15), rest: 60, group: "A"),
            RedTemplateFix.entry(2, RedFix.bench, RedTemplateFix.planned(2, 80, 5), rest: 150),
        ])
        let s = WorkoutFactory.makeWorkout(from: template, now: RedFix.t0)
        XCTAssertEqual(s.exercises.map { $0.supersetGroup }, [nil, nil])
    }

    func testMakeWorkoutFromAnEmptyTemplate() {
        let s = WorkoutFactory.makeWorkout(from: WorkoutTemplate(name: "Nothing", entries: []), now: RedFix.t0)
        XCTAssertTrue(s.exercises.isEmpty)
        XCTAssertTrue(s.templateBaseline.isEmpty)
        XCTAssertEqual(s.currentIndex, 0)
    }

    func testAFactoryWorkoutRunsTheDesignFlow() {
        var s = WorkoutFactory.makeWorkout(from: RedTemplateFix.upperA(), now: RedFix.t0)
        // bench: two warm-ups (60 s), then working sets (150 s)
        let expected = [60, 60, 150, 150, 150]
        for (i, rest) in expected.enumerated() {
            s = RedFix.reduced(s, RedFix.toggle(s, 0, i), at: Double(100 * (i + 1)))
            XCTAssertEqual(s.rest?.totalSeconds, rest)
        }
        // lateral / pushdown superset
        s = RedFix.reduced(s, .goTo(index: 3), at: 700)
        s = RedFix.reduced(s, .logNextSet, at: 710)
        XCTAssertEqual(s.currentIndex, 4)
        XCTAssertNil(s.rest)
        s = RedFix.reduced(s, .logNextSet, at: 720)
        XCTAssertEqual(s.currentIndex, 3)
        XCTAssertEqual(s.rest?.totalSeconds, 60)
        XCTAssertEqual(s.exercises[3].doneCount, 1)
        XCTAssertEqual(s.exercises[4].doneCount, 1)
    }

    // MARK: updatedTemplate

    func testUnchangedWorkoutRoundTripsToAnEqualTemplate() {
        let template = RedTemplateFix.upperA()
        let workout = WorkoutFactory.makeWorkout(from: template, now: RedFix.t0)
        XCTAssertEqual(WorkoutFactory.updatedTemplate(template, from: workout), template)
    }

    func testLoggingSetsDoesNotChangeTheTemplate() {
        let template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(from: template, now: RedFix.t0)
        for i in 0..<5 { workout = RedFix.reduced(workout, RedFix.toggle(workout, 0, i), at: Double(i * 200)) }
        workout = RedFix.reduced(workout, .toggleLastSetRIR(2), at: 2_000)
        XCTAssertEqual(WorkoutFactory.updatedTemplate(template, from: workout), template)
    }

    func testUpdatedTemplateKeepsIdNameAndLastPerformed() {
        let template = RedTemplateFix.upperA(lastPerformed: RedFix.at(-86_400))
        var workout = WorkoutFactory.makeWorkout(from: template, now: RedFix.t0)
        workout = RedFix.reduced(workout, .rename("Renamed in the workout"))
        workout = RedFix.reduced(workout, .removeExercise(exerciseID: RedFix.ex(workout, 5)))
        let updated = WorkoutFactory.updatedTemplate(template, from: workout)
        XCTAssertEqual(updated.id, template.id)
        XCTAssertEqual(updated.name, "Upper A · Push")
        XCTAssertEqual(updated.lastPerformed, RedFix.at(-86_400))
        XCTAssertEqual(updated.entries.count, 5)
    }

    func testUpdatedTemplateReflectsEditsAddedRemovedAndReorderedExercises() {
        let template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(from: template, now: RedFix.t0)
        workout = RedFix.reduced(workout, .addExercises([RedFix.squat]))
        workout = RedFix.reduced(workout, .removeExercise(exerciseID: RedFix.ex(workout, 1)))           // incline
        workout = RedFix.reduced(workout, .moveExercise(from: 0, to: 1))                                 // bench after ohp
        workout = RedFix.reduced(workout, .setWeight(exerciseID: RedFix.ex(workout, 1), setID: RedFix.setID(workout, 1, 0), kg: 47.5))
        workout = RedFix.reduced(workout, .setRest(exerciseID: RedFix.ex(workout, 1), seconds: 105))
        workout = RedFix.reduced(workout, .addSet(exerciseID: RedFix.ex(workout, 0)))

        let updated = WorkoutFactory.updatedTemplate(template, from: workout)
        XCTAssertEqual(updated.entries.map { $0.exercise.id }, ["ohp", "bench", "lateral", "pushdown", "crossover", "squat"])
        XCTAssertEqual(shapes(updated), shapes(workout))
        // kept entries keep their template entry id, the new one gets a fresh id
        XCTAssertEqual(updated.entries[0].id, template.entries[2].id)      // ohp
        XCTAssertEqual(updated.entries[1].id, template.entries[0].id)      // bench
        XCTAssertEqual(updated.entries[2].id, template.entries[3].id)
        XCTAssertEqual(updated.entries[3].id, template.entries[4].id)
        XCTAssertEqual(updated.entries[4].id, template.entries[5].id)
        XCTAssertFalse(template.entries.map { $0.id }.contains(updated.entries[5].id))
        XCTAssertEqual(updated.entries.count, 6)
        XCTAssertEqual(Set(updated.entries.map { $0.id }).count, 6)
    }

    func testUpdatedTemplateReflectsSetValuesRestAndSupersetChanges() {
        let template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(from: template, now: RedFix.t0)
        workout = RedFix.reduced(workout, .setWeight(exerciseID: RedFix.ex(workout, 2), setID: RedFix.setID(workout, 2, 1), kg: 47.5))
        workout = RedFix.reduced(workout, .setReps(exerciseID: RedFix.ex(workout, 2), setID: RedFix.setID(workout, 2, 1), reps: 6))
        workout = RedFix.reduced(workout, .setSetType(exerciseID: RedFix.ex(workout, 2), setID: RedFix.setID(workout, 2, 2), type: .drop))
        workout = RedFix.reduced(workout, .setRest(exerciseID: RedFix.ex(workout, 0), seconds: 180))
        workout = RedFix.reduced(workout, .toggleSuperset(exerciseID: RedFix.ex(workout, 3)))    // dissolve A
        workout = RedFix.reduced(workout, .deleteSet(exerciseID: RedFix.ex(workout, 5), setID: RedFix.setID(workout, 5, 2)))
        let updated = WorkoutFactory.updatedTemplate(template, from: workout)
        XCTAssertEqual(updated.entries[2].plannedSets[1], PlannedSet(type: .normal, weightKg: 47.5, reps: 6))
        XCTAssertEqual(updated.entries[2].plannedSets[2].type, .drop)
        XCTAssertEqual(updated.entries[0].restSeconds, 180)
        XCTAssertNil(updated.entries[3].supersetGroup)
        XCTAssertNil(updated.entries[4].supersetGroup)
        XCTAssertEqual(updated.entries[5].plannedSets.count, 2)
        XCTAssertEqual(shapes(updated), shapes(workout))
    }

    func testUpdatedTemplateTakesAReplacedExerciseAndKeepsItsEntryID() {
        let template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(from: template, now: RedFix.t0)
        workout = RedFix.reduced(workout, .replaceExercise(exerciseID: RedFix.ex(workout, 1), with: RedFix.squat))
        let updated = WorkoutFactory.updatedTemplate(template, from: workout)
        XCTAssertEqual(updated.entries[1].id, template.entries[1].id)
        XCTAssertEqual(updated.entries[1].exercise.id, "squat")
        XCTAssertEqual(updated.entries[1].plannedSets.count, 3)
        XCTAssertEqual(updated.entries[1].restSeconds, 180)
    }

    func testUpdatedTemplateIncludesPendingAndDoneSets() {
        let template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(from: template, now: RedFix.t0)
        workout = RedFix.reduced(workout, RedFix.toggle(workout, 1, 0), at: 1)
        let updated = WorkoutFactory.updatedTemplate(template, from: workout)
        XCTAssertEqual(updated.entries[1].plannedSets.count, 3)
    }

    func testUpdatedTemplateOfAnEmptiedWorkoutHasNoEntries() {
        let template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(from: template, now: RedFix.t0)
        for _ in 0..<6 { workout = RedFix.reduced(workout, .removeExercise(exerciseID: RedFix.ex(workout, 0)), at: 1) }
        XCTAssertTrue(workout.exercises.isEmpty)
        XCTAssertTrue(WorkoutFactory.updatedTemplate(template, from: workout).entries.isEmpty)
    }

    func testUpdatedTemplateNeverReusesAnEntryIDTwice() {
        let template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(from: template, now: RedFix.t0)
        workout.exercises[1].templateEntryID = workout.exercises[0].templateEntryID    // a corrupted link
        let updated = WorkoutFactory.updatedTemplate(template, from: workout)
        XCTAssertEqual(Set(updated.entries.map { $0.id }).count, 6)
    }

    // MARK: template(from:name:)

    func testSaveAsTemplateCreatesANewTemplateWithNewEntryIDs() {
        let source = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(from: source, now: RedFix.t0)
        workout = RedFix.reduced(workout, .addExercises([RedFix.plank]))
        let saved = WorkoutFactory.template(from: workout, name: "Push + core")
        XCTAssertEqual(saved.name, "Push + core")
        XCTAssertNotEqual(saved.id, source.id)
        XCTAssertNil(saved.lastPerformed)
        XCTAssertEqual(saved.entries.count, 7)
        XCTAssertEqual(shapes(saved), shapes(workout))
        let ids = saved.entries.map { $0.id }
        XCTAssertEqual(Set(ids).count, 7)
        XCTAssertTrue(Set(ids).isDisjoint(with: source.entries.map { $0.id }))
        XCTAssertTrue(Set(ids).isDisjoint(with: workout.exercises.map { $0.id }))
        XCTAssertEqual(saved.entries.map { $0.supersetGroup }, [nil, nil, nil, "A", "A", nil, nil])
    }

    func testSaveAsTemplateTrimsTheNameAndFallsBackToTheWorkoutName() {
        let workout = WorkoutFactory.makeWorkout(from: RedTemplateFix.upperA(), now: RedFix.t0)
        XCTAssertEqual(WorkoutFactory.template(from: workout, name: "  Heavy day \n").name, "Heavy day")
        XCTAssertEqual(WorkoutFactory.template(from: workout, name: "   ").name, "Upper A · Push")
        let unnamed = WorkoutFactory.makeEmpty(name: " ", now: RedFix.t0)
        XCTAssertEqual(WorkoutFactory.template(from: unnamed, name: "").name, "Workout")
    }

    func testSavedTemplateStartsAnIdenticalWorkout() {
        var workout = WorkoutFactory.makeWorkout(from: RedTemplateFix.upperA(), now: RedFix.t0)
        workout = RedFix.reduced(workout, .addExercises([RedFix.pushup]))
        workout = RedFix.reduced(workout, .removeExercise(exerciseID: RedFix.ex(workout, 2)))
        let saved = WorkoutFactory.template(from: workout, name: "Mine")
        let again = WorkoutFactory.makeWorkout(from: saved, now: RedFix.at(99))
        XCTAssertEqual(shapes(again), shapes(workout))
        XCTAssertEqual(again.templateID, saved.id)
        XCTAssertEqual(again.templateBaseline, saved.entries.map { $0.id })
    }

    func testTemplateWorkoutTemplateRoundTripThroughTheReducer() {
        let template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(from: template, now: RedFix.t0)
        var clock = 0.0
        func step(_ action: WorkoutAction) {
            clock += 5
            WorkoutReducer.reduce(&workout, action, now: RedFix.at(clock))
        }
        step(RedFix.toggle(workout, 0, 0))
        step(.setWeight(exerciseID: RedFix.ex(workout, 0), setID: RedFix.setID(workout, 0, 4), kg: 87.5))
        step(.addExercises([RedFix.plank]))
        step(.moveExerciseBy(exerciseID: RedFix.ex(workout, 6), delta: -6))
        step(.removeExercise(exerciseID: RedFix.ex(workout, 2)))      // incline
        step(.undo)                                                    // put it back
        let updated = WorkoutFactory.updatedTemplate(template, from: workout)
        let next = WorkoutFactory.makeWorkout(from: updated, now: RedFix.at(1_000))
        XCTAssertEqual(shapes(next), shapes(workout))
        XCTAssertEqual(next.exercises.first?.exercise.id, "plank")
        XCTAssertEqual(next.exercises.first(where: { $0.exercise.id == "bench" })?.sets[4].weightKg, 87.5)
        // everything in the new workout is pending again
        XCTAssertTrue(next.exercises.allSatisfy { $0.doneCount == 0 })
    }

    func testStateAndTemplateSurviveJSONRoundTrips() throws {
        let template = RedTemplateFix.upperA()
        var workout = WorkoutFactory.makeWorkout(from: template, now: RedFix.t0)
        workout = RedFix.reduced(workout, RedFix.toggle(workout, 0, 2), at: 30)
        workout = RedFix.reduced(workout, .removeExercise(exerciseID: RedFix.ex(workout, 5)), at: 31)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedState = try decoder.decode(WorkoutState.self, from: try encoder.encode(workout))
        XCTAssertEqual(decodedState, workout)
        let decodedTemplate = try decoder.decode(WorkoutTemplate.self, from: try encoder.encode(template))
        XCTAssertEqual(decodedTemplate, template)
    }
}
