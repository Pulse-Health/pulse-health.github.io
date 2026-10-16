import Foundation
import XCTest
@testable import PulseStrengthCore

/// Builders for the recovery tests. Everything is relative to one fixed `now`, so no time zone or calendar is involved.
private enum R {
    static let now = SvcSyncFix.epoch
    static let hour: TimeInterval = 3_600
    static let day: TimeInterval = 86_400

    /// A workout that finished `hours` before `now` and trained the given muscle groups with the given number of working sets.
    static func workout(_ n: Int, hoursAgo hours: Double, _ muscles: [(MuscleGroup, Int)]) -> CompletedWorkout {
        let finished = now.addingTimeInterval(-hours * hour)
        return CompletedWorkout(
            id: SvcSyncFix.uuid(9_000 + n), name: "Workout \(n)", templateID: nil,
            startedAt: finished.addingTimeInterval(-3_000), finishedAt: finished, durationSeconds: 3_000, volumeKg: 0,
            loggedSets: muscles.reduce(0) { $0 + $1.1 }, averageHeartRate: nil, averageRIR: nil, exercises: [], personalRecords: [],
            muscleSets: muscles.map { MuscleSets(muscle: $0.0, sets: $0.1) }
        )
    }

    static func percents(_ history: [CompletedWorkout]) -> [MuscleGroup: Int] {
        RecoveryEstimator.estimates(history: history, now: now).mapValues { $0.percent }
    }
}

final class RecoveryEstimatorTests: XCTestCase {
    func testHasDataNeedsAWorkoutInTheLastThreeWeeks() {
        XCTAssertFalse(RecoveryEstimator.hasData(history: [], now: R.now))
        XCTAssertTrue(RecoveryEstimator.hasData(history: [R.workout(1, hoursAgo: 21 * 24, [(.chest, 1)])], now: R.now))
        XCTAssertFalse(RecoveryEstimator.hasData(history: [R.workout(1, hoursAgo: 21 * 24 + 1, [(.chest, 1)])], now: R.now))
    }

    private func assertPercents(
        _ history: [CompletedWorkout], _ expected: [MuscleGroup: Int], file: StaticString = #filePath, line: UInt = #line
    ) {
        let actual = R.percents(history)
        for muscle in MuscleGroup.allCases {
            XCTAssertEqual(actual[muscle], expected[muscle] ?? 100, "\(muscle)", file: file, line: line)
        }
    }

    // MARK: No data

    func testWithoutHistoryEveryGroupReadsFullyRecoveredAndHasNoData() {
        let estimates = RecoveryEstimator.estimates(history: [], now: R.now)
        XCTAssertEqual(Set(estimates.keys), Set(MuscleGroup.allCases))
        for estimate in estimates.values {
            XCTAssertEqual(estimate, RecoveryEstimate(percent: 100, hasData: false))
        }
        XCTAssertNil(RecoveryEstimator.readinessPercent(history: [], now: R.now))
    }

    func testAWorkoutOlderThanThreeWeeksGivesNoData() {
        let old = R.workout(1, hoursAgo: 22 * 24, [(.chest, 10)])
        let estimates = RecoveryEstimator.estimates(history: [old], now: R.now)
        XCTAssertTrue(estimates.values.allSatisfy { !$0.hasData && $0.percent == 100 })
        XCTAssertNil(RecoveryEstimator.readinessPercent(history: [old], now: R.now))
    }

    // MARK: The formula, table driven

    func testSingleWorkoutCases() {
        // (hours since finish, working sets, expected percent): hoursNeeded = 24 + 6 * min(sets, 12).
        let cases: [(Double, Int, Int)] = [
            (10, 3, 24),      // 10 / 42 = 23.8 %
            (48, 12, 50),     // 48 / 96
            (48, 20, 50),     // the sets are capped at 12
            (15, 1, 50),      // 15 / 30
            (0, 5, 0),        // just finished
            (86.4, 12, 90),   // 86.4 / 96
            (96, 12, 100),    // exactly recovered
            (200, 12, 100),   // long recovered
            (21, 2, 58),      // 21 / 36 = 58.3 %
            (6, 6, 10),       // 6 / 60
        ]
        for (hours, sets, expected) in cases {
            let history = [R.workout(1, hoursAgo: hours, [(.chest, sets)])]
            assertPercents(history, [.chest: expected])
            let estimates = RecoveryEstimator.estimates(history: history, now: R.now)
            XCTAssertTrue(estimates.values.allSatisfy { $0.hasData }, "\(hours) h \(sets) sets")
        }
    }

    func testEveryMuscleGroupIsEstimatedOnItsOwn() {
        let history = [R.workout(1, hoursAgo: 12, [(.chest, 6), (.arms, 3), (.shoulders, 0)])]
        // chest: 12 / 60 = 20 %, arms: 12 / 42 = 28.6 %, shoulders: no working sets.
        assertPercents(history, [.chest: 20, .arms: 29])
    }

    func testTheMostFatiguingWorkoutDecides() {
        // A: 12 sets, 24 h ago -> 24 / 96 = 25 %. B: 3 sets, 30 h ago -> 30 / 42 = 71 %. The minimum wins, whatever the order.
        let a = R.workout(1, hoursAgo: 24, [(.chest, 12)])
        let b = R.workout(2, hoursAgo: 30, [(.chest, 3)])
        assertPercents([a, b], [.chest: 25])
        assertPercents([b, a], [.chest: 25])
        // A lighter, more recent workout can be the one that decides: 1 set 3 h ago -> 3 / 30 = 10 %.
        let c = R.workout(3, hoursAgo: 3, [(.chest, 1)])
        assertPercents([c, a, b], [.chest: 10])
    }

    func testAWorkoutOutsideTheFiveDayWindowCountsForNothing() {
        let old = R.workout(1, hoursAgo: 5 * 24 + 1, [(.legs, 12)])
        assertPercents([old], [:])
        XCTAssertTrue(RecoveryEstimator.estimates(history: [old], now: R.now).values.allSatisfy { $0.hasData })
    }

    func testTheWindowBoundariesAreInclusive() {
        // Exactly five days ago: inside the window, and long recovered anyway.
        assertPercents([R.workout(1, hoursAgo: 5 * 24, [(.legs, 12)])], [:])
        // Exactly 21 days ago still counts as data; a second later does not.
        let edge = CompletedWorkout(
            id: SvcSyncFix.uuid(1), name: "Edge", templateID: nil, startedAt: R.now, finishedAt: R.now.addingTimeInterval(-21 * R.day),
            durationSeconds: 0, volumeKg: 0, loggedSets: 0, averageHeartRate: nil, averageRIR: nil, exercises: [], personalRecords: [], muscleSets: []
        )
        XCTAssertTrue(RecoveryEstimator.estimates(history: [edge], now: R.now)[.chest]?.hasData ?? false)
        var older = edge
        older.finishedAt = R.now.addingTimeInterval(-21 * R.day - 1)
        XCTAssertFalse(RecoveryEstimator.estimates(history: [older], now: R.now)[.chest]?.hasData ?? true)
    }

    func testAWorkoutThatFinishedInTheFutureCountsAsJustFinished() {
        let future = R.workout(1, hoursAgo: -2, [(.back, 4)])
        assertPercents([future], [.back: 0])
    }

    func testAWorkoutWithoutWorkingSetsLeavesEverythingRecoveredButHasData() {
        let warmupsOnly = R.workout(1, hoursAgo: 1, [])
        assertPercents([warmupsOnly], [:])
        XCTAssertEqual(RecoveryEstimator.readinessPercent(history: [warmupsOnly], now: R.now), 100)
    }

    func testTheResultIsTheSameForTheSameInputAndDoesNotDependOnTheDeviceCalendar() {
        let history = [R.workout(1, hoursAgo: 30, [(.chest, 8), (.shoulders, 4)]), R.workout(2, hoursAgo: 80, [(.legs, 10)])]
        XCTAssertEqual(R.percents(history), R.percents(history))
        // chest 30 / 72 = 41.7 %, shoulders 30 / 48 = 62.5 % (rounds half up), legs 80 / 84 = 95.2 %.
        assertPercents(history, [.chest: 42, .shoulders: 63, .legs: 95])
    }

    // MARK: Readiness

    func testReadinessIsTheEqualWeightedMeanOfTheSixGroups() {
        // chest 24, the other five 100: (24 + 500) / 6 = 87.33.
        let history = [R.workout(1, hoursAgo: 10, [(.chest, 3)])]
        XCTAssertEqual(RecoveryEstimator.readinessPercent(history: history, now: R.now), 87)
        // chest 0, legs 0, four groups 100: 400 / 6 = 66.67.
        let both = [R.workout(1, hoursAgo: 0, [(.chest, 3), (.legs, 5)])]
        XCTAssertEqual(RecoveryEstimator.readinessPercent(history: both, now: R.now), 67)
    }

    func testProviderAnswersWithThePercentOfTheEstimates() {
        let history = [R.workout(1, hoursAgo: 10, [(.chest, 3)])]
        let provider = RecoveryEstimator.provider(history: history, now: R.now)
        XCTAssertEqual(provider(.chest), 24)
        XCTAssertEqual(provider(.legs), 100)
        let none = RecoveryEstimator.provider(history: [], now: R.now)
        XCTAssertEqual(MuscleGroup.allCases.map { none($0) }, [100, 100, 100, 100, 100, 100])
    }

    func testStrengthDataAndModelExposeTheEstimates() {
        var data = StrengthData()
        XCTAssertNil(data.readinessPercent(now: R.now))
        data.history = [R.workout(1, hoursAgo: 10, [(.chest, 3)])]
        XCTAssertEqual(data.recoveryEstimates(now: R.now)[.chest], RecoveryEstimate(percent: 24, hasData: true))
        XCTAssertEqual(data.readinessPercent(now: R.now), 87)
        XCTAssertEqual(data.recoveryProvider(now: R.now)(.chest), 24)
        svcMain {
            let model = StrengthDataModel(persistence: nil)
            XCTAssertNil(model.readinessPercent(now: R.now))
            model.record(data.history[0], updateTemplate: nil)
            XCTAssertEqual(model.recoveryEstimates(now: R.now)[.chest]?.percent, 24)
            XCTAssertEqual(model.readinessPercent(now: R.now), 87)
            XCTAssertEqual(model.recoveryProvider(now: R.now)(.chest), 24)
        }
    }

    // MARK: Old files

    func testWorkoutsSavedByAnOlderBuildAreEstimatedFromTheirMuscleSets() throws {
        // The shape the sample history has had since the first version: muscleSets is stored with every workout.
        let workout = R.workout(1, hoursAgo: 10, [(.chest, 3)])
        let data = try StrengthJSON.makeEncoder().encode([workout])
        let loaded = try StrengthJSON.makeDecoder().decode([CompletedWorkout].self, from: data)
        XCTAssertEqual(RecoveryEstimator.estimates(history: loaded, now: R.now)[.chest]?.percent, 24)
    }
}

// MARK: - The default of the engine and the controller

final class DefaultRecoveryTests: XCTestCase {
    func testTheEngineEstimatesRecoveryFromTheStoredHistoryByDefault() {
        svcMain {
            let clock = SvcClock()
            let model = StrengthDataModel(persistence: nil)
            model.saveTemplate(StarterTemplates.all[0])
            let engine = WorkoutEngine(role: .authority, persistence: nil, data: model, clock: clock.reader)
            engine.start(template: model.data.templates[0])
            XCTAssertEqual(engine.presentation(now: clock.now)?.card?.recoveryPercent, 100, "no history: fully recovered")

            // Bench (chest) was trained with 3 sets ten hours ago.
            model.record(R.workout(1, hoursAgo: 10, [(.chest, 3)]), updateTemplate: nil)
            XCTAssertEqual(engine.presentation(now: clock.now)?.card?.recoveryPercent, 24)
            XCTAssertEqual(engine.presentation(now: clock.now)?.card?.recoveryLevel, .low)
            XCTAssertEqual(engine.recovery(.chest), 24)
            XCTAssertEqual(engine.recovery(.legs), 100)

            // Ten hours later the same history reads higher: 20 / 42.
            clock.advance(10 * R.hour)
            XCTAssertEqual(engine.presentation(now: clock.now)?.card?.recoveryPercent, 48)
        }
    }

    func testThePresentationEstimatesAtTheTimeItIsAskedFor() {
        svcMain {
            let clock = SvcClock()
            let model = StrengthDataModel(persistence: nil)
            model.saveTemplate(StarterTemplates.all[0])
            model.record(R.workout(1, hoursAgo: 10, [(.chest, 3)]), updateTemplate: nil)
            let engine = WorkoutEngine(role: .authority, persistence: nil, data: model, clock: clock.reader)
            engine.start(template: model.data.templates[0])
            XCTAssertEqual(engine.presentation(now: clock.now)?.card?.recoveryPercent, 24)
            XCTAssertEqual(engine.presentation(now: clock.now.addingTimeInterval(10 * R.hour))?.card?.recoveryPercent, 48, "the clock did not move, the asked time did")
        }
    }

    func testTheCardSaysWhenTheRecoveryIsOnlyTheDefault() {
        svcMain {
            let clock = SvcClock()
            let model = StrengthDataModel(persistence: nil)
            model.saveTemplate(StarterTemplates.all[0])
            let engine = WorkoutEngine(role: .authority, persistence: nil, data: model, clock: clock.reader)
            engine.start(template: model.data.templates[0])
            XCTAssertEqual(engine.presentation(now: clock.now)?.card?.recoveryPercent, 100)
            XCTAssertEqual(engine.presentation(now: clock.now)?.card?.recoveryHasData, false, "no history: 100 is not a measurement")

            model.record(R.workout(1, hoursAgo: 10, [(.chest, 3)]), updateTemplate: nil)
            XCTAssertEqual(engine.presentation(now: clock.now)?.card?.recoveryHasData, true)

            let later = clock.now.addingTimeInterval(22 * R.day)
            XCTAssertEqual(engine.presentation(now: later)?.card?.recoveryPercent, 100)
            XCTAssertEqual(engine.presentation(now: later)?.card?.recoveryHasData, false, "the last workout is older than 21 days")
            XCTAssertTrue(model.recoveryHasData(now: clock.now))
            XCTAssertFalse(model.recoveryHasData(now: later))
        }
    }

    func testAnInjectedProviderIsTakenForRealData() {
        svcMain {
            let clock = SvcClock()
            let engine = WorkoutEngine(role: .authority, persistence: nil, data: StrengthDataModel(persistence: nil), recovery: { _ in 100 }, clock: clock.reader)
            engine.start(template: StarterTemplates.all[0])
            XCTAssertEqual(engine.presentation(now: clock.now)?.card?.recoveryHasData, true, "the Pulse app's own model needs no history here")
        }
    }

    func testAProviderThatWasSetReplacesTheEstimateAndStays() {
        svcMain {
            let clock = SvcClock()
            let model = StrengthDataModel(persistence: nil)
            model.saveTemplate(StarterTemplates.all[0])
            model.record(R.workout(1, hoursAgo: 10, [(.chest, 3)]), updateTemplate: nil)
            let engine = WorkoutEngine(role: .authority, persistence: nil, data: model, recovery: DemoRecovery.provider, clock: clock.reader)
            engine.start(template: model.data.templates[0])
            XCTAssertEqual(engine.presentation(now: clock.now)?.card?.recoveryPercent, 88, "the demo provider passed to init wins")
            engine.recovery = { _ in 33 }
            XCTAssertEqual(engine.presentation(now: clock.now)?.card?.recoveryPercent, 33)
        }
    }

    #if canImport(Combine) || PULSE_COMBINE_SHIM
    func testTheControllerAndTheStoreUseTheEstimatorByDefault() {
        svcMain {
            let store = StrengthStore(persistence: nil)
            let clock = SvcClock()
            let controller = WorkoutController(store: store, persistence: nil, clock: clock.reader)
            XCTAssertEqual(controller.recovery(.chest), 100)
            XCTAssertNil(store.readinessPercent(now: clock.now))

            store.record(R.workout(1, hoursAgo: 10, [(.chest, 3)]), updateTemplate: nil)
            XCTAssertEqual(controller.recovery(.chest), 24)
            XCTAssertEqual(store.recoveryEstimates(now: clock.now)[.chest], RecoveryEstimate(percent: 24, hasData: true))
            XCTAssertEqual(store.readinessPercent(now: clock.now), 87)
            XCTAssertEqual(store.recoveryProvider(now: clock.now)(.chest), 24)

            controller.recovery = DemoRecovery.provider
            XCTAssertEqual(controller.recovery(.chest), 88)
        }
    }

    func testTheControllerCardFollowsTheHistory() {
        svcMain {
            let store = StrengthStore(persistence: nil)
            let clock = SvcClock()
            let controller = WorkoutController(store: store, persistence: nil, clock: clock.reader)
            controller.startWorkout(template: StarterTemplates.all[0])
            XCTAssertEqual(controller.presentation(now: clock.now)?.card?.recoveryHasData, false)
            store.record(R.workout(1, hoursAgo: 10, [(.chest, 3)]), updateTemplate: nil)
            XCTAssertEqual(controller.presentation(now: clock.now)?.card?.recoveryHasData, true)
        }
    }

    func testTheDemoRecoveryCanStillBePassedToTheController() {
        svcMain {
            let store = StrengthStore(persistence: nil)
            let controller = WorkoutController(store: store, persistence: nil, recovery: DemoRecovery.provider)
            XCTAssertEqual(controller.recovery(.legs), 64)
        }
    }
    #endif
}
