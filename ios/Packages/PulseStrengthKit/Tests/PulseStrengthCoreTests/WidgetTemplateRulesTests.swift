import Foundation
import XCTest
@testable import PulseStrengthCore

/// widgets/SPEC.md section 2: nextUp, templates, the exercise summary, overload, formCue and loadedBar.
final class WidgetNextUpRuleTests: XCTestCase {
    private let utc = WidFix.context()

    private func threeTemplates(performed: [Date?]) -> [WorkoutTemplate] {
        [
            WidFix.template(1, "Upper A · Push", [WidFix.entry("bench", WidFix.planned(3, 80, 6))], last: performed[0]),
            WidFix.template(2, "Lower A · Quads", [WidFix.entry("squat", WidFix.planned(3, 100, 5))], last: performed[1]),
            WidFix.template(3, "Upper B · Pull", [WidFix.entry("brow", WidFix.planned(3, 60, 8))], last: performed[2]),
        ]
    }

    private func next(_ templates: [WorkoutTemplate], plans: [WorkoutPlan] = []) -> NextUpSummary? {
        WidFix.snapshot(StrengthData(templates: templates, plans: plans)).nextUp
    }

    // MARK: nextUp

    func testNextUpIsTheTemplateAfterTheMostRecentlyPerformedOneInStoreOrder() {
        let day = { (offset: Double) in Optional(WidFix.now.addingTimeInterval(-offset * 86_400)) }
        XCTAssertEqual(next(threeTemplates(performed: [day(5), day(7), day(3)]))?.name, "Upper A · Push", "after Upper B (the newest) comes Upper A: wrapping")
        XCTAssertEqual(next(threeTemplates(performed: [day(5), day(2), day(3)]))?.name, "Upper B · Pull", "after Lower A comes Upper B")
        XCTAssertEqual(next(threeTemplates(performed: [day(1), day(2), day(3)]))?.name, "Lower A · Quads")
    }

    func testNextUpWithNothingPerformedIsTheFirstTemplate() {
        XCTAssertEqual(next(threeTemplates(performed: [nil, nil, nil]))?.name, "Upper A · Push")
        let summary = next(threeTemplates(performed: [nil, nil, nil]))
        XCTAssertNil(summary?.lastPerformedAt)
        XCTAssertNil(summary?.daysSince)
    }

    func testNextUpTakesTheLowestIndexOnATieOfTheMostRecentlyPerformed() {
        let same = Optional(WidFix.now.addingTimeInterval(-86_400))
        XCTAssertEqual(next(threeTemplates(performed: [nil, same, same]))?.name, "Upper B · Pull", "Lower A (index 1) is the latest one, so Upper B comes next")
    }

    func testNextUpOfASingleTemplateIsThatTemplate() {
        let only = WidFix.template(1, "Full Body", [WidFix.entry("bench", WidFix.planned(3, 60, 8))], last: WidFix.now.addingTimeInterval(-86_400))
        let snapshot = WidFix.snapshot(StrengthData(templates: [only]))
        XCTAssertEqual(snapshot.nextUp?.templateID, only.id)
        XCTAssertEqual(snapshot.templates.map { $0.isSuggested }, [true])
    }

    func testNoTemplatesMeansNoNextUpAndAnEmptyLauncher() {
        let snapshot = WidFix.snapshot(StrengthData())
        XCTAssertNil(snapshot.nextUp)
        XCTAssertTrue(snapshot.templates.isEmpty)
        XCTAssertNil(snapshot.overload)
        XCTAssertNil(snapshot.formCue)
        XCTAssertNil(snapshot.loadedBar)
        XCTAssertNil(snapshot.tomorrow)
    }

    func testNextUpDescribesTheTemplate() {
        let template = WidFix.template(1, "Upper A · Push", [
            WidFix.entry("bench", [PlannedSet(type: .warmup, weightKg: 50, reps: 8)] + WidFix.planned(3, 85, 5), rest: 150),
            WidFix.entry("lateral", WidFix.planned(3, 8, 15), rest: 60),
        ], last: WidFix.date(2026, 10, 11, 20, 0))
        let summary = next([template])
        XCTAssertEqual(summary?.templateID, template.id)
        XCTAssertEqual(summary?.name, "Upper A · Push")
        XCTAssertEqual(summary?.splitLabel, "Push day")
        XCTAssertEqual(summary?.exerciseCount, 2)
        XCTAssertEqual(summary?.setCount, 7, "every planned set, warm-ups included")
        XCTAssertEqual(summary?.estimatedMinutes, template.estimatedMinutes)
        XCTAssertEqual(summary?.lastPerformedAt, WidFix.date(2026, 10, 11, 20, 0))
        XCTAssertEqual(summary?.daysSince, 5)
        XCTAssertEqual(summary?.exercises.map { $0.exerciseID }, ["bench", "lateral"])
        XCTAssertEqual(summary?.exercises.map { $0.name }, ["Barbell bench press", "Dumbbell lateral raise"])
        XCTAssertEqual(summary?.exercises.map { $0.muscle }, [.chest, .shoulders])
        XCTAssertEqual(summary?.exercises.map { $0.setCount }, [4, 3], "all planned sets including warm-ups")
        XCTAssertEqual(summary?.exercises.map { $0.summary }, ["3 × 85", "3 × 8"])
        XCTAssertNil(summary?.planName)
        XCTAssertNil(summary?.planPosition)
        XCTAssertNil(summary?.planCount)
    }

    func testNextUpDaysSinceCountsCalendarDays() {
        let template = WidFix.template(1, "Legs", [], last: WidFix.date(2026, 10, 15, 23, 50))
        XCTAssertEqual(next([template])?.daysSince, 1, "23:50 yesterday is 1 day ago")
    }

    // MARK: nextUp and a training plan

    func testNextUpIsTheNextWorkoutOfTheActivePlan() {
        let templates = threeTemplates(performed: [WidFix.now.addingTimeInterval(-86_400), nil, nil])
        let plan = WidFix.plan([templates[2], templates[0], templates[1]], name: "Pull first", nextIndex: 1)
        let summary = next(templates, plans: [plan])
        XCTAssertEqual(summary?.name, "Upper A · Push", "the plan's index 1, although the rotation would say Lower A")
        XCTAssertEqual(summary?.planName, "Pull first")
        XCTAssertEqual(summary?.planPosition, 2, "1-based position in the plan's rotation")
        XCTAssertEqual(summary?.planCount, 3)
        let snapshot = WidFix.snapshot(StrengthData(templates: templates, plans: [plan]))
        XCTAssertEqual(snapshot.templates.filter { $0.isSuggested }.map { $0.name }, ["Upper A · Push"])
    }

    func testAnInactivePlanIsIgnored() {
        let templates = threeTemplates(performed: [nil, nil, nil])
        let plan = WidFix.plan([templates[2], templates[1]], nextIndex: 1, active: false)
        let summary = next(templates, plans: [plan])
        XCTAssertEqual(summary?.name, "Upper A · Push")
        XCTAssertNil(summary?.planName)
    }

    func testAPlanOfTemplatesThatNoLongerExistFallsBackToTheRotationWithoutPlanFields() {
        let templates = threeTemplates(performed: [nil, nil, nil])
        let ghost = WorkoutPlan(name: "Gone", templateIDs: [WidFix.uuid(9_001), WidFix.uuid(9_002)], isActive: true)
        let summary = next(templates, plans: [ghost])
        XCTAssertEqual(summary?.name, "Upper A · Push")
        XCTAssertNil(summary?.planName)
        XCTAssertNil(summary?.planPosition)
    }

    func testThePlanPositionSkipsTemplatesThatWereDeleted() {
        let templates = threeTemplates(performed: [nil, nil, nil])
        let plan = WorkoutPlan(name: "P", templateIDs: [WidFix.uuid(9_001), templates[1].id, templates[2].id], nextIndex: 0, isActive: true)
        let summary = next(templates, plans: [plan])
        XCTAssertEqual(summary?.name, "Lower A · Quads", "the first existing workout after the index")
        XCTAssertEqual(summary?.planPosition, 2)
        XCTAssertEqual(summary?.planCount, 3, "the plan lists three workouts, one of them gone")
    }

    // MARK: templates

    func testTemplatesKeepStoreOrderAndMarkTheSuggestedOne() {
        let templates = threeTemplates(performed: [WidFix.now.addingTimeInterval(-5 * 86_400), nil, WidFix.date(2026, 10, 13, 9, 41)])
        let list = WidFix.snapshot(StrengthData(templates: templates)).templates
        XCTAssertEqual(list.map { $0.name }, ["Upper A · Push", "Lower A · Quads", "Upper B · Pull"])
        XCTAssertEqual(list.map { $0.isSuggested }, [true, false, false], "after Upper B comes Upper A")
        XCTAssertEqual(list.map { $0.templateID }, templates.map { $0.id })
        XCTAssertEqual(list.map { $0.exerciseCount }, [1, 1, 1])
        XCTAssertEqual(list.map { $0.estimatedMinutes }, templates.map { $0.estimatedMinutes })
        XCTAssertEqual(list.map { $0.daysSince }, [5, nil, 3], "a template that was never performed has no days")
        XCTAssertEqual(list.map { $0.lastPerformedAt }, templates.map { $0.lastPerformed })
    }

    func testTemplatesNeverPerformedHaveNoLastPerformed() {
        let list = WidFix.snapshot(StrengthData(templates: threeTemplates(performed: [nil, nil, nil]))).templates
        XCTAssertTrue(list.allSatisfy { $0.lastPerformedAt == nil && $0.daysSince == nil })
        XCTAssertEqual(list.map { $0.isSuggested }, [true, false, false])
    }

    // MARK: Exercise summary

    private func summary(_ exerciseID: String, _ sets: [PlannedSet]) -> String {
        WidgetTemplates.summary(of: WidFix.entry(exerciseID, sets))
    }

    func testExerciseSummaryOfAWeightExerciseIsTheWorkingSetsTimesTheHeaviestWorkingWeight() {
        XCTAssertEqual(summary("bench", [PlannedSet(type: .warmup, weightKg: 100, reps: 3)] + WidFix.planned(3, 85, 5)), "3 × 85", "a heavier warm-up does not count")
        XCTAssertEqual(summary("bench", [PlannedSet(weightKg: 80, reps: 6), PlannedSet(weightKg: 82.5, reps: 5), PlannedSet(weightKg: 77.5, reps: 8)]), "3 × 82.5")
        XCTAssertEqual(summary("bench", [PlannedSet(type: .drop, weightKg: 60, reps: 10), PlannedSet(type: .failure, weightKg: 70, reps: 6)]), "2 × 70")
    }

    func testExerciseSummaryCountsAllSetsWhenThereAreOnlyWarmUps() {
        XCTAssertEqual(summary("bench", [PlannedSet(type: .warmup, weightKg: 40, reps: 8), PlannedSet(type: .warmup, weightKg: 50, reps: 5)]), "2 × 50")
        XCTAssertEqual(summary("bench", []), "0 × 0")
    }

    func testExerciseSummaryOfARepsOnlyExerciseIsTheSetsTimesTheMostReps() {
        XCTAssertEqual(summary("pushup", [PlannedSet(weightKg: 0, reps: 12), PlannedSet(weightKg: 0, reps: 10), PlannedSet(weightKg: 0, reps: 8)]), "3 × 12")
        XCTAssertEqual(summary("pullup", WidFix.planned(4, 0, 6)), "4 × 6")
    }

    func testExerciseSummaryOfADurationExerciseIsTheSetsTimesTheLongestTime() {
        XCTAssertEqual(summary("plank", [PlannedSet(weightKg: 0, reps: 30), PlannedSet(weightKg: 0, reps: 45), PlannedSet(weightKg: 0, reps: 40)]), "3 × 45 s")
    }

    func testExerciseSummaryCountsARepRangeWithTheTopOfTheRange() {
        XCTAssertEqual(summary("pushup", WidFix.planned(3, 0, 8, repsMax: 12)), "3 × 12")
        XCTAssertEqual(summary("plank", WidFix.planned(2, 0, 30, repsMax: 60)), "2 × 60 s")
        XCTAssertEqual(summary("bench", WidFix.planned(3, 80, 6, repsMax: 8)), "3 × 80", "a weight exercise names no reps")
    }
}

final class WidgetOverloadRuleTests: XCTestCase {
    private func overload(
        template entries: [TemplateEntry],
        history: [CompletedWorkout],
        extraTemplates: [WorkoutTemplate] = []
    ) -> OverloadTarget? {
        let template = WidFix.template(1, "Upper A · Push", entries)
        return WidFix.snapshot(StrengthData(templates: [template] + extraTemplates, history: history)).overload
    }

    private func benchHistory(_ sets: [CompletedSet], daysAgo: Double = 5, n: Int = 1) -> [CompletedWorkout] {
        [WidFix.workout(n, "Upper A · Push", daysAgo: daysAgo).with(exercises: [WidFix.lift("bench", sets, n: n)])]
    }

    func testOverloadAddsTheWeightStepWhenLastTimeReachedThePlannedReps() throws {
        let target = try XCTUnwrap(overload(
            template: [WidFix.entry("bench", WidFix.planned(4, 82.5, 6))],
            history: benchHistory([WidFix.set(80, 6), WidFix.set(80, 6), WidFix.set(80, 5)])
        ))
        XCTAssertEqual(target.exerciseID, "bench")
        XCTAssertEqual(target.exerciseName, "Barbell bench press")
        XCTAssertEqual(target.lastWeightKg, 80)
        XCTAssertEqual(target.lastReps, 6)
        XCTAssertEqual(target.lastDaysAgo, 5)
        XCTAssertEqual(target.targetWeightKg, 82.5, "the barbell step is 2.5 kg")
        XCTAssertEqual(target.targetReps, 6)
        XCTAssertEqual(target.targetSets, 4, "the planned working sets")
        XCTAssertEqual(target.deltaKg, 2.5)
    }

    func testOverloadUsesTheExercisesOwnWeightStep() throws {
        let dumbbell = try XCTUnwrap(overload(
            template: [WidFix.entry("incline", WidFix.planned(3, 28, 10))],
            history: [WidFix.workout(1, daysAgo: 3).with(exercises: [WidFix.lift("incline", [WidFix.set(26, 10)], n: 1)])]
        ))
        XCTAssertEqual(dumbbell.targetWeightKg, 28, "dumbbells step by 2 kg")
        XCTAssertEqual(dumbbell.deltaKg, 2)
        let cable = try XCTUnwrap(overload(
            template: [WidFix.entry("pushdown", WidFix.planned(3, 30, 12))],
            history: [WidFix.workout(1, daysAgo: 3).with(exercises: [WidFix.lift("pushdown", [WidFix.set(30, 13)], n: 1)])]
        ))
        XCTAssertEqual(cable.targetWeightKg, 32.5)
        XCTAssertEqual(cable.targetReps, 12, "the planned reps, not last time's")
    }

    func testOverloadAddsOneRepWhenLastTimeFellShortOfThePlannedReps() throws {
        let target = try XCTUnwrap(overload(
            template: [WidFix.entry("bench", WidFix.planned(3, 82.5, 6))],
            history: benchHistory([WidFix.set(80, 5)])
        ))
        XCTAssertEqual(target.targetWeightKg, 80, "same weight")
        XCTAssertEqual(target.targetReps, 6, "one more rep than last time")
        XCTAssertEqual(target.deltaKg, 0)
    }

    func testOverloadNeverAsksForMoreThanThePlannedReps() throws {
        let target = try XCTUnwrap(overload(
            template: [WidFix.entry("bench", WidFix.planned(3, 82.5, 6))],
            history: benchHistory([WidFix.set(80, 4)])
        ))
        XCTAssertEqual(target.targetReps, 5, "min(lastReps + 1, plannedReps)")
        let far = try XCTUnwrap(overload(
            template: [WidFix.entry("bench", WidFix.planned(3, 82.5, 3))],
            history: benchHistory([WidFix.set(80, 2)])
        ))
        XCTAssertEqual(far.targetReps, 3)
    }

    func testOverloadTakesTheBestWorkingSetByEstimatedOneRepMax() throws {
        // 100 × 3 = 110, 90 × 6 = 108, 80 × 12 = 112 (the best), and a heavier warm-up that does not count.
        let sets = [WidFix.set(120, 5, .warmup), WidFix.set(100, 3), WidFix.set(90, 6), WidFix.set(80, 12)]
        let target = try XCTUnwrap(overload(template: [WidFix.entry("bench", WidFix.planned(3, 80, 8))], history: benchHistory(sets)))
        XCTAssertEqual(target.lastWeightKg, 80)
        XCTAssertEqual(target.lastReps, 12)
        XCTAssertEqual(target.targetWeightKg, 82.5)
    }

    func testOverloadLooksAtTheNewestWorkoutThatContainsTheExerciseOnly() throws {
        let history = [
            WidFix.workout(3, "Lower A · Quads", daysAgo: 1).with(exercises: [WidFix.lift("squat", [WidFix.set(100, 5)], n: 3)]),
            WidFix.workout(2, "Upper A · Push", daysAgo: 5).with(exercises: [WidFix.lift("bench", [WidFix.set(80, 6)], n: 2)]),
            WidFix.workout(1, "Upper A · Push", daysAgo: 12).with(exercises: [WidFix.lift("bench", [WidFix.set(90, 6)], n: 1)]),
        ]
        let target = try XCTUnwrap(overload(template: [WidFix.entry("bench", WidFix.planned(3, 82.5, 6))], history: history))
        XCTAssertEqual(target.lastWeightKg, 80, "the heavier session 12 days ago is not the last time")
        XCTAssertEqual(target.lastDaysAgo, 5)
    }

    func testOverloadWalksTheEntriesToTheFirstThatTracksWeightHasAWorkingSetAndHasHistory() throws {
        let entries = [
            WidFix.entry("pullup", WidFix.planned(3, 0, 8)),                                              // does not track weight
            WidFix.entry("ohp", [PlannedSet(type: .warmup, weightKg: 30, reps: 8)]),                       // no working set
            WidFix.entry("bench", WidFix.planned(3, 82.5, 6)),                                            // no history
            WidFix.entry("squat", WidFix.planned(3, 100, 5)),                                             // the one
            WidFix.entry("deadlift", WidFix.planned(3, 120, 5)),
        ]
        let history = [
            WidFix.workout(1, daysAgo: 4).with(exercises: [
                WidFix.lift("ohp", [WidFix.set(40, 8)], n: 1), WidFix.lift("squat", [WidFix.set(97.5, 5)], n: 2), WidFix.lift("deadlift", [WidFix.set(120, 5)], n: 3),
            ]),
        ]
        let target = try XCTUnwrap(overload(template: entries, history: history))
        XCTAssertEqual(target.exerciseID, "squat")
        XCTAssertEqual(target.targetWeightKg, 100)
    }

    func testOverloadIsNilWhenNothingHasHistoryOrNothingTracksWeight() {
        XCTAssertNil(overload(template: [WidFix.entry("bench", WidFix.planned(3, 82.5, 6))], history: []))
        XCTAssertNil(overload(template: [WidFix.entry("pushup", WidFix.planned(3, 0, 12)), WidFix.entry("plank", WidFix.planned(3, 0, 45))], history: benchHistory([WidFix.set(80, 6)])), "no weight exercises")
        XCTAssertNil(overload(template: [], history: benchHistory([WidFix.set(80, 6)])))
    }

    func testOverloadIgnoresAWorkoutThatHoldsOnlyWarmUpsOfTheExercise() {
        XCTAssertNil(overload(template: [WidFix.entry("bench", WidFix.planned(3, 82.5, 6))], history: benchHistory([WidFix.set(60, 8, .warmup)])))
    }

    func testOverloadIsForTheNextUpTemplateOnly() throws {
        // The rotation says Lower A (after Upper A); the bench is only in Upper A.
        let upper = WidFix.template(1, "Upper A · Push", [WidFix.entry("bench", WidFix.planned(3, 82.5, 6))], last: WidFix.now.addingTimeInterval(-86_400))
        let lower = WidFix.template(2, "Lower A · Quads", [WidFix.entry("squat", WidFix.planned(3, 100, 5))])
        let history = [WidFix.workout(1, daysAgo: 1).with(exercises: [WidFix.lift("bench", [WidFix.set(80, 6)], n: 1), WidFix.lift("squat", [WidFix.set(95, 5)], n: 2)])]
        let target = try XCTUnwrap(WidFix.snapshot(StrengthData(templates: [upper, lower], history: history)).overload)
        XCTAssertEqual(target.exerciseID, "squat")
        XCTAssertEqual(target.targetWeightKg, 97.5)
    }

    // MARK: Rep ranges

    func testOverloadWithARepRangeAsksForOneMoreRepUntilTheTopOfTheRange() throws {
        let entries = [WidFix.entry("bench", WidFix.planned(3, 80, 8, repsMax: 10))]
        let target = try XCTUnwrap(overload(template: entries, history: benchHistory([WidFix.set(80, 8)])))
        XCTAssertEqual(target.targetWeightKg, 80)
        XCTAssertEqual(target.targetReps, 9)
        let nearTop = try XCTUnwrap(overload(template: entries, history: benchHistory([WidFix.set(80, 9)])))
        XCTAssertEqual(nearTop.targetReps, 10, "at most the top of the range")
    }

    func testOverloadWithARepRangeAddsWeightAtTheTopAndStartsAgainAtTheBottom() throws {
        let entries = [WidFix.entry("bench", WidFix.planned(3, 80, 8, repsMax: 10))]
        let target = try XCTUnwrap(overload(template: entries, history: benchHistory([WidFix.set(80, 10)])))
        XCTAssertEqual(target.targetWeightKg, 82.5)
        XCTAssertEqual(target.targetReps, 8, "the bottom of the range")
        XCTAssertEqual(target.deltaKg, 2.5)
    }
}

final class WidgetFormCueAndLoadedBarRuleTests: XCTestCase {
    private func snapshot(_ entries: [TemplateEntry], now: Date = WidFix.now) -> WidgetSnapshot {
        WidFix.snapshot(StrengthData(templates: [WidFix.template(1, "Upper A · Push", entries)]), now: now)
    }

    // MARK: formCue

    func testFormCueIsAnEntryOfTheFirstExerciseThatHasCuesRotatingWithTheDayOfTheYear() throws {
        let entries = [WidFix.entry("bench", WidFix.planned(3, 80, 6)), WidFix.entry("incline", WidFix.planned(3, 28, 10))]
        let bench = try XCTUnwrap(ExerciseLibrary.exercise(id: "bench"))
        XCTAssertEqual(bench.cues.count, 3)
        // 16 October 2026 is day 289 of the year: (289 - 1) mod 3 = 0, the first cue.
        for (offset, expected) in [0, 1, 2, 0, 1].enumerated() {
            let cue = try XCTUnwrap(snapshot(entries, now: WidFix.now.addingTimeInterval(Double(offset) * 86_400)).formCue)
            XCTAssertEqual(cue.exerciseID, "bench")
            XCTAssertEqual(cue.exerciseName, "Barbell bench press")
            XCTAssertEqual(cue.count, 3)
            XCTAssertEqual(cue.index, expected + 1, "1-based, day \(289 + offset)")
            XCTAssertEqual(cue.cue, bench.cues[expected])
        }
    }

    func testFormCueSkipsEntriesWhoseExerciseHasNoCues() throws {
        var bare = try XCTUnwrap(ExerciseLibrary.exercise(id: "bench"))
        bare.cues = []
        let entries = [
            TemplateEntry(exercise: bare, plannedSets: WidFix.planned(3, 80, 6), restSeconds: 90),
            WidFix.entry("incline", WidFix.planned(3, 28, 10)),
        ]
        let cue = try XCTUnwrap(snapshot(entries).formCue)
        XCTAssertEqual(cue.exerciseID, "incline")
        XCTAssertEqual(cue.count, 3)
    }

    func testFormCueIsNilWhenNoExerciseHasCues() throws {
        var bare = try XCTUnwrap(ExerciseLibrary.exercise(id: "bench"))
        bare.cues = []
        XCTAssertNil(snapshot([TemplateEntry(exercise: bare, plannedSets: WidFix.planned(3, 80, 6), restSeconds: 90)]).formCue)
        XCTAssertNil(snapshot([]).formCue)
    }

    // MARK: loadedBar

    func testLoadedBarIsTheHeaviestWorkingSetAmongTheExercisesThatUsePlates() throws {
        let entries = [
            WidFix.entry("legpress", WidFix.planned(3, 200, 10)),                                           // a machine: no plates
            WidFix.entry("ohp", WidFix.planned(3, 45, 8)),
            WidFix.entry("bench", [PlannedSet(type: .warmup, weightKg: 100, reps: 3)] + WidFix.planned(3, 85, 5)),
        ]
        let bar = try XCTUnwrap(snapshot(entries).loadedBar)
        XCTAssertEqual(bar.exerciseID, "bench")
        XCTAssertEqual(bar.exerciseName, "Barbell bench press")
        XCTAssertEqual(bar.totalKg, 85, "the 100 kg warm-up is not a working set")
        XCTAssertEqual(bar.barKg, 20)
        XCTAssertEqual(bar.platesPerSide, [25, 5, 2.5], "(85 - 20) / 2 = 32.5 kg a side")
        XCTAssertEqual(bar.leftoverKg, 0)
        XCTAssertEqual(bar.summary, "25 + 5 + 2.5")
    }

    func testLoadedBarTakesTheFirstEntryOnATie() throws {
        let entries = [WidFix.entry("squat", WidFix.planned(3, 100, 5)), WidFix.entry("bench", WidFix.planned(3, 100, 5))]
        XCTAssertEqual(try XCTUnwrap(snapshot(entries).loadedBar).exerciseID, "squat")
    }

    func testLoadedBarUsesTheBarOfTheExercise() throws {
        let bar = try XCTUnwrap(snapshot([WidFix.entry("skull", WidFix.planned(3, 30, 10))]).loadedBar)
        XCTAssertEqual(bar.barKg, 10, "the skull crusher bar weighs 10 kg")
        XCTAssertEqual(bar.platesPerSide, [10])
        XCTAssertEqual(bar.summary, "10")
    }

    func testLoadedBarReportsWhatThePlatesCannotMake() throws {
        let bar = try XCTUnwrap(snapshot([WidFix.entry("bench", WidFix.planned(3, 21, 5))]).loadedBar)
        XCTAssertEqual(bar.platesPerSide, [])
        XCTAssertEqual(bar.leftoverKg, 0.5)
        XCTAssertEqual(bar.summary, "")
    }

    func testLoadedBarIsNilWithoutABarbellWeightExerciseOrBelowTheEmptyBar() {
        XCTAssertNil(snapshot([WidFix.entry("legpress", WidFix.planned(3, 200, 10)), WidFix.entry("pushup", WidFix.planned(3, 0, 12))]).loadedBar, "no weight exercises with plates")
        XCTAssertNil(snapshot([WidFix.entry("bench", WidFix.planned(3, 15, 10))]).loadedBar, "lighter than the bar")
        XCTAssertNil(snapshot([WidFix.entry("bench", [PlannedSet(type: .warmup, weightKg: 60, reps: 5)])]).loadedBar, "no working set")
        XCTAssertNil(snapshot([]).loadedBar)
    }
}
