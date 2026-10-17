import Foundation
import XCTest
@testable import PulseStrengthCore

/// Training plans under the persistence machinery (corrupt-file backup, schema, reset), their consistency when templates change, and the
/// template diff of rep ranges.
final class PlanIntegrationTests: XCTestCase {
    private typealias F = SvcDataFix

    // MARK: Fixtures

    private func makeDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PulseStrength-plans-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func template(_ n: Int, _ name: String) -> WorkoutTemplate {
        WorkoutTemplate(
            id: SvcSyncFix.uuid(7000 + n),
            name: name,
            entries: [
                TemplateEntry(
                    id: SvcSyncFix.uuid(7100 + n), exercise: ExerciseLibrary.exercise(id: "bench")!,
                    plannedSets: [PlannedSet(weightKg: 60, reps: 8, repsMax: 10), PlannedSet(weightKg: 60, reps: 8, repsMax: 10)],
                    restSeconds: 120
                ),
            ]
        )
    }

    private func fourWorkouts() -> (templates: [WorkoutTemplate], plan: WorkoutPlan) {
        let templates = (1...4).map { template($0, "W\($0)") }
        let plan = WorkoutPlan(id: SvcSyncFix.uuid(7900), name: "Four", templateIDs: templates.map { $0.id }, isActive: true)
        return (templates, plan)
    }

    private func block(_ name: String, in directory: URL) throws {
        let target = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: target.appendingPathComponent("keep"))
    }

    // MARK: WorkoutPlan.removeTemplate

    func testRemovingATemplateKeepsTheCursorOnTheWorkoutThatWasNext() {
        let (templates, original) = fourWorkouts()
        var plan = original
        plan.nextIndex = 2
        XCTAssertTrue(plan.removeTemplate(templates[1].id))
        XCTAssertEqual(plan.templateIDs, [templates[0].id, templates[2].id, templates[3].id])
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W3", "an earlier workout left: the next one is still W3")
        XCTAssertEqual(plan.nextIndex, 1)
    }

    func testRemovingTheNextWorkoutMakesTheOneAfterItNext() {
        let (templates, original) = fourWorkouts()
        var plan = original
        plan.nextIndex = 1
        plan.removeTemplate(templates[1].id)
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W3")
        XCTAssertEqual(plan.nextIndex, 1)
    }

    func testRemovingTheLastWorkoutWhileItIsNextWrapsToTheFirst() {
        let (templates, original) = fourWorkouts()
        var plan = original
        plan.nextIndex = 3
        plan.removeTemplate(templates[3].id)
        XCTAssertEqual(plan.nextIndex, 0)
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W1")
    }

    func testRemovingALaterWorkoutLeavesTheCursor() {
        let (templates, original) = fourWorkouts()
        var plan = original
        plan.nextIndex = 1
        plan.removeTemplate(templates[3].id)
        XCTAssertEqual(plan.nextIndex, 1)
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W2")
    }

    func testRemovingATemplateThatIsListedTwiceTakesEveryOccurrence() {
        let (templates, _) = fourWorkouts()
        var plan = WorkoutPlan(name: "Twice", templateIDs: [templates[0].id, templates[1].id, templates[0].id, templates[2].id], nextIndex: 3)
        plan.removeTemplate(templates[0].id)
        XCTAssertEqual(plan.templateIDs, [templates[1].id, templates[2].id])
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W3")
    }

    func testRemovingTheOnlyWorkoutLeavesAnEmptyRotationWithAValidCursor() {
        let (templates, _) = fourWorkouts()
        var plan = WorkoutPlan(name: "One", templateIDs: [templates[0].id], nextIndex: 5)
        XCTAssertTrue(plan.removeTemplate(templates[0].id))
        XCTAssertEqual(plan.templateIDs, [])
        XCTAssertEqual(plan.nextIndex, 0)
        XCTAssertNil(plan.nextWorkout(in: templates))
    }

    func testRemovingATemplateThePlanDoesNotHoldChangesNothing() {
        let (templates, original) = fourWorkouts()
        var plan = original
        XCTAssertFalse(plan.removeTemplate(SvcSyncFix.uuid(1)))
        XCTAssertEqual(plan, original)
        XCTAssertNotNil(plan.nextWorkout(in: templates))
    }

    func testACursorOutsideTheRotationIsWrappedBeforeItIsAdjusted() {
        let (templates, _) = fourWorkouts()
        var plan = WorkoutPlan(name: "Far", templateIDs: templates.map { $0.id }, nextIndex: 6)   // 6 % 4 = 2: W3 is next
        plan.removeTemplate(templates[0].id)
        XCTAssertEqual(plan.nextWorkout(in: templates)?.name, "W3")
    }

    // MARK: Deleting and duplicating templates

    @MainActor
    func testDeletingATemplateTakesItOutOfEveryPlanAndSavesBothFiles() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        let (templates, plan) = fourWorkouts()
        var other = WorkoutPlan(id: SvcSyncFix.uuid(7901), name: "Other", templateIDs: [templates[1].id, templates[2].id], nextIndex: 1)
        other.isActive = false
        let model = StrengthDataModel(persistence: persistence)
        templates.forEach { model.saveTemplate($0) }
        model.savePlan(plan)
        model.savePlan(other)

        try model.deleteTemplate(id: templates[1].id).get()
        XCTAssertEqual(model.data.plans[0].templateIDs, [templates[0].id, templates[2].id, templates[3].id])
        XCTAssertEqual(model.data.plans[1].templateIDs, [templates[2].id])
        XCTAssertEqual(model.data.plans[1].nextWorkout(in: model.data.templates)?.name, "W3")
        let reloaded = StrengthDataModel(persistence: persistence)
        XCTAssertEqual(reloaded.data.plans, model.data.plans, "the plans file was written too")
        XCTAssertEqual(reloaded.data.plans.map { $0.isActive }, [true, false])
    }

    @MainActor
    func testDeletingATemplateOfNoPlanWritesNoPlansFile() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        let model = StrengthDataModel(persistence: persistence)
        model.saveTemplate(template(1, "W1"))
        try model.deleteTemplate(id: SvcSyncFix.uuid(7001)).get()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("plans.json").path))
    }

    @MainActor
    func testADuplicateIsInNoPlanAndTheRotationsStayAsTheyAre() throws {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let (templates, plan) = fourWorkouts()
        let model = StrengthDataModel(persistence: persistence)
        templates.forEach { model.saveTemplate($0) }
        model.savePlan(plan)
        let copy = try model.duplicateTemplate(id: templates[1].id, name: "W2 copy").get()
        XCTAssertEqual(model.data.plans, [plan])
        XCTAssertFalse(model.data.plans[0].templateIDs.contains(copy.id))
        XCTAssertEqual(model.nextTemplate()?.name, "W1")
    }

    @MainActor
    func testEditingACustomExerciseLeavesThePlansAlone() throws {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let (templates, plan) = fourWorkouts()
        let custom = F.customExercise("Hex press")
        var withCustom = templates[0]
        withCustom.entries.append(TemplateEntry(exercise: custom, plannedSets: [PlannedSet(weightKg: 20, reps: 10)], restSeconds: 60))
        let model = StrengthDataModel(persistence: persistence)
        model.addCustomExercise(custom)
        model.saveTemplate(withCustom)
        templates.dropFirst().forEach { model.saveTemplate($0) }
        model.savePlan(plan)
        var renamed = custom
        renamed.name = "Hex press (neutral grip)"
        try model.updateCustomExercise(renamed).get()
        XCTAssertEqual(model.data.plans, [plan])
        XCTAssertEqual(try model.deleteCustomExercise(id: custom.id).get(), 1)
        XCTAssertEqual(model.data.plans, [plan], "the template stays in the rotation, without the exercise")
    }

    // MARK: Sample data

    func testRemovingSampleDataKeepsTheUsersPlansAndTheirOtherTemplates() {
        var data = StrengthData.demo(now: SvcSyncFix.epoch)
        let mine = template(1, "Mine")
        data.saveTemplate(mine)
        let userPlan = WorkoutPlan(id: SvcSyncFix.uuid(7910), name: "Mine only", templateIDs: [mine.id], isActive: true)
        var mixed = WorkoutPlan(id: SvcSyncFix.uuid(7911), name: "Mixed", templateIDs: [SampleData.templateIDs[0], mine.id], nextIndex: 1)
        mixed.isActive = false
        data.savePlan(userPlan)
        data.savePlan(mixed)
        data.activatePlan(id: userPlan.id)

        _ = data.removeSampleData()
        XCTAssertEqual(data.plans.map { $0.id }, [userPlan.id, mixed.id], "no plan is deleted")
        XCTAssertEqual(data.plans[0], userPlan.withActive(true), "a plan without a sample template is untouched")
        XCTAssertEqual(data.plans[1].templateIDs, [mine.id], "the deleted sample template leaves the rotation")
        XCTAssertEqual(data.plans[1].nextWorkout(in: data.templates)?.name, "Mine")
        XCTAssertEqual(data.activePlan?.id, userPlan.id)
    }

    // MARK: Reset

    func testResettingThePlansKeepsTheTemplates() {
        var data = StrengthData()
        let (templates, plan) = fourWorkouts()
        templates.forEach { data.saveTemplate($0) }
        data.savePlan(plan)
        data.resetData(.plans)
        XCTAssertEqual(data.plans, [])
        XCTAssertEqual(data.templates, templates)
    }

    func testResettingTheTemplatesEmptiesTheRotationsButKeepsThePlans() {
        var data = StrengthData()
        let (templates, plan) = fourWorkouts()
        templates.forEach { data.saveTemplate($0) }
        data.savePlan(plan)
        data.resetData(.templates)
        XCTAssertEqual(data.templates, [])
        XCTAssertEqual(data.plans.count, 1)
        XCTAssertEqual(data.plans[0].templateIDs, [])
        XCTAssertEqual(data.plans[0].nextIndex, 0)
        XCTAssertEqual(data.plans[0].name, "Four")
        XCTAssertNil(data.nextTemplate())
    }

    func testPlansBelongToTheScopeAll() {
        XCTAssertTrue(ResetScope.all.contains(.plans))
        var data = StrengthData(plans: [WorkoutPlan(name: "P", templateIDs: [])])
        data.resetData(.all)
        XCTAssertEqual(data, StrengthData())
    }

    @MainActor
    func testResettingThePlansWritesAnEmptyPlansFileAndAllRemovesIt() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        let (templates, plan) = fourWorkouts()
        let model = StrengthDataModel(persistence: persistence)
        templates.forEach { model.saveTemplate($0) }
        model.savePlan(plan)
        try model.resetData(.plans).get()
        XCTAssertEqual(persistence.loadPlans(), [])
        XCTAssertEqual(persistence.loadTemplates().count, 4)

        model.savePlan(plan)
        try model.resetData(.all).get()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("plans.json").path))
        XCTAssertEqual(StrengthDataModel(persistence: persistence).data.plans, [])
    }

    @MainActor
    func testResettingTheTemplatesAlsoWritesTheEmptiedRotations() throws {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let (templates, plan) = fourWorkouts()
        let model = StrengthDataModel(persistence: persistence)
        templates.forEach { model.saveTemplate($0) }
        model.savePlan(plan)
        try model.resetData(.templates).get()
        let reloaded = StrengthDataModel(persistence: persistence)
        XCTAssertEqual(reloaded.data.plans.map { $0.templateIDs }, [[]])
    }

    // MARK: Persistence

    @MainActor
    func testADamagedPlansFileIsBackedUpReportedAndKeptUntilTheNextSave() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory, clock: { SvcSyncFix.epoch })
        let garbage = "{ this is not a plan list"
        try Data(garbage.utf8).write(to: directory.appendingPathComponent("plans.json"))

        let model = StrengthDataModel(persistence: persistence)
        XCTAssertEqual(model.data.plans, [])
        let issue = try XCTUnwrap(model.persistenceIssues.first { $0.fileName == "plans.json" })
        XCTAssertEqual(issue.kind, .unreadableFile)
        let backup = try XCTUnwrap(issue.backupFileName)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(backup)), Data(garbage.utf8))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("plans.json")), Data(garbage.utf8), "loading overwrites nothing")

        let (templates, plan) = fourWorkouts()
        templates.forEach { model.saveTemplate($0) }
        try model.savePlan(plan).get()
        XCTAssertEqual(FileStrengthPersistence(directory: directory).loadPlans(), [plan])
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(backup)), Data(garbage.utf8), "the backup survives the save")
    }

    @MainActor
    func testAFailedPlansWriteIsReportedAndKeptInMemory() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        try block("plans.json", in: directory)
        let (_, plan) = fourWorkouts()
        let model = StrengthDataModel(persistence: persistence)
        guard case .failure = model.savePlan(plan) else { return XCTFail("the file cannot be replaced") }
        XCTAssertNotNil(model.lastPersistenceError)
        XCTAssertEqual(model.data.plans, [plan], "the change stays in memory")
    }

    func testAPlansFileAloneIsADataFileSoNothingIsSeededOverIt() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.savePlans([WorkoutPlan(name: "P", templateIDs: [])])
        XCTAssertTrue(persistence.hasDataFiles)
        svcMain {
            let model = StrengthDataModel(persistence: persistence, seedDemoData: true, now: SvcSyncFix.epoch)
            XCTAssertTrue(model.data.templates.isEmpty)
            XCTAssertEqual(model.data.plans.count, 1)
        }
    }

    func testAMigrationBackupHoldsThePlansFile() throws {
        let directory = makeDirectory()
        let before = FileStrengthPersistence(directory: directory)
        try before.savePlans([WorkoutPlan(name: "P", templateIDs: [])])
        try FileManager.default.removeItem(at: directory.appendingPathComponent("schema.json"))
        let persistence = FileStrengthPersistence(directory: directory, migrations: [PersistenceMigration { _ in }])
        XCTAssertEqual(persistence.currentSchemaVersion, 2)
        XCTAssertEqual(persistence.loadPlans().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("schema-v1-backup/plans.json").path))
    }

    @MainActor
    func testANewerSchemaRefusesToWritePlans() throws {
        let directory = makeDirectory()
        try Data("{\"version\":99}".utf8).write(to: directory.appendingPathComponent("schema.json"))
        let model = StrengthDataModel(persistence: FileStrengthPersistence(directory: directory))
        guard case .failure = model.savePlan(WorkoutPlan(name: "P", templateIDs: [])) else { return XCTFail("a newer data format is never written") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("plans.json").path))
    }

    @MainActor
    func testEveryPlanChangeWritesOnlyThePlansFile() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        let (templates, plan) = fourWorkouts()
        let model = StrengthDataModel(persistence: persistence)
        templates.forEach { model.saveTemplate($0) }
        model.savePlan(plan)
        func written(_ change: () -> Void) -> [String] {
            for name in FileStrengthPersistence.dataFileNames { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
            change()
            return FileStrengthPersistence.dataFileNames
                .filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }.sorted()
        }
        XCTAssertEqual(written { model.skipNextWorkout(planID: plan.id) }, ["plans.json"])
        XCTAssertEqual(written { model.activatePlan(id: plan.id) }, [], "already the active one: nothing changes")
        XCTAssertEqual(written { model.deletePlan(id: SvcSyncFix.uuid(1)) }, [], "an unknown plan changes nothing")
        XCTAssertEqual(written { model.deletePlan(id: plan.id) }, ["plans.json"])
    }

    // MARK: Import

    func testImportedCustomRepsOnlyExercisesCanCarryALoadLikeEveryOtherCustomOne() {
        let ring = Exercise.custom(name: "Ring dip", muscle: .chest, equipment: .bodyweight, tracking: .repsOnly, id: "custom-ring-dip")
        var imported = ring
        imported.allowsAddedWeight = false   // what a file without the flag decodes to
        let hold = Exercise.custom(name: "L-sit", muscle: .core, equipment: .bodyweight, tracking: .duration, id: "custom-lsit")
        let withCustom = WorkoutTemplate(name: "Rings", entries: [
            TemplateEntry(exercise: imported, plannedSets: [PlannedSet(weightKg: 0, reps: 8)], restSeconds: 90),
            TemplateEntry(exercise: hold, plannedSets: [PlannedSet(weightKg: 0, reps: 30)], restSeconds: 60),
        ])
        let bundle = PlanBundle(plans: [], templates: [withCustom], customExercises: [imported, hold]).sanitized()
        XCTAssertEqual(bundle.templates[0].entries.map { $0.exercise.allowsAddedWeight }, [true, false])
        XCTAssertEqual(bundle.customExercises.map { $0.allowsAddedWeight }, [true, false])
        XCTAssertEqual(bundle.customExercises[0], ring)
    }

    // MARK: Template diff and rep ranges

    private func workout(from template: WorkoutTemplate) -> WorkoutState {
        WorkoutFactory.makeWorkout(from: template, now: SvcSyncFix.epoch, id: SvcSyncFix.uuid(7800))
    }

    func testAWorkoutStartedFromARangeIsNotChanged() {
        let planned = template(1, "W1")
        let state = workout(from: planned)
        XCTAssertTrue(TemplateDiff.compute(for: state, against: planned).isEmpty)
    }

    func testARepInsideTheRangeIsNoChange() {
        let planned = template(1, "W1")
        var state = workout(from: planned)
        for reps in [8, 9, 10] {
            state.exercises[0].sets[0].reps = reps
            state.exercises[0].sets[0].isDone = true
            XCTAssertTrue(TemplateDiff.compute(for: state, against: planned).isEmpty, "\(reps) reps are inside 8-10")
        }
    }

    func testARepOutsideTheRangeIsARepsChange() {
        let planned = template(1, "W1")
        var state = workout(from: planned)
        for reps in [7, 11, 15] {
            state.exercises[0].sets[1].reps = reps
            let diff = TemplateDiff.compute(for: state, against: planned)
            XCTAssertEqual(diff.changedExercises.map { $0.kinds }, [[.reps]], "\(reps) reps are outside 8-10")
        }
    }

    func testAPlainNumberStillNeedsTheExactReps() {
        var planned = template(1, "W1")
        planned.entries[0].plannedSets = [PlannedSet(weightKg: 60, reps: 8), PlannedSet(weightKg: 60, reps: 8, repsMax: 8)]
        var state = workout(from: planned)
        state.exercises[0].sets[0].reps = 9
        state.exercises[0].sets[1].reps = 9
        XCTAssertEqual(TemplateDiff.compute(for: state, against: planned).changedExercises.map { $0.kinds }, [[.reps]])
        state.exercises[0].sets[0].reps = 8
        state.exercises[0].sets[1].reps = 8
        XCTAssertTrue(TemplateDiff.compute(for: state, against: planned).isEmpty, "a range whose top is not above its bottom is a plain number")
    }

    func testADifferentRangeInTheTemplateIsARepsChangeForTheWorkoutStartedFromTheOldOne() {
        let old = template(1, "W1")
        let state = workout(from: old)
        var edited = old
        edited.entries[0].plannedSets = [PlannedSet(weightKg: 60, reps: 12, repsMax: 15), PlannedSet(weightKg: 60, reps: 12, repsMax: 15)]
        XCTAssertEqual(TemplateDiff.compute(for: state, against: edited).changedExercises.map { $0.kinds }, [[.reps]])
    }

    func testAnAcceptedUpdateKeepsTheRangeWhileTheRepsAreBelowItsTop() {
        let planned = template(1, "W1")
        var state = workout(from: planned)
        state.exercises[0].sets[0].reps = 9
        state.exercises[0].sets[1].reps = 10
        let updated = WorkoutFactory.updatedTemplate(planned, from: state)
        XCTAssertEqual(updated.entries[0].plannedSets.map { $0.repsMax }, [10, nil])
    }
}

private extension WorkoutPlan {
    func withActive(_ value: Bool) -> WorkoutPlan {
        var copy = self
        copy.isActive = value
        return copy
    }
}
