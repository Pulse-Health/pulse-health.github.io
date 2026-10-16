import Foundation
import XCTest
@testable import PulseStrengthCore

/// widgets/SPEC.md section 2: week, streakWeeks, month and year. `WidFix.now` is Friday 2026-10-16 09:41 UTC; the current week runs from
/// Monday 12 October to Sunday 18 October.
final class WidgetWeekRuleTests: XCTestCase {
    private func week(_ history: [CompletedWorkout], goal: Int = 4, zone: String = "UTC", now: Date = WidFix.now) -> WeekSummary {
        WidFix.snapshot(history: history, context: WidFix.context(zone, goal: goal), now: now).week
    }

    func testWeekDaysAreMondayToSundayAtLocalMidnightWithTheirLetters() {
        let result = week([])
        XCTAssertEqual(result.weekStart, WidFix.date(2026, 10, 12))
        XCTAssertEqual(result.days.count, 7)
        XCTAssertEqual(result.days.map { $0.letter }, ["M", "T", "W", "T", "F", "S", "S"])
        XCTAssertEqual(result.days.map { $0.date }, (12...18).map { WidFix.date(2026, 10, $0) })
        XCTAssertEqual(result.goal, 4)
        XCTAssertEqual(result.completed, 0)
        XCTAssertEqual(result.streakWeeks, 0)
        XCTAssertNil(result.lastWorkoutAt)
        XCTAssertNil(result.daysSinceLastWorkout)
        XCTAssertTrue(result.days.allSatisfy { $0.sessions == 0 && $0.label == nil })
    }

    func testWeekCompletedCountsTheWorkoutsThatDayBucketIntoThisWeek() {
        let history = [
            WidFix.workout(1, at: WidFix.date(2026, 10, 15, 18, 0)),
            WidFix.workout(2, at: WidFix.date(2026, 10, 12, 0, 0, 0)),          // Monday 00:00:00 is in
            WidFix.workout(3, at: WidFix.date(2026, 10, 11, 23, 59, 59)),       // Sunday 23:59:59 of the week before is out
            WidFix.workout(4, at: WidFix.date(2026, 9, 1)),
        ]
        XCTAssertEqual(week(history).completed, 2)
    }

    func testWeekDaysHaveSessionsLabelIsTodayAndIsFuture() {
        let history = [
            WidFix.workout(1, "Upper B · Pull", at: WidFix.date(2026, 10, 13, 9, 0)),
            WidFix.workout(2, "Legs", at: WidFix.date(2026, 10, 15, 18, 30)),
        ]
        let days = week(history).days
        XCTAssertEqual(days.map { $0.sessions }, [0, 1, 0, 1, 0, 0, 0])
        XCTAssertEqual(days.map { $0.label }, [nil, "UB", nil, "LE", nil, nil, nil])
        XCTAssertEqual(days.map { $0.isToday }, [false, false, false, false, true, false, false], "today is Friday")
        XCTAssertEqual(days.map { $0.isFuture }, [false, false, false, false, false, true, true])
    }

    func testWeekDayLabelIsTheInitialsOfTheEarliestWorkoutOfTheDay() {
        let history = [
            WidFix.workout(1, "Upper A · Push", at: WidFix.date(2026, 10, 14, 18, 0)),
            WidFix.workout(2, "Lower A · Quads", at: WidFix.date(2026, 10, 14, 7, 0)),
        ]
        let wednesday = week(history).days[2]
        XCTAssertEqual(wednesday.sessions, 2)
        XCTAssertEqual(wednesday.label, "LA", "the 07:00 workout is the earliest, whatever the order of the history")
    }

    func testWeekLastWorkoutAtIsTheLatestFinishedAt() {
        let history = [
            WidFix.workout(1, at: WidFix.date(2026, 10, 10, 8, 0)),
            WidFix.workout(2, at: WidFix.date(2026, 10, 14, 18, 0)),
            WidFix.workout(3, at: WidFix.date(2026, 10, 12, 7, 0)),
        ]
        XCTAssertEqual(week(history).lastWorkoutAt, WidFix.date(2026, 10, 14, 18, 0))
    }

    func testWeekDaysSinceLastWorkoutCountsCalendarDays() {
        XCTAssertEqual(week([WidFix.workout(1, at: WidFix.date(2026, 10, 15, 23, 50))]).daysSinceLastWorkout, 1, "23:50 yesterday is 1 day ago")
        XCTAssertEqual(week([WidFix.workout(1, at: WidFix.date(2026, 10, 16, 0, 5))]).daysSinceLastWorkout, 0)
        XCTAssertEqual(week([WidFix.workout(1, at: WidFix.date(2026, 10, 9, 9, 42))]).daysSinceLastWorkout, 7)
        XCTAssertNil(week([]).daysSinceLastWorkout, "nil without history")
    }

    // MARK: Time zones and the week boundary

    func testTheWeekChangesAtMondayMidnightNotOneSecondBefore() {
        let sunday = WidFix.workout(1, at: WidFix.date(2026, 10, 18, 23, 59, 58))
        let monday = WidFix.workout(2, at: WidFix.date(2026, 10, 19, 0, 0, 0))
        let history = [monday, sunday]

        let lastSecondOfTheWeek = week(history, now: WidFix.date(2026, 10, 18, 23, 59, 59))
        XCTAssertEqual(lastSecondOfTheWeek.weekStart, WidFix.date(2026, 10, 12))
        XCTAssertEqual(lastSecondOfTheWeek.completed, 1, "the Monday workout is in the future: next week")
        XCTAssertTrue(lastSecondOfTheWeek.days[6].isToday)
        XCTAssertEqual(lastSecondOfTheWeek.days[6].sessions, 1)
        XCTAssertTrue(lastSecondOfTheWeek.days.allSatisfy { !$0.isFuture })

        let firstSecondOfTheNext = week(history, now: WidFix.date(2026, 10, 19, 0, 0, 0))
        XCTAssertEqual(firstSecondOfTheNext.weekStart, WidFix.date(2026, 10, 19))
        XCTAssertEqual(firstSecondOfTheNext.completed, 1, "only the workout of Monday 00:00:00 is in the new week")
        XCTAssertTrue(firstSecondOfTheNext.days[0].isToday)
        XCTAssertEqual(firstSecondOfTheNext.days[0].sessions, 1)
        XCTAssertEqual(firstSecondOfTheNext.daysSinceLastWorkout, 0)
    }

    func testSundayEveningInOneZoneIsMondayInAnother() {
        // 2026-10-18T22:30Z: Sunday evening in UTC, already Monday 11:30 in Auckland (UTC+13), Sunday 15:30 in Los Angeles.
        let now = WidFix.date(2026, 10, 18, 22, 30)
        let history = [WidFix.workout(1, at: WidFix.date(2026, 10, 18, 22, 0))]
        let utc = week(history, zone: "UTC", now: now)
        let auckland = week(history, zone: "Pacific/Auckland", now: now)
        let losAngeles = week(history, zone: "America/Los_Angeles", now: now)
        XCTAssertEqual(utc.weekStart, WidFix.date(2026, 10, 12))
        XCTAssertTrue(utc.days[6].isToday)
        XCTAssertEqual(auckland.weekStart, WidFix.date(2026, 10, 19, zone: "Pacific/Auckland"))
        XCTAssertTrue(auckland.days[0].isToday, "Monday in New Zealand")
        XCTAssertEqual(auckland.days[0].sessions, 1, "the workout is on Monday there")
        XCTAssertEqual(losAngeles.weekStart, WidFix.date(2026, 10, 12, zone: "America/Los_Angeles"))
        XCTAssertTrue(losAngeles.days[6].isToday)
    }

    func testWeekDaysAcrossADaylightSavingChangeAreConsecutiveLocalMidnights() {
        // Clocks go back in Berlin on Sunday 25 October 2026: the week of 19 October has a 25 hour Sunday.
        let now = WidFix.date(2026, 10, 22, 12, 0, zone: "Europe/Berlin")
        let history = [WidFix.workout(1, at: WidFix.date(2026, 10, 25, 23, 30, zone: "Europe/Berlin"))]
        let result = week(history, zone: "Europe/Berlin", now: now)
        XCTAssertEqual(result.weekStart, WidFix.date(2026, 10, 19, zone: "Europe/Berlin"))
        XCTAssertEqual(result.days.map { $0.date }, (19...25).map { WidFix.date(2026, 10, $0, zone: "Europe/Berlin") })
        XCTAssertEqual(result.days[6].sessions, 1, "23:30 on the long Sunday is still Sunday")
        XCTAssertTrue(result.days[6].isFuture)
        XCTAssertTrue(result.days[3].isToday)
    }

    func testAWorkoutLateAtNightBelongsToItsLocalDayInEachZone() {
        let instant = WidFix.date(2026, 10, 14, 11, 30)         // Wednesday 11:30Z
        let history = [WidFix.workout(1, at: instant)]
        XCTAssertEqual(week(history, zone: "UTC").days.map { $0.sessions }, [0, 0, 1, 0, 0, 0, 0])
        XCTAssertEqual(week(history, zone: "Pacific/Auckland").days.map { $0.sessions }, [0, 0, 0, 1, 0, 0, 0], "Thursday 00:30 in New Zealand")
        XCTAssertEqual(week(history, zone: "America/Los_Angeles").days.map { $0.sessions }, [0, 0, 1, 0, 0, 0, 0])
    }

    // MARK: A workout in the future

    func testAWorkoutInTheFutureBelongsToItsDayAndCountsAsToday() {
        let future = WidFix.workout(1, "Upper A · Push", at: WidFix.date(2026, 10, 18, 9, 41))          // Sunday, two days ahead
        let snapshot = WidFix.snapshot(history: [future, WidFix.workout(2, at: WidFix.date(2026, 10, 13, 9, 41))])
        XCTAssertEqual(snapshot.week.completed, 2, "its day is in this week")
        XCTAssertEqual(snapshot.week.days[6].sessions, 1)
        XCTAssertTrue(snapshot.week.days[6].isFuture)
        XCTAssertEqual(snapshot.week.lastWorkoutAt, future.finishedAt)
        XCTAssertEqual(snapshot.week.daysSinceLastWorkout, 0, "a date in the future counts as 0 days")
        XCTAssertEqual(snapshot.lastSession?.workoutID, future.id)
    }

    func testAWorkoutInAFutureWeekIsNotInThisWeekButIsStillTheLastWorkout() {
        let future = WidFix.workout(1, at: WidFix.date(2026, 10, 30, 9, 41))
        let snapshot = WidFix.snapshot(history: [future])
        XCTAssertEqual(snapshot.week.completed, 0)
        XCTAssertEqual(snapshot.week.daysSinceLastWorkout, 0)
        XCTAssertEqual(snapshot.week.lastWorkoutAt, future.finishedAt)
    }

    func testAPersonalRecordInTheFutureIsNeverFresh() {
        let record = PersonalRecord(exerciseID: "bench", exerciseName: "Bench", weightKg: 85, reps: 5, estimated1RM: 99, previousBest: 95)
        let snapshot = WidFix.snapshot(history: [WidFix.workout(1, at: WidFix.now.addingTimeInterval(3_600), records: [record])])
        XCTAssertEqual(snapshot.latestPR?.isFresh, false)
    }
}

final class WidgetStreakRuleTests: XCTestCase {
    /// One workout in each of the weeks at `offsets` before the current one (0 = this week), `perWeek` workouts each.
    private func weeks(_ offsets: [Int], perWeek: Int = 1) -> [CompletedWorkout] {
        var history: [CompletedWorkout] = []
        for offset in offsets {
            for index in 0..<perWeek {
                history.append(WidFix.workout(history.count + 1, at: WidFix.date(2026, 10, 13, 9, index).addingTimeInterval(Double(-offset) * 7 * 86_400)))
            }
        }
        return history
    }

    private func streak(_ history: [CompletedWorkout], goal: Int) -> Int {
        WidFix.snapshot(history: history, context: WidFix.context(goal: goal)).week.streakWeeks
    }

    func testStreakWeeksCountsTheWeeksThatMetTheGoalGoingBackwardsAndTheCurrentWeekCountsWhenMet() {
        XCTAssertEqual(streak(weeks([0, 1, 2], perWeek: 2), goal: 2), 3)
        XCTAssertEqual(streak(weeks([1, 2], perWeek: 2), goal: 2), 2, "the current week has not met the goal yet")
    }

    func testTheCurrentWeekIsSkippedNotABreakWhenItHasNotMetTheGoal() {
        var history = weeks([1, 2, 3], perWeek: 2)
        history.append(WidFix.workout(99, at: WidFix.date(2026, 10, 13, 12, 0)))     // one workout this week, goal 2
        XCTAssertEqual(streak(history, goal: 2), 3)
    }

    func testTheStreakStopsAtTheFirstEarlierWeekBelowTheGoal() {
        // Weeks 0, 1 and 2 met the goal, week 3 did not, weeks 4 and 5 did.
        var history = weeks([0, 1, 2, 4, 5], perWeek: 2)
        history.append(WidFix.workout(98, at: WidFix.date(2026, 10, 13, 12, 0).addingTimeInterval(-3 * 7 * 86_400)))
        XCTAssertEqual(streak(history, goal: 2), 3)
    }

    func testAnEarlierWeekWithoutAnyWorkoutBreaksTheStreak() {
        XCTAssertEqual(streak(weeks([0, 1, 3, 4], perWeek: 1), goal: 1), 2)
    }

    func testTheGoalDecidesWhichWeeksCount() {
        let history = weeks([0, 1, 2, 3], perWeek: 3)
        XCTAssertEqual(streak(history, goal: 3), 4)
        XCTAssertEqual(streak(history, goal: 4), 0)
        XCTAssertEqual(streak(history, goal: 1), 4)
    }

    func testAWorkoutInAFutureWeekDoesNotCountForThePast() {
        var history = weeks([1, 2], perWeek: 1)
        history.append(WidFix.workout(77, at: WidFix.date(2026, 10, 27, 9, 0)))
        XCTAssertEqual(streak(history, goal: 1), 2)
    }

    func testStreakWeeksStopsAt520() {
        let history = (0..<600).map { WidFix.workout($0 + 1, at: WidFix.date(2026, 10, 13, 9, 0).addingTimeInterval(Double(-$0) * 7 * 86_400)) }
        XCTAssertEqual(streak(history, goal: 1), 520)
        XCTAssertEqual(WidgetPeriods.streakCap, 520)
    }

    func testStreakWeeksIsZeroWithoutHistory() {
        XCTAssertEqual(streak([], goal: 1), 0)
    }
}

final class WidgetMonthRuleTests: XCTestCase {
    private func month(_ history: [CompletedWorkout], now: Date = WidFix.now, zone: String = "UTC") -> MonthSummary {
        WidFix.snapshot(history: history, context: WidFix.context(zone), now: now).month
    }

    func testMonthHasTheNameTheStartAndOneEntryPerDay() {
        let october = month([])
        XCTAssertEqual(october.title, "October")
        XCTAssertEqual(october.monthStart, WidFix.date(2026, 10, 1))
        XCTAssertEqual(october.days.map { $0.day }, Array(1...31))
        XCTAssertEqual(october.sessionCount, 0)
        XCTAssertTrue(october.days.allSatisfy { $0.level == 0 && $0.sessions == 0 })
        XCTAssertEqual(month([], now: WidFix.date(2026, 2, 10)).days.count, 28)
        XCTAssertEqual(month([], now: WidFix.date(2024, 2, 10)).days.count, 29)
        XCTAssertEqual(month([], now: WidFix.date(2026, 4, 10)).days.count, 30)
        XCTAssertEqual(month([], now: WidFix.date(2026, 4, 10)).title, "April")
    }

    func testMonthLeadingBlankDaysIsTheWeekdayOfThe1stWithMondayZero() {
        XCTAssertEqual(month([]).leadingBlankDays, 3, "1 October 2026 is a Thursday")
        XCTAssertEqual(month([], now: WidFix.date(2026, 6, 15)).leadingBlankDays, 0, "1 June 2026 is a Monday")
        XCTAssertEqual(month([], now: WidFix.date(2026, 2, 15)).leadingBlankDays, 6, "1 February 2026 is a Sunday")
        XCTAssertEqual(month([], now: WidFix.date(2026, 3, 15)).leadingBlankDays, 6, "1 March 2026 is a Sunday")
    }

    func testMonthMarksTodayAndTheFuture() {
        let days = month([]).days
        XCTAssertEqual(days.filter { $0.isToday }.map { $0.day }, [16])
        XCTAssertEqual(days.filter { $0.isFuture }.map { $0.day }, Array(17...31))
    }

    func testMonthCountsSessionsAndSumsTheVolumePerDay() {
        let history = [
            WidFix.workout(1, at: WidFix.date(2026, 10, 3, 8, 0), volumeKg: 400),
            WidFix.workout(2, at: WidFix.date(2026, 10, 3, 18, 0), volumeKg: 500),
            WidFix.workout(3, at: WidFix.date(2026, 10, 9, 9, 0), volumeKg: 900),
            WidFix.workout(4, at: WidFix.date(2026, 9, 30, 23, 59), volumeKg: 5_000),     // September
            WidFix.workout(5, at: WidFix.date(2026, 11, 1, 0, 0), volumeKg: 5_000),       // November
        ]
        let october = month(history)
        XCTAssertEqual(october.sessionCount, 3)
        XCTAssertEqual(october.days[2].sessions, 2)
        XCTAssertEqual(october.days[8].sessions, 1)
        XCTAssertEqual(october.days[2].level, 3, "400 + 500 equals the heaviest day, 900")
        XCTAssertEqual(october.days[8].level, 3)
    }

    func testMonthLevelIsByVolumeAgainstTheHeaviestDay() {
        // The heaviest day has 900 kg: up to 300 kg is level 1, up to 600 level 2, above that level 3.
        let volumes: [(day: Int, kg: Double)] = [(1, 300), (2, 301), (3, 600), (4, 601), (5, 900), (6, 0), (7, 10)]
        let history = volumes.enumerated().map { WidFix.workout($0.offset + 1, at: WidFix.date(2026, 10, $0.element.day, 9, 0), volumeKg: $0.element.kg) }
        let levels = month(history).days.prefix(8).map { $0.level }
        XCTAssertEqual(Array(levels), [1, 2, 2, 3, 3, 1, 1, 0], "300 is a third: 1; 301: 2; 600 is two thirds: 2; 601: 3; 900: 3; 0 kg and 10 kg: 1")
    }

    func testMonthWhoseVolumesAreAllZeroGivesLevelOne() {
        let history = [
            WidFix.workout(1, at: WidFix.date(2026, 10, 2, 9, 0), volumeKg: 0),
            WidFix.workout(2, at: WidFix.date(2026, 10, 5, 9, 0), volumeKg: 0),
        ]
        let days = month(history).days
        XCTAssertEqual(days.map { $0.level }.prefix(6).map { $0 }, [0, 1, 0, 0, 1, 0])
    }

    func testMonthFollowsTheLocalMonthOfTheZone() {
        // 2026-09-30T20:00Z is already 1 October 09:00 in Auckland (UTC+13).
        let now = WidFix.date(2026, 9, 30, 20, 0)
        let history = [
            WidFix.workout(1, at: WidFix.date(2026, 9, 30, 10, 0), volumeKg: 100),      // 30 September 23:00 in Auckland
            WidFix.workout(2, at: WidFix.date(2026, 9, 30, 19, 0), volumeKg: 100),      // 1 October 08:00 in Auckland
        ]
        let utc = month(history, now: now, zone: "UTC")
        let auckland = month(history, now: now, zone: "Pacific/Auckland")
        XCTAssertEqual(utc.title, "September")
        XCTAssertEqual(utc.days.count, 30)
        XCTAssertEqual(utc.sessionCount, 2)
        XCTAssertEqual(utc.days[29].sessions, 2)
        XCTAssertEqual(auckland.title, "October")
        XCTAssertEqual(auckland.days.count, 31)
        XCTAssertEqual(auckland.monthStart, WidFix.date(2026, 10, 1, zone: "Pacific/Auckland"))
        XCTAssertEqual(auckland.sessionCount, 1, "only the second workout is in October there")
        XCTAssertEqual(auckland.days[0].sessions, 1)
        XCTAssertTrue(auckland.days[0].isToday)
    }

    func testMonthWithADaylightSavingChangeInsideIt() {
        // Clocks go back in Berlin on 25 October 2026.
        let now = WidFix.date(2026, 10, 28, 9, 0, zone: "Europe/Berlin")
        let history = [
            WidFix.workout(1, at: WidFix.date(2026, 10, 24, 23, 30, zone: "Europe/Berlin"), volumeKg: 100),
            WidFix.workout(2, at: WidFix.date(2026, 10, 25, 0, 15, zone: "Europe/Berlin"), volumeKg: 100),
            WidFix.workout(3, at: WidFix.date(2026, 10, 25, 23, 59, zone: "Europe/Berlin"), volumeKg: 100),
            WidFix.workout(4, at: WidFix.date(2026, 10, 26, 0, 0, zone: "Europe/Berlin"), volumeKg: 100),
        ]
        let october = month(history, now: now, zone: "Europe/Berlin")
        XCTAssertEqual(october.days.count, 31)
        XCTAssertEqual(october.monthStart, WidFix.date(2026, 10, 1, zone: "Europe/Berlin"))
        XCTAssertEqual(october.days[23].sessions, 1)
        XCTAssertEqual(october.days[24].sessions, 2, "both workouts of the 25 hour day")
        XCTAssertEqual(october.days[25].sessions, 1)
        XCTAssertEqual(october.days.filter { $0.isToday }.map { $0.day }, [28])
        XCTAssertEqual(october.leadingBlankDays, 3)
    }
}

final class WidgetYearRuleTests: XCTestCase {
    private func year(_ history: [CompletedWorkout], now: Date = WidFix.now, zone: String = "UTC") -> YearSummary {
        WidFix.snapshot(history: history, context: WidFix.context(zone), now: now).year
    }

    func testYearHasTwelveMonthsOfTonnesRoundedToATenth() {
        let history = [
            WidFix.workout(1, at: WidFix.date(2026, 1, 5), volumeKg: 1_234),
            WidFix.workout(2, at: WidFix.date(2026, 1, 20), volumeKg: 2_000),
            WidFix.workout(3, at: WidFix.date(2026, 10, 2), volumeKg: 1_260),
        ]
        let result = year(history)
        XCTAssertEqual(result.year, 2026)
        XCTAssertEqual(result.sessionCount, 3)
        XCTAssertEqual(result.tonnes, 4.5, "4,494 kg is 4.494 t")
        XCTAssertEqual(result.monthlyTonnes.count, 12)
        XCTAssertEqual(result.monthlyTonnes[0], 3.2, "3,234 kg")
        XCTAssertEqual(result.monthlyTonnes[9], 1.3, "1,260 kg")
        XCTAssertEqual(result.monthlyTonnes.enumerated().filter { $0.offset != 0 && $0.offset != 9 }.map { $0.element }, Array(repeating: 0, count: 10))
    }

    func testYearIsTheCalendarYearOfNow() {
        let history = [
            WidFix.workout(1, at: WidFix.date(2025, 12, 31, 23, 59), volumeKg: 9_000),
            WidFix.workout(2, at: WidFix.date(2026, 1, 1, 0, 0), volumeKg: 1_000),
            WidFix.workout(3, at: WidFix.date(2027, 1, 1, 0, 0), volumeKg: 8_000),
        ]
        let result = year(history)
        XCTAssertEqual(result.sessionCount, 1)
        XCTAssertEqual(result.tonnes, 1)
        XCTAssertEqual(year(history, now: WidFix.date(2025, 6, 1)).tonnes, 9)
    }

    func testYearFollowsTheLocalCalendarOfTheZone() {
        // 2025-12-31T23:30Z is already 1 January 2026 in Auckland.
        let history = [WidFix.workout(1, at: WidFix.date(2025, 12, 31, 23, 30), volumeKg: 2_000)]
        let now = WidFix.date(2026, 3, 1)
        XCTAssertEqual(year(history, now: now, zone: "UTC").tonnes, 0)
        XCTAssertEqual(year(history, now: now, zone: "Pacific/Auckland").tonnes, 2)
        XCTAssertEqual(year(history, now: now, zone: "Pacific/Auckland").monthlyTonnes[0], 2)
    }

    func testYearWithoutHistoryIsAllZeros() {
        let result = year([])
        XCTAssertEqual(result, YearSummary(year: 2026, tonnes: 0, sessionCount: 0, monthlyTonnes: Array(repeating: 0, count: 12)))
    }
}
