import Foundation
import XCTest
@testable import PulseStrengthCore

// Every text the Core builds for a weight, in kilograms and in pounds, with the separators of an explicit locale; the plate
// calculator and the steppers in pounds; the unit in the workout settings and its way to the Watch.

private let enUS = Locale(identifier: "en_US")
private let deDE = Locale(identifier: "de_DE")

private enum UF {
    static let start = SvcSyncFix.epoch

    static func uuid(_ n: Int) -> UUID { SvcSyncFix.uuid(0x5300 + n) }

    static func exercise(_ id: String) -> Exercise { ExerciseLibrary.exercise(id: id)! }

    /// Bench press with a previous best of 100 kg (e1RM) and two previous sets, a pull-up and a plank.
    ///
    /// Bench: a done warm-up 40 x 10, a done set 60 x 8, then 82.5 x 6 and 100 x 5 pending. `rest` starts a 90 s rest.
    static func state(unit: WeightUnit, previousBest: Double = 100, rest: Bool = false) -> WorkoutState {
        var bench = exercise("bench")
        bench.previousBestE1RM = previousBest
        bench.previousSets = [PreviousSet(weightKg: 80, reps: 6), PreviousSet(weightKg: 82.5, reps: 5)]
        let benchEntry = WorkoutExercise(id: uuid(1), exercise: bench, sets: [
            LoggedSet(id: uuid(11), type: .warmup, weightKg: 40, reps: 10, isDone: true),
            LoggedSet(id: uuid(12), type: .normal, weightKg: 60, reps: 8, isDone: true),
            LoggedSet(id: uuid(13), type: .normal, weightKg: 82.5, reps: 6),
            LoggedSet(id: uuid(14), type: .normal, weightKg: 100, reps: 5),
        ], restSeconds: 150)
        let pullEntry = WorkoutExercise(id: uuid(2), exercise: exercise("pullup"), sets: [LoggedSet(id: uuid(21), weightKg: 0, reps: 8)], restSeconds: 90)
        let plankEntry = WorkoutExercise(id: uuid(3), exercise: exercise("plank"), sets: [LoggedSet(id: uuid(31), weightKg: 0, reps: 45)], restSeconds: 45)
        return WorkoutState(
            id: uuid(9), name: "Push", exercises: [benchEntry, pullEntry, plankEntry], startedAt: start,
            rest: rest ? RestState(endsAt: start.addingTimeInterval(150), totalSeconds: 90) : nil,
            lastLogged: SetRef(exerciseID: uuid(1), setID: uuid(12)),
            settings: WorkoutSettings(weightUnit: unit)
        )
    }

    static func present(_ state: WorkoutState, _ locale: Locale = enUS) -> ActiveWorkoutPresentation {
        WorkoutPresenter.present(state, now: start.addingTimeInterval(60), recovery: DemoRecovery.provider, locale: locale)
    }

    static func snapshot(_ state: WorkoutState, _ locale: Locale = enUS) -> WorkoutSnapshot {
        SnapshotBuilder.make(from: state, now: start.addingTimeInterval(60), locale: locale)
    }

    static func rows(_ presentation: ActiveWorkoutPresentation) -> [ActiveWorkoutPresentation.SetRow] {
        presentation.card?.rows ?? []
    }
}

// MARK: - Presenter

final class UnitsPresenterTests: XCTestCase {
    func testKilogramGoldenStrings() throws {
        let p = UF.present(UF.state(unit: .kg, rest: true))
        XCTAssertEqual(p.header.volumeText, "480")
        let card = try XCTUnwrap(p.card)
        XCTAssertEqual(card.weightColumnTitle, "kg")
        XCTAssertEqual(card.repsColumnTitle, "Reps")
        XCTAssertEqual(card.rows.map { $0.weightText }, ["40", "60", "82.5", "100"])
        XCTAssertEqual(card.rows.map { $0.previousText }, ["–", "80 × 6", "82.5 × 5", "–"], "warm-ups match warm-ups, working sets working sets")
        XCTAssertEqual(try XCTUnwrap(p.dock).nextSetText, "Next · Set 2 · 82.5 kg × 6")
        XCTAssertNil(card.coachTip, "no coach tip while a rest runs")
        XCTAssertEqual(card.rows[2].accessibilityLabel, "Set 3, working set, 82.5 kilograms, 6 reps, not logged")
        XCTAssertEqual(card.rows[1].accessibilityLabel, "Set 2, working set, 60 kilograms, 8 reps, logged")
    }

    func testPoundGoldenStrings() throws {
        let p = UF.present(UF.state(unit: .lb, rest: true))
        XCTAssertEqual(p.header.volumeText, "1,058", "480 kg are 1,058.2 lb")
        let card = try XCTUnwrap(p.card)
        XCTAssertEqual(card.weightColumnTitle, "lb")
        XCTAssertEqual(card.rows.map { $0.weightText }, ["88.2", "132.3", "181.9", "220.5"])
        XCTAssertEqual(card.rows.map { $0.previousText }, ["–", "176.4 × 6", "181.9 × 5", "–"])
        XCTAssertEqual(try XCTUnwrap(p.dock).nextSetText, "Next · Set 2 · 181.9 lb × 6")
        XCTAssertEqual(card.rows[2].accessibilityLabel, "Set 3, working set, 181.9 pounds, 6 reps, not logged")
        XCTAssertEqual(card.rows[1].accessibilityLabel, "Set 2, working set, 132.3 pounds, 8 reps, logged")
    }

    func testGermanSeparators() throws {
        let kg = UF.present(UF.state(unit: .kg, rest: true), deDE)
        XCTAssertEqual(UF.rows(kg).map { $0.weightText }, ["40", "60", "82,5", "100"])
        XCTAssertEqual(UF.rows(kg).map { $0.previousText }, ["–", "80 × 6", "82,5 × 5", "–"])
        XCTAssertEqual(try XCTUnwrap(kg.dock).nextSetText, "Next · Set 2 · 82,5 kg × 6")
        XCTAssertEqual(UF.rows(kg)[2].accessibilityLabel, "Set 3, working set, 82,5 kilograms, 6 reps, not logged")

        let lb = UF.present(UF.state(unit: .lb, rest: true), deDE)
        XCTAssertEqual(lb.header.volumeText, "1.058")
        XCTAssertEqual(UF.rows(lb).map { $0.weightText }, ["88,2", "132,3", "181,9", "220,5"])
        XCTAssertEqual(try XCTUnwrap(lb.dock).nextSetText, "Next · Set 2 · 181,9 lb × 6")
    }

    func testTheDefaultLocaleIsEnglishAndTheDefaultUnitComesFromTheState() {
        let state = UF.state(unit: .kg, rest: true)
        XCTAssertEqual(
            WorkoutPresenter.present(state, now: UF.start, recovery: DemoRecovery.provider),
            WorkoutPresenter.present(state, now: UF.start, recovery: DemoRecovery.provider, locale: enUS)
        )
        XCTAssertEqual(
            SnapshotBuilder.make(from: state, now: UF.start),
            SnapshotBuilder.make(from: state, now: UF.start, locale: enUS)
        )
    }

    func testTheCoachTipNamesAWeightInTheUnitOfTheWorkout() throws {
        let kg = try XCTUnwrap(UF.present(UF.state(unit: .kg)).card?.coachTip)
        XCTAssertEqual(kg, "87.5 kg × 5 on your last set would beat your best estimated 1RM of 100 kg.")
        let lb = try XCTUnwrap(UF.present(UF.state(unit: .lb)).card?.coachTip)
        XCTAssertEqual(lb, "190 lb × 5 on your last set would beat your best estimated 1RM of 220 lb.")
        let german = try XCTUnwrap(UF.present(UF.state(unit: .kg), deDE).card?.coachTip)
        XCTAssertEqual(german, "87,5 kg × 5 on your last set would beat your best estimated 1RM of 100 kg.")
    }

    func testTheCoachTipStepIsTheStepOfTheExerciseInTheUnitOfTheWorkout() throws {
        // A previous best of 98 kg does not land on a multiple of 5 lb: 5 reps need 84.0 kg = 185.2 lb.
        let barbell = try XCTUnwrap(UF.present(UF.state(unit: .lb, previousBest: 98)).card?.coachTip)
        XCTAssertTrue(barbell.hasPrefix("190 lb × 5"), barbell)
        var other = UF.state(unit: .lb, previousBest: 98)
        other.exercises[0].exercise.equipment = .other
        let bodyweightStep = try XCTUnwrap(UF.present(other).card?.coachTip)
        XCTAssertTrue(bodyweightStep.hasPrefix("187.5 lb × 5"), bodyweightStep)
        let kg = try XCTUnwrap(UF.present(UF.state(unit: .kg, previousBest: 98)).card?.coachTip)
        XCTAssertTrue(kg.hasPrefix("85 kg × 5"), kg)
    }

    func testTheWeightOfAPoundCoachTipReallyBeatsTheRecordOnceStored() throws {
        let tip = try XCTUnwrap(UF.present(UF.state(unit: .lb)).card?.coachTip)
        XCTAssertTrue(tip.hasPrefix("190 lb"))
        // Typing 190 lb stores 86.18 kg; that set must be a personal record against the previous best of 100 kg.
        let kg = try XCTUnwrap(WeightFormatter.parse("190", unit: .lb, locale: enUS))
        let stored = try XCTUnwrap(WorkoutReducer.roundedWeight(kg))
        XCTAssertGreaterThan(Estimated1RM.epley(weightKg: stored, reps: 5), 100 + PresenterSupport.recordMargin)
        let below = try XCTUnwrap(WorkoutReducer.roundedWeight(WeightUnit.lb.toKg(185)))
        XCTAssertLessThan(Estimated1RM.epley(weightKg: below, reps: 5), 100 + PresenterSupport.recordMargin, "one step less does not")
    }

    func testLowestBeatingWeightFollowsTheStepOfTheUnit() {
        XCTAssertEqual(PresenterSupport.lowestBeatingWeight(baseline: 100, reps: 5, step: 2.5, unit: .kg), 87.5)
        XCTAssertEqual(PresenterSupport.lowestBeatingWeight(baseline: 100, reps: 5, step: 5, unit: .lb), 86.18)
        XCTAssertEqual(PresenterSupport.lowestBeatingWeight(baseline: 100, reps: 1, step: 2.5, unit: .kg), 97.5)
        XCTAssertEqual(PresenterSupport.lowestBeatingWeight(baseline: 100, reps: 1, step: 5, unit: .lb), 97.52, "215 lb")
        XCTAssertNil(PresenterSupport.lowestBeatingWeight(baseline: 100, reps: 5, step: 0, unit: .lb))
        XCTAssertNil(PresenterSupport.lowestBeatingWeight(baseline: .infinity, reps: 5, step: 5, unit: .lb))
        XCTAssertNil(PresenterSupport.lowestBeatingWeight(baseline: 1e300, reps: 5, step: 5, unit: .lb))
    }

    func testARecordSetCarriesItsEstimateInTheUnitOfTheWorkout() throws {
        // Previous best 50 kg: the done 60 x 8 set (e1RM 76 kg) is a record.
        let kg = UF.rows(UF.present(UF.state(unit: .kg, previousBest: 50)))
        XCTAssertEqual(kg[1].estimated1RM, 76)
        XCTAssertTrue(kg[1].isPersonalRecord)
        let lb = UF.rows(UF.present(UF.state(unit: .lb, previousBest: 50)))
        XCTAssertEqual(lb[1].estimated1RM, 168, "76 kg are 167.55 lb")
        XCTAssertNil(lb[0].estimated1RM)
    }

    func testRepsOnlyAndDurationExercisesShowNoWeight() throws {
        var state = UF.state(unit: .lb)
        state.currentIndex = 1
        let pull = try XCTUnwrap(UF.present(state).card)
        XCTAssertEqual(pull.weightColumnTitle, "Added")
        XCTAssertEqual(pull.rows.map { $0.weightText }, ["BW"])
        state.currentIndex = 2
        let plank = try XCTUnwrap(UF.present(state).card)
        XCTAssertEqual(plank.weightColumnTitle, "")
        XCTAssertEqual(plank.rows.map { $0.weightText }, ["–"])
    }

    func testTheWorkoutHeaderVolumeLeavesWarmUpsOut() {
        var state = UF.state(unit: .kg)
        XCTAssertEqual(UF.present(state).header.volumeText, "480")
        WorkoutReducer.reduce(&state, .logNextSet, now: UF.start)
        XCTAssertEqual(UF.present(state).header.volumeText, "975", "480 + 82.5 x 6")
        var inPounds = state
        inPounds.settings.weightUnit = .lb
        XCTAssertEqual(UF.present(inPounds).header.volumeText, "2,150", "975 kg are 2,149.5 lb")
    }

    func testTheFinishedWorkoutIsTheSameInEveryUnit() {
        var kg = UF.state(unit: .kg, previousBest: 50)
        for _ in 0..<2 { WorkoutReducer.reduce(&kg, .logNextSet, now: UF.start) }
        var lb = kg
        lb.settings.weightUnit = .lb
        let finish = UF.start.addingTimeInterval(600)
        let inKilograms = SummaryBuilder.build(from: kg, finishedAt: finish)
        XCTAssertEqual(inKilograms, SummaryBuilder.build(from: lb, finishedAt: finish), "a summary is stored in kilograms whatever the unit of the workout")
        let expectedVolume: Double = 480 + 495 + 500
        XCTAssertEqual(inKilograms.volumeKg, expectedVolume, accuracy: 1e-9)
        XCTAssertEqual(inKilograms.personalRecords.first?.weightKg, 100)
    }

    func testTheFinishTextsAreUnaffectedByTheUnit() {
        let kg = UF.present(UF.state(unit: .kg)).finishCheck
        let lb = UF.present(UF.state(unit: .lb)).finishCheck
        XCTAssertEqual(kg, lb)
        XCTAssertEqual(kg.diffMessage, "Changes: 3 added.", "the workout has no template, so every exercise counts as added")
        XCTAssertEqual(TemplateDiff(added: 1, removed: 2, reordered: true).summary, "1 added, 2 removed, new order")
    }
}

// MARK: - Snapshot

final class UnitsSnapshotTests: XCTestCase {
    func testKilogramsAndPounds() {
        let kg = UF.snapshot(UF.state(unit: .kg))
        XCTAssertEqual(kg.weightUnit, .kg)
        XCTAssertEqual(kg.weightText, "82.5")
        XCTAssertEqual(kg.nextSetText, "Set 3 · 82.5 kg × 6")
        XCTAssertEqual(kg.volumeText, "480")
        XCTAssertEqual(kg.setLabel, "Set 3 of 4")

        let lb = UF.snapshot(UF.state(unit: .lb))
        XCTAssertEqual(lb.weightUnit, .lb)
        XCTAssertEqual(lb.weightText, "181.9")
        XCTAssertEqual(lb.nextSetText, "Set 3 · 181.9 lb × 6")
        XCTAssertEqual(lb.volumeText, "1,058")
        XCTAssertEqual(lb.setLabel, kg.setLabel)
    }

    func testGermanSeparators() {
        let kg = UF.snapshot(UF.state(unit: .kg), deDE)
        XCTAssertEqual(kg.weightText, "82,5")
        XCTAssertEqual(kg.nextSetText, "Set 3 · 82,5 kg × 6")
        let lb = UF.snapshot(UF.state(unit: .lb), deDE)
        XCTAssertEqual(lb.weightText, "181,9")
        XCTAssertEqual(lb.volumeText, "1.058")
    }

    func testAWarmUpAndTheOtherTrackingKinds() throws {
        var state = UF.state(unit: .lb)
        state.exercises[0].sets[0].isDone = false
        let warmup = UF.snapshot(state)
        XCTAssertEqual(warmup.nextSetText, "Warm-up · 88.2 lb × 10")
        XCTAssertEqual(warmup.weightText, "88.2")

        state = UF.state(unit: .lb)
        for index in 2...3 { state.exercises[0].sets[index].isDone = true }
        let pull = UF.snapshot(state)
        XCTAssertEqual(pull.tracking, .repsOnly)
        XCTAssertEqual(pull.weightText, "BW")
        XCTAssertEqual(pull.nextSetText, "Set 1 · 8 reps")
        XCTAssertEqual(pull.weightUnit, .lb, "the unit travels with every snapshot")
    }

    func testAllSetsLoggedStillCarriesTheUnit() {
        var state = UF.state(unit: .lb)
        for k in state.exercises.indices { for i in state.exercises[k].sets.indices { state.exercises[k].sets[i].isDone = true } }
        let snapshot = UF.snapshot(state)
        XCTAssertEqual(snapshot.phase, .complete)
        XCTAssertEqual(snapshot.weightUnit, .lb)
        XCTAssertEqual(snapshot.weightText, "–")
    }

    func testTheSnapshotRoundTripsAndAnOlderOneReadsAsKilograms() throws {
        for unit in WeightUnit.allCases {
            let snapshot = UF.snapshot(UF.state(unit: unit, rest: true))
            let data = try StrengthJSON.makeEncoder().encode(snapshot)
            XCTAssertEqual(try StrengthJSON.makeDecoder().decode(WorkoutSnapshot.self, from: data), snapshot)
        }
        // A Live Activity that an older build started has no "weightUnit" in its content state.
        let snapshot = UF.snapshot(UF.state(unit: .lb, rest: true))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: StrengthJSON.makeEncoder().encode(snapshot)) as? [String: Any])
        XCTAssertEqual(object["weightUnit"] as? String, "lb")
        object["weightUnit"] = nil
        let old = try StrengthJSON.makeDecoder().decode(WorkoutSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        var expected = snapshot
        expected.weightUnit = .kg
        XCTAssertEqual(old, expected)
        object["weightUnit"] = "stone"
        XCTAssertEqual(try StrengthJSON.makeDecoder().decode(WorkoutSnapshot.self, from: JSONSerialization.data(withJSONObject: object)), expected)
    }

    func testTheMemberwiseInitializerDefaultsToKilograms() {
        let base = UF.snapshot(UF.state(unit: .kg))
        let rebuilt = WorkoutSnapshot(
            workoutID: base.workoutID, revision: base.revision, workoutName: base.workoutName, activeStart: base.activeStart,
            isPaused: base.isPaused, elapsedWhenPaused: base.elapsedWhenPaused, phase: base.phase, exerciseName: base.exerciseName,
            exerciseIndex: base.exerciseIndex, exerciseCount: base.exerciseCount, targetExerciseID: base.targetExerciseID,
            targetSetID: base.targetSetID, setLabel: base.setLabel, tracking: base.tracking, weightText: base.weightText,
            repsText: base.repsText, repsUnit: base.repsUnit, showsWeight: base.showsWeight, restStartedAt: base.restStartedAt,
            restEndsAt: base.restEndsAt, restTotalSeconds: base.restTotalSeconds, restFrozenRemaining: base.restFrozenRemaining,
            heartRate: base.heartRate, volumeText: base.volumeText, loggedSets: base.loggedSets, totalSets: base.totalSets,
            nextSetText: base.nextSetText, nextExerciseName: base.nextExerciseName
        )
        XCTAssertEqual(rebuilt, base)
        XCTAssertEqual(rebuilt.weightUnit, .kg)
    }

    func testTheSnapshotStaysSmallEnoughForALiveActivity() throws {
        let data = try StrengthJSON.makeEncoder().encode(UF.snapshot(UF.state(unit: .lb, rest: true)))
        XCTAssertLessThan(data.count, 1_500)
    }
}

// MARK: - Plates

final class PlateCalculatorUnitsTests: XCTestCase {
    private func plan(_ total: Double, bar: Double = 45, _ unit: WeightUnit = .lb) -> PlatePlan? {
        PlateCalculator.plan(total: total, bar: bar, unit: unit)
    }

    func testThePlatesOfEachUnit() {
        XCTAssertEqual(PlateCalculator.plates(in: .kg), [25, 20, 15, 10, 5, 2.5, 1.25])
        XCTAssertEqual(PlateCalculator.plates(in: .kg), PlateCalculator.availablePlates)
        XCTAssertEqual(PlateCalculator.plates(in: .lb), [45, 35, 25, 10, 5, 2.5])
    }

    func testTypicalLoadsInPounds() {
        XCTAssertEqual(plan(45), PlatePlan(perSide: [], leftover: 0, unit: .lb))
        XCTAssertEqual(plan(135), PlatePlan(perSide: [45], leftover: 0, unit: .lb))
        XCTAssertEqual(plan(95), PlatePlan(perSide: [25], leftover: 0, unit: .lb))
        XCTAssertEqual(plan(155), PlatePlan(perSide: [45, 10], leftover: 0, unit: .lb))
        XCTAssertEqual(plan(185), PlatePlan(perSide: [45, 25], leftover: 0, unit: .lb))
        XCTAssertEqual(plan(225), PlatePlan(perSide: [45, 45], leftover: 0, unit: .lb))
        XCTAssertEqual(plan(315), PlatePlan(perSide: [45, 45, 45], leftover: 0, unit: .lb))
        XCTAssertEqual(plan(405), PlatePlan(perSide: [45, 45, 45, 45], leftover: 0, unit: .lb))
        XCTAssertEqual(plan(140), PlatePlan(perSide: [45, 2.5], leftover: 0, unit: .lb))
        XCTAssertEqual(plan(50), PlatePlan(perSide: [2.5], leftover: 0, unit: .lb))
        XCTAssertEqual(plan(100), PlatePlan(perSide: [25, 2.5], leftover: 0, unit: .lb))
        XCTAssertEqual(plan(115), PlatePlan(perSide: [35], leftover: 0, unit: .lb))
    }

    func testPoundLoadsThatThePlatesCannotMakeLeaveAnAmountPerSide() {
        XCTAssertEqual(plan(137.5), PlatePlan(perSide: [45], leftover: 1.25, unit: .lb))
        XCTAssertEqual(plan(47), PlatePlan(perSide: [], leftover: 1, unit: .lb))
        XCTAssertEqual(plan(46), PlatePlan(perSide: [], leftover: 0.5, unit: .lb))
        XCTAssertEqual(plan(46.5)?.leftover, 0.75)
    }

    func testBelowTheBarOrInvalidInputGivesNoPlan() {
        XCTAssertNil(plan(40))
        XCTAssertNil(plan(44.99))
        XCTAssertNil(plan(.nan))
        XCTAssertNil(plan(.infinity))
        XCTAssertNil(plan(135, bar: -1))
        XCTAssertNil(plan(135, bar: .nan))
        XCTAssertNil(plan(300_000), "above 100,000 kg")
        XCTAssertNotNil(plan(200_000), "100,000 kg are 220,462 lb")
        XCTAssertEqual(plan(45, bar: 0), PlatePlan(perSide: [10, 10, 2.5], leftover: 0, unit: .lb), "no bar: 22.5 lb on each side")
    }

    func testKilogramPlansAreTheSameThroughBothEntryPoints() {
        for total in stride(from: 0.0, through: 260, by: 1.25) {
            for bar in [0.0, 10, 20] {
                let old = PlateCalculator.plan(totalKg: total, barKg: bar)
                let new = PlateCalculator.plan(total: total, bar: bar, unit: .kg)
                XCTAssertEqual(old, new, "\(total) / \(bar)")
                if let new { XCTAssertEqual(new.unit, .kg) }
            }
        }
    }

    func testThePlanKeepsItsKilogramValuesUnderTheOldNames() {
        let kg = PlatePlan(perSide: [25, 5], leftoverKg: 0.25)
        XCTAssertEqual(kg.unit, .kg)
        XCTAssertEqual(kg.leftover, 0.25)
        XCTAssertEqual(kg.leftoverKg, 0.25)
        XCTAssertEqual(kg, PlatePlan(perSide: [25, 5], leftover: 0.25, unit: .kg))
        XCTAssertNotEqual(kg, PlatePlan(perSide: [25, 5], leftover: 0.25, unit: .lb))

        var lb = PlatePlan(perSide: [45], leftover: 2.5, unit: .lb)
        XCTAssertEqual(lb.leftoverKg, 1.13, "2.5 lb are 1.134 kg")
        lb.leftoverKg = 4.5359237
        XCTAssertEqual(lb.leftover, 10, accuracy: 1e-9)
    }

    func testTheBarOfAnExerciseInEachUnit() throws {
        let bench = UF.exercise("bench")
        XCTAssertEqual(bench.barWeight(in: .kg), 20)
        XCTAssertEqual(bench.barWeight(in: .lb), 45)
        let skull = UF.exercise("skull")
        XCTAssertEqual(skull.barKg, 10)
        XCTAssertEqual(skull.barWeight(in: .kg), 10)
        XCTAssertEqual(skull.barWeight(in: .lb), 25)
        var custom = bench
        for (kg, lb) in [(15.0, 35.0), (25, 55), (0, 0), (7, 15), (12, 30), (20.4, 45), (-3, 0)] {
            custom.barKg = kg
            XCTAssertEqual(custom.barWeight(in: .lb), lb, "\(kg) kg")
            XCTAssertEqual(custom.barWeight(in: .kg), kg)
        }
        custom.barKg = .nan
        XCTAssertEqual(custom.barWeight(in: .lb), 0)
    }

    func testAPoundLoadOnTheBarOfTheExerciseFromAStoredWeight() throws {
        let bench = UF.exercise("bench")
        let stored = try XCTUnwrap(WorkoutReducer.roundedWeight(WeightUnit.lb.toKg(225)))
        let formatter = WeightFormatter(unit: .lb, locale: enUS)
        let plan = try XCTUnwrap(PlateCalculator.plan(total: formatter.displayValue(kg: stored), bar: bench.barWeight(in: .lb), unit: .lb))
        XCTAssertEqual(plan, PlatePlan(perSide: [45, 45], leftover: 0, unit: .lb), "225 lb typed, stored as 102.06 kg, is two 45s per side")
    }
}

// MARK: - Steps

final class WeightStepUnitsTests: XCTestCase {
    func testTheStepOfEveryEquipmentInBothUnits() {
        let expectedLb: [Equipment: Double] = [.barbell: 5, .machine: 5, .cable: 5, .dumbbell: 5, .bodyweight: 2.5, .other: 2.5]
        for equipment in Equipment.allCases {
            var exercise = UF.exercise("bench")
            exercise.equipment = equipment
            XCTAssertEqual(exercise.weightStep(in: .kg), exercise.weightStepKg, "\(equipment)")
            XCTAssertEqual(exercise.weightStep(in: .lb), expectedLb[equipment], "\(equipment)")
        }
        XCTAssertEqual(UF.exercise("bench").weightStepKg, 2.5)
    }

    private func nudged(_ state: WorkoutState, _ steps: Int) -> WorkoutState {
        var copy = state
        WorkoutReducer.reduce(&copy, .nudgeNextSet(weightSteps: steps, repsSteps: 0), now: UF.start)
        return copy
    }

    private func nextWeightKg(_ state: WorkoutState) -> Double {
        let target = WorkoutTargets.nextPending(in: state)!
        return state.exercises[target.exerciseIndex].sets[target.setIndex].weightKg
    }

    private func poundState(_ pounds: Double, equipment: Equipment = .barbell) -> WorkoutState {
        var state = UF.state(unit: .lb)
        state.exercises[0].exercise.equipment = equipment
        state.exercises[0].sets[2].weightKg = WorkoutReducer.roundedWeight(WeightUnit.lb.toKg(pounds)) ?? 0
        return state
    }

    func testAKilogramStepIsTheStepInKilograms() {
        let state = UF.state(unit: .kg)
        XCTAssertEqual(nextWeightKg(nudged(state, 1)), 85)
        XCTAssertEqual(nextWeightKg(nudged(state, -1)), 80)
        XCTAssertEqual(nextWeightKg(nudged(state, 4)), 92.5)
        XCTAssertEqual(nextWeightKg(nudged(state, -100)), 0, "never below zero")
    }

    func testAPoundStepMovesFivePounds() {
        let state = poundState(135)
        XCTAssertEqual(nextWeightKg(state), 61.23)
        let up = nudged(state, 1)
        XCTAssertEqual(nextWeightKg(up), 63.5, "140 lb = 63.50 kg")
        XCTAssertEqual(WeightUnit.lb.displayValue(kg: nextWeightKg(up)), 140)
        XCTAssertEqual(WeightUnit.lb.displayValue(kg: nextWeightKg(nudged(state, -1))), 130)
        XCTAssertEqual(WeightUnit.lb.displayValue(kg: nextWeightKg(nudged(state, 2))), 145)
        XCTAssertEqual(nextWeightKg(up) - nextWeightKg(state), 2.27, accuracy: 1e-9, "5 lb is 2.268 kg")
    }

    func testStepsUpAndDownReturnToTheStartingDisplayedWeight() {
        for start in [45.0, 100, 135, 182.5, 225, 315, 0, 2.5, 99.9] {
            for steps in 1...40 {
                let state = poundState(start)
                let there = nudged(state, steps)
                let back = nudged(there, -steps)
                XCTAssertEqual(WeightUnit.lb.displayValue(kg: nextWeightKg(back)), start, accuracy: 1e-9, "\(start) lb, \(steps) steps")
                XCTAssertEqual(WeightUnit.lb.displayValue(kg: nextWeightKg(there)), start + 5 * Double(steps), accuracy: 1e-9)
            }
        }
    }

    func testAStepUpAndTheSameStepDownReturnToTheSameStoredWeightOfAKilogramWeight() {
        for kg in [60.0, 100, 80, 50, 20, 62.5, 142.37, 0.01] {
            for equipment in [Equipment.barbell, .bodyweight] {
                var state = UF.state(unit: .lb)
                state.exercises[0].exercise.equipment = equipment
                state.exercises[0].sets[2].weightKg = kg
                for steps in 1...40 {
                    let back = nudged(nudged(state, steps), -steps)
                    XCTAssertEqual(nextWeightKg(back), kg, "\(kg) kg, \(equipment), \(steps) steps")
                }
            }
        }
    }

    func testAKilogramWeightNearARoundingTieComesBackToTheSameShownWeightAndAlmostTheSameStoredOne() {
        // 75 kg is 165.347 lb: the step up has to take the shown weight, so the way back is not exact in kilograms but is never off by more than 0.04 kg.
        var state = UF.state(unit: .lb)
        state.exercises[0].sets[2].weightKg = 75
        for steps in 1...40 {
            let there = nudged(state, steps)
            let back = nudged(there, -steps)
            XCTAssertEqual(WeightUnit.lb.displayValue(kg: nextWeightKg(there)), 165.3 + 5 * Double(steps), accuracy: 1e-9, "\(steps) steps")
            XCTAssertEqual(WeightUnit.lb.displayValue(kg: nextWeightKg(back)), 165.3, accuracy: 1e-9, "\(steps) steps back")
            XCTAssertEqual(nextWeightKg(back), 75, accuracy: 0.04, "\(steps) steps back")
        }
    }

    func testOneStepAtATimeNeverDrifts() {
        var state = poundState(135)
        for _ in 0..<60 { state = nudged(state, 1) }
        XCTAssertEqual(WeightUnit.lb.displayValue(kg: nextWeightKg(state)), 435, accuracy: 1e-9)
        for _ in 0..<60 { state = nudged(state, -1) }
        XCTAssertEqual(WeightUnit.lb.displayValue(kg: nextWeightKg(state)), 135, accuracy: 1e-9)
    }

    func testANonFiniteStoredWeightIsLeftAloneByANudge() {
        for unit in WeightUnit.allCases {
            for bad in [Double.nan, .infinity, -.infinity] {
                var state = UF.state(unit: unit)
                state.exercises[0].sets[2].weightKg = bad
                for steps in [1, -1, 3] {
                    let result = nextWeightKg(nudged(state, steps))
                    XCTAssertEqual(result.bitPattern, bad.bitPattern, "\(bad) in \(unit), \(steps) steps")
                }
            }
        }
    }

    func testDumbbellAndBodyweightStepsInPounds() {
        let dumbbell = poundState(40, equipment: .dumbbell)
        XCTAssertEqual(WeightUnit.lb.displayValue(kg: nextWeightKg(nudged(dumbbell, 1))), 45)
        let other = poundState(40, equipment: .other)
        XCTAssertEqual(WeightUnit.lb.displayValue(kg: nextWeightKg(nudged(other, 1))), 42.5)
        XCTAssertEqual(WeightUnit.lb.displayValue(kg: nextWeightKg(nudged(other, -1))), 37.5)
    }

    func testAnUnroundedStoredWeightStartsFromWhatIsShown() {
        var state = UF.state(unit: .lb)
        state.exercises[0].sets[2].weightKg = 61.2349699514
        XCTAssertEqual(WeightUnit.lb.displayValue(kg: nextWeightKg(nudged(state, 1))), 140, accuracy: 1e-9)
    }

    func testTheUnitOfTheWorkoutDecidesTheStep() {
        var state = UF.state(unit: .kg)
        state.exercises[0].sets[2].weightKg = 60
        let kg = nextWeightKg(nudged(state, 1))
        XCTAssertEqual(kg, 62.5)
        state.settings.weightUnit = .lb
        let lb = nextWeightKg(nudged(state, 1))
        XCTAssertEqual(WeightUnit.lb.displayValue(kg: lb), 137.3, accuracy: 1e-9, "132.3 lb shown + 5 lb")
    }
}

// MARK: - Settings, action and sync

final class WorkoutSettingsUnitTests: XCTestCase {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    func testTheDefaultUnitIsKilograms() {
        XCTAssertEqual(WorkoutSettings().weightUnit, .kg)
        XCTAssertEqual(WorkoutSettings(autoStartRest: false, alertWhenRestEnds: true).weightUnit, .kg)
        XCTAssertEqual(WorkoutSettings(weightUnit: .lb), WorkoutSettings(autoStartRest: true, alertWhenRestEnds: true, weightUnit: .lb))
    }

    func testRoundTrip() throws {
        for unit in WeightUnit.allCases {
            let settings = WorkoutSettings(autoStartRest: false, alertWhenRestEnds: true, weightUnit: unit)
            let data = try StrengthJSON.makeEncoder().encode(settings)
            XCTAssertEqual(try StrengthJSON.makeDecoder().decode(WorkoutSettings.self, from: data), settings)
        }
        let text = String(decoding: try StrengthJSON.makeEncoder().encode(WorkoutSettings(weightUnit: .lb)), as: UTF8.self)
        XCTAssertEqual(text, "{\"alertWhenRestEnds\":true,\"autoStartRest\":true,\"weightUnit\":\"lb\"}")
    }

    func testAnOldPayloadWithoutTheUnitReadsAsKilograms() throws {
        let old = try StrengthJSON.makeDecoder().decode(WorkoutSettings.self, from: json("{\"autoStartRest\":false,\"alertWhenRestEnds\":true}"))
        XCTAssertEqual(old, WorkoutSettings(autoStartRest: false, alertWhenRestEnds: true, weightUnit: .kg))
    }

    func testAnUnknownUnitReadsAsKilogramsAndTheOtherFieldsAreStillRequired() throws {
        let future = try StrengthJSON.makeDecoder().decode(
            WorkoutSettings.self, from: json("{\"autoStartRest\":true,\"alertWhenRestEnds\":true,\"weightUnit\":\"stone\"}")
        )
        XCTAssertEqual(future.weightUnit, .kg)
        XCTAssertThrowsError(try StrengthJSON.makeDecoder().decode(WorkoutSettings.self, from: json("{\"weightUnit\":\"lb\"}")))
    }

    func testTheUnitTravelsWithTheStateThroughTheSyncCodec() throws {
        var state = SvcSyncFix.richState()
        state.settings.weightUnit = .lb
        let message = SyncMessage.state(SyncEnvelope(state: state, endedWorkoutID: nil, sentAt: SvcSyncFix.at(5)))
        let decoded = try SyncCodec.decode(SyncCodec.encode(message))
        XCTAssertEqual(decoded, message)
        guard case let .state(envelope) = decoded else { return XCTFail("a state message") }
        XCTAssertEqual(envelope.state?.settings.weightUnit, .lb)
    }

    func testAStateWrittenByAnOlderBuildDecodesAsKilograms() throws {
        var state = SvcSyncFix.richState()
        state.settings.weightUnit = .lb
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: StrengthJSON.makeEncoder().encode(state)) as? [String: Any])
        var settings = try XCTUnwrap(object["settings"] as? [String: Any])
        XCTAssertEqual(settings["weightUnit"] as? String, "lb")
        settings["weightUnit"] = nil
        object["settings"] = settings
        let old = try StrengthJSON.makeDecoder().decode(WorkoutState.self, from: JSONSerialization.data(withJSONObject: object))
        var expected = state
        expected.settings.weightUnit = .kg
        XCTAssertEqual(old, expected)
    }

    func testAnOldEnvelopeOfAPhoneBuildWithoutTheUnitStillDecodes() throws {
        let state = SvcSyncFix.richState()
        let message = SyncMessage.state(SyncEnvelope(state: state, endedWorkoutID: nil, sentAt: SvcSyncFix.at(5)))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: StrengthJSON.makeEncoder().encode(message)) as? [String: Any])
        // {"state": {"_0": {"state": {..., "settings": {...}}}}}
        var outer = try XCTUnwrap(object["state"] as? [String: Any])
        var envelope = try XCTUnwrap(outer["_0"] as? [String: Any])
        var inner = try XCTUnwrap(envelope["state"] as? [String: Any])
        var settings = try XCTUnwrap(inner["settings"] as? [String: Any])
        settings["weightUnit"] = nil
        inner["settings"] = settings
        envelope["state"] = inner
        outer["_0"] = envelope
        object["state"] = outer
        let decoded = try SyncCodec.decode([SyncCodec.payloadKey: JSONSerialization.data(withJSONObject: object)])
        XCTAssertEqual(decoded, message)
    }
}

final class SetWeightUnitActionTests: XCTestCase {
    func testTheReducerSetsTheUnitAndBumpsTheRevisionOnce() {
        var state = UF.state(unit: .kg)
        state.revision = 7
        WorkoutReducer.reduce(&state, .setWeightUnit(.lb), now: UF.start)
        XCTAssertEqual(state.settings.weightUnit, .lb)
        XCTAssertEqual(state.revision, 8)
        WorkoutReducer.reduce(&state, .setWeightUnit(.lb), now: UF.start)
        XCTAssertEqual(state.revision, 8, "the same unit again changes nothing")
        WorkoutReducer.reduce(&state, .setWeightUnit(.kg), now: UF.start)
        XCTAssertEqual(state.settings.weightUnit, .kg)
        XCTAssertEqual(state.revision, 9)
    }

    func testTheStoredWeightsAndTheOtherSettingsDoNotChange() {
        let before = UF.state(unit: .kg, rest: true)
        var after = before
        WorkoutReducer.reduce(&after, .setWeightUnit(.lb), now: UF.start)
        XCTAssertEqual(after.exercises, before.exercises)
        XCTAssertEqual(after.rest, before.rest)
        XCTAssertEqual(after.settings.autoStartRest, before.settings.autoStartRest)
        XCTAssertEqual(after.settings.alertWhenRestEnds, before.settings.alertWhenRestEnds)
        var expected = before
        expected.settings.weightUnit = .lb
        expected.revision = before.revision + 1
        XCTAssertEqual(after, expected)
    }

    func testTheActionCodecRoundTripsAndIsPartOfTheKnownActions() throws {
        for unit in WeightUnit.allCases {
            let action = WorkoutAction.setWeightUnit(unit)
            let data = try JSONEncoder().encode(action)
            XCTAssertEqual(try JSONDecoder().decode(WorkoutAction.self, from: data), action)
            let command = SyncMessage.command(RemoteCommand(id: SvcSyncFix.uuid(77), action: action, origin: .phone, issuedAt: SvcSyncFix.at(1)))
            XCTAssertEqual(try SyncCodec.decode(SyncCodec.encode(command)), command)
        }
        XCTAssertTrue(SvcSyncFix.allActions().contains(.setWeightUnit(.lb)))
    }

    func testAChangedUnitChangesTheTextsOfTheNextPresentationAndSnapshot() throws {
        var state = UF.state(unit: .kg, rest: true)
        XCTAssertEqual(UF.present(state).dock?.nextSetText, "Next · Set 2 · 82.5 kg × 6")
        WorkoutReducer.reduce(&state, .setWeightUnit(.lb), now: UF.start)
        XCTAssertEqual(UF.present(state).dock?.nextSetText, "Next · Set 2 · 181.9 lb × 6")
        XCTAssertEqual(UF.snapshot(state).weightUnit, .lb)
    }

    func testWeightsTypedInPoundsShowTheSameNumberAfterTheReducerStoredThem() throws {
        var state = UF.state(unit: .lb)
        let ref = (exerciseID: UF.uuid(1), setID: UF.uuid(13))
        for typed in ["135", "225", "132.3", "181,9", "45", "1000"] {
            let kg = try XCTUnwrap(WeightFormatter.parse(typed, unit: .lb, locale: enUS), typed)
            WorkoutReducer.reduce(&state, .setWeight(exerciseID: ref.exerciseID, setID: ref.setID, kg: kg), now: UF.start)
            XCTAssertEqual(UF.rows(UF.present(state))[2].weightText, typed.replacingOccurrences(of: ",", with: "."), typed)
        }
    }
}

// MARK: - Exercise history texts

final class UnitsHistoryTests: XCTestCase {
    private typealias F = SvcDataFix

    private func history(_ format: DisplayFormat) -> ExerciseHistory {
        let workout = F.workout(1, finishedAt: F.daysAgo(3), [F.entry("bench", [F.warmup(50, 8), F.work(80, 6), F.work(85, 5), F.work(80, 5)], n: 1)])
        return StrengthData(history: [workout]).history(for: "bench", now: F.now, format: format)
    }

    func testTheDefaultIsKilogramsInEnglish() {
        let defaults = StrengthData(history: [F.workout(1, finishedAt: F.daysAgo(3), [F.entry("bench", [F.work(85, 5)], n: 1)])])
        XCTAssertEqual(defaults.history(for: "bench", now: F.now), defaults.history(for: "bench", now: F.now, format: .metric))
        XCTAssertEqual(defaults.history(for: "bench", now: F.now).bestSetText, "85 kg × 5")
    }

    func testKilogramTexts() {
        let h = history(.metric)
        XCTAssertEqual(h.bestSetText, "85 kg × 5")
        XCTAssertEqual(
            h.records.map { $0.label },
            ["Estimated 1RM", "Best set", "Heaviest weight", "Best 3RM", "Best 5RM", "Most reps at 80 kg", "Best session volume"]
        )
        XCTAssertEqual(h.records.map { $0.value }, ["99 kg", "85 kg × 5", "85 kg", "85 kg", "85 kg", "6", "1,305 kg"])
    }

    func testPoundTexts() {
        let h = history(DisplayFormat(unit: .lb, locale: enUS))
        XCTAssertEqual(h.bestSetText, "187.4 lb × 5")
        XCTAssertEqual(
            h.records.map { $0.label },
            ["Estimated 1RM", "Best set", "Heaviest weight", "Best 3RM", "Best 5RM", "Most reps at 176.4 lb", "Best session volume"]
        )
        XCTAssertEqual(h.records.map { $0.value }, ["219 lb", "187.4 lb × 5", "187.4 lb", "187.4 lb", "187.4 lb", "6", "2,877 lb"])
    }

    func testGermanSeparators() {
        let kg = history(DisplayFormat(unit: .kg, locale: deDE))
        XCTAssertEqual(kg.bestSetText, "85 kg × 5")
        XCTAssertEqual(kg.records.map { $0.value }, ["99 kg", "85 kg × 5", "85 kg", "85 kg", "85 kg", "6", "1.305 kg"])
        let lb = history(DisplayFormat(unit: .lb, locale: deDE))
        XCTAssertEqual(lb.bestSetText, "187,4 lb × 5")
        XCTAssertEqual(lb.records.map { $0.label }[5], "Most reps at 176,4 lb")
        XCTAssertEqual(lb.records.map { $0.value }.last, "2.877 lb")
    }

    func testTheNumbersStayInKilograms() {
        let kg = history(.metric)
        let lb = history(DisplayFormat(unit: .lb, locale: enUS))
        XCTAssertEqual(kg.bestE1RM, lb.bestE1RM)
        XCTAssertEqual(kg.volumeLast30Days, lb.volumeLast30Days)
        XCTAssertEqual(kg.sessions, lb.sessions)
        XCTAssertEqual(kg.e1RMSeries, lb.e1RMSeries)
    }

    func testRelativeStrengthAndBodyweightLoadFollowUnitAndLocale() {
        let bench = F.workout(1, finishedAt: F.daysAgo(3), [F.entry("bench", [F.work(100, 5)], n: 1)])
        let pull = F.workout(2, finishedAt: F.daysAgo(20), [F.entry("pullup", [F.work(0, 8), F.work(0, 6)], n: 2)])
        var data = StrengthData(history: [bench, pull])
        data.recordBodyWeight(kg: 80, date: F.daysAgo(30))
        let germanKg = DisplayFormat(unit: .kg, locale: deDE)
        let germanLb = DisplayFormat(unit: .lb, locale: deDE)
        XCTAssertEqual(data.history(for: "bench", now: F.now, format: germanKg).records.last?.value, "1,5× bodyweight")
        XCTAssertEqual(data.history(for: "bench", now: F.now).records.last?.value, "1.5× bodyweight")
        XCTAssertEqual(data.history(for: "bench", now: F.now, format: germanLb).records.last?.value, "1,5× bodyweight", "a ratio has no unit")
        XCTAssertEqual(data.history(for: "pullup", now: F.now).records.last?.value, "1,120 kg")
        XCTAssertEqual(data.history(for: "pullup", now: F.now, format: germanLb).records.last?.value, "2.469 lb")
        XCTAssertEqual(data.history(for: "pullup", now: F.now, format: DisplayFormat(unit: .lb, locale: enUS)).records.last?.value, "2,469 lb")
    }

    func testTheMultipleTextTakesTheDecimalMarkOfTheLocale() {
        XCTAssertEqual(BodyWeightRules.multipleText(1.4), "1.4×")
        XCTAssertEqual(BodyWeightRules.multipleText(1.4, locale: deDE), "1,4×")
        XCTAssertEqual(BodyWeightRules.multipleText(2, locale: deDE), "2,0×")
        XCTAssertEqual(BodyWeightRules.multipleText(.nan, locale: deDE), "–")
    }
}
