import Foundation
import XCTest
@testable import PulseStrengthCore

/// widgets/SPEC.md section 2, "Calendar": days and weeks in the snapshot's time zone.
final class WidgetCalendarTests: XCTestCase {
    private func calendar(_ zone: String) -> WidgetCalendar {
        WidgetCalendar(context: WidFix.context(zone))
    }

    // MARK: Civil dates

    func testCivilDatesAndDayNumbersAreInverseForAWideRangeOfDays() {
        for day in stride(from: -800_000, through: 800_000, by: 37) {
            let civil = WidgetCalendar.civil(fromDay: day)
            XCTAssertEqual(WidgetCalendar.dayNumber(year: civil.year, month: civil.month, day: civil.day), day, "day \(day)")
            XCTAssertTrue((1...12).contains(civil.month))
            XCTAssertTrue((1...WidgetCalendar.daysInMonth(year: civil.year, month: civil.month)).contains(civil.day))
        }
    }

    func testCivilDatesMatchFoundationsGregorianCalendar() {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0)!
        for day in stride(from: 0, through: 60_000, by: 101) {
            let components = gregorian.dateComponents([.year, .month, .day, .weekday], from: Date(timeIntervalSince1970: Double(day) * 86_400))
            let civil = WidgetCalendar.civil(fromDay: day)
            XCTAssertEqual([civil.year, civil.month, civil.day], [components.year!, components.month!, components.day!], "day \(day)")
            // Foundation counts Sunday as 1.
            XCTAssertEqual((WidgetCalendar.weekdayIndex(ofDay: day) + 1) % 7 + 1, components.weekday!, "weekday of day \(day)")
        }
    }

    func testKnownDays() {
        XCTAssertEqual(WidgetCalendar.dayNumber(year: 1970, month: 1, day: 1), 0)
        XCTAssertEqual(WidgetCalendar.weekdayIndex(ofDay: 0), 3, "1970-01-01 was a Thursday")
        let friday = WidgetCalendar.dayNumber(year: 2026, month: 10, day: 16)
        XCTAssertEqual(friday, 20_742)
        XCTAssertEqual(WidgetCalendar.weekdayIndex(ofDay: friday), 4)
        XCTAssertEqual(WidgetCalendar.monday(onOrBefore: friday), WidgetCalendar.dayNumber(year: 2026, month: 10, day: 12))
        let monday = WidgetCalendar.dayNumber(year: 2026, month: 10, day: 12)
        XCTAssertEqual(WidgetCalendar.monday(onOrBefore: monday), monday, "a Monday starts its own week")
        XCTAssertEqual(WidgetCalendar.monday(onOrBefore: monday - 1), monday - 7, "Sunday belongs to the week before")
        XCTAssertEqual(WidgetCalendar.weekdayIndex(ofDay: -1), 2, "1969-12-31 was a Wednesday")
    }

    func testMonthLengthsIncludingLeapYears() {
        XCTAssertEqual((1...12).map { WidgetCalendar.daysInMonth(year: 2026, month: $0) }, [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])
        XCTAssertEqual(WidgetCalendar.daysInMonth(year: 2024, month: 2), 29)
        XCTAssertEqual(WidgetCalendar.daysInMonth(year: 2100, month: 2), 28)
        XCTAssertEqual(WidgetCalendar.daysInMonth(year: 2000, month: 2), 29)
    }

    func testDayOfYear() {
        XCTAssertEqual(WidgetCalendar.dayOfYear(ofDay: WidgetCalendar.dayNumber(year: 2026, month: 1, day: 1)), 1)
        XCTAssertEqual(WidgetCalendar.dayOfYear(ofDay: WidgetCalendar.dayNumber(year: 2026, month: 10, day: 16)), 289)
        XCTAssertEqual(WidgetCalendar.dayOfYear(ofDay: WidgetCalendar.dayNumber(year: 2026, month: 12, day: 31)), 365)
        XCTAssertEqual(WidgetCalendar.dayOfYear(ofDay: WidgetCalendar.dayNumber(year: 2024, month: 12, day: 31)), 366)
    }

    func testNamesAreEnglishAndMondayFirst() {
        XCTAssertEqual(WidgetCalendar.weekdayLetters, ["M", "T", "W", "T", "F", "S", "S"])
        XCTAssertEqual(WidgetCalendar.weekdayNames.first, "Monday")
        XCTAssertEqual(WidgetCalendar.weekdayNames.last, "Sunday")
        XCTAssertEqual(WidgetCalendar.monthNames.count, 12)
        XCTAssertEqual(WidgetCalendar.monthNames[9], "October")
    }

    // MARK: Local days

    func testADayIsTheLocalDateNotTheUTCDate() {
        let instant = WidFix.date(2026, 10, 16, 11, 30)                   // 2026-10-16T11:30:00Z
        XCTAssertEqual(calendar("UTC").day(of: instant), 20_742)
        XCTAssertEqual(calendar("Pacific/Auckland").day(of: instant), 20_743, "00:30 on the 17th in New Zealand (UTC+13)")
        XCTAssertEqual(calendar("America/Los_Angeles").day(of: instant), 20_742, "04:30 on the 16th in California (UTC-7)")
        XCTAssertEqual(calendar("America/Los_Angeles").day(of: WidFix.date(2026, 10, 16, 3, 0)), 20_741, "20:00 on the 15th in California")
    }

    func testDaysBetweenCountsTheLocalMidnightsCrossed() {
        let utc = calendar("UTC")
        let today = WidFix.date(2026, 10, 16, 9, 41)
        XCTAssertEqual(utc.daysBetween(WidFix.date(2026, 10, 15, 23, 50), today), 1, "23:50 yesterday is 1 day ago")
        XCTAssertEqual(utc.daysBetween(WidFix.date(2026, 10, 16, 0, 0), today), 0)
        XCTAssertEqual(utc.daysBetween(WidFix.date(2026, 10, 16, 9, 40), today), 0)
        XCTAssertEqual(utc.daysBetween(WidFix.date(2026, 10, 13, 9, 41), today), 3)
        XCTAssertEqual(utc.daysBetween(WidFix.date(2026, 10, 13, 23, 59), WidFix.date(2026, 10, 14, 0, 1)), 1, "two minutes apart, one midnight")
        XCTAssertEqual(utc.daysBetween(WidFix.date(2026, 10, 17, 9, 41), today), 0, "a date in the future counts as 0")
        XCTAssertEqual(utc.daysBetween(today, today), 0)
    }

    func testDaysBetweenFollowsTheZoneOfTheSnapshot() {
        let earlier = WidFix.date(2026, 10, 15, 22, 0)                    // 15 Oct 22:00Z
        let later = WidFix.date(2026, 10, 16, 1, 0)                       // 16 Oct 01:00Z
        XCTAssertEqual(calendar("UTC").daysBetween(earlier, later), 1)
        XCTAssertEqual(calendar("Pacific/Auckland").daysBetween(earlier, later), 0, "both are the 16th in New Zealand (UTC+13)")
    }

    func testAnInstantThatIsNotFiniteCountsAsTheEpochDay() {
        XCTAssertEqual(calendar("UTC").day(of: Date(timeIntervalSince1970: .nan)), 0)
        XCTAssertEqual(calendar("UTC").day(of: Date(timeIntervalSince1970: .infinity)), 0)
        XCTAssertEqual(calendar("UTC").minuteOfDay(Date(timeIntervalSince1970: .nan)), 0)
    }

    // MARK: Start of day and daylight saving

    func testStartOfDayIsLocalMidnight() {
        XCTAssertEqual(calendar("UTC").startOfDay(20_742), WidFix.date(2026, 10, 16))
        XCTAssertEqual(calendar("Pacific/Auckland").startOfDay(20_742), WidFix.date(2026, 10, 16, zone: "Pacific/Auckland"))
        XCTAssertEqual(calendar("America/Los_Angeles").startOfDay(20_742), WidFix.date(2026, 10, 16, zone: "America/Los_Angeles"))
        XCTAssertEqual(calendar("Asia/Kolkata").startOfDay(20_742), WidFix.date(2026, 10, 16, zone: "Asia/Kolkata"))
    }

    func testADaylightSavingDayIsOneDayLongAndStillBucketsCorrectly() {
        let berlin = calendar("Europe/Berlin")
        let day = WidgetCalendar.dayNumber(year: 2026, month: 10, day: 25)              // clocks go back at 03:00: a 25 hour day
        XCTAssertEqual(berlin.startOfDay(day + 1).timeIntervalSince(berlin.startOfDay(day)), 25 * 3_600)
        XCTAssertEqual(berlin.day(of: WidFix.date(2026, 10, 25, 0, 30, zone: "Europe/Berlin")), day)
        XCTAssertEqual(berlin.day(of: WidFix.date(2026, 10, 25, 23, 59, 59, zone: "Europe/Berlin")), day)
        XCTAssertEqual(berlin.day(of: WidFix.date(2026, 10, 26, 0, 0, zone: "Europe/Berlin")), day + 1)
        let spring = WidgetCalendar.dayNumber(year: 2026, month: 3, day: 29)            // clocks go forward: a 23 hour day
        XCTAssertEqual(berlin.startOfDay(spring + 1).timeIntervalSince(berlin.startOfDay(spring)), 23 * 3_600)

        let losAngeles = calendar("America/Los_Angeles")
        let fall = WidgetCalendar.dayNumber(year: 2026, month: 11, day: 1)
        XCTAssertEqual(losAngeles.startOfDay(fall + 1).timeIntervalSince(losAngeles.startOfDay(fall)), 25 * 3_600)
        XCTAssertEqual(losAngeles.daysBetween(WidFix.date(2026, 10, 31, 23, 0, zone: "America/Los_Angeles"), WidFix.date(2026, 11, 2, 0, 30, zone: "America/Los_Angeles")), 2)
    }

    func testMinuteOfDayIsLocal() {
        let instant = WidFix.date(2026, 10, 16, 11, 30)
        XCTAssertEqual(calendar("UTC").minuteOfDay(instant), 11 * 60 + 30)
        XCTAssertEqual(calendar("Pacific/Auckland").minuteOfDay(instant), 30, "00:30 local")
        XCTAssertEqual(calendar("America/Los_Angeles").minuteOfDay(instant), 4 * 60 + 30)
        XCTAssertEqual(calendar("UTC").minuteOfDay(WidFix.date(2026, 10, 16, 23, 59, 59)), 1_439)
        XCTAssertEqual(calendar("UTC").minuteOfDay(WidFix.date(2026, 10, 16, 0, 0, 0)), 0)
    }

    func testAnUnknownTimeZoneIdentifierCountsInUTCAndIsReportedAsUTC() {
        let context = WidFix.context("Nowhere/Land")
        XCTAssertEqual(WidgetCalendar(context: context).day(of: WidFix.date(2026, 10, 16, 23, 30)), 20_742)
        let snapshot = WidFix.snapshot(StrengthData(), context: context)
        XCTAssertEqual(snapshot.timeZoneID, "UTC")
        XCTAssertEqual(WidFix.snapshot(StrengthData(), context: WidFix.context("Pacific/Auckland")).timeZoneID, "Pacific/Auckland")
    }
}

/// widgets/SPEC.md section 2: initials(name) and the labels cut out of template names.
final class WidgetNameRuleTests: XCTestCase {
    func testInitialsOfTwoOrMoreTokensAreTheFirstCharacterOfTheFirstTwo() {
        XCTAssertEqual(WidgetText.initials(of: "Upper A · Push"), "UA", "the dot has no letter or digit and is dropped")
        XCTAssertEqual(WidgetText.initials(of: "Lower A · Quads"), "LA")
        XCTAssertEqual(WidgetText.initials(of: "push day"), "PD", "upper case")
        XCTAssertEqual(WidgetText.initials(of: "Full Body Workout"), "FB")
    }

    func testInitialsOfOneTokenAreItsFirstTwoCharacters() {
        XCTAssertEqual(WidgetText.initials(of: "Legs"), "LE")
        XCTAssertEqual(WidgetText.initials(of: "x"), "X")
        XCTAssertEqual(WidgetText.initials(of: "  Pull  "), "PU")
        XCTAssertEqual(WidgetText.initials(of: "· Push ·"), "PU", "only one token is left")
    }

    func testInitialsWithoutAnyTokenAreWO() {
        XCTAssertEqual(WidgetText.initials(of: ""), "WO")
        XCTAssertEqual(WidgetText.initials(of: "   "), "WO")
        XCTAssertEqual(WidgetText.initials(of: "· - ·"), "WO")
    }

    func testInitialsKeepDigitsAndSplitOnAnyWhitespace() {
        XCTAssertEqual(WidgetText.initials(of: "5x5 Strength"), "5S")
        XCTAssertEqual(WidgetText.initials(of: "Upper\tB\nPull"), "UB")
        XCTAssertEqual(WidgetText.initials(of: "Ärm Tag"), "ÄT")
    }

    func testSplitLabelIsTheTextAfterTheLastDotPlusDay() {
        XCTAssertEqual(WidgetText.splitLabel(of: "Upper A · Push"), "Push day")
        XCTAssertEqual(WidgetText.splitLabel(of: "Upper · A · Pull "), "Pull day", "the last dot")
        XCTAssertEqual(WidgetText.splitLabel(of: "Full body"), "Full body", "without a dot it is the name")
        XCTAssertEqual(WidgetText.splitLabel(of: "Legs ·"), "Legs ·", "nothing after the dot: the name")
        XCTAssertEqual(WidgetText.splitLabel(of: "Legs ·   "), "Legs ·   ")
    }

    func testRowLabelIsTheTextAfterTheDotOrTheName() {
        XCTAssertEqual(WidgetText.rowLabel(of: "Lower A · Quads"), "Quads")
        XCTAssertEqual(WidgetText.rowLabel(of: "Cardio"), "Cardio")
    }

    func testShortNameIsTheNameUpToTheFirstSpaceDot() {
        XCTAssertEqual(WidgetText.shortName(of: "Lower A · Quads"), "Lower A")
        XCTAssertEqual(WidgetText.shortName(of: "A · B · C"), "A")
        XCTAssertEqual(WidgetText.shortName(of: "Cardio"), "Cardio")
        XCTAssertEqual(WidgetText.shortName(of: " · Odd"), " · Odd", "an empty start falls back to the name")
    }

    func testRoundingHelpers() {
        XCTAssertEqual(WidgetText.tenth(99.1666), 99.2)
        XCTAssertEqual(WidgetText.tenth(58.36), 58.4)
        XCTAssertEqual(WidgetText.tenth(58.34), 58.3)
        XCTAssertEqual(WidgetText.tenth(-3.2000000000000028), -3.2)
        XCTAssertEqual(WidgetText.hundredth(1.2399), 1.24)
        XCTAssertEqual(WidgetText.hundredth(1.2451), 1.25)
        XCTAssertEqual(WidgetText.hundredth(1.2449), 1.24)
        XCTAssertEqual(WidgetText.platesText([25, 5, 2.5]), "25 + 5 + 2.5")
        XCTAssertEqual(WidgetText.platesText([]), "")
    }
}
