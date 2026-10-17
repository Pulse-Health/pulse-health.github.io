import XCTest
@testable import PulseStrengthCore

// MARK: - What changed in the kept exercises

final class TemplateDiffLoadsTests: XCTestCase {
    private let template = PresFix.upperA()

    private func fresh() -> WorkoutState { PresFix.freshUpperA() }

    private func diff(_ state: WorkoutState) -> TemplateDiff { TemplateDiff.compute(for: state, against: template) }

    private func entryID(_ n: Int) -> UUID { PresFix.uuid(0x200 + n, 0) }

    private func changes(_ state: WorkoutState) -> [UUID: Set<TemplateDiff.Change>] {
        Dictionary(uniqueKeysWithValues: diff(state).changedExercises.map { ($0.entryID, $0.kinds) })
    }

    private func edit(_ s: WorkoutState, _ action: WorkoutAction) -> WorkoutState { PresFix.reduced(s, action, at: 1) }

    // The design's workout: bench = [W 50x8, W 70x5, 82.5x6, 82.5x6, 85x6] (rest 150), incline 3 x 28 x 10 (90), ohp 3 x 45 x 8 (120),
    // lateral 3 x 8 x 15 and pushdown 3 x 30 x 12 (superset A, rest 60), crossover 3 x 15 x 12 (60).

    func testAnUnchangedWorkoutAsksNothing() {
        XCTAssertTrue(diff(fresh()).isEmpty)
        XCTAssertEqual(diff(fresh()), TemplateDiff())
        XCTAssertTrue(diff(fresh()).changedExercises.isEmpty)
    }

    func testLoggingSetsIsNoChange() {
        XCTAssertTrue(diff(PresFix.loggedEverything(fresh())).isEmpty)
        XCTAssertTrue(diff(PresFix.goldenState()).isEmpty)
    }

    func testAWorkingSetWeight() {
        let s = fresh()
        let changed = edit(s, .setWeight(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[2].id, kg: 87.5))
        XCTAssertEqual(changes(changed), [entryID(1): [.weight]])
        XCTAssertEqual(diff(changed).changedExercises.map { $0.name }, ["Barbell bench press"])
        XCTAssertFalse(diff(changed).hasStructureChanges)
        XCTAssertFalse(diff(changed).isEmpty)
    }

    func testAWarmUpIsNotCompared() {
        let s = fresh()
        var changed = edit(s, .setWeight(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[0].id, kg: 55))
        changed = edit(changed, .setReps(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[1].id, reps: 3))
        XCTAssertTrue(diff(changed).isEmpty, "warm-up weights and reps are not what a template is updated for")
    }

    func testWorkingSetReps() {
        let s = fresh()
        let changed = edit(s, .setReps(exerciseID: s.exercises[1].id, setID: s.exercises[1].sets[0].id, reps: 12))
        XCTAssertEqual(changes(changed), [entryID(2): [.reps]])
    }

    func testTheWeightIsComparedAfterRoundingToAHundredthOfAKilogram() {
        let s = fresh()
        var same = s
        same.exercises[0].sets[2].weightKg = 82.504                    // a value the reducer never stores
        XCTAssertTrue(diff(same).isEmpty)
        same.exercises[0].sets[2].weightKg = 82.51
        XCTAssertEqual(changes(same), [entryID(1): [.weight]])
        same.exercises[0].sets[2].weightKg = 82.4949
        XCTAssertEqual(changes(same), [entryID(1): [.weight]], "82.49 is not 82.5")
        same.exercises[0].sets[2].weightKg = .nan
        XCTAssertEqual(changes(same), [entryID(1): [.weight]], "a weight that is not a number never traps")
    }

    func testAddingOrDeletingASetIsASetCountChange() {
        let s = fresh()
        let added = edit(s, .addSet(exerciseID: s.exercises[1].id))
        XCTAssertEqual(changes(added), [entryID(2): [.setCount]], "a copy of the last set changes neither weight nor reps")
        let deleted = edit(s, .deleteSet(exerciseID: s.exercises[2].id, setID: s.exercises[2].sets[2].id))
        XCTAssertEqual(changes(deleted), [entryID(3): [.setCount]])
        // a set that is added and edited is a count change only: the working sets cannot be paired any more
        var both = added
        both = edit(both, .setWeight(exerciseID: s.exercises[1].id, setID: both.exercises[1].sets[3].id, kg: 40))
        XCTAssertEqual(changes(both), [entryID(2): [.setCount]])
    }

    func testAWarmUpThatIsAddedCountsAsASetNotAsAWorkingSet() {
        let s = fresh()
        var changed = edit(s, .addSet(exerciseID: s.exercises[1].id))
        changed = edit(changed, .setSetType(exerciseID: s.exercises[1].id, setID: changed.exercises[1].sets[3].id, type: .warmup))
        XCTAssertEqual(changes(changed), [entryID(2): [.setCount]], "the three working sets are as planned")
    }

    func testASetTypeChange() {
        let s = fresh()
        let dropped = edit(s, .setSetType(exerciseID: s.exercises[1].id, setID: s.exercises[1].sets[2].id, type: .drop))
        XCTAssertEqual(changes(dropped), [entryID(2): [.setType]])
        let warmedUp = edit(s, .setSetType(exerciseID: s.exercises[1].id, setID: s.exercises[1].sets[0].id, type: .warmup))
        XCTAssertEqual(changes(warmedUp), [entryID(2): [.setType]])
        // back to what it was
        XCTAssertTrue(diff(edit(dropped, .setSetType(exerciseID: s.exercises[1].id, setID: s.exercises[1].sets[2].id, type: .normal))).isEmpty)
    }

    func testTheRest() {
        let s = fresh()
        let changed = edit(s, .setRest(exerciseID: s.exercises[2].id, seconds: 90))
        XCTAssertEqual(changes(changed), [entryID(3): [.restSeconds]])
        XCTAssertTrue(diff(edit(s, .setRest(exerciseID: s.exercises[2].id, seconds: 120))).isEmpty, "the same rest")
        XCTAssertEqual(changes(edit(s, .setRest(exerciseID: s.exercises[2].id, seconds: 0))), [entryID(3): [.restSeconds]], "timer off")
    }

    func testSeveralChangesInOneExercise() {
        var s = fresh()
        s = edit(s, .setWeight(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[4].id, kg: 90))
        s = edit(s, .setReps(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[4].id, reps: 4))
        s = edit(s, .setRest(exerciseID: s.exercises[0].id, seconds: 180))
        s = edit(s, .setSetType(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[3].id, type: .failure))
        XCTAssertEqual(changes(s), [entryID(1): [.weight, .reps, .restSeconds, .setType]])
        s = edit(s, .addSet(exerciseID: s.exercises[0].id))
        XCTAssertEqual(changes(s), [entryID(1): [.setCount, .restSeconds]], "with another number of sets neither the types nor the working sets are paired")
    }

    func testTheChangedExercisesComeInWorkoutOrder() {
        var s = fresh()
        s = edit(s, .setRest(exerciseID: s.exercises[5].id, seconds: 30))
        s = edit(s, .setReps(exerciseID: s.exercises[1].id, setID: s.exercises[1].sets[0].id, reps: 9))
        s = edit(s, .addSet(exerciseID: s.exercises[3].id))
        XCTAssertEqual(diff(s).changedExercises.map { $0.entryID }, [entryID(2), entryID(4), entryID(6)])
    }

    func testStructureAndLoadsTogether() {
        var s = fresh()
        s = edit(s, .removeExercise(exerciseID: s.exercises[2].id))
        s = edit(s, .addExercises([PresFix.lib("dips")]))
        s = edit(s, .setWeight(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[2].id, kg: 80))
        let result = diff(s)
        XCTAssertEqual(result.added, 1)
        XCTAssertEqual(result.removed, 1)
        XCTAssertEqual(result.changedExercises.map { $0.entryID }, [entryID(1)])
        XCTAssertTrue(result.hasStructureChanges)
    }

    func testAnAddedExerciseIsNotAlsoAChangedOne() {
        var s = fresh()
        s = edit(s, .addExercises([PresFix.lib("bench")]))
        XCTAssertEqual(diff(s).added, 1)
        XCTAssertTrue(diff(s).changedExercises.isEmpty)
    }

    func testWithoutTheTemplateOnlyTheStructureIsTold() {
        var s = fresh()
        s = edit(s, .setWeight(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[2].id, kg: 80))
        XCTAssertTrue(TemplateDiff.compute(for: s).isEmpty, "compute(for:) never compared the sets")
        XCTAssertTrue(TemplateDiff.compute(for: s, against: nil).isEmpty)
        s = edit(s, .addExercises([PresFix.lib("dips")]))
        XCTAssertEqual(TemplateDiff.compute(for: s), TemplateDiff(added: 1, removed: 0, reordered: false))
        XCTAssertEqual(TemplateDiff.compute(for: s, against: nil), TemplateDiff(added: 1, removed: 0, reordered: false))
    }

    func testAnEntryTheTemplateNoLongerHasIsSkipped() {
        var shorter = template
        shorter.entries.remove(at: 1)
        var s = fresh()
        s = edit(s, .setReps(exerciseID: s.exercises[1].id, setID: s.exercises[1].sets[0].id, reps: 9))
        XCTAssertTrue(TemplateDiff.compute(for: s, against: shorter).changedExercises.isEmpty)
    }

    func testTimedAndRepsOnlyExercises() {
        let plank = PresFix.lib("plank")
        let planned = TemplateEntry(
            id: PresFix.uuid(0x2A1, 0), exercise: plank, plannedSets: PresFix.planned(2, 0, 45), restSeconds: 45
        )
        let pullup = TemplateEntry(
            id: PresFix.uuid(0x2A2, 0), exercise: PresFix.lib("pullup"), plannedSets: PresFix.planned(2, 0, 8), restSeconds: 90
        )
        let pushup = TemplateEntry(
            id: PresFix.uuid(0x2A3, 0), exercise: PresFix.lib("pushup"), plannedSets: PresFix.planned(2, 0, 12), restSeconds: 60
        )
        let t = WorkoutTemplate(id: PresFix.uuid(0x2FE, 1), name: "Core", entries: [planned, pullup, pushup])
        var s = WorkoutFactory.makeWorkout(from: t, now: PresFix.t0)
        XCTAssertTrue(TemplateDiff.compute(for: s, against: t).isEmpty)
        s = edit(s, .setReps(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[0].id, reps: 60))
        s = edit(s, .setWeight(exerciseID: s.exercises[1].id, setID: s.exercises[1].sets[0].id, kg: -15))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: TemplateDiff.compute(for: s, against: t).changedExercises.map { ($0.entryID, $0.kinds) }),
            [planned.id: [.reps], pullup.id: [.weight]], "seconds are reps; an added or assisted load is a weight"
        )
        // a push-up set that an old file gave a weight is not a change: it has no weight to edit
        var odd = s
        odd.exercises[2].sets[0].weightKg = 20
        XCTAssertNil(TemplateDiff.compute(for: odd, against: t).changedExercises.first { $0.entryID == pushup.id })
    }

    // MARK: Text

    func testTheSummaryNamesTheFirstTwoChanges() {
        var s = fresh()
        s = edit(s, .setWeight(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[2].id, kg: 87.5))
        XCTAssertEqual(diff(s).summary, "Barbell bench press weight")
        s = edit(s, .addSet(exerciseID: s.exercises[1].id))
        XCTAssertEqual(diff(s).summary, "Barbell bench press weight, Incline dumbbell press sets")
        s = edit(s, .setRest(exerciseID: s.exercises[2].id, seconds: 60))
        XCTAssertEqual(diff(s).summary, "Barbell bench press weight, Incline dumbbell press sets and 1 more")
        s = edit(s, .setRest(exerciseID: s.exercises[3].id, seconds: 30))
        s = edit(s, .setRest(exerciseID: s.exercises[4].id, seconds: 30))
        XCTAssertEqual(diff(s).summary, "Barbell bench press weight, Incline dumbbell press sets and 3 more")
    }

    func testTheSummaryPutsTheStructureFirstAndJoinsSeveralKinds() {
        var s = fresh()
        s = edit(s, .addExercises([PresFix.lib("dips")]))
        s = edit(s, .setReps(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[2].id, reps: 4))
        s = edit(s, .setWeight(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[2].id, kg: 90))
        XCTAssertEqual(diff(s).summary, "1 added, Barbell bench press weight and reps")
        s = edit(s, .setRest(exerciseID: s.exercises[0].id, seconds: 200))
        XCTAssertEqual(diff(s).summary, "1 added, Barbell bench press weight, reps and rest")
        s = edit(s, .addSet(exerciseID: s.exercises[0].id))
        XCTAssertEqual(diff(s).summary, "1 added, Barbell bench press sets and rest")
        XCTAssertEqual(diff(s).structureSummary, "1 added")
    }

    func testTheSetTypesReadAsSetTypes() {
        let s = fresh()
        let changed = edit(s, .setSetType(exerciseID: s.exercises[1].id, setID: s.exercises[1].sets[2].id, type: .drop))
        XCTAssertEqual(diff(changed).summary, "Incline dumbbell press set types")
    }

    func testTheSummaryOfNothingIsNone() {
        XCTAssertEqual(TemplateDiff().summary, "none")
        XCTAssertEqual(TemplateDiff().structureSummary, "none")
        XCTAssertEqual(TemplateDiff(added: 0, removed: 1, reordered: true).summary, "1 removed, new order")
    }

    // MARK: Coding

    func testADiffWrittenBeforeTheChangedExercisesDecodes() throws {
        let old = try JSONDecoder().decode(TemplateDiff.self, from: Data("{\"added\":1,\"removed\":0,\"reordered\":true}".utf8))
        XCTAssertEqual(old, TemplateDiff(added: 1, removed: 0, reordered: true))
        XCTAssertTrue(old.changedExercises.isEmpty)
        let full = TemplateDiff(
            added: 0, removed: 0, reordered: false,
            changedExercises: [TemplateDiff.ChangedExercise(entryID: PresFix.uuid(1, 1), name: "Bench", kinds: [.weight, .setType])]
        )
        XCTAssertEqual(try JSONDecoder().decode(TemplateDiff.self, from: try JSONEncoder().encode(full)), full)
        XCTAssertEqual(TemplateDiff.Change.allCases, [.setCount, .weight, .reps, .restSeconds, .setType])
        XCTAssertEqual(TemplateDiff.ChangedExercise(entryID: PresFix.uuid(1, 1), name: "x", kinds: []).id, PresFix.uuid(1, 1))
    }
}

// MARK: - Asking to update the template

final class TemplateUpdatePromptTests: XCTestCase {
    private func check(_ state: WorkoutState, _ prompt: TemplateUpdatePrompt?, template: WorkoutTemplate? = PresFix.upperA()) -> ActiveWorkoutPresentation.FinishCheck {
        let presentation: ActiveWorkoutPresentation
        if let prompt {
            presentation = WorkoutPresenter.present(
                state, now: PresFix.at(10), recovery: DemoRecovery.provider, template: template, templateUpdatePrompt: prompt
            )
        } else {
            presentation = WorkoutPresenter.present(state, now: PresFix.at(10), recovery: DemoRecovery.provider)
        }
        return presentation.finishCheck
    }

    private var heavier: WorkoutState {
        let s = PresFix.freshUpperA()
        return PresFix.reduced(s, .setWeight(exerciseID: s.exercises[0].id, setID: s.exercises[0].sets[2].id, kg: 90), at: 1)
    }

    private var withNewExercise: WorkoutState {
        PresFix.reduced(PresFix.freshUpperA(), .addExercises([PresFix.lib("dips")]), at: 1)
    }

    func testWhenChangedAsksForLoadsAndStructure() {
        XCTAssertTrue(check(heavier, .whenChanged).asksToUpdateTemplate)
        XCTAssertEqual(check(heavier, .whenChanged).diffMessage, "Changes: Barbell bench press weight.")
        XCTAssertTrue(check(withNewExercise, .whenChanged).asksToUpdateTemplate)
        XCTAssertEqual(check(withNewExercise, .whenChanged).diffMessage, "Changes: 1 added.")
        XCTAssertEqual(check(heavier, .whenChanged).templateDiff.changedExercises.count, 1)
    }

    func testStructureOnlyKeepsTodaysBehaviour() {
        let weight = check(heavier, .structureOnly)
        XCTAssertFalse(weight.asksToUpdateTemplate, "a heavier set is not worth a question")
        XCTAssertEqual(weight.diffMessage, "Changes: none.")
        let structure = check(withNewExercise, .structureOnly)
        XCTAssertTrue(structure.asksToUpdateTemplate)
        XCTAssertEqual(structure.diffMessage, "Changes: 1 added.")
        var both = withNewExercise
        both = PresFix.reduced(both, .setWeight(exerciseID: both.exercises[0].id, setID: both.exercises[0].sets[2].id, kg: 90), at: 2)
        XCTAssertEqual(check(both, .structureOnly).diffMessage, "Changes: 1 added.", "the loads are left out of the text too")
    }

    func testNeverAsksForAnything() {
        XCTAssertFalse(check(heavier, .never).asksToUpdateTemplate)
        XCTAssertFalse(check(withNewExercise, .never).asksToUpdateTemplate)
    }

    func testNothingChangedNeverAsksWhateverThePreference() {
        for prompt in TemplateUpdatePrompt.allCases {
            let unchanged = check(PresFix.goldenState(), prompt)
            XCTAssertFalse(unchanged.asksToUpdateTemplate, "\(prompt)")
            XCTAssertEqual(unchanged.diffMessage, "Changes: none.")
            XCTAssertFalse(check(PresFix.loggedEverything(PresFix.freshUpperA()), prompt).asksToUpdateTemplate, "\(prompt)")
        }
    }

    func testAWorkoutWithoutATemplateNeverAsks() {
        var free = withNewExercise
        free.templateID = nil
        for prompt in TemplateUpdatePrompt.allCases {
            XCTAssertFalse(check(free, prompt).asksToUpdateTemplate, "\(prompt)")
        }
    }

    func testWithoutTheTemplateThePresenterTellsTheStructureAsBefore() {
        XCTAssertFalse(check(heavier, nil).asksToUpdateTemplate, "no template to compare with: today's behaviour")
        XCTAssertTrue(check(withNewExercise, nil).asksToUpdateTemplate)
        XCTAssertFalse(check(heavier, .whenChanged, template: nil).asksToUpdateTemplate)
    }

    func testThePromptedUpdateHasTheNewLoads() {
        var s = heavier
        s = PresFix.reduced(s, .setReps(exerciseID: s.exercises[1].id, setID: s.exercises[1].sets[0].id, reps: 12), at: 2)
        s = PresFix.reduced(s, .setRest(exerciseID: s.exercises[2].id, seconds: 90), at: 3)
        XCTAssertTrue(check(s, .whenChanged).asksToUpdateTemplate)
        let updated = WorkoutFactory.updatedTemplate(PresFix.upperA(), from: s)
        XCTAssertEqual(updated.entries.map { $0.id }, PresFix.upperA().entries.map { $0.id }, "kept entries keep their ids")
        XCTAssertEqual(updated.entries[0].plannedSets.map { $0.weightKg }, [50, 70, 90, 82.5, 85])
        XCTAssertEqual(updated.entries[1].plannedSets.map { $0.reps }, [12, 10, 10])
        XCTAssertEqual(updated.entries[2].restSeconds, 90)
        // and against the updated template the workout asks nothing any more
        XCTAssertTrue(TemplateDiff.compute(for: s, against: updated).isEmpty)
        XCTAssertEqual(updated.id, PresFix.upperA().id)
        XCTAssertEqual(updated.name, PresFix.upperA().name)
    }
}

// MARK: - Through the engine and the store

final class TemplateUpdateEngineTests: XCTestCase {
    @MainActor
    private func change(_ rig: SvcRig) -> UUID {
        let state = rig.engine.state!
        rig.engine.send(.setWeight(exerciseID: state.exercises[0].id, setID: state.exercises[0].sets[2].id, kg: 90))
        return state.id
    }

    func testTheEngineComparesWithTheSavedTemplateAndFollowsTheChoice() throws {
        try svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            XCTAssertFalse(try XCTUnwrap(rig.engine.presentation(now: rig.clock.now)).finishCheck.asksToUpdateTemplate, "nothing changed")
            XCTAssertTrue(rig.engine.templateDiff().isEmpty)

            _ = change(rig)
            XCTAssertEqual(rig.model.preferences.askToUpdateTemplate, .whenChanged, "the default")
            XCTAssertTrue(try XCTUnwrap(rig.engine.presentation(now: rig.clock.now)).finishCheck.asksToUpdateTemplate)
            XCTAssertEqual(rig.engine.templateDiff().changedExercises.map { $0.name }, ["Barbell bench press"])

            var preferences = rig.model.preferences
            preferences.askToUpdateTemplate = .structureOnly
            _ = rig.model.updatePreferences(preferences)
            XCTAssertFalse(try XCTUnwrap(rig.engine.presentation(now: rig.clock.now)).finishCheck.asksToUpdateTemplate)
            XCTAssertEqual(rig.engine.templateDiff().changedExercises.count, 1, "the diff itself does not depend on the choice")
            rig.engine.send(.addExercises([ExerciseLibrary.exercise(id: "dips")!]))
            XCTAssertTrue(try XCTUnwrap(rig.engine.presentation(now: rig.clock.now)).finishCheck.asksToUpdateTemplate)

            preferences.askToUpdateTemplate = .never
            _ = rig.model.updatePreferences(preferences)
            XCTAssertFalse(try XCTUnwrap(rig.engine.presentation(now: rig.clock.now)).finishCheck.asksToUpdateTemplate)
        }
    }

    func testAnUnchangedWorkoutNeverAsksAndFinishingKeepsTheTemplate() throws {
        try svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            rig.logSets(20)
            XCTAssertFalse(try XCTUnwrap(rig.engine.presentation(now: rig.clock.now)).finishCheck.asksToUpdateTemplate)
            let before = rig.upperA
            XCTAssertNotNil(rig.engine.finish(updateTemplate: false))
            XCTAssertEqual(rig.model.template(id: before.id)?.entries, before.entries)
        }
    }

    func testUpdatingTheTemplateStoresTheNewWeights() throws {
        try svcMain {
            let rig = SvcRig(self)
            rig.startUpperA()
            _ = change(rig)
            rig.logSets(5)
            XCTAssertNotNil(rig.engine.finish(updateTemplate: true))
            let stored = try XCTUnwrap(rig.model.template(id: rig.upperA.id))
            XCTAssertEqual(stored.entries[0].plannedSets.map { $0.weightKg }, [50, 70, 90, 82.5, 85])
        }
    }

    func testTheMirrorHasNoTemplateAndTellsTheStructureOnly() throws {
        try svcMain {
            let phone = SvcRig(self)
            phone.startUpperA()
            let watch = SvcRig(self, role: .mirror, seed: false)
            watch.engine.receive(phone.engine.makeEnvelope(now: phone.clock.now))
            let state = try XCTUnwrap(watch.engine.state)
            watch.engine.send(.setWeight(exerciseID: state.exercises[0].id, setID: state.exercises[0].sets[2].id, kg: 90), origin: .watch)
            XCTAssertTrue(watch.engine.templateDiff().isEmpty, "the Watch does not hold the template")
            XCTAssertFalse(try XCTUnwrap(watch.engine.presentation(now: watch.clock.now)).finishCheck.asksToUpdateTemplate)
        }
    }
}
