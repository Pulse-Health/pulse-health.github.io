import Foundation
import XCTest
@testable import PulseStrengthCore

/// widgets/SPEC.md section 2: lifts, plateaus, strengthRatio and block. `WidFix.now` is Friday 2026-10-16 09:41 UTC.
private enum LiftFix {
    /// A workout `daysAgo` days before `now` in which `exerciseID` has the recorded estimate `e1RM`.
    static func session(_ n: Int, _ exerciseID: String, daysAgo: Double, e1RM: Double) -> CompletedWorkout {
        WidFix.workout(n, daysAgo: daysAgo).with(exercises: [WidFix.lift(exerciseID, [WidFix.set(50, 5)], best: e1RM, n: n)])
    }

    /// The lifts of the snapshot of `history`.
    static func lifts(_ history: [CompletedWorkout], now: Date = WidFix.now) -> [LiftTrend] {
        WidFix.snapshot(history: history, now: now).lifts
    }

    /// Sessions of `exerciseID` with the given estimates, oldest first, `spacing` days apart, the newest `newest` days ago.
    static func series(_ exerciseID: String, _ values: [Double], newest: Double = 1, spacing: Double = 4, firstNumber: Int = 1) -> [CompletedWorkout] {
        values.enumerated().map { offset, value in
            session(firstNumber + offset, exerciseID, daysAgo: newest + Double(values.count - 1 - offset) * spacing, e1RM: value)
        }
    }
}

final class WidgetLiftsRuleTests: XCTestCase {
    func testLiftsAreTheWeightTrackingExercisesOfTheLast90Days() {
        let history = [
            WidFix.workout(1, daysAgo: 2).with(exercises: [
                WidFix.lift("bench", [WidFix.set(80, 6)], n: 1),
                WidFix.lift("pullup", [WidFix.set(0, 8)], n: 2),                       // reps only
                WidFix.lift("plank", [WidFix.set(0, 45)], n: 3),                       // duration
            ]),
        ]
        XCTAssertEqual(LiftFix.lifts(history).map { $0.exerciseID }, ["bench"])
        XCTAssertEqual(LiftFix.lifts([]).count, 0)
    }

    func testLiftsNeedASessionWithinTheLast90Days() {
        let day = 86_400.0
        let old = WidFix.workout(1, at: WidFix.now.addingTimeInterval(-90 * day - 1)).with(exercises: [WidFix.lift("squat", [WidFix.set(100, 5)], n: 1)])
        let edge = WidFix.workout(2, at: WidFix.now.addingTimeInterval(-90 * day)).with(exercises: [WidFix.lift("bench", [WidFix.set(80, 5)], n: 2)])
        XCTAssertEqual(LiftFix.lifts([old, edge]).map { $0.exerciseID }, ["bench"], "exactly 90 days ago is in, a second more is out")
    }

    func testAnOldSessionStillFeedsThePointsOfALiftThatWasTrainedRecently() {
        let history = [
            LiftFix.session(2, "bench", daysAgo: 3, e1RM: 100),
            LiftFix.session(1, "bench", daysAgo: 200, e1RM: 90),
        ]
        let bench = LiftFix.lifts(history)[0]
        XCTAssertEqual(bench.points.map { $0.value }, [90, 100], "the points come from all of the history")
        XCTAssertEqual(bench.sessionCount, 1, "but only the sessions of the last 90 days are counted")
    }

    func testLiftsAreRankedByTheNumberOfDistinctWorkoutsThenTheMostRecentThenTheID() {
        var history: [CompletedWorkout] = []
        var n = 0
        func add(_ id: String, daysAgo: Double) {
            n += 1
            history.append(LiftFix.session(n, id, daysAgo: daysAgo, e1RM: 100))
        }
        // squat 3 sessions; ohp 2 (latest 1 day ago); bench 2 (latest 1 day ago); curl 2 (latest 5 days ago); deadlift 1 (latest 1 day ago)
        add("squat", daysAgo: 20); add("squat", daysAgo: 10); add("squat", daysAgo: 6)
        add("ohp", daysAgo: 8); add("ohp", daysAgo: 1)
        add("bench", daysAgo: 9); add("bench", daysAgo: 1)
        add("curl", daysAgo: 12); add("curl", daysAgo: 5)
        add("deadlift", daysAgo: 1)
        let ids = LiftFix.lifts(history).map { $0.exerciseID }
        XCTAssertEqual(ids, ["squat", "bench", "ohp", "curl", "deadlift"], "bench and ohp tie on count and recency: the smaller id first")
    }

    func testLiftsAreLimitedToTheTopEightMostTrainedFirst() {
        let ids = ["bench", "incline", "crossover", "cpress", "ohp", "dbpress", "lateral", "rdelt", "curl", "dbcurl"]
        var history: [CompletedWorkout] = []
        for (offset, id) in ids.enumerated() {
            // The earlier ids are trained more often.
            for repeatCount in 0..<(ids.count - offset) {
                history.append(LiftFix.session(offset * 100 + repeatCount + 1, id, daysAgo: 1 + Double(repeatCount) * 3, e1RM: 50))
            }
        }
        let lifts = LiftFix.lifts(history)
        XCTAssertEqual(lifts.count, 8)
        XCTAssertEqual(lifts.map { $0.exerciseID }, Array(ids.prefix(8)))
    }

    func testASessionValueIsTheGreatestRecordedEstimateOfTheExerciseInThatWorkout() {
        let workout = WidFix.workout(1, daysAgo: 2).with(exercises: [
            WidFix.lift("bench", [WidFix.set(50, 5)], best: 90, n: 1),
            WidFix.lift("bench", [WidFix.set(50, 5)], best: 104.44, n: 2),               // the same exercise twice in one workout
            WidFix.lift("squat", [WidFix.set(100, 5)], best: 130, n: 3),
        ])
        let lifts = LiftFix.lifts([workout])
        XCTAssertEqual(lifts.first { $0.exerciseID == "bench" }?.currentE1RM, 104.4)
        XCTAssertEqual(lifts.first { $0.exerciseID == "bench" }?.points.count, 1, "one workout is one session")
        XCTAssertEqual(lifts.first { $0.exerciseID == "bench" }?.sessionCount, 1)
    }

    func testASessionValueFallsBackToTheBestEpleyEstimateOfTheNonWarmUpSetsWhenNoneWasRecorded() {
        let sets = [WidFix.set(120, 10, .warmup), WidFix.set(60, 10), WidFix.set(75, 6)]       // 80.0 and 90.0; the warm-up would be 160
        let workout = WidFix.workout(1, daysAgo: 2).with(exercises: [WidFix.lift("bench", sets, best: 0, n: 1)])
        XCTAssertEqual(LiftFix.lifts([workout])[0].currentE1RM, 90)
    }

    func testAnExerciseWithoutAnyEstimateIsNotASession() {
        let warmUpsOnly = WidFix.workout(1, daysAgo: 2).with(exercises: [WidFix.lift("bench", [WidFix.set(40, 8, .warmup)], best: 0, n: 1)])
        let noWeight = WidFix.workout(2, daysAgo: 3).with(exercises: [WidFix.lift("squat", [WidFix.set(0, 8)], best: 0, n: 2)])
        XCTAssertEqual(LiftFix.lifts([warmUpsOnly, noWeight]).count, 0)
    }

    func testPointsAreTheLastSixSessionsOldestFirstRoundedToATenth() {
        let values = [80.04, 81.26, 82.5, 83.74, 84.01, 85.96, 86.0]
        let bench = LiftFix.lifts(LiftFix.series("bench", values))[0]
        XCTAssertEqual(bench.points.count, 6)
        XCTAssertEqual(bench.points.map { $0.value }, [81.3, 82.5, 83.7, 84, 86, 86])
        XCTAssertEqual(bench.points.map { $0.date }, bench.points.map { $0.date }.sorted(), "oldest first")
        XCTAssertEqual(bench.currentE1RM, 86)
        XCTAssertEqual(bench.bestE1RM, 86)
        XCTAssertEqual(bench.sessionCount, 7, "all seven sessions are within 90 days")
    }

    func testDeltaIsTheLatestMinusTheOneBeforeAndZeroForOnePoint() {
        let two = LiftFix.lifts(LiftFix.series("bench", [96, 99.2]))[0]
        XCTAssertEqual(two.deltaKg, 3.2, "rounded to a tenth: 99.2 - 96 has floating point noise")
        let down = LiftFix.lifts(LiftFix.series("bench", [99.2, 96]))[0]
        XCTAssertEqual(down.deltaKg, -3.2)
        XCTAssertEqual(LiftFix.lifts(LiftFix.series("bench", [90]))[0].deltaKg, 0)
    }

    func testPRIndexMarksTheBestPointWhenItBeatEveryEarlierOne() {
        XCTAssertEqual(LiftFix.lifts(LiftFix.series("bench", [93, 99, 96]))[0].prIndex, 1)
        XCTAssertEqual(LiftFix.lifts(LiftFix.series("bench", [90, 95, 100]))[0].prIndex, 2)
        XCTAssertEqual(LiftFix.lifts(LiftFix.series("bench", [100, 95, 90]))[0].prIndex, nil, "the best is the first point: it beat nothing")
        XCTAssertEqual(LiftFix.lifts(LiftFix.series("bench", [58.4, 58.4, 58.4]))[0].prIndex, nil, "a flat lift has no record")
        XCTAssertEqual(LiftFix.lifts(LiftFix.series("bench", [90]))[0].prIndex, nil, "a single session beat nothing")
    }

    func testPRIndexIsTheFirstPointOfATiedBest() {
        XCTAssertEqual(LiftFix.lifts(LiftFix.series("bench", [90, 100, 100]))[0].prIndex, 1, "the record was set at index 1 and matched afterwards")
        XCTAssertEqual(LiftFix.lifts(LiftFix.series("bench", [100, 100, 90]))[0].prIndex, nil)
    }

    func testLiftNameIsTheNameFromTheNewestWorkout() {
        let older = WidFix.workout(1, daysAgo: 9).with(exercises: [CompletedExercise(exerciseID: "bench", name: "Bench (old name)", muscle: .chest, mediaKey: nil, tracking: .weightReps, sets: [WidFix.set(80, 5)], isPersonalRecord: false, bestE1RM: 93)])
        let newer = WidFix.workout(2, daysAgo: 2).with(exercises: [CompletedExercise(exerciseID: "bench", name: "Barbell bench press", muscle: .chest, mediaKey: nil, tracking: .weightReps, sets: [WidFix.set(80, 5)], isPersonalRecord: false, bestE1RM: 93)])
        XCTAssertEqual(LiftFix.lifts([newer, older])[0].name, "Barbell bench press")
        XCTAssertEqual(LiftFix.lifts([older, newer])[0].name, "Barbell bench press", "whatever the order of the history")
    }

    func testSessionsOfTheSameInstantKeepTheOlderPositionOfTheHistoryFirst() {
        // Two workouts finished at the same moment; the history lists the newer one first, so the other one is the older session.
        let at = WidFix.now.addingTimeInterval(-86_400)
        let first = WidFix.workout(1, at: at).with(exercises: [WidFix.lift("bench", [WidFix.set(50, 5)], best: 90, n: 1)])
        let second = WidFix.workout(2, at: at).with(exercises: [WidFix.lift("bench", [WidFix.set(50, 5)], best: 100, n: 2)])
        XCTAssertEqual(LiftFix.lifts([second, first])[0].points.map { $0.value }, [90, 100])
    }
}

final class WidgetPlateauRuleTests: XCTestCase {
    private func plateaus(_ history: [CompletedWorkout]) -> [PlateauFlag] {
        WidFix.snapshot(history: history).plateaus
    }

    private func status(_ values: [Double]) -> PlateauFlag? {
        plateaus(LiftFix.series("bench", values)).first
    }

    func testPlateausNeedAtLeastThreePoints() {
        XCTAssertEqual(plateaus(LiftFix.series("bench", [90, 95])), [])
        XCTAssertEqual(plateaus([]), [])
        XCTAssertEqual(status([90, 95, 100])?.exerciseID, "bench")
    }

    func testALiftWhoseLatestPointIsANewBestIsRising() {
        let flag = status([90, 95, 100])
        XCTAssertEqual(flag?.status, .rising)
        XCTAssertEqual(flag?.flatSessions, 1, "count - p: the best was set by the last point")
        XCTAssertNil(flag?.tip)
        XCTAssertEqual(flag?.name, "Barbell bench press")
    }

    func testAFirstPointThatStaysTheBestCountsAsTheNewBestOfThatPosition() {
        let flag = status([100, 99, 98])
        XCTAssertEqual(flag?.flatSessions, 3, "p = 0: the first point counts")
        XCTAssertEqual(flag?.status, .flat, "3 sessions and the last point within 3 % of the best")
    }

    func testFlatNeedsThreeSessionsWithoutANewBestAndTheLastPointWithinThreePercent() {
        XCTAssertEqual(status([100, 100, 100])?.status, .flat)
        XCTAssertEqual(status([100, 99, 98])?.status, .flat)
        XCTAssertEqual(status([100, 100, 97])?.status, .flat, "exactly 97 % is still flat")
        XCTAssertEqual(status([90, 100, 98])?.status, .rising, "only 2 sessions since the best and within 3 %")
    }

    func testFallingNeedsTwoSessionsWithoutANewBestAndTheLastPointMoreThanThreePercentBelow() {
        XCTAssertEqual(status([100, 99, 96])?.status, .falling)
        XCTAssertEqual(status([90, 100, 96])?.status, .falling, "2 sessions since the best, 4 % down")
        XCTAssertEqual(status([100, 100, 96.9])?.status, .falling, "just under 97 %")
        XCTAssertEqual(status([90, 95, 100, 99, 95])?.flatSessions, 3)
        XCTAssertEqual(status([90, 95, 100, 99, 95])?.status, .falling)
    }

    func testPlateauFlatSessionsAreTheNumberOfPointsFromTheLatestNewBestToTheEnd() {
        XCTAssertEqual(status([90, 100, 95, 96, 97, 98])?.flatSessions, 5)
        XCTAssertEqual(status([100, 100, 100, 101])?.flatSessions, 1, "equal values are no new best, 101 is")
        XCTAssertEqual(status([90, 100, 100, 100])?.flatSessions, 3, "p = 1: matching the best is not a new best")
    }

    func testOnlyTheFirstFlatLiftCarriesTheTip() {
        var history = LiftFix.series("bench", [100, 100, 100], firstNumber: 1)
        history += LiftFix.series("squat", [150, 150, 150], firstNumber: 10)
        history += LiftFix.series("ohp", [60, 60, 60], firstNumber: 20)
        let flags = plateaus(history)
        XCTAssertEqual(flags.count, 3)
        XCTAssertTrue(flags.allSatisfy { $0.status == .flat })
        XCTAssertEqual(flags.map { $0.tip }, ["Try 3 × 8 at about 90% for two weeks.", nil, nil])
    }

    func testTheTipGoesToTheFirstFlatLiftEvenWhenARisingLiftComesFirst() {
        var history = LiftFix.series("bench", [90, 95, 100], spacing: 3, firstNumber: 1)
        history += LiftFix.series("squat", [150, 150, 150], firstNumber: 10)
        history += LiftFix.series("ohp", [60, 60, 60], firstNumber: 20)
        let flags = plateaus(history)
        XCTAssertEqual(flags.map { $0.status }, [.rising, .flat, .flat])
        XCTAssertEqual(flags.map { $0.tip }, [nil, "Try 3 × 8 at about 90% for two weeks.", nil])
    }

    func testPlateausAreTheFirstFourLiftsWithEnoughPoints() {
        var history: [CompletedWorkout] = []
        let ids = ["bench", "incline", "crossover", "cpress", "ohp", "dbpress"]
        for (offset, id) in ids.enumerated() {
            history += LiftFix.series(id, [100, 100, 100], spacing: 3, firstNumber: offset * 10 + 1)
        }
        history += LiftFix.series("curl", [50, 50], spacing: 3, firstNumber: 100)               // two points: skipped
        let flags = plateaus(history)
        XCTAssertEqual(flags.count, 4)
        XCTAssertEqual(flags.map { $0.exerciseID }, Array(WidFix.snapshot(history: history).lifts.filter { $0.points.count >= 3 }.prefix(4)).map { $0.exerciseID })
    }
}

final class WidgetStrengthRatioRuleTests: XCTestCase {
    private func ratio(_ history: [CompletedWorkout], context: WidgetContext = WidFix.context(), data: StrengthData? = nil) -> StrengthRatio? {
        let source = data ?? StrengthData(history: history)
        return WidFix.snapshot(source, context: context).strengthRatio
    }

    func testStrengthRatioIsTheFirstListedMainLift() {
        // curl is trained most, then squat, then bench: the first main lift of `lifts` is the squat.
        var history = LiftFix.series("curl", [40, 41, 42, 43], firstNumber: 1)
        history += LiftFix.series("squat", [120, 125, 130], firstNumber: 10)
        history += LiftFix.series("bench", [90], firstNumber: 20)
        let result = ratio(history)
        XCTAssertEqual(result?.exerciseID, "squat")
        XCTAssertEqual(result?.exerciseName, "Back squat")
        XCTAssertEqual(result?.estimated1RM, 130, "its best e1RM")
        XCTAssertEqual(result?.goalRatio, 2.0)
    }

    func testStrengthRatioGoalsAre15For2For25And1() {
        let goals = [("bench", 1.5), ("squat", 2.0), ("deadlift", 2.5), ("ohp", 1.0)]
        for (id, goal) in goals {
            XCTAssertEqual(ratio(LiftFix.series(id, [100]))?.goalRatio, goal, id)
        }
        XCTAssertNil(ratio(LiftFix.series("curl", [40])), "not a main lift")
        XCTAssertNil(ratio([]))
    }

    func testStrengthRatioUsesTheBestEstimateOfThePoints() {
        XCTAssertEqual(ratio(LiftFix.series("bench", [93, 99.2, 96]))?.estimated1RM, 99.2)
    }

    func testStrengthRatioWithoutBodyweightHasNoRatio() {
        let result = ratio(LiftFix.series("bench", [99.2]))
        XCTAssertNil(result?.bodyweightKg)
        XCTAssertNil(result?.ratio)
    }

    func testStrengthRatioIsTheEstimateOverTheBodyweightRoundedToHundredths() {
        let result = ratio(LiftFix.series("bench", [99.2]), context: WidFix.context(bodyweightKg: 80))
        XCTAssertEqual(result?.bodyweightKg, 80)
        XCTAssertEqual(result?.ratio, 1.24)
        let uneven = ratio(LiftFix.series("bench", [100]), context: WidFix.context(bodyweightKg: 83))
        XCTAssertEqual(uneven?.ratio, 1.2, "100 / 83 = 1.2048 rounds to 1.2")
        XCTAssertEqual(ratio(LiftFix.series("bench", [100]), context: WidFix.context(bodyweightKg: 70))?.ratio, 1.43, "100 / 70 = 1.4286")
    }

    func testStrengthRatioFallsBackToTheNewestBodyWeightOfTheData() {
        let weights = [BodyWeightEntry(date: WidFix.date(2026, 10, 10), kg: 82), BodyWeightEntry(date: WidFix.date(2026, 9, 1), kg: 90)]
        let data = StrengthData(history: LiftFix.series("bench", [99.2]), bodyWeights: weights)
        let result = ratio([], data: data)
        XCTAssertEqual(result?.bodyweightKg, 82, "the list is newest first")
        XCTAssertEqual(result?.ratio, 1.21)
    }

    func testTheContextsBodyweightWinsOverTheStoredOne() {
        let data = StrengthData(history: LiftFix.series("bench", [99.2]), bodyWeights: [BodyWeightEntry(date: WidFix.date(2026, 10, 10), kg: 82)])
        XCTAssertEqual(ratio([], context: WidFix.context(bodyweightKg: 75), data: data)?.bodyweightKg, 75)
    }

    func testABodyweightThatIsNotAboveZeroCountsAsUnknown() {
        for bad in [0.0, -5.0, Double.nan, Double.infinity] {
            let result = ratio(LiftFix.series("bench", [99.2]), context: WidFix.context(bodyweightKg: bad))
            XCTAssertNil(result?.ratio, "\(bad)")
            XCTAssertNil(result?.bodyweightKg, "\(bad)")
        }
    }
}

final class WidgetBlockRuleTests: XCTestCase {
    private let push = WidFix.template(1, "Upper A · Push")
    private let pull = WidFix.template(2, "Upper B · Pull")

    private func block(_ history: [CompletedWorkout], templates: [WorkoutTemplate]? = nil, context: WidgetContext = WidFix.context(), plans: [WorkoutPlan] = [], now: Date = WidFix.now) -> TrainingBlock? {
        WidFix.snapshot(StrengthData(templates: templates ?? [push, pull], history: history, plans: plans), context: context, now: now).block
    }

    private func done(_ n: Int, _ name: String, _ templateID: UUID?, _ date: Date) -> CompletedWorkout {
        WidFix.workout(n, name, at: date, templateID: templateID)
    }

    func testBlockIsNilWithoutHistory() {
        XCTAssertNil(block([]))
    }

    func testBlockIsCountedInFourWeeksFromTheWeekOfTheFirstWorkout() {
        // The first workout was on Monday 21 September: 3 whole weeks before this week's Monday (12 October).
        let result = block([done(1, "Upper A · Push", push.id, WidFix.date(2026, 9, 21, 9, 0))])
        XCTAssertEqual(result?.name, "Block 1")
        XCTAssertEqual(result?.weekIndex, 4)
        XCTAssertEqual(result?.weekCount, 4)
    }

    func testBlockNumberAndWeekIndexAdvanceEveryFourWeeks() {
        let expectations: [(first: Date, name: String, week: Int)] = [
            (WidFix.date(2026, 10, 14, 9, 0), "Block 1", 1),            // n = 0: this very week
            (WidFix.date(2026, 10, 6, 9, 0), "Block 1", 2),             // n = 1
            (WidFix.date(2026, 9, 30, 9, 0), "Block 1", 3),             // n = 2
            (WidFix.date(2026, 9, 21, 9, 0), "Block 1", 4),             // n = 3
            (WidFix.date(2026, 9, 14, 9, 0), "Block 2", 1),             // n = 4
            (WidFix.date(2026, 8, 24, 9, 0), "Block 2", 4),             // n = 7
            (WidFix.date(2026, 8, 17, 9, 0), "Block 3", 1),             // n = 8
        ]
        for item in expectations {
            let result = block([done(1, "Upper A · Push", push.id, item.first)])
            XCTAssertEqual(result?.name, item.name, "\(item.first)")
            XCTAssertEqual(result?.weekIndex, item.week, "\(item.first)")
        }
    }

    func testBlockRowsAreTheFirstFourTemplatesLabelledWithTheTextAfterTheDot() {
        let templates = [push, pull, WidFix.template(3, "Lower A · Quads"), WidFix.template(4, "Cardio"), WidFix.template(5, "Fifth · Ignored")]
        let result = block([done(1, "Upper A · Push", push.id, WidFix.date(2026, 10, 14, 9, 0))], templates: templates)
        XCTAssertEqual(result?.rows.map { $0.label }, ["Push", "Pull", "Quads", "Cardio"])
        XCTAssertEqual(result?.rows.map { $0.cells.count }, [4, 4, 4, 4])
    }

    func testBlockCellsAreDoneMissedPlannedOrUpcoming() {
        // Block 1, week 4 (first workout Monday 21 September). Weeks: 21-27 Sep, 28 Sep - 4 Oct, 5-11 Oct, 12-18 Oct (now).
        let history = [
            done(5, "Upper B · Pull", pull.id, WidFix.date(2026, 10, 13, 9, 0)),          // week 4: Pull done
            done(4, "Upper A · Push", nil, WidFix.date(2026, 10, 1, 9, 0)),               // week 2: no template id: matched by name
            done(3, "Upper B · Pull", pull.id, WidFix.date(2026, 9, 24, 9, 0)),           // week 1: Pull done
            done(2, "Upper A · Push", push.id, WidFix.date(2026, 9, 22, 9, 0)),           // week 1: Push done
        ]
        let result = block(history)
        func states(_ row: Int) -> [BlockCellState]? { result?.rows[row].cells.map { $0.state } }
        XCTAssertEqual(states(0), [.done, .done, .missed, .planned], "Push: weeks 1 and 2 done, week 3 missed, the current week planned")
        XCTAssertEqual(states(1), [.done, .missed, .missed, .done], "Pull")
        XCTAssertEqual(result?.sessionsDone, 4)
        XCTAssertEqual(result?.sessionsPlanned, 16, "goal 4 x 4 weeks so far")
        XCTAssertEqual(result?.sessionsMissed, 3)
    }

    func testBlockCellsAfterTheCurrentWeekAreUpcoming() {
        let result = block([done(1, "Upper A · Push", push.id, WidFix.date(2026, 10, 14, 9, 0))])
        XCTAssertEqual(result?.weekIndex, 1)
        XCTAssertEqual(result?.rows[0].cells.map { $0.state }, [.done, .upcoming, .upcoming, .upcoming])
        XCTAssertEqual(result?.rows[1].cells.map { $0.state }, [.planned, .upcoming, .upcoming, .upcoming])
        XCTAssertEqual(result?.sessionsPlanned, 4)
        XCTAssertEqual(result?.sessionsMissed, 0)
    }

    func testAWorkoutWithATemplateIDOnlyCountsForThatTemplateEvenWhenTheNameMatches() {
        let result = block([done(1, "Upper A · Push", WidFix.uuid(9_999), WidFix.date(2026, 10, 14, 9, 0))])
        XCTAssertEqual(result?.rows[0].cells.first?.state, .planned, "the id names another template")
        XCTAssertEqual(result?.sessionsDone, 1, "the workout still counts toward the block")
    }

    func testBlockSessionsDoneCountTheWorkoutsFromTheMondayTheBlockBegan() {
        // The first workout was on Monday 14 September: n = 4, so block 2 begins on Monday 12 October, this very week.
        let history = [
            done(4, "Upper A · Push", push.id, WidFix.date(2026, 10, 13, 9, 0)),
            done(3, "Upper A · Push", push.id, WidFix.date(2026, 10, 12, 0, 0, 0)),         // Monday 00:00:00: in the block
            done(2, "Upper A · Push", push.id, WidFix.date(2026, 10, 11, 23, 59, 59)),      // the Sunday before: not in it
            done(1, "Upper A · Push", push.id, WidFix.date(2026, 9, 14, 9, 0)),
        ]
        let result = block(history)
        XCTAssertEqual(result?.name, "Block 2")
        XCTAssertEqual(result?.weekIndex, 1)
        XCTAssertEqual(result?.sessionsDone, 2)
        XCTAssertEqual(result?.sessionsPlanned, 4)
    }

    func testBlockSessionsPlannedUseThePlansDaysPerWeekAsTheGoal() {
        let plan = WidFix.plan([push, pull], daysPerWeek: 3)
        let result = block([done(1, "Upper A · Push", push.id, WidFix.date(2026, 9, 21, 9, 0))], plans: [plan])
        XCTAssertEqual(result?.sessionsPlanned, 12, "3 per week x 4 weeks")
    }

    func testBlockWithoutTemplatesHasNoRowsButStillCountsSessions() {
        let result = block([done(1, "Upper A · Push", nil, WidFix.date(2026, 10, 14, 9, 0))], templates: [])
        XCTAssertEqual(result?.rows.count, 0)
        XCTAssertEqual(result?.sessionsDone, 1)
        XCTAssertEqual(result?.sessionsMissed, 0)
    }

    func testBlockOfAHistoryInTheFutureStartsAtWeekOne() {
        let result = block([done(1, "Upper A · Push", push.id, WidFix.date(2026, 12, 1, 9, 0))])
        XCTAssertEqual(result?.name, "Block 1")
        XCTAssertEqual(result?.weekIndex, 1)
    }

    // MARK: The lift of the block

    func testBlockLiftChangeRunsFromTheLastSessionBeforeTheBlockToTheLatest() {
        // First workout Monday 24 August: block 2 began on Monday 21 September, this is its week 4.
        var history = [done(1, "Upper A · Push", push.id, WidFix.date(2026, 8, 24, 9, 0))]
        let bench = { (n: Int, date: Date, value: Double) in
            WidFix.workout(n, at: date).with(exercises: [WidFix.lift("bench", [WidFix.set(50, 5)], best: value, n: n)])
        }
        history += [
            bench(10, WidFix.date(2026, 9, 3, 9, 0), 88),
            bench(11, WidFix.date(2026, 9, 17, 9, 0), 90),                              // the last session before the block
            bench(12, WidFix.date(2026, 9, 23, 9, 0), 92),
            bench(13, WidFix.date(2026, 10, 14, 9, 0), 96.2),
        ]
        let result = block(history)
        XCTAssertEqual(result?.name, "Block 2")
        XCTAssertEqual(result?.liftName, "Barbell bench press")
        XCTAssertEqual(result?.liftDeltaKg, 6.2)
    }

    func testBlockLiftChangeStartsAtTheFirstSessionInsideTheBlockWhenNoneCameBefore() {
        var history = [done(1, "Upper A · Push", push.id, WidFix.date(2026, 8, 24, 9, 0))]
        let bench = { (n: Int, date: Date, value: Double) in
            WidFix.workout(n, at: date).with(exercises: [WidFix.lift("bench", [WidFix.set(50, 5)], best: value, n: n)])
        }
        history += [bench(12, WidFix.date(2026, 9, 23, 9, 0), 92), bench(13, WidFix.date(2026, 10, 14, 9, 0), 96.2)]
        XCTAssertEqual(block(history)?.liftDeltaKg, 4.2)
    }

    func testBlockLiftIsNilForALiftWithFewerThanTwoSessionsOrWithoutLifts() {
        var history = [done(1, "Upper A · Push", push.id, WidFix.date(2026, 8, 24, 9, 0))]
        XCTAssertNil(block(history)?.liftName, "no lift at all")
        XCTAssertNil(block(history)?.liftDeltaKg)
        history.append(WidFix.workout(2, at: WidFix.date(2026, 10, 14, 9, 0)).with(exercises: [WidFix.lift("bench", [WidFix.set(80, 5)], n: 2)]))
        XCTAssertNil(block(history)?.liftName, "one session")
        XCTAssertNil(block(history)?.liftDeltaKg)
    }

    func testBlockLiftIsTheFirstOfTheListedLifts() {
        var history = [done(1, "Upper A · Push", push.id, WidFix.date(2026, 9, 21, 9, 0))]
        history += LiftFix.series("squat", [100, 110], newest: 2, spacing: 4, firstNumber: 20)
        history += LiftFix.series("bench", [90, 95, 99], newest: 1, spacing: 3, firstNumber: 30)
        XCTAssertEqual(block(history)?.liftName, "Barbell bench press", "bench was trained in more workouts")
    }
}
