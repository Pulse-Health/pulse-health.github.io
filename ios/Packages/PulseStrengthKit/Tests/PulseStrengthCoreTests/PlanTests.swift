import Foundation
import XCTest
@testable import PulseStrengthCore

/// Plans (rotations of templates), rep ranges, entry notes and the plan import.
final class PlanTests: XCTestCase {
    private let now = SvcSyncFix.epoch

    // MARK: Fixtures

    private func exercise(_ id: String) -> Exercise { ExerciseLibrary.exercise(id: id)! }

    private func template(_ n: Int, _ name: String, lastPerformed: Date? = nil, note: String? = nil) -> WorkoutTemplate {
        WorkoutTemplate(
            id: SvcSyncFix.uuid(9000 + n),
            name: name,
            entries: [
                TemplateEntry(
                    id: SvcSyncFix.uuid(9100 + n), exercise: exercise("bench"),
                    plannedSets: [PlannedSet(weightKg: 60, reps: 8, repsMax: 10), PlannedSet(type: .failure, weightKg: 60, reps: 8, repsMax: 10)],
                    restSeconds: 120, note: note
                ),
            ],
            lastPerformed: lastPerformed
        )
    }

    /// Five templates "W1" ... "W5" and a plan over all of them.
    private func fiveWorkouts() -> (templates: [WorkoutTemplate], plan: WorkoutPlan) {
        let templates = (1...5).map { template($0, "W\($0)") }
        let plan = WorkoutPlan(id: SvcSyncFix.uuid(9900), name: "Five", templateIDs: templates.map { $0.id }, isActive: true)
        return (templates, plan)
    }

    private func finished(_ n: Int, template: WorkoutTemplate?, at date: Date) -> CompletedWorkout {
        SvcDataFix.workout(n, name: template?.name ?? "Workout", templateID: template?.id, finishedAt: date, [])
    }

    private func makePersistence() -> FileStrengthPersistence {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return persistence
    }

    // MARK: Rotation

    func testTheRotationStartsAtTheFirstWorkoutAndMovesOnAfterEachOne() {
        var (templates, plan) = fiveWorkouts()
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W1")
        XCTAssertEqual(plan.nextPosition(in: templates), 1)
        plan.advance(after: templates[0].id)
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W2")
        plan.advance(after: templates[4].id)
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W1", "the rotation wraps around")
        templates.removeAll()
        XCTAssertNil(plan.nextWorkout(in: templates))
        XCTAssertNil(plan.nextPosition(in: templates))
    }

    func testDoingAWorkoutOutOfOrderContinuesAfterIt() {
        let (templates, original) = fiveWorkouts()
        var plan = original
        plan.advance(after: templates[3].id)
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W5")
    }

    func testAWorkoutThatIsNotInThePlanChangesNothing() {
        let (templates, original) = fiveWorkouts()
        var plan = original
        plan.advance(after: SvcSyncFix.uuid(1))
        XCTAssertEqual(plan, original)
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W1")
    }

    func testSkippingPassesOverTheNextWorkoutAndWraps() {
        var (templates, plan) = fiveWorkouts()
        plan.skip(in: templates)
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W2")
        plan.nextIndex = 4
        plan.skip(in: templates)
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W1")
        templates.removeAll()
        let before = plan
        plan.skip(in: templates)
        XCTAssertEqual(plan, before, "nothing to skip")
    }

    func testATemplateThatNoLongerExistsIsPassedOver() {
        var (templates, plan) = fiveWorkouts()
        templates.remove(at: 1)
        plan.nextIndex = 1
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W3")
        XCTAssertEqual(plan.nextPosition(in: templates), 3)
        XCTAssertEqual(plan.workouts(in: templates).map { $0.name }, ["W1", "W3", "W4", "W5"])
    }

    func testAnOutOfRangeIndexStillFindsAWorkout() {
        let (templates, original) = fiveWorkouts()
        var plan = original
        plan.nextIndex = 12
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W3")
        plan.nextIndex = -1
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W5")
        XCTAssertNil(WorkoutPlan(name: "Empty", templateIDs: []).nextWorkout(in: templates))
    }

    func testCompletedCountOnlyCountsPlanWorkoutsOfTheLastSevenDays() {
        let (templates, plan) = fiveWorkouts()
        let outsider = template(7, "Other")
        let history = [
            finished(1, template: templates[0], at: now.addingTimeInterval(-3600)),
            finished(2, template: templates[1], at: now.addingTimeInterval(-6 * 86_400)),
            finished(3, template: templates[2], at: now.addingTimeInterval(-8 * 86_400)),
            finished(4, template: outsider, at: now.addingTimeInterval(-3600)),
            finished(5, template: nil, at: now.addingTimeInterval(-3600)),
            finished(6, template: templates[3], at: now.addingTimeInterval(3600)),
        ]
        XCTAssertEqual(plan.completedCount(in: history, now: now), 2)
        XCTAssertEqual(plan.completedCount(in: history, now: now, days: 14), 3)
    }

    func testWithoutAPlanTheRotationFollowsTheMostRecentTemplate() {
        let templates = [template(1, "A"), template(2, "B", lastPerformed: now), template(3, "C")]
        XCTAssertEqual(TemplateRotation.next(in: templates)?.name, "C")
        XCTAssertEqual(TemplateRotation.next(in: [templates[0], templates[2]])?.name, "A")
        XCTAssertNil(TemplateRotation.next(in: []))
        XCTAssertEqual(StrengthData(templates: templates).nextTemplate()?.name, "C")
    }

    // MARK: Plans in the data

    func testTheActivePlanDecidesWhatIsNext() {
        let (templates, plan) = fiveWorkouts()
        var data = StrengthData(templates: templates + [template(8, "Z", lastPerformed: now)], plans: [plan])
        XCTAssertEqual(data.nextTemplate()?.name, "W1", "not 'the template after the last performed one'")
        data.plans[0].isActive = false
        XCTAssertEqual(data.nextTemplate()?.name, "W1", "falls back to the template rotation: first in the list, none of the plan's was performed")
        XCTAssertNil(data.activePlan)
    }

    func testRecordingAWorkoutOfThePlanAdvancesItOnceEvenWhenRecordedAgain() {
        let (templates, plan) = fiveWorkouts()
        var data = StrengthData(templates: templates, plans: [plan])
        let first = finished(1, template: templates[0], at: now)
        data.record(first, updateTemplate: nil)
        XCTAssertEqual(data.nextTemplate()?.name, "W2")
        data.record(first, updateTemplate: nil)
        XCTAssertEqual(data.nextTemplate()?.name, "W2", "the same workout id does not advance the rotation again")
        data.record(finished(2, template: templates[1], at: now.addingTimeInterval(60)), updateTemplate: nil)
        data.record(finished(3, template: nil, at: now.addingTimeInterval(120)), updateTemplate: nil)
        XCTAssertEqual(data.nextTemplate()?.name, "W3", "a workout without a template leaves the plan alone")
        XCTAssertEqual(data.plans[0].nextIndex, 2)
    }

    func testSkippingActivatingAndDeletingPlans() {
        let (templates, plan) = fiveWorkouts()
        var second = WorkoutPlan(id: SvcSyncFix.uuid(9901), name: "Two", templateIDs: [templates[0].id, templates[1].id])
        var data = StrengthData(templates: templates, plans: [plan])
        data.savePlan(second)
        XCTAssertEqual(data.plans.map { $0.name }, ["Five", "Two"])
        XCTAssertEqual(data.activePlan?.name, "Five")

        second.isActive = true
        data.savePlan(second)
        XCTAssertEqual(data.activePlan?.name, "Two", "saving an active plan deactivates the others")
        XCTAssertEqual(data.plans.filter { $0.isActive }.count, 1)

        data.activatePlan(id: plan.id)
        XCTAssertEqual(data.activePlan?.name, "Five")
        data.activatePlan(id: SvcSyncFix.uuid(1))
        XCTAssertEqual(data.activePlan?.name, "Five", "an unknown id changes nothing")

        data.skipNextWorkout(planID: plan.id)
        XCTAssertEqual(data.nextTemplate()?.name, "W2")
        data.skipNextWorkout(planID: SvcSyncFix.uuid(1))
        XCTAssertEqual(data.nextTemplate()?.name, "W2")

        data.deletePlan(id: plan.id)
        XCTAssertEqual(data.plans.map { $0.name }, ["Two"])
        XCTAssertEqual(data.templates.count, 5, "the workouts stay")
    }

    // MARK: Rep ranges and notes

    func testRepRangeText() {
        XCTAssertEqual(PlannedSet(weightKg: 0, reps: 8).repsText, "8")
        XCTAssertEqual(PlannedSet(weightKg: 0, reps: 8, repsMax: 10).repsText, "8\u{2013}10")
        XCTAssertEqual(PlannedSet(weightKg: 0, reps: 8, repsMax: 8).repsText, "8")
        XCTAssertEqual(PlannedSet(weightKg: 0, reps: 8, repsMax: 5).repsText, "8")
    }

    func testTemplatesSavedBeforeRangesAndNotesStillLoad() throws {
        let old = """
        [{"id":"\(SvcSyncFix.uuid(1).uuidString)","name":"Old","entries":[{"id":"\(SvcSyncFix.uuid(2).uuidString)",
        "exercise":\(String(data: try StrengthJSON.makeEncoder().encode(exercise("squat")), encoding: .utf8)!),
        "plannedSets":[{"type":"normal","weightKg":80,"reps":6}],"restSeconds":180}]}]
        """
        let persistence = makePersistence()
        try old.write(to: persistence.directory.appendingPathComponent("templates.json"), atomically: true, encoding: .utf8)
        let loaded = persistence.loadTemplates()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded[0].entries[0].note)
        XCTAssertNil(loaded[0].entries[0].plannedSets[0].repsMax)
    }

    func testRangesAndNotesRoundTripThroughTheFile() throws {
        let persistence = makePersistence()
        let saved = [template(1, "W1", note: "Pause on the chest.")]
        try persistence.saveTemplates(saved)
        XCTAssertEqual(persistence.loadTemplates(), saved)
        XCTAssertEqual(persistence.loadTemplates()[0].entries[0].plannedSets[0].repsMax, 10)
    }

    func testAnEntryNoteBecomesTheExerciseNoteAndComesBack() {
        let source = template(1, "W1", note: "Pause on the chest.")
        var state = WorkoutFactory.makeWorkout(from: source, now: now)
        XCTAssertEqual(state.exercises[0].note, "Pause on the chest.")
        XCTAssertEqual(WorkoutFactory.updatedTemplate(source, from: state).entries[0].note, "Pause on the chest.")

        state.exercises[0].note = "  "
        XCTAssertNil(WorkoutFactory.updatedTemplate(source, from: state).entries[0].note, "a blank note is no note")
        XCTAssertEqual(WorkoutFactory.makeWorkout(from: template(2, "W2"), now: now).exercises[0].note, "")
        XCTAssertNil(WorkoutFactory.template(from: WorkoutFactory.makeWorkout(from: template(2, "W2"), now: now), name: "Copy").entries[0].note)
    }

    func testUpdatingATemplateKeepsTheRepRangeUntilTheTopIsReached() {
        let source = template(1, "W1")
        var state = WorkoutFactory.makeWorkout(from: source, now: now)
        state.exercises[0].sets[0].reps = 9
        state.exercises[0].sets[1].reps = 10
        let sets = WorkoutFactory.updatedTemplate(source, from: state).entries[0].plannedSets
        XCTAssertEqual(sets[0].repsMax, 10, "9 is still inside 8-10")
        XCTAssertEqual(sets[0].repsText, "9\u{2013}10")
        XCTAssertNil(sets[1].repsMax, "10 reps reached the top of the range")
        XCTAssertNil(WorkoutFactory.template(from: state, name: "Copy").entries[0].plannedSets[0].repsMax, "a new template has no ranges")
    }

    // MARK: Import

    private func bundleData(_ bundle: PlanBundle) throws -> Data {
        try StrengthJSON.makeEncoder().encode(bundle)
    }

    private func sampleBundle() -> PlanBundle {
        let (templates, plan) = fiveWorkouts()
        let swing = Exercise.custom(name: "Kettlebell swing", muscle: .legs, equipment: .other, tracking: .weightReps, id: "custom-kettlebell-swing")
        var withSwing = templates
        withSwing[0].entries.append(TemplateEntry(exercise: swing, plannedSets: [PlannedSet(weightKg: 0, reps: 15)], restSeconds: 60))
        return PlanBundle(plans: [plan], templates: withSwing, customExercises: [swing])
    }

    @MainActor
    func testImportingAPlanAddsItsWorkoutsAndExercisesAndMakesItActive() throws {
        let persistence = makePersistence()
        let model = StrengthDataModel(persistence: persistence)
        let result = model.importPlan(from: try bundleData(sampleBundle()))
        XCTAssertEqual(try result.get(), PlanImportSummary(plans: 1, templates: 5, customExercises: 1))
        XCTAssertEqual(model.data.templates.count, 5)
        XCTAssertEqual(model.data.customExercises.map { $0.id }, ["custom-kettlebell-swing"])
        XCTAssertEqual(model.data.activePlan?.name, "Five")
        XCTAssertEqual(model.nextTemplate()?.name, "W1")
        XCTAssertNil(model.lastPersistenceError)

        let reloaded = StrengthDataModel(persistence: persistence)
        XCTAssertEqual(reloaded.data.templates, model.data.templates)
        XCTAssertEqual(reloaded.data.plans, model.data.plans)
        XCTAssertEqual(reloaded.data.customExercises, model.data.customExercises)
    }

    @MainActor
    func testImportingAgainReplacesInsteadOfDuplicatingAndKeepsProgress() throws {
        let model = StrengthDataModel(persistence: nil)
        let data = try bundleData(sampleBundle())
        _ = model.importPlan(from: data)
        let id = model.data.templates[2].id
        _ = model.record(finished(1, template: model.data.templates[2], at: now), updateTemplate: nil)
        XCTAssertEqual(model.nextTemplate()?.name, "W4")

        XCTAssertEqual(try model.importPlan(from: data).get(), PlanImportSummary(plans: 1, templates: 5, customExercises: 0))
        XCTAssertEqual(model.data.templates.count, 5)
        XCTAssertEqual(model.data.plans.count, 1)
        XCTAssertEqual(model.nextTemplate()?.name, "W4", "the place in the rotation survives a re-import")
        XCTAssertEqual(model.data.template(id: id)?.lastPerformed, now, "so does the history link")
        XCTAssertEqual(model.data.customExercises.count, 1)
    }

    @MainActor
    func testAnImportedPlanReplacesTheActiveOne() throws {
        let model = StrengthDataModel(persistence: nil)
        model.savePlan(WorkoutPlan(name: "Old", templateIDs: [], isActive: true))
        _ = model.importPlan(from: try bundleData(sampleBundle()))
        XCTAssertEqual(model.data.activePlan?.name, "Five")
        XCTAssertEqual(model.data.plans.count, 2)
    }

    @MainActor
    func testFilesThatAreNotPlansAreRefusedAndChangeNothing() throws {
        let model = StrengthDataModel(persistence: nil)
        XCTAssertEqual(model.importPlan(from: Data("not json".utf8)), .failure(.unreadable))
        XCTAssertEqual(model.importPlan(from: Data("[1,2]".utf8)), .failure(.unreadable))

        var newer = sampleBundle()
        newer.version = 2
        XCTAssertEqual(model.importPlan(from: try bundleData(newer)), .failure(.newerVersion(2)))
        let empty = PlanBundle(plans: [], templates: [])
        XCTAssertEqual(model.importPlan(from: try bundleData(empty)), .failure(.empty))
        XCTAssertTrue(model.data.templates.isEmpty)
        XCTAssertTrue(model.data.plans.isEmpty)
        XCTAssertFalse(PlanImportError.unreadable.message.isEmpty)
    }

    /// `Fixtures/pulse-import-ulppl.json` is the file `tools/youtube-workouts/yt_workout.py` wrote for Jeff Nippard's UL/PPL playlist
    /// (a copy of `out/pulse-import.json`; the tool's tests fail when the two differ). The app must take it as it is.
    @MainActor
    func testTheFileTheVideoToolWritesImportsUnchanged() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/pulse-import-ulppl.json")
        let fileData = try Data(contentsOf: url)
        let bundle = try PlanBundle.decode(from: fileData)

        let model = StrengthDataModel(persistence: nil)
        XCTAssertEqual(try model.importPlan(from: fileData).get(), PlanImportSummary(plans: 1, templates: 5, customExercises: 18))
        // The tool still writes the library's old design history into the built-in exercises; the importer replaces every built-in
        // exercise by the library's own entry, which carries no history. Nothing else may change.
        var written = bundle.templates
        for t in written.indices {
            for e in written[t].entries.indices where ExerciseLibrary.exercise(id: written[t].entries[e].exercise.id) != nil {
                written[t].entries[e].exercise.previousBestE1RM = 0
                written[t].entries[e].exercise.previousSets = []
            }
        }
        XCTAssertEqual(model.data.templates, written, "sanitising changed nothing the tool wrote")
        XCTAssertEqual(model.data.plans.map { $0.templateIDs }, bundle.plans.map { $0.templateIDs })

        let plan = try XCTUnwrap(model.data.activePlan)
        XCTAssertEqual(plan.name, "Jeff Nippard UL/PPL")
        XCTAssertEqual(plan.daysPerWeek, 5)
        let order = plan.workouts(in: model.data.templates).map { $0.name }
        XCTAssertEqual(order, ["UL/PPL \u{00B7} Upper", "UL/PPL \u{00B7} Lower", "UL/PPL \u{00B7} Push", "UL/PPL \u{00B7} Pull", "UL/PPL \u{00B7} Legs"])
        XCTAssertEqual(model.nextTemplate()?.name, order[0])
        XCTAssertEqual(model.data.customExercises.count, 18)
        XCTAssertTrue(model.data.customExercises.allSatisfy { $0.isCustom && $0.id.hasPrefix("custom-") })

        // Every exercise of every workout is a library or an imported custom exercise, and the data is runnable as it is.
        let known = Set(ExerciseLibrary.builtIn.map { $0.id } + model.data.customExercises.map { $0.id })
        for template in model.data.templates {
            XCTAssertFalse(template.entries.isEmpty, template.name)
            for entry in template.entries {
                XCTAssertTrue(known.contains(entry.exercise.id), entry.exercise.id)
                XCTAssertFalse(entry.plannedSets.isEmpty, entry.exercise.name)
            }
        }

        // The push day: bench 3 x 8-10, the last lateral raise... and the notes reach the running workout.
        let push = try XCTUnwrap(model.data.templates.first { $0.name.hasSuffix("Push") })
        XCTAssertEqual(push.entries[0].exercise.id, "bench")
        XCTAssertEqual(push.entries[0].plannedSets.map { $0.repsText }, ["8\u{2013}10", "8\u{2013}10", "8\u{2013}10"])
        let workout = WorkoutFactory.makeWorkout(from: push, now: now)
        XCTAssertEqual(workout.exercises[0].note, push.entries[0].note)
        XCTAssertFalse(workout.exercises[0].note.isEmpty)
        XCTAssertEqual(workout.exercises[0].sets.map { $0.reps }, [8, 8, 8], "the workout starts at the bottom of the range")
    }

    func testAnImportIsBroughtIntoTheRangeTheAppAccepts() {
        let (templates, plan) = fiveWorkouts()
        var wild = templates
        wild[0].name = "   "
        wild[0].lastPerformed = now
        wild[0].entries[0].restSeconds = 99_999
        wild[0].entries[0].note = "  \n "
        wild[0].entries[0].plannedSets = [
            PlannedSet(weightKg: -5, reps: -3, repsMax: 4),
            PlannedSet(weightKg: .infinity, reps: 50_000, repsMax: 60_000),
            PlannedSet(weightKg: 20, reps: 10, repsMax: 10),
        ]
        var tooMany = plan
        tooMany.templateIDs.append(SvcSyncFix.uuid(1))
        tooMany.daysPerWeek = 12
        tooMany.nextIndex = 99
        var data = StrengthData()
        data.importBundle(PlanBundle(plans: [tooMany], templates: wild))

        let first = data.templates[0]
        XCTAssertEqual(first.name, "Workout")
        XCTAssertNil(first.lastPerformed)
        XCTAssertEqual(first.entries[0].restSeconds, WorkoutReducer.maximumRestSeconds)
        XCTAssertNil(first.entries[0].note)
        let sets = first.entries[0].plannedSets
        XCTAssertEqual(sets.map { $0.reps }, [0, 10_000, 10])
        XCTAssertEqual(sets.map { $0.weightKg }, [0, 0, 20])
        XCTAssertEqual(sets.map { $0.repsMax }, [4, nil, nil])
        XCTAssertEqual(data.plans[0].templateIDs.count, 5, "the unknown template was dropped")
        XCTAssertEqual(data.plans[0].nextIndex, 4)
        XCTAssertNil(data.plans[0].daysPerWeek)
    }

    func testBuiltInExercisesComeFromTheLibraryNotFromTheFile() {
        var (templates, plan) = fiveWorkouts()
        templates[0].entries[0].exercise.name = "Hacked name"
        templates[0].entries[0].exercise.cues = ["x"]
        var data = StrengthData()
        data.importBundle(PlanBundle(plans: [plan], templates: templates))
        XCTAssertEqual(data.templates[0].entries[0].exercise, exercise("bench"))

        var clash = Exercise.custom(name: "Squat", muscle: .legs, equipment: .barbell, tracking: .weightReps, id: "squat")
        clash.name = "Not the squat"
        var other = StrengthData()
        other.importBundle(PlanBundle(plans: [plan], templates: templates, customExercises: [clash]))
        XCTAssertTrue(other.customExercises.isEmpty, "a custom exercise never takes a built-in id")
    }

    func testTheImportSummaryReadsAsASentence() {
        XCTAssertEqual(PlanImportSummary(plans: 1, templates: 5, customExercises: 18).message, "Imported 1 plan with 5 workouts and 18 new exercises.")
        XCTAssertEqual(PlanImportSummary(plans: 0, templates: 1, customExercises: 0).message, "Imported 1 workout.")
        XCTAssertEqual(PlanImportSummary(plans: 2, templates: 2, customExercises: 1).message, "Imported 2 plans with 2 workouts and 1 new exercise.")
    }

    // MARK: Plans in the store

    @MainActor
    func testPlansAreSavedAndReloaded() {
        let persistence = makePersistence()
        let (templates, plan) = fiveWorkouts()
        let model = StrengthDataModel(persistence: persistence)
        templates.forEach { model.saveTemplate($0) }
        model.savePlan(plan)
        model.skipNextWorkout(planID: plan.id)
        XCTAssertEqual(StrengthDataModel(persistence: persistence).nextTemplate()?.name, "W2")

        model.deletePlan(id: plan.id)
        XCTAssertTrue(StrengthDataModel(persistence: persistence).data.plans.isEmpty)
        model.savePlan(plan)
        model.activatePlan(id: plan.id)
        XCTAssertEqual(StrengthDataModel(persistence: persistence).data.activePlan?.id, plan.id)
    }

    @MainActor
    func testFinishingAPlanWorkoutAdvancesAndSavesThePlan() {
        let persistence = makePersistence()
        let (templates, plan) = fiveWorkouts()
        let model = StrengthDataModel(persistence: persistence)
        templates.forEach { model.saveTemplate($0) }
        model.savePlan(plan)
        _ = model.record(finished(1, template: templates[0], at: now), updateTemplate: nil)
        XCTAssertEqual(StrengthDataModel(persistence: persistence).nextTemplate()?.name, "W2")
    }

    #if canImport(Combine) || PULSE_COMBINE_SHIM
    @MainActor
    func testTheObservableStorePublishesPlans() throws {
        let store = StrengthStore(persistence: nil)
        XCTAssertTrue(store.plans.isEmpty)
        XCTAssertNil(store.activePlan)
        XCTAssertNil(store.nextTemplate)
        _ = store.importPlan(from: try bundleData(sampleBundle()))
        XCTAssertEqual(store.plans.count, 1)
        XCTAssertEqual(store.activePlan?.name, "Five")
        XCTAssertEqual(store.nextTemplate?.name, "W1")
        store.skipNextWorkout(planID: store.plans[0].id)
        XCTAssertEqual(store.nextTemplate?.name, "W2")
        store.deletePlan(id: store.plans[0].id)
        XCTAssertTrue(store.plans.isEmpty)
        XCTAssertEqual(store.templates.count, 5)
        XCTAssertEqual(store.importPlan(from: Data("x".utf8)), .failure(.unreadable))
    }
    #endif
}
