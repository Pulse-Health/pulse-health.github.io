import Foundation
import XCTest
@testable import PulseStrengthCore

/// The builder as a whole (widgets/SPEC.md section 2): the demo data, an empty store, the goal and body weight inputs, what is copied
/// from the context, and the rebuild a widget does from the files.
final class WidgetSnapshotBuilderTests: XCTestCase {
    private let utc = WidFix.context()

    private func demo(_ context: WidgetContext? = nil) -> WidgetSnapshot {
        WidFix.snapshot(StrengthData.demo(now: WidFix.now), context: context ?? utc)
    }

    // MARK: The demo data

    func testTheDemoDataGivesTheNumbersOfTheRules() throws {
        let snapshot = demo()
        XCTAssertEqual(snapshot.schemaVersion, WidgetSnapshot.currentSchemaVersion)
        XCTAssertEqual(snapshot.generatedAt, WidFix.now)
        XCTAssertEqual(snapshot.timeZoneID, "UTC")

        // Friday 16 October: one workout this week (Upper B on Tuesday), three days since it, the week before had three workouts.
        XCTAssertEqual(snapshot.week.completed, 1)
        XCTAssertEqual(snapshot.week.goal, 4)
        XCTAssertEqual(snapshot.week.days.map { $0.label }, [nil, "UB", nil, nil, nil, nil, nil])
        XCTAssertEqual(snapshot.week.daysSinceLastWorkout, 3)
        XCTAssertEqual(snapshot.week.streakWeeks, 0, "last week had 3 of 4")

        // After Upper B (3 days ago) comes Upper A.
        XCTAssertEqual(snapshot.nextUp?.name, "Upper A · Push")
        XCTAssertEqual(snapshot.nextUp?.daysSince, 5)
        XCTAssertEqual(snapshot.templates.map { $0.isSuggested }, [true, false, false])
        XCTAssertEqual(snapshot.lastSession?.name, "Upper B · Pull")
        XCTAssertEqual(snapshot.lastSession?.durationMinutes, 52)

        // The one record of the demo: bench, 85 x 5 ten days ago.
        let pr = try XCTUnwrap(snapshot.latestPR)
        XCTAssertEqual(pr.exerciseID, "bench")
        XCTAssertEqual(pr.estimated1RM, 85 * (1 + 5.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(pr.deltaKg, 85 * (1 + 5.0 / 30) - 95, accuracy: 1e-9)
        XCTAssertFalse(pr.isFresh)

        // Bench last time: 80 x 6, so 82.5 x 6 today.
        XCTAssertEqual(snapshot.overload?.lastWeightKg, 80)
        XCTAssertEqual(snapshot.overload?.targetWeightKg, 82.5)
        XCTAssertEqual(snapshot.overload?.targetSets, 3)

        XCTAssertEqual(snapshot.freshness.map { $0.daysSince }, [5, 3, 3, 3, 7, nil])
        XCTAssertEqual(snapshot.freshness.map { $0.status }, [.ready, .recovering, .recovering, .recovering, .ready, .ready])
        XCTAssertEqual(snapshot.weeklySets.totalSets, 15)
        XCTAssertEqual(snapshot.weeklySets.laggingMuscle, .chest)
        XCTAssertEqual(snapshot.month.title, "October")
        XCTAssertEqual(snapshot.month.leadingBlankDays, 3)
        XCTAssertEqual(snapshot.month.sessionCount, 5)
        XCTAssertEqual(snapshot.year.sessionCount, 5)
        XCTAssertEqual(snapshot.year.tonnes, 31.9)
        XCTAssertEqual(snapshot.block?.name, "Block 1")
        XCTAssertEqual(snapshot.block?.weekIndex, 3)
        XCTAssertEqual(snapshot.formCue?.exerciseID, "bench")
        XCTAssertEqual(snapshot.loadedBar?.summary, "25 + 5 + 2.5")
        XCTAssertNil(snapshot.restDay, "one workout this week and none yesterday")
        XCTAssertEqual(snapshot.tomorrow?.plannedMinuteOfDay, 530)
        XCTAssertEqual(snapshot.tomorrow?.weekday, "Saturday")
        XCTAssertEqual(snapshot.bodyMap.message, "Chest untouched. Upper A is next in line.")
    }

    func testTheDemoLiftsAndPlateausFollowTheRules() {
        let snapshot = demo()
        XCTAssertEqual(snapshot.lifts.map { $0.exerciseID }, ["bench", "crossover", "incline", "lateral", "ohp", "pushdown", "brow", "crow"])
        let bench = snapshot.lifts[0]
        XCTAssertEqual(bench.points.map { $0.value }, [93, 99.2, 96])
        XCTAssertEqual(bench.prIndex, 1)
        XCTAssertEqual(bench.deltaKg, -3.2)
        XCTAssertEqual(bench.sessionCount, 3)
        XCTAssertEqual(snapshot.lifts[6].sessionCount, 1)
        XCTAssertNil(snapshot.lifts[6].prIndex)
        XCTAssertEqual(snapshot.plateaus.map { $0.exerciseID }, ["bench", "crossover", "incline", "lateral"])
        XCTAssertEqual(snapshot.plateaus.map { $0.status }, [.falling, .falling, .falling, .falling])
        XCTAssertEqual(snapshot.strengthRatio?.exerciseID, "bench")
        XCTAssertNil(snapshot.strengthRatio?.ratio, "the demo data has no body weight")
    }

    func testTheDemoSnapshotSurvivesTheStoreEncoding() throws {
        let snapshot = demo()
        let data = try StrengthJSON.makeEncoder().encode(snapshot)
        XCTAssertEqual(try StrengthJSON.makeDecoder().decode(WidgetSnapshot.self, from: data), snapshot)
    }

    func testTheSnapshotIsAPureFunctionOfItsInput() {
        let data = StrengthData.demo(now: WidFix.now)
        XCTAssertEqual(WidFix.snapshot(data), WidFix.snapshot(data))
    }

    func testTheOrderOfTheHistoryDoesNotMatterWhenAllFinishTimesDiffer() {
        // The history is newest first by contract; a shuffled list gives the same snapshot because every rule orders by finishedAt.
        let data = StrengthData.demo(now: WidFix.now)
        var shuffled = data
        shuffled.history = [data.history[2], data.history[0], data.history[4], data.history[1], data.history[3]]
        XCTAssertEqual(WidFix.snapshot(shuffled), WidFix.snapshot(data))
    }

    // MARK: An empty store

    func testAnEmptyStoreGivesAnEmptyButCompleteSnapshot() {
        let snapshot = WidFix.snapshot(StrengthData())
        XCTAssertEqual(snapshot.week.days.count, 7)
        XCTAssertEqual(snapshot.week.completed, 0)
        XCTAssertEqual(snapshot.week.streakWeeks, 0)
        XCTAssertNil(snapshot.week.lastWorkoutAt)
        XCTAssertNil(snapshot.week.daysSinceLastWorkout)
        XCTAssertNil(snapshot.nextUp)
        XCTAssertEqual(snapshot.templates, [])
        XCTAssertNil(snapshot.lastSession)
        XCTAssertNil(snapshot.latestPR)
        XCTAssertNil(snapshot.overload)
        XCTAssertEqual(snapshot.freshness.map { $0.muscle }, MuscleGroup.allCases)
        XCTAssertTrue(snapshot.freshness.allSatisfy { $0.daysSince == nil && $0.status == .ready })
        XCTAssertEqual(snapshot.weeklySets.muscles.count, 6)
        XCTAssertEqual(snapshot.weeklySets.totalSets, 0)
        XCTAssertEqual(snapshot.weeklySets.setsToGo, 48)
        XCTAssertEqual(snapshot.lifts, [])
        XCTAssertEqual(snapshot.month.days.count, 31)
        XCTAssertEqual(snapshot.plateaus, [])
        XCTAssertEqual(snapshot.year.monthlyTonnes, Array(repeating: 0, count: 12))
        XCTAssertNil(snapshot.block)
        XCTAssertNil(snapshot.formCue)
        XCTAssertNil(snapshot.loadedBar)
        XCTAssertNil(snapshot.strengthRatio)
        XCTAssertNil(snapshot.restDay)
        XCTAssertNil(snapshot.tomorrow)
        XCTAssertEqual(snapshot.bodyMap.levels.count, 6)
        XCTAssertEqual(snapshot.bodyMap.untouched, MuscleGroup.allCases)
        XCTAssertEqual(snapshot.bodyMap.message, "Chest untouched.")
        XCTAssertNil(snapshot.readiness)
        XCTAssertEqual(snapshot.partners, [])
        XCTAssertNil(snapshot.active)
    }

    func testTheEmptySnapshotHelperIsTheBuilderOnNoData() {
        let context = WidFix.context("Europe/Berlin", goal: 5)
        XCTAssertEqual(WidgetSnapshot.empty(now: WidFix.now, context: context), WidFix.snapshot(StrengthData(), context: context))
        XCTAssertEqual(WidgetSnapshot.empty(now: WidFix.now, context: context).week.goal, 5)
    }

    func testAStoreOfTemplatesOnlyHasANextUpButNoHistoryCards() {
        let template = WidFix.template(1, "Upper A · Push", [WidFix.entry("bench", WidFix.planned(3, 80, 6))])
        let snapshot = WidFix.snapshot(StrengthData(templates: [template]))
        XCTAssertEqual(snapshot.nextUp?.name, "Upper A · Push")
        XCTAssertNil(snapshot.nextUp?.daysSince)
        XCTAssertNil(snapshot.lastSession)
        XCTAssertNil(snapshot.overload, "no history")
        XCTAssertNil(snapshot.block)
        XCTAssertNotNil(snapshot.formCue)
        XCTAssertEqual(snapshot.loadedBar?.totalKg, 80)
        XCTAssertEqual(snapshot.tomorrow?.templateName, "Upper A · Push")
        XCTAssertNil(snapshot.tomorrow?.plannedMinuteOfDay)
    }

    func testAStoreWithoutWeightExercisesHasNoLiftCards() {
        let bodyweight = WidFix.template(1, "Calisthenics", [WidFix.entry("pushup", WidFix.planned(3, 0, 12)), WidFix.entry("plank", WidFix.planned(3, 0, 45))])
        let history = [WidFix.workout(1, "Calisthenics", daysAgo: 2).with(exercises: [
            WidFix.lift("pushup", [WidFix.set(0, 12)], n: 1), WidFix.lift("plank", [WidFix.set(0, 45)], n: 2),
        ])]
        let snapshot = WidFix.snapshot(StrengthData(templates: [bodyweight], history: history))
        XCTAssertEqual(snapshot.lifts, [])
        XCTAssertEqual(snapshot.plateaus, [])
        XCTAssertNil(snapshot.overload)
        XCTAssertNil(snapshot.loadedBar)
        XCTAssertNil(snapshot.strengthRatio)
        XCTAssertNil(snapshot.block?.liftName)
        XCTAssertEqual(snapshot.formCue?.exerciseID, "pushup", "cues still work")
        XCTAssertNotNil(snapshot.nextUp)
        XCTAssertEqual(snapshot.nextUp?.exercises.map { $0.summary }, ["3 × 12", "3 × 45 s"])
    }

    // MARK: The weekly goal

    func testTheGoalIsTheContextsWeeklyGoalBroughtIntoOneToSeven() {
        XCTAssertEqual(WidFix.snapshot(StrengthData(), context: WidFix.context(goal: 5)).week.goal, 5)
        XCTAssertEqual(WidFix.snapshot(StrengthData(), context: WidFix.context(goal: 0)).week.goal, 1)
        XCTAssertEqual(WidFix.snapshot(StrengthData(), context: WidFix.context(goal: 12)).week.goal, 7)
        XCTAssertEqual(WidFix.snapshot(StrengthData()).week.goal, 4, "the default")
    }

    func testTheActivePlansDaysPerWeekIsTheGoalWhenItHasOne() {
        let templates = [WidFix.template(1, "Upper"), WidFix.template(2, "Lower")]
        let plan = WidFix.plan(templates, daysPerWeek: 3)
        let withPlan = WidFix.snapshot(StrengthData(templates: templates, plans: [plan]), context: WidFix.context(goal: 5))
        XCTAssertEqual(withPlan.week.goal, 3)
        let noTarget = WidFix.plan(templates, daysPerWeek: nil)
        XCTAssertEqual(WidFix.snapshot(StrengthData(templates: templates, plans: [noTarget]), context: WidFix.context(goal: 5)).week.goal, 5, "a plan without a target leaves the setting")
        let inactive = WidFix.plan(templates, daysPerWeek: 3, active: false)
        XCTAssertEqual(WidFix.snapshot(StrengthData(templates: templates, plans: [inactive]), context: WidFix.context(goal: 5)).week.goal, 5, "only the active plan counts")
    }

    func testAPlansDaysPerWeekIsBroughtIntoOneToSevenToo() {
        let templates = [WidFix.template(1, "Upper")]
        let goal = { (days: Int) in WidFix.snapshot(StrengthData(templates: templates, plans: [WidFix.plan(templates, daysPerWeek: days)])).week.goal }
        XCTAssertEqual(goal(0), 1)
        XCTAssertEqual(goal(9), 7)
        XCTAssertEqual(goal(6), 6)
    }

    func testThePlansGoalDecidesTheStreakAndTheRestDay() {
        // Two workouts in each of the last two weeks and Tuesday + Wednesday of this one; nothing yesterday (Thursday), now Friday.
        let templates = [WidFix.template(1, "Upper")]
        var history: [CompletedWorkout] = []
        for week in 0..<3 {
            for day in [13, 14] {
                history.append(WidFix.workout(history.count + 1, at: WidFix.date(2026, 10, day, 9, 0).addingTimeInterval(Double(-week) * 7 * 86_400)))
            }
        }
        let twoPerWeek = WidFix.plan(templates, daysPerWeek: 2)
        let strict = StrengthData(templates: templates, history: history, plans: [WidFix.plan(templates, daysPerWeek: 3)])
        let relaxed = StrengthData(templates: templates, history: history, plans: [twoPerWeek])
        XCTAssertEqual(WidFix.snapshot(relaxed).week.streakWeeks, 3)
        XCTAssertNotNil(WidFix.snapshot(relaxed).restDay, "2 of 2: a rest day")
        XCTAssertEqual(WidFix.snapshot(strict).week.streakWeeks, 0)
        XCTAssertNil(WidFix.snapshot(strict).restDay)
    }

    // MARK: Copied from the context

    func testReadinessPartnersAndTheRunningWorkoutAreCopiedFromTheContext() {
        let readiness = ReadinessSummary(score: 82, label: "Ready", message: "Good sleep.", source: "Pulse")
        let partners = [PartnerWeek(name: "Sam", initials: "S", completed: 4, goal: 4, closedWeek: true)]
        let state = WorkoutFactory.makeWorkout(from: SampleData.templates(now: WidFix.now)[0], now: WidFix.now)
        let active = SnapshotBuilder.make(from: state, now: WidFix.now)
        var context = WidFix.context()
        context.readiness = readiness
        context.partners = partners
        context.active = active
        let snapshot = WidFix.snapshot(StrengthData(), context: context)
        XCTAssertEqual(snapshot.readiness, readiness)
        XCTAssertEqual(snapshot.partners, partners)
        XCTAssertEqual(snapshot.active, active)
    }

    func testTheBodyWeightComesFromTheContextOrTheStoredWeighIns() {
        let history = BuilderFix.history()
        let weights = [BodyWeightEntry(date: WidFix.date(2026, 10, 10), kg: 80)]
        let stored = WidFix.snapshot(StrengthData(history: history, bodyWeights: weights))
        XCTAssertEqual(stored.strengthRatio?.bodyweightKg, 80)
        XCTAssertEqual(stored.strengthRatio?.ratio, 1.24)
        let override = WidFix.snapshot(StrengthData(history: history, bodyWeights: weights), context: WidFix.context(bodyweightKg: 90))
        XCTAssertEqual(override.strengthRatio?.bodyweightKg, 90)
        let none = WidFix.snapshot(StrengthData(history: history))
        XCTAssertNil(none.strengthRatio?.bodyweightKg)
    }

    // MARK: Damaged files

    func testValuesFromADamagedFileNeverCrashTheBuilder() {
        let broken = CompletedSet(type: .normal, weightKg: .infinity, reps: Int.max, rir: Int.min, loggedAt: Date(timeIntervalSince1970: .infinity))
        let samples = (0..<20).map { HeartRateSample(bpm: $0 % 2 == 0 ? Int.max : Int.min, at: WidFix.now) }
        let workouts = [
            WidFix.workout(1, at: Date.distantPast, durationSeconds: Int.max, volumeKg: .nan).with(exercises: [
                WidFix.lift("bench", [broken, WidFix.set(.nan, 5), WidFix.set(80, 6, at: Date(timeIntervalSince1970: .nan))], best: .infinity, n: 1),
            ]),
            WidFix.workout(2, at: Date.distantFuture, durationSeconds: Int.min, volumeKg: .infinity, heartRate: samples),
            WidFix.workout(3, at: Date(timeIntervalSince1970: .nan), durationSeconds: 0, volumeKg: -5),
            WidFix.workout(4, at: Date(timeIntervalSince1970: -1e18)),
        ]
        let template = WidFix.template(1, "Upper A · Push", [WidFix.entry("bench", WidFix.planned(3, 80, 6))], last: Date(timeIntervalSince1970: .nan))
        let snapshot = WidFix.snapshot(StrengthData(templates: [template], history: workouts))
        XCTAssertEqual(snapshot.week.days.count, 7)
        XCTAssertEqual(snapshot.month.days.count, 31)
        XCTAssertEqual(snapshot.year.monthlyTonnes.count, 12)
        XCTAssertEqual(snapshot.freshness.count, 6)
    }

    // MARK: A big history

    func testAHistoryOfThousandsOfWorkoutsIsBuiltQuickly() {
        // A workout every day and a half for twelve years: every week has four or five, so with a goal of 2 the streak hits its cap.
        var history: [CompletedWorkout] = []
        for index in 0..<3_000 {
            history.append(WidFix.workout(index + 1, "Upper A · Push", daysAgo: Double(index) * 1.5, volumeKg: 5_000).with(exercises: [
                WidFix.lift("bench", [WidFix.set(60 + Double(index % 20), 5), WidFix.set(70, 5, .warmup)], n: 1),
                WidFix.lift("squat", [WidFix.set(80 + Double(index % 10), 5)], n: 2),
            ]).with(muscles: [MuscleSets(muscle: .chest, sets: 3), MuscleSets(muscle: .legs, sets: 3)]))
        }
        let templates = [WidFix.template(1, "Upper A · Push", [WidFix.entry("bench", WidFix.planned(3, 82.5, 5))]), WidFix.template(2, "Lower", [WidFix.entry("squat", WidFix.planned(3, 100, 5))])]
        let started = Date()
        let snapshot = WidFix.snapshot(StrengthData(templates: templates, history: history), context: WidFix.context(goal: 2))
        XCTAssertLessThan(Date().timeIntervalSince(started), 20)
        XCTAssertEqual(snapshot.week.streakWeeks, 520)
        XCTAssertEqual(snapshot.lifts.map { $0.exerciseID }, ["bench", "squat"])
        XCTAssertEqual(snapshot.year.sessionCount, history.filter { $0.finishedAt >= WidFix.date(2026, 1, 1) }.count)
        XCTAssertEqual(snapshot.lastSession?.workoutID, history[0].id)
    }
}

/// A few history helpers of the builder tests.
private enum BuilderFix {
    /// Bench sessions with the estimates 93, 99.2 and 96 (newest first).
    static func history() -> [CompletedWorkout] {
        [(1, 96.0), (2, 99.2), (3, 93.0)].map { offset, value in
            WidFix.workout(offset, daysAgo: Double(offset) * 4).with(exercises: [WidFix.lift("bench", [WidFix.set(50, 5)], best: value, n: offset)])
        }
    }
}

// MARK: - What a widget rebuilds from the files

final class WidgetSnapshotStoreRebuildTests: XCTestCase {
    private func makeDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetRebuild-" + UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private let yesterday = WidFix.now.addingTimeInterval(-86_400)

    func testWithoutAnyDataThereIsNothingToShow() {
        XCTAssertNil(WidgetSnapshotStore.loadForDisplay(now: WidFix.now, directory: nil))
        XCTAssertNil(WidgetSnapshotStore.loadForDisplay(now: WidFix.now, directory: makeDirectory()))
    }

    func testAStoredSnapshotOfTheSameDayIsShownAsItIs() throws {
        let directory = makeDirectory()
        var stored = WidFix.snapshot(StrengthData.demo(now: WidFix.now))
        stored.week.goal = 6                                          // unlike anything the files would give
        try WidgetSnapshotStore.save(stored, directory: directory)
        XCTAssertEqual(WidgetSnapshotStore.loadForDisplay(now: WidFix.now.addingTimeInterval(3_600), directory: directory), stored)
    }

    func testAStoredSnapshotOfAnEarlierDayIsRebuiltFromTheFilesWithTheirGoalPlanAndWeighIns() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        let data = StrengthData.demo(now: WidFix.now)
        try persistence.saveTemplates(data.templates)
        try persistence.saveHistory(data.history)
        try persistence.saveSettings(StrengthSettings(weeklyGoal: 5))
        try persistence.saveBodyWeights([BodyWeightEntry(date: WidFix.date(2026, 10, 10), kg: 80)])
        let plan = WorkoutPlan(name: "Pull first", templateIDs: [data.templates[2].id, data.templates[0].id], nextIndex: 1, daysPerWeek: nil, isActive: true)
        try persistence.savePlans([plan])
        try WidgetSnapshotStore.save(WidFix.snapshot(StrengthData.demo(now: yesterday), now: yesterday), directory: directory)

        let rebuilt = try XCTUnwrap(WidgetSnapshotStore.loadForDisplay(now: WidFix.now, directory: directory))
        XCTAssertEqual(rebuilt.generatedAt, WidFix.now)
        XCTAssertEqual(rebuilt.week.goal, 5, "the goal is the setting in settings.json")
        XCTAssertEqual(rebuilt.nextUp?.name, "Upper A · Push")
        XCTAssertEqual(rebuilt.nextUp?.planName, "Pull first")
        XCTAssertEqual(rebuilt.nextUp?.planPosition, 2)
        XCTAssertEqual(rebuilt.nextUp?.planCount, 2)
        XCTAssertEqual(rebuilt.strengthRatio?.bodyweightKg, 80, "the newest weigh-in")
        XCTAssertEqual(rebuilt.lastSession?.name, "Upper B · Pull")
    }

    func testTheActivePlansTargetBeatsTheSettingWhenRebuilding() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        let data = StrengthData.demo(now: WidFix.now)
        try persistence.saveTemplates(data.templates)
        try persistence.saveHistory(data.history)
        try persistence.saveSettings(StrengthSettings(weeklyGoal: 5))
        try persistence.savePlans([WorkoutPlan(name: "P", templateIDs: data.templates.map { $0.id }, daysPerWeek: 3, isActive: true)])
        let rebuilt = try XCTUnwrap(WidgetSnapshotStore.loadForDisplay(now: WidFix.now, directory: directory))
        XCTAssertEqual(rebuilt.week.goal, 3)
    }

    func testRebuildingFromFilesWithoutASettingsFileUsesTheDefaultGoal() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        try persistence.saveTemplates(StrengthData.demo(now: WidFix.now).templates)
        XCTAssertEqual(WidgetSnapshotStore.loadForDisplay(now: WidFix.now, directory: directory)?.week.goal, 4)
    }

    func testTheBodyWeightOfTheStoredSnapshotCarriesOverWhenTheFilesHoldNone() throws {
        let directory = makeDirectory()
        let persistence = FileStrengthPersistence(directory: directory)
        let data = StrengthData.demo(now: WidFix.now)
        try persistence.saveTemplates(data.templates)
        try persistence.saveHistory(data.history)
        try WidgetSnapshotStore.save(WidFix.snapshot(data, context: WidFix.context(bodyweightKg: 77), now: yesterday), directory: directory)
        XCTAssertEqual(WidgetSnapshotStore.loadForDisplay(now: WidFix.now, directory: directory)?.strengthRatio?.bodyweightKg, 77)
    }
}
