import Foundation
import XCTest
@testable import PulseStrengthCore

/// Dates in a fixed calendar, so the schedule maths does not depend on the machine's time zone.
private enum BW {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, calendar: Calendar = utc) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func on(_ interval: WeighInInterval = .weekly, hour: Int = 8, minute: Int = 0, enabledAt: Date? = nil) -> WeighInPreferences {
        WeighInPreferences(isEnabled: true, interval: interval, hour: hour, minute: minute, enabledAt: enabledAt)
    }
}

// MARK: - Rules

final class BodyWeightRulesTests: XCTestCase {
    func testNormalisedRoundsToOneDecimal() {
        XCTAssertEqual(BodyWeightRules.normalised(82.54), 82.5)
        XCTAssertEqual(BodyWeightRules.normalised(82.56), 82.6)
        XCTAssertEqual(BodyWeightRules.normalised(80), 80)
    }

    func testNormalisedRejectsImplausibleWeights() {
        XCTAssertNil(BodyWeightRules.normalised(.nan))
        XCTAssertNil(BodyWeightRules.normalised(.infinity))
        XCTAssertNil(BodyWeightRules.normalised(0))
        XCTAssertNil(BodyWeightRules.normalised(-70))
        XCTAssertNil(BodyWeightRules.normalised(19.9))
        XCTAssertNil(BodyWeightRules.normalised(500.1))
        XCTAssertEqual(BodyWeightRules.normalised(20), 20)
        XCTAssertEqual(BodyWeightRules.normalised(500), 500)
    }

    func testParseAcceptsBothDecimalSeparatorsAndAKilogramSuffix() {
        XCTAssertEqual(BodyWeightRules.parse("82.5"), 82.5)
        XCTAssertEqual(BodyWeightRules.parse("82,5"), 82.5)
        XCTAssertEqual(BodyWeightRules.parse("  82.5 kg "), 82.5)
        XCTAssertEqual(BodyWeightRules.parse("82KG"), 82)
        XCTAssertEqual(BodyWeightRules.parse("82."), 82)
        XCTAssertEqual(BodyWeightRules.parse("82.54"), 82.5)
    }

    func testParseRejectsEverythingElse() {
        for text in ["", " ", "kg", "abc", "82.5.1", "82,5,1", "1,234.5", "-80", "+80", "0x50", "inf", "nan", "8 2", "82 lb", "٨٢", "19", "501", "1e2"] {
            XCTAssertNil(BodyWeightRules.parse(text), "'\(text)' must not parse")
        }
    }
}

// MARK: - Preferences

final class WeighInPreferencesTests: XCTestCase {
    func testTheReminderIsOffByDefault() {
        let preferences = WeighInPreferences()
        XCTAssertFalse(preferences.isEnabled)
        XCTAssertEqual(preferences.interval, .weekly)
        XCTAssertEqual(preferences.hour, 8)
        XCTAssertEqual(preferences.minute, 0)
        XCTAssertNil(preferences.enabledAt)
    }

    func testTheTimeOfDayIsClamped() {
        let preferences = WeighInPreferences(hour: 31, minute: -4)
        XCTAssertEqual(preferences.hour, 23)
        XCTAssertEqual(preferences.minute, 0)
    }

    func testTurningOnRemembersWhenButStayingOnDoesNot() {
        var preferences = WeighInPreferences()
        let first = BW.date(2026, 10, 1, 9)
        preferences.setEnabled(true, now: first)
        XCTAssertTrue(preferences.isEnabled)
        XCTAssertEqual(preferences.enabledAt, first)

        preferences.setEnabled(true, now: BW.date(2026, 10, 5))
        XCTAssertEqual(preferences.enabledAt, first, "already on: the start does not move")

        preferences.setEnabled(false, now: BW.date(2026, 10, 6))
        XCTAssertFalse(preferences.isEnabled)

        let again = BW.date(2026, 10, 9, 9)
        preferences.setEnabled(true, now: again)
        XCTAssertEqual(preferences.enabledAt, again, "turned on again: a new start")
    }

    func testCodableRoundTrip() throws {
        let preferences = WeighInPreferences(isEnabled: true, interval: .monthly, hour: 7, minute: 45, enabledAt: BW.date(2026, 10, 1, 9))
        let data = try StrengthJSON.makeEncoder().encode(preferences)
        XCTAssertEqual(try StrengthJSON.makeDecoder().decode(WeighInPreferences.self, from: data), preferences)
    }

    func testAMissingKeyReadsAsItsDefault() throws {
        let data = Data(#"{"isEnabled":true,"interval":"everyTwoWeeks"}"#.utf8)
        let decoded = try StrengthJSON.makeDecoder().decode(WeighInPreferences.self, from: data)
        XCTAssertEqual(decoded, WeighInPreferences(isEnabled: true, interval: .everyTwoWeeks, hour: 8, minute: 0, enabledAt: nil))
    }
}

// MARK: - Schedule

final class WeighInScheduleTests: XCTestCase {
    private let calendar = BW.utc

    private func due(_ last: Date?, _ preferences: WeighInPreferences) -> Date? {
        WeighInSchedule.dueDate(lastWeighIn: last, preferences: preferences, calendar: calendar)
    }

    private func isDue(_ last: Date?, _ preferences: WeighInPreferences, _ now: Date) -> Bool {
        WeighInSchedule.isDue(lastWeighIn: last, preferences: preferences, now: now, calendar: calendar)
    }

    private func reminders(_ last: Date?, _ preferences: WeighInPreferences, _ now: Date, count: Int = 3) -> [Date] {
        WeighInSchedule.reminders(lastWeighIn: last, preferences: preferences, now: now, calendar: calendar, count: count)
    }

    func testNothingIsDueOrScheduledWhileTheReminderIsOff() {
        let off = WeighInPreferences(isEnabled: false)
        let last = BW.date(2026, 10, 1, 7)
        XCTAssertNil(due(last, off))
        XCTAssertFalse(isDue(last, off, BW.date(2027, 1, 1)))
        XCTAssertFalse(isDue(nil, off, BW.date(2027, 1, 1)))
        XCTAssertEqual(reminders(last, off, BW.date(2026, 10, 2)), [])
    }

    func testTheWeighInIsDueOneIntervalAfterTheLatestOneAtTheChosenTime() {
        let last = BW.date(2026, 10, 7, 22, 15)       // Wednesday evening
        XCTAssertEqual(due(last, BW.on(.weekly)), BW.date(2026, 10, 14, 8, 0))
        XCTAssertEqual(due(last, BW.on(.everyTwoWeeks, hour: 6, minute: 30)), BW.date(2026, 10, 21, 6, 30))
        XCTAssertEqual(due(last, BW.on(.monthly)), BW.date(2026, 11, 7, 8, 0))
    }

    func testIsDueFlipsAtTheDueDate() {
        let last = BW.date(2026, 10, 7, 7, 30)
        let preferences = BW.on(.weekly)
        XCTAssertFalse(isDue(last, preferences, BW.date(2026, 10, 14, 7, 59)))
        XCTAssertTrue(isDue(last, preferences, BW.date(2026, 10, 14, 8, 0)))
        XCTAssertTrue(isDue(last, preferences, BW.date(2026, 11, 30)))
    }

    func testWithoutAWeighInTheReminderIsDueRightAwayAndCountsFromWhenItWasTurnedOn() {
        let enabledAt = BW.date(2026, 10, 7, 12)
        let preferences = BW.on(.weekly, enabledAt: enabledAt)
        XCTAssertTrue(isDue(nil, preferences, enabledAt))
        XCTAssertEqual(due(nil, preferences), BW.date(2026, 10, 14, 8, 0))
        XCTAssertEqual(
            reminders(nil, preferences, enabledAt),
            [BW.date(2026, 10, 14, 8), BW.date(2026, 10, 21, 8), BW.date(2026, 10, 28, 8)]
        )
    }

    func testLoggingAWeightMovesTheNextReminderOut() {
        let preferences = BW.on(.weekly)
        let before = BW.date(2026, 10, 7, 7)
        let now = BW.date(2026, 10, 14, 9)            // the reminder of 14 October 8:00 has just passed
        XCTAssertTrue(isDue(before, preferences, now))
        XCTAssertEqual(reminders(before, preferences, now).first, BW.date(2026, 10, 21, 8))

        let after = now                               // the user weighs in now
        XCTAssertFalse(isDue(after, preferences, now))
        XCTAssertEqual(reminders(after, preferences, now).first, BW.date(2026, 10, 21, 8))
    }

    func testRemindersAreOnlyInTheFutureSoonestFirstAndAtMostThree() {
        let last = BW.date(2026, 10, 7, 7)
        let preferences = BW.on(.weekly)
        XCTAssertEqual(
            reminders(last, preferences, BW.date(2026, 10, 8)),
            [BW.date(2026, 10, 14, 8), BW.date(2026, 10, 21, 8), BW.date(2026, 10, 28, 8)]
        )
        XCTAssertEqual(reminders(last, preferences, BW.date(2026, 10, 8), count: 1), [BW.date(2026, 10, 14, 8)])
        XCTAssertEqual(reminders(last, preferences, BW.date(2026, 10, 8), count: 0), [])
        XCTAssertEqual(reminders(last, preferences, BW.date(2026, 10, 8), count: 50).count, WeighInSchedule.maximumReminders)
    }

    func testAnIgnoredReminderIsFollowedByTheNextOneAnIntervalLaterNotTheNextMorning() {
        let last = BW.date(2026, 10, 1, 7)
        let preferences = BW.on(.weekly)
        // Due on 8 October 8:00; the app is opened on the 10th without weighing in.
        XCTAssertEqual(
            reminders(last, preferences, BW.date(2026, 10, 10, 12)),
            [BW.date(2026, 10, 15, 8), BW.date(2026, 10, 22, 8), BW.date(2026, 10, 29, 8)]
        )
    }

    func testAVeryOldWeighInStillFindsTheNextReminders() {
        let last = BW.date(2020, 1, 1, 7)
        let now = BW.date(2026, 10, 10)
        let result = reminders(last, BW.on(.weekly), now)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy { $0 > now })
        XCTAssertTrue(result[0].timeIntervalSince(now) <= 7 * 86_400)
    }

    func testMonthEndDatesDoNotDriftForGood() {
        let last = BW.date(2025, 12, 31, 7)
        let result = reminders(last, BW.on(.monthly), BW.date(2026, 1, 5))
        // Counted from the due date (31 January), so March is the 31st again, not the 28th.
        XCTAssertEqual(result, [BW.date(2026, 1, 31, 8), BW.date(2026, 2, 28, 8), BW.date(2026, 3, 31, 8)])
    }

    func testWithoutAnyStartDateTheFirstReminderIsTheNextTimeOfDay() {
        let preferences = BW.on(.weekly, enabledAt: nil)
        XCTAssertNil(due(nil, preferences))
        XCTAssertTrue(isDue(nil, preferences, BW.date(2026, 10, 7)))
        let early = reminders(nil, preferences, BW.date(2026, 10, 7, 6))
        XCTAssertEqual(early, [BW.date(2026, 10, 7, 8), BW.date(2026, 10, 14, 8), BW.date(2026, 10, 21, 8)])
        let late = reminders(nil, preferences, BW.date(2026, 10, 7, 9))
        XCTAssertEqual(late.first, BW.date(2026, 10, 8, 8))
    }

    func testTheClockTimeSurvivesADaylightSavingChange() throws {
        guard let zone = TimeZone(identifier: "America/New_York") else { throw XCTSkip("no time zone data") }
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        // The US clocks went forward on Sunday 8 March 2026.
        let last = BW.date(2026, 3, 4, 7, 0, calendar: local)
        let result = WeighInSchedule.reminders(
            lastWeighIn: last, preferences: BW.on(.weekly), now: BW.date(2026, 3, 5, calendar: local), calendar: local
        )
        XCTAssertEqual(result.count, 3)
        for date in result {
            let parts = local.dateComponents([.hour, .minute], from: date)
            XCTAssertEqual(parts.hour, 8, "\(date)")
            XCTAssertEqual(parts.minute, 0)
        }
        XCTAssertEqual(local.dateComponents([.month, .day], from: result[0]).day, 11)
    }
}

// MARK: - Data and persistence

final class BodyWeightDataTests: XCTestCase {
    private func makePersistence() -> FileStrengthPersistence {
        let persistence = FileStrengthPersistence.temporary()
        let directory = persistence.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return persistence
    }

    func testRecordingKeepsTheNewestFirstAndRoundsTheWeight() {
        var data = StrengthData()
        XCTAssertNil(data.latestBodyWeight)
        let first = data.recordBodyWeight(kg: 82.44, date: BW.date(2026, 10, 1, 7))
        data.recordBodyWeight(kg: 81.9, date: BW.date(2026, 10, 15, 7))
        data.recordBodyWeight(kg: 82.0, date: BW.date(2026, 10, 8, 7))
        XCTAssertEqual(first?.kg, 82.4)
        XCTAssertEqual(data.bodyWeights.map { $0.kg }, [81.9, 82.0, 82.4])
        XCTAssertEqual(data.latestBodyWeight?.kg, 81.9)
    }

    func testTwoWeighInsAtTheSameInstantAreBothKeptNewestInsertedFirst() {
        var data = StrengthData()
        let when = BW.date(2026, 10, 1, 7)
        data.recordBodyWeight(kg: 80, date: when)
        data.recordBodyWeight(kg: 81, date: when)
        XCTAssertEqual(data.bodyWeights.map { $0.kg }, [81, 80])
    }

    func testAnImplausibleWeightIsRefusedAndChangesNothing() {
        var data = StrengthData()
        data.recordBodyWeight(kg: 80, date: BW.date(2026, 10, 1))
        let before = data
        XCTAssertNil(data.recordBodyWeight(kg: 0, date: BW.date(2026, 10, 2)))
        XCTAssertNil(data.recordBodyWeight(kg: .nan, date: BW.date(2026, 10, 2)))
        XCTAssertNil(data.recordBodyWeight(kg: 900, date: BW.date(2026, 10, 2)))
        XCTAssertEqual(data, before)
    }

    func testRecordingWithAnExistingIdReplacesTheEntry() {
        var data = StrengthData()
        let id = UUID()
        data.recordBodyWeight(kg: 80, date: BW.date(2026, 10, 1), id: id)
        data.recordBodyWeight(kg: 79.5, date: BW.date(2026, 10, 3), id: id)
        XCTAssertEqual(data.bodyWeights.count, 1)
        XCTAssertEqual(data.bodyWeights.first?.kg, 79.5)
        XCTAssertEqual(data.bodyWeights.first?.date, BW.date(2026, 10, 3))
    }

    func testDeleting() {
        var data = StrengthData()
        let entry = data.recordBodyWeight(kg: 80, date: BW.date(2026, 10, 1))!
        XCTAssertFalse(data.deleteBodyWeight(id: UUID()))
        XCTAssertEqual(data.bodyWeights.count, 1)
        XCTAssertTrue(data.deleteBodyWeight(id: entry.id))
        XCTAssertTrue(data.bodyWeights.isEmpty)
    }

    func testBodyWeightDoesNotCountAsTrainingDataForTheDemoSeed() {
        var data = StrengthData()
        data.recordBodyWeight(kg: 80, date: BW.date(2026, 10, 1))
        XCTAssertTrue(data.isEmpty)
        XCTAssertTrue(data.seedDemoDataIfEmpty(now: BW.date(2026, 10, 2)))
        XCTAssertEqual(data.bodyWeights.count, 1, "seeding leaves the weigh-ins alone")
    }

    func testIsWeighInDueUsesTheLatestEntryAndThePreferences() {
        var data = StrengthData()
        let calendar = BW.utc
        XCTAssertFalse(data.isWeighInDue(now: BW.date(2026, 10, 20), calendar: calendar), "off")
        data.weighIn = BW.on(.weekly, enabledAt: BW.date(2026, 10, 1))
        XCTAssertTrue(data.isWeighInDue(now: BW.date(2026, 10, 1), calendar: calendar), "on, nothing logged yet")
        data.recordBodyWeight(kg: 80, date: BW.date(2026, 10, 20, 7))
        XCTAssertFalse(data.isWeighInDue(now: BW.date(2026, 10, 21), calendar: calendar))
        XCTAssertTrue(data.isWeighInDue(now: BW.date(2026, 10, 27, 8), calendar: calendar))
    }

    func testPersistenceReadsAsEmptyAndOffBeforeAnythingWasSaved() {
        let persistence = makePersistence()
        XCTAssertEqual(persistence.loadBodyWeights(), [])
        XCTAssertEqual(persistence.loadWeighInPreferences(), WeighInPreferences())
    }

    func testPersistenceRoundTrip() throws {
        let persistence = makePersistence()
        let entries = [
            BodyWeightEntry(id: SvcSyncFix.uuid(2), date: BW.date(2026, 10, 8, 7), kg: 81.5),
            BodyWeightEntry(id: SvcSyncFix.uuid(1), date: BW.date(2026, 10, 1, 7), kg: 82.0)
        ]
        let preferences = WeighInPreferences(isEnabled: true, interval: .everyTwoWeeks, hour: 6, minute: 15, enabledAt: BW.date(2026, 10, 1))
        try persistence.saveBodyWeights(entries)
        try persistence.saveWeighInPreferences(preferences)
        XCTAssertEqual(persistence.loadBodyWeights(), entries)
        XCTAssertEqual(persistence.loadWeighInPreferences(), preferences)
    }

    func testCorruptFilesReadAsEmptyAndAnUnreadableEntryIsSkipped() throws {
        let persistence = makePersistence()
        try Data("not json".utf8).write(to: persistence.directory.appendingPathComponent("body-weights.json"))
        try Data("{".utf8).write(to: persistence.directory.appendingPathComponent("weigh-in-preferences.json"))
        XCTAssertEqual(persistence.loadBodyWeights(), [])
        XCTAssertEqual(persistence.loadWeighInPreferences(), WeighInPreferences())

        let good = BodyWeightEntry(id: SvcSyncFix.uuid(1), date: BW.date(2026, 10, 1), kg: 80)
        let goodJSON = String(decoding: try StrengthJSON.makeEncoder().encode(good), as: UTF8.self)
        try Data("[\(goodJSON),{\"kg\":\"heavy\"}]".utf8).write(to: persistence.directory.appendingPathComponent("body-weights.json"))
        XCTAssertEqual(persistence.loadBodyWeights(), [good])
    }

    func testTheModelSavesWhatItChangesAndANewModelSeesIt() {
        let persistence = makePersistence()
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            XCTAssertNil(model.recordBodyWeight(kg: 3, date: BW.date(2026, 10, 1)))
            XCTAssertEqual(persistence.loadBodyWeights(), [], "a refused weight is not written")

            let entry = model.recordBodyWeight(kg: 82.5, date: BW.date(2026, 10, 1, 7))
            XCTAssertEqual(persistence.loadBodyWeights(), entry.map { [$0] })

            var preferences = WeighInPreferences()
            preferences.setEnabled(true, now: BW.date(2026, 10, 1, 7))
            preferences.interval = .monthly
            model.setWeighInPreferences(preferences)
            XCTAssertEqual(persistence.loadWeighInPreferences(), preferences)
            XCTAssertNil(model.lastPersistenceError)
        }
        svcMain {
            let reopened = StrengthDataModel(persistence: persistence)
            XCTAssertEqual(reopened.data.latestBodyWeight?.kg, 82.5)
            XCTAssertEqual(reopened.data.weighIn.interval, .monthly)
            XCTAssertTrue(reopened.data.weighIn.isEnabled)

            let id = reopened.data.bodyWeights[0].id
            XCTAssertFalse(reopened.deleteBodyWeight(id: UUID()))
            XCTAssertTrue(reopened.deleteBodyWeight(id: id))
            XCTAssertEqual(persistence.loadBodyWeights(), [])
        }
    }

    func testRecordingAWorkoutLeavesTheBodyWeightAlone() {
        let persistence = makePersistence()
        svcMain {
            let model = StrengthDataModel(persistence: persistence)
            model.recordBodyWeight(kg: 82.5, date: BW.date(2026, 10, 1, 7))
            let workout = SvcDataFix.workout(1, finishedAt: BW.date(2026, 10, 2), [SvcDataFix.entry("bench", [SvcDataFix.work(100, 5)], n: 1)])
            model.record(workout, updateTemplate: nil)
            XCTAssertEqual(model.data.bodyWeights.count, 1)
            XCTAssertEqual(persistence.loadBodyWeights().count, 1)
        }
    }

#if canImport(Combine) || PULSE_COMBINE_SHIM
    func testTheStorePublishesWeighInsAndPreferences() {
        let persistence = makePersistence()
        svcMain {
            let store = StrengthStore(persistence: persistence)
            XCTAssertNil(store.latestBodyWeight)
            XCTAssertFalse(store.weighIn.isEnabled)

            store.recordBodyWeight(kg: 83, date: BW.date(2026, 10, 1, 7))
            store.recordBodyWeight(kg: 82.4, date: BW.date(2026, 10, 8, 7))
            XCTAssertEqual(store.bodyWeights.map { $0.kg }, [82.4, 83])
            XCTAssertEqual(store.latestBodyWeight?.kg, 82.4)

            var preferences = store.weighIn
            preferences.setEnabled(true, now: BW.date(2026, 10, 8, 7))
            store.setWeighInPreferences(preferences)
            XCTAssertTrue(store.weighIn.isEnabled)
            XCTAssertFalse(store.isWeighInDue(now: BW.date(2026, 10, 9), calendar: BW.utc))
            XCTAssertTrue(store.isWeighInDue(now: BW.date(2026, 10, 15, 8), calendar: BW.utc))

            XCTAssertTrue(store.deleteBodyWeight(id: store.bodyWeights[0].id))
            XCTAssertEqual(store.bodyWeights.map { $0.kg }, [83])

            let reopened = StrengthStore(persistence: persistence)
            XCTAssertEqual(reopened.bodyWeights.map { $0.kg }, [83])
            XCTAssertEqual(reopened.weighIn, store.weighIn)
        }
    }
#endif
}
