import Foundation
import XCTest
@testable import PulseStrengthCore

/// widgets/SPEC.md section 2: freshness, weeklySets and bodyMap. `WidFix.now` is Friday 2026-10-16 09:41 UTC.
final class WidgetFreshnessRuleTests: XCTestCase {
    private func freshness(_ history: [CompletedWorkout]) -> [MuscleFreshness] {
        WidFix.snapshot(history: history).freshness
    }

    private func chest(_ sets: Int = 3) -> [MuscleSets] { [MuscleSets(muscle: .chest, sets: sets)] }

    func testFreshnessHasAllSixGroupsInMuscleGroupOrder() {
        let result = freshness([])
        XCTAssertEqual(result.map { $0.muscle }, [.chest, .back, .shoulders, .arms, .legs, .core])
        XCTAssertTrue(result.allSatisfy { $0.daysSince == nil && $0.status == .ready }, "never trained: ready")
    }

    func testFreshnessDaysSinceComesFromTheLatestWorkoutThatTrainedTheGroup() {
        let history = [
            WidFix.workout(3, "Upper B · Pull", daysAgo: 3, templateID: nil).with(muscles: [MuscleSets(muscle: .back, sets: 12), MuscleSets(muscle: .arms, sets: 3)]),
            WidFix.workout(2, "Upper A · Push", daysAgo: 5).with(muscles: [MuscleSets(muscle: .chest, sets: 9), MuscleSets(muscle: .shoulders, sets: 6)]),
            WidFix.workout(1, "Lower A · Quads", daysAgo: 7).with(muscles: [MuscleSets(muscle: .legs, sets: 12)]),
        ]
        let result = freshness(history)
        XCTAssertEqual(result.map { $0.daysSince }, [5, 3, 5, 3, 7, nil])
        XCTAssertEqual(freshness(history.reversed()).map { $0.daysSince }, [5, 3, 5, 3, 7, nil], "whatever the order of the history")
    }

    func testFreshnessUsesTheNewestWorkoutOfTheGroup() {
        let history = [
            WidFix.workout(1, daysAgo: 9).with(muscles: chest()),
            WidFix.workout(2, daysAgo: 2).with(muscles: chest()),
            WidFix.workout(3, daysAgo: 6).with(muscles: chest()),
        ]
        XCTAssertEqual(freshness(history)[0].daysSince, 2)
    }

    func testFreshnessStatusIsReadyFromFourDaysRecoveringForTwoOrThreeAndWorkedForTodayAndYesterday() {
        let expected: [(days: Double, status: FreshnessStatus)] = [
            (0, .worked), (1, .worked), (2, .recovering), (3, .recovering), (4, .ready), (5, .ready), (30, .ready),
        ]
        for (days, status) in expected {
            let result = freshness([WidFix.workout(1, daysAgo: days).with(muscles: chest())])[0]
            XCTAssertEqual(result.daysSince, Int(days), "\(days) days ago")
            XCTAssertEqual(result.status, status, "\(days) days ago")
        }
    }

    func testFreshnessCountsCalendarDays() {
        let late = freshness([WidFix.workout(1, at: WidFix.date(2026, 10, 15, 23, 50)).with(muscles: chest())])[0]
        XCTAssertEqual(late.daysSince, 1, "23:50 yesterday is 1 day ago")
        XCTAssertEqual(late.status, .worked)
    }

    func testFreshnessIgnoresAGroupEntryWithoutSets() {
        let history = [
            WidFix.workout(2, daysAgo: 0).with(muscles: [MuscleSets(muscle: .chest, sets: 0)]),
            WidFix.workout(1, daysAgo: 6).with(muscles: chest()),
        ]
        XCTAssertEqual(freshness(history)[0].daysSince, 6)
    }
}

final class WidgetWeeklySetsRuleTests: XCTestCase {
    private func weekly(_ history: [CompletedWorkout]) -> WeeklySetsSummary {
        WidFix.snapshot(history: history).weeklySets
    }

    private func sets(chest: Int = 0, back: Int = 0, shoulders: Int = 0, arms: Int = 0, legs: Int = 0, core: Int = 0) -> [MuscleSets] {
        [(MuscleGroup.chest, chest), (.back, back), (.shoulders, shoulders), (.arms, arms), (.legs, legs), (.core, core)]
            .filter { $0.1 > 0 }.map { MuscleSets(muscle: $0.0, sets: $0.1) }
    }

    private func thisWeek(_ muscles: [MuscleSets]) -> [CompletedWorkout] {
        [WidFix.workout(1, at: WidFix.date(2026, 10, 14, 9, 0)).with(muscles: muscles)]
    }

    func testWeeklySetsSumsTheMuscleSetsOfThisWeeksWorkouts() {
        let history = [
            WidFix.workout(1, at: WidFix.date(2026, 10, 12, 0, 0, 0)).with(muscles: sets(chest: 9, back: 3)),            // Monday 00:00:00: in
            WidFix.workout(2, at: WidFix.date(2026, 10, 15, 9, 0)).with(muscles: sets(chest: 4, legs: 5)),
            WidFix.workout(3, at: WidFix.date(2026, 10, 11, 23, 59, 59)).with(muscles: sets(chest: 20)),                // last Sunday: out
            WidFix.workout(4, at: WidFix.date(2026, 10, 20, 9, 0)).with(muscles: sets(chest: 20)),                      // next week: out
        ]
        let result = weekly(history)
        XCTAssertEqual(result.muscles.map { $0.muscle }, MuscleGroup.allCases)
        XCTAssertEqual(result.muscles.map { $0.sets }, [13, 3, 0, 0, 5, 0])
    }

    func testWeeklySetsTargetsAreTenToFourteenForTheMajorsAndSixToTenForArmsAndCore() {
        let result = weekly([])
        XCTAssertEqual(result.muscles.map { $0.targetLow }, [10, 10, 10, 6, 10, 6])
        XCTAssertEqual(result.muscles.map { $0.targetHigh }, [14, 14, 14, 10, 14, 10])
    }

    func testWeeklySetsStatusIsUnderBelowTheLowBoundOverAboveTheHighBoundElseOnTarget() {
        let below = weekly(thisWeek(sets(chest: 9, arms: 5))).muscles
        XCTAssertEqual(below[0].status, .under)
        XCTAssertEqual(below[3].status, .under)
        let low = weekly(thisWeek(sets(chest: 10, arms: 6))).muscles
        XCTAssertEqual(low[0].status, .onTarget, "the low bound is on target")
        XCTAssertEqual(low[3].status, .onTarget)
        let high = weekly(thisWeek(sets(chest: 14, arms: 10))).muscles
        XCTAssertEqual(high[0].status, .onTarget, "so is the high bound")
        XCTAssertEqual(high[3].status, .onTarget)
        let above = weekly(thisWeek(sets(chest: 15, arms: 11))).muscles
        XCTAssertEqual(above[0].status, .over)
        XCTAssertEqual(above[3].status, .over)
        XCTAssertEqual(weekly([]).muscles.map { $0.status }, Array(repeating: .under, count: 6), "no sets is under")
    }

    func testWeeklySetsTotalIsTheFourMajorsAgainst48() {
        let result = weekly(thisWeek(sets(chest: 12, back: 10, shoulders: 9, arms: 8, legs: 6, core: 4)))
        XCTAssertEqual(result.totalSets, 37, "arms and core are not part of the total")
        XCTAssertEqual(result.totalTarget, 48)
        XCTAssertEqual(result.setsToGo, 11)
        let over = weekly(thisWeek(sets(chest: 20, back: 20, shoulders: 20, legs: 20)))
        XCTAssertEqual(over.totalSets, 80)
        XCTAssertEqual(over.setsToGo, 0, "never negative")
        let none = weekly([])
        XCTAssertEqual(none.totalSets, 0)
        XCTAssertEqual(none.setsToGo, 48)
    }

    func testWeeklySetsLaggingMuscleIsTheMajorWithTheFewestSetsFirstOnATie() {
        XCTAssertEqual(weekly(thisWeek(sets(chest: 12, back: 10, shoulders: 9, legs: 6))).laggingMuscle, .legs)
        XCTAssertEqual(weekly(thisWeek(sets(chest: 12, back: 11, shoulders: 15, legs: 11))).laggingMuscle, .back, "back and legs tie: the first in MuscleGroup order")
        XCTAssertEqual(weekly(thisWeek(sets(chest: 3, back: 3, shoulders: 3, legs: 3))).laggingMuscle, .chest)
        XCTAssertEqual(weekly([]).laggingMuscle, .chest)
        XCTAssertEqual(weekly(thisWeek(sets(chest: 12, back: 12, shoulders: 12, legs: 11))).laggingMuscle, .legs, "arms and core are never lagging")
    }

    func testWeeklySetsLaggingMuscleIsNilOnceEveryMajorReachedTwelve() {
        XCTAssertNil(weekly(thisWeek(sets(chest: 12, back: 12, shoulders: 12, legs: 12))).laggingMuscle)
        XCTAssertNil(weekly(thisWeek(sets(chest: 20, back: 13, shoulders: 12, legs: 14))).laggingMuscle)
    }
}

final class WidgetBodyMapRuleTests: XCTestCase {
    private func bodyMap(_ muscles: [MuscleSets], templates: [WorkoutTemplate] = [], history extra: [CompletedWorkout] = []) -> BodyMap {
        let week = WidFix.workout(1, at: WidFix.date(2026, 10, 14, 9, 0)).with(muscles: muscles)
        return WidFix.snapshot(StrengthData(templates: templates, history: [week] + extra)).bodyMap
    }

    private func sets(_ pairs: [(MuscleGroup, Int)]) -> [MuscleSets] { pairs.map { MuscleSets(muscle: $0.0, sets: $0.1) } }

    func testBodyMapLevelIsZeroForNoSetsOneUpToFourTwoUpToNineThreeFromTen() {
        let counts = [0, 1, 4, 5, 9, 10, 25]
        let expected = [0, 1, 1, 2, 2, 3, 3]
        for (count, level) in zip(counts, expected) {
            let result = bodyMap(sets([(.chest, count)])).levels.first { $0.muscle == .chest }
            XCTAssertEqual(result?.level, level, "\(count) sets")
        }
        XCTAssertEqual(bodyMap([]).levels.map { $0.muscle }, MuscleGroup.allCases)
    }

    func testBodyMapUntouchedAreTheGroupsWithNoSetsThisWeek() {
        let result = bodyMap(sets([(.chest, 6), (.back, 3), (.arms, 2)]))
        XCTAssertEqual(result.untouched, [.shoulders, .legs, .core])
        XCTAssertEqual(bodyMap([]).untouched, MuscleGroup.allCases)
    }

    func testBodyMapOnlyCountsThisWeek() {
        let lastWeek = WidFix.workout(2, at: WidFix.date(2026, 10, 11, 23, 0)).with(muscles: sets([(.legs, 12)]))
        XCTAssertEqual(bodyMap([], history: [lastWeek]).untouched, MuscleGroup.allCases)
    }

    private func pushPull() -> [WorkoutTemplate] {
        [
            WidFix.template(1, "Upper A · Push", [WidFix.entry("bench", WidFix.planned(3, 80, 6)), WidFix.entry("ohp", WidFix.planned(3, 45, 8))]),
            WidFix.template(2, "Lower A · Quads", [
                WidFix.entry("squat", [PlannedSet(type: .warmup, weightKg: 40, reps: 8)] + WidFix.planned(3, 80, 6)),
                WidFix.entry("legext", WidFix.planned(3, 45, 12)),
            ]),
        ]
    }

    func testBodyMapMessageNamesTheFirstUntouchedMajorAndSaysItsTemplateIsNextInLine() {
        var templates = pushPull()
        templates[0].lastPerformed = WidFix.now.addingTimeInterval(-86_400)            // Upper A was last: Lower A is next
        let message = bodyMap(sets([(.chest, 12), (.back, 9), (.shoulders, 6)]), templates: templates).message
        XCTAssertEqual(message, "Legs untouched. Lower A is next in line.")
    }

    func testBodyMapMessageSuggestsTheTemplateWhenItIsNotTheNextUp() {
        var templates = pushPull()
        templates[1].lastPerformed = WidFix.now.addingTimeInterval(-86_400)            // Lower A was last: Upper A is next
        let message = bodyMap(sets([(.chest, 12), (.back, 9), (.shoulders, 6)]), templates: templates).message
        XCTAssertEqual(message, "Legs untouched. Try Lower A.")
    }

    func testBodyMapMessageUsesTheFirstUntouchedMajorInMuscleGroupOrder() {
        let message = bodyMap(sets([(.back, 6)]), templates: pushPull()).message
        XCTAssertTrue(message.hasPrefix("Chest untouched."), message)
        XCTAssertEqual(message, "Chest untouched. Upper A is next in line.", "nothing was performed: the first template is next")
    }

    func testBodyMapMessagePicksTheTemplateWithTheMostNonWarmUpSetsOfTheGroup() {
        // Lower B has 2 sets of squats, Lower A has 3 working sets (plus a warm-up that does not count).
        var templates = pushPull()
        templates.append(WidFix.template(3, "Lower B · Hamstrings", [WidFix.entry("rdl", WidFix.planned(2, 70, 8)), WidFix.entry("legcurl", WidFix.planned(2, 35, 12))]))
        let message = bodyMap(sets([(.chest, 12), (.back, 9), (.shoulders, 6)]), templates: templates).message
        XCTAssertEqual(message, "Legs untouched. Try Lower A.", "Lower A has 6 working leg sets, Lower B has 4")
        // The first template wins a tie: Lower B and Lower C both have 4 working leg sets.
        let glutes = WidFix.template(4, "Lower C · Glutes", [WidFix.entry("hipthrust", WidFix.planned(2, 70, 8)), WidFix.entry("lunge", WidFix.planned(2, 12, 10))])
        let tie = [templates[0], templates[2], glutes]
        XCTAssertEqual(bodyMap(sets([(.chest, 12), (.back, 9), (.shoulders, 6)]), templates: tie).message, "Legs untouched. Try Lower B.")
    }

    func testBodyMapMessageWithoutATemplateForTheGroupIsJustTheGroup() {
        let onlyPush = [pushPull()[0]]
        XCTAssertEqual(bodyMap(sets([(.chest, 12), (.back, 9), (.shoulders, 6)]), templates: onlyPush).message, "Legs untouched.")
        XCTAssertEqual(bodyMap(sets([(.chest, 12), (.back, 9), (.shoulders, 6)])).message, "Legs untouched.", "no templates at all")
    }

    func testBodyMapMessageUsesTheWholeNameWhenItHasNoDot() {
        let templates = [WidFix.template(1, "Upper", [WidFix.entry("bench", WidFix.planned(3, 80, 6))]), WidFix.template(2, "Legs", [WidFix.entry("squat", WidFix.planned(3, 80, 6))])]
        XCTAssertEqual(bodyMap(sets([(.chest, 12), (.back, 9), (.shoulders, 6)]), templates: templates).message, "Legs untouched. Try Legs.", "Upper is next after nothing was performed")
    }

    func testBodyMapMessageWhenEveryMajorGroupWasTrained() {
        let all = sets([(.chest, 1), (.back, 1), (.shoulders, 1), (.legs, 1)])
        let result = bodyMap(all)
        XCTAssertEqual(result.message, "Every major group has been trained this week.")
        XCTAssertEqual(result.untouched, [.arms, .core], "arms and core do not count for the message")
    }
}
