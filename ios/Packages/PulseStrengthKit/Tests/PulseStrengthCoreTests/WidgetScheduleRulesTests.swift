import Foundation
import XCTest
@testable import PulseStrengthCore

/// widgets/SPEC.md section 2: restDay and tomorrow.
final class WidgetRestDayRuleTests: XCTestCase {
    private func restDay(_ history: [CompletedWorkout], now: Date, goal: Int = 4, zone: String = "UTC") -> RestDaySuggestion? {
        WidFix.snapshot(history: history, context: WidFix.context(zone, goal: goal), now: now).restDay
    }

    /// 12 October 2026 is a Monday; `weekday` 0 is that Monday.
    private func day(_ weekday: Int, hour: Int = 9, minute: Int = 41) -> Date {
        WidFix.date(2026, 10, 12 + weekday, hour, minute)
    }

    func testRestDayAfterAWorkoutYesterdayIsOneOfFourRoutinesByWeekday() {
        let routines: [(title: String, focus: String, minutes: Int)] = [
            ("10-min mobility", "Hips and T-spine", 10),
            ("8-min shoulder reset", "Shoulders and upper back", 8),
            ("12-min hips and hamstrings", "Hips and hamstrings", 12),
            ("6-min wrist and ankle prep", "Wrists and ankles", 6),
        ]
        // Tuesday to Sunday have a workout the day before; the Monday one follows a workout on Sunday 11 October.
        let yesterdays = [WidFix.date(2026, 10, 11, 18, 0)] + (0..<6).map { day($0, hour: 18, minute: 0) }
        for weekday in 0..<7 {
            let history = [WidFix.workout(1, at: yesterdays[weekday])]
            let result = restDay(history, now: day(weekday))
            let expected = routines[weekday % 4]
            XCTAssertEqual(result?.title, expected.title, "weekday \(weekday)")
            XCTAssertEqual(result?.focus, expected.focus, "weekday \(weekday)")
            XCTAssertEqual(result?.minutes, expected.minutes, "weekday \(weekday)")
            XCTAssertEqual(result?.reason, "Rest day")
        }
    }

    func testRestDayIsNilWhenAWorkoutWasDoneToday() {
        let history = [WidFix.workout(1, at: day(3, hour: 7, minute: 0)), WidFix.workout(2, at: day(4, hour: 8, minute: 0))]
        XCTAssertNil(restDay(history, now: day(4)), "a workout yesterday, but one this morning too")
        let laterToday = [WidFix.workout(1, at: day(3, hour: 18, minute: 0)), WidFix.workout(2, at: day(4, hour: 20, minute: 0))]
        XCTAssertNil(restDay(laterToday, now: day(4)), "a workout dated later today is today's")
    }

    func testRestDayIsNilWithoutAWorkoutYesterdayWhenTheGoalIsNotMet() {
        let history = [WidFix.workout(1, at: day(0, hour: 18, minute: 0))]               // Monday evening, now is Thursday
        XCTAssertNil(restDay(history, now: day(3), goal: 4))
        XCTAssertNil(restDay([], now: day(3)), "no history, nothing to recover from")
    }

    func testRestDayWhenTheGoalIsMetEvenWithoutAWorkoutYesterday() {
        let history = [WidFix.workout(1, at: day(0, hour: 18, minute: 0)), WidFix.workout(2, at: day(1, hour: 18, minute: 0))]
        XCTAssertNotNil(restDay(history, now: day(4), goal: 2), "2 of 2 workouts this week: a rest day")
        XCTAssertNil(restDay(history, now: day(4), goal: 3))
    }

    func testRestDayCountsYesterdayAsALocalCalendarDay() {
        XCTAssertNotNil(restDay([WidFix.workout(1, at: WidFix.date(2026, 10, 15, 23, 50))], now: WidFix.date(2026, 10, 16, 0, 10)), "20 minutes ago, but yesterday")
        XCTAssertNil(restDay([WidFix.workout(1, at: WidFix.date(2026, 10, 14, 23, 50))], now: WidFix.date(2026, 10, 16, 9, 0)), "two days ago")
        // 2026-10-15T22:00Z is 11:00 on the 16th in Auckland: a workout "today" there.
        let history = [WidFix.workout(1, at: WidFix.date(2026, 10, 15, 22, 0))]
        let now = WidFix.date(2026, 10, 16, 1, 0)
        XCTAssertNotNil(restDay(history, now: now, zone: "UTC"), "UTC: yesterday")
        XCTAssertNil(restDay(history, now: now, zone: "Pacific/Auckland"), "Auckland: both are the 16th")
    }
}

final class WidgetTomorrowRuleTests: XCTestCase {
    private let upper = WidFix.template(1, "Upper A · Push", [WidFix.entry("bench", WidFix.planned(3, 80, 6))])

    private func tomorrow(_ history: [CompletedWorkout], now: Date = WidFix.now, zone: String = "UTC", templates: [WorkoutTemplate]? = nil) -> TomorrowPlan? {
        WidFix.snapshot(StrengthData(templates: templates ?? [upper], history: history), context: WidFix.context(zone), now: now).tomorrow
    }

    /// A workout that started at `hour:minute` on 'day' of October 2026 and lasted 50 minutes.
    private func started(_ n: Int, day: Int, hour: Int, minute: Int, zone: String = "UTC") -> CompletedWorkout {
        let start = WidFix.date(2026, 10, day, hour, minute, zone: zone)
        return WidFix.workout(n, at: start.addingTimeInterval(3_000), durationSeconds: 3_000)
    }

    func testTomorrowNeedsANextUp() {
        XCTAssertNil(tomorrow([started(1, day: 12, hour: 7, minute: 0)], templates: []))
    }

    func testTomorrowNamesTheNextWorkoutAndTomorrowsWeekday() throws {
        let plan = try XCTUnwrap(tomorrow([]))
        XCTAssertEqual(plan.templateName, "Upper A · Push")
        XCTAssertEqual(plan.weekday, "Saturday", "16 October 2026 is a Friday")
        XCTAssertTrue(plan.isInferred)
        XCTAssertEqual(plan.note, "Gym bag ready?")
        XCTAssertNil(plan.plannedMinuteOfDay, "no history, no usual time")
        let weekdays = (0..<7).map { tomorrow([], now: WidFix.date(2026, 10, 12 + $0, 9, 0))?.weekday }
        XCTAssertEqual(weekdays, ["Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday", "Monday"])
    }

    func testTomorrowTheStartTimeIsTheMedianOfTheStartsRoundedToFiveMinutes() {
        // Starts 07:02, 07:08 and 06:58: the median is 07:02 = 422 minutes, which rounds to 420.
        let history = [started(1, day: 14, hour: 7, minute: 2), started(2, day: 13, hour: 7, minute: 8), started(3, day: 12, hour: 6, minute: 58)]
        XCTAssertEqual(tomorrow(history)?.plannedMinuteOfDay, 420)
        let late = [started(1, day: 14, hour: 18, minute: 3), started(2, day: 13, hour: 18, minute: 30), started(3, day: 12, hour: 18, minute: 0)]
        XCTAssertEqual(tomorrow(late)?.plannedMinuteOfDay, 18 * 60 + 5, "18:03 rounds to 18:05")
    }

    func testTomorrowWithAnEvenNumberOfWorkoutsAveragesTheTwoMiddleStartsAndRoundsHalvesUp() {
        // 07:05 (425) and 07:10 (430): 427.5 minutes is 85.5 steps of five, which rounds up to 86 = 430.
        let history = [started(1, day: 14, hour: 7, minute: 5), started(2, day: 13, hour: 7, minute: 10)]
        XCTAssertEqual(tomorrow(history)?.plannedMinuteOfDay, 430)
        // 07:00 (420) and 07:04 (424): 422 minutes rounds to 420.
        XCTAssertEqual(tomorrow([started(1, day: 14, hour: 7, minute: 0), started(2, day: 13, hour: 7, minute: 4)])?.plannedMinuteOfDay, 420)
    }

    func testTomorrowUsesTheStartNotTheFinishOfTheWorkout() {
        // Finished at 08:00 after 50 minutes: it started at 07:10.
        let workout = WidFix.workout(1, at: WidFix.date(2026, 10, 14, 8, 0), durationSeconds: 3_000)
        XCTAssertEqual(tomorrow([workout])?.plannedMinuteOfDay, 7 * 60 + 10)
    }

    func testTomorrowLooksAtTheLatestTenWorkoutsOnly() {
        var history = (1...10).map { started($0, day: 14, hour: 7, minute: 0).movedBack(days: Double($0)) }
        history += [started(20, day: 14, hour: 20, minute: 0).movedBack(days: 40), started(21, day: 14, hour: 20, minute: 0).movedBack(days: 41)]
        XCTAssertEqual(tomorrow(history)?.plannedMinuteOfDay, 420, "the two evening workouts are older than the latest ten")
        XCTAssertEqual(tomorrow(history.reversed())?.plannedMinuteOfDay, 420, "whatever the order of the history")
    }

    func testTomorrowTheStartTimeIsInTheLocalTimeZone() {
        // 07:00 UTC is 20:00 in Auckland (UTC+13).
        let history = [started(1, day: 14, hour: 7, minute: 0), started(2, day: 13, hour: 7, minute: 0)]
        XCTAssertEqual(tomorrow(history, zone: "UTC")?.plannedMinuteOfDay, 420)
        XCTAssertEqual(tomorrow(history, zone: "Pacific/Auckland")?.plannedMinuteOfDay, 20 * 60)
    }

    func testTomorrowTheStartTimeWrapsAtMidnight() {
        // 23:58 rounds to 24:00, which is 0.
        let history = [started(1, day: 14, hour: 23, minute: 58), started(2, day: 13, hour: 23, minute: 58)]
        XCTAssertEqual(tomorrow(history)?.plannedMinuteOfDay, 0)
    }
}

private extension CompletedWorkout {
    /// The same workout `days` days earlier.
    func movedBack(days: Double) -> CompletedWorkout {
        var copy = self
        copy.startedAt = startedAt.addingTimeInterval(-days * 86_400)
        copy.finishedAt = finishedAt.addingTimeInterval(-days * 86_400)
        return copy
    }
}
