import XCTest
@testable import PulseStrengthCore

final class WidgetStoreTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WidgetStore-" + UUID().uuidString, isDirectory: true)
    }

    func testSnapshotSavesAndLoadsAndRejectsANewerSchema() throws {
        let directory = temporaryDirectory()
        XCTAssertNil(WidgetSnapshotStore.load(directory: directory))
        try WidgetSnapshotStore.save(WidgetSnapshot.preview, directory: directory)
        XCTAssertEqual(WidgetSnapshotStore.load(directory: directory), WidgetSnapshot.preview)

        var newer = WidgetSnapshot.preview
        newer.schemaVersion = WidgetSnapshot.currentSchemaVersion + 1
        try WidgetSnapshotStore.save(newer, directory: directory)
        XCTAssertNil(WidgetSnapshotStore.load(directory: directory))
    }

    func testInboxKeepsOrderDrainsOnceAndDropsOldCommands() throws {
        let inbox = WidgetCommandInbox(directory: temporaryDirectory())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try inbox.append(PendingWidgetCommand(action: .skipRest, issuedAt: now.addingTimeInterval(-700)))
        try inbox.append(PendingWidgetCommand(action: .logNextSet, issuedAt: now.addingTimeInterval(-5)))
        try inbox.append(PendingWidgetCommand(action: .adjustRest(seconds: 30), issuedAt: now.addingTimeInterval(-1)))
        XCTAssertEqual(inbox.peek().count, 3)
        let drained = try inbox.drain(now: now)
        XCTAssertEqual(drained.map { $0.action }, [.logNextSet, .adjustRest(seconds: 30)])
        XCTAssertTrue(try inbox.drain(now: now).isEmpty)
    }

    func testInboxCarriesDeepLinks() throws {
        let inbox = WidgetCommandInbox(directory: temporaryDirectory())
        let id = UUID()
        try inbox.append(PendingWidgetCommand(deepLink: .start(templateID: id)))
        let drained = try inbox.drain()
        XCTAssertEqual(drained.count, 1)
        XCTAssertNil(drained[0].action)
        XCTAssertEqual(drained[0].link, .start(templateID: id))
    }

    func testInboxCapsItsSize() throws {
        let inbox = WidgetCommandInbox(directory: temporaryDirectory())
        let now = Date()
        for index in 0..<(WidgetCommandInbox.capacity + 10) {
            try inbox.append(PendingWidgetCommand(action: .adjustRest(seconds: index), issuedAt: now))
        }
        let drained = try inbox.drain(now: now)
        XCTAssertEqual(drained.count, WidgetCommandInbox.capacity)
        XCTAssertEqual(drained.last?.action, .adjustRest(seconds: WidgetCommandInbox.capacity + 9))
    }

    func testContextClampsTheGoalAndBuildsAMondayFirstCalendar() {
        XCTAssertEqual(WidgetContext(weeklyGoal: 0).weeklyGoal, 1)
        XCTAssertEqual(WidgetContext(weeklyGoal: 12).weeklyGoal, 7)
        let context = WidgetContext(timeZoneID: "UTC")
        XCTAssertEqual(context.calendar.firstWeekday, 2)
        let saturday = Date(timeIntervalSince1970: 1_792_230_060) // 2026-10-17T09:41:00Z
        XCTAssertEqual(context.calendar.dateInterval(of: .weekOfYear, for: saturday)?.start, Date(timeIntervalSince1970: 1_791_763_200)) // Monday 12 Oct
    }

    func testEmptySnapshotHasAnEmptyWeek() {
        let snapshot = WidgetSnapshot.empty(now: Date(timeIntervalSince1970: 1_792_230_060), context: WidgetContext(timeZoneID: "UTC"))
        XCTAssertNil(snapshot.nextUp)
        XCTAssertEqual(snapshot.week.goal, 4)
    }
}
