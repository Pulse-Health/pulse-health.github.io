import XCTest
@testable import PulseStrengthCore

/// The shape of the widget data contract (widgets/tools/schema.py): the preview decodes, survives a round trip, and an
/// older Live Activity payload without the new optional fields still decodes.
final class WidgetSnapshotContractTests: XCTestCase {
    func testPreviewDecodesAndHasEveryHomeScreenSection() {
        let preview = WidgetSnapshot.preview
        XCTAssertEqual(preview.schemaVersion, WidgetSnapshot.currentSchemaVersion)
        XCTAssertEqual(preview.week.days.count, 7)
        XCTAssertEqual(preview.week.completed, 3)
        XCTAssertEqual(preview.week.goal, 4)
        XCTAssertEqual(preview.nextUp?.name, "Upper A · Push")
        XCTAssertEqual(preview.nextUp?.exercises.count, 6)
        XCTAssertEqual(preview.templates.count, 3)
        XCTAssertEqual(preview.freshness.count, MuscleGroup.allCases.count)
        XCTAssertEqual(preview.weeklySets.muscles.count, MuscleGroup.allCases.count)
        XCTAssertEqual(preview.month.days.count, 31)
        XCTAssertEqual(preview.year.monthlyTonnes.count, 12)
        XCTAssertEqual(preview.bodyMap.levels.count, MuscleGroup.allCases.count)
        XCTAssertNil(preview.active)
    }

    func testPreviewRoundTripsThroughTheStoreEncoding() throws {
        let preview = WidgetSnapshot.preview
        let data = try StrengthJSON.makeEncoder().encode(preview)
        let decoded = try StrengthJSON.makeDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, preview)
    }

    func testOlderLiveActivityPayloadWithoutMomentsDecodes() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let state = WorkoutFactory.makeWorkout(from: SampleData.templates(now: now)[0], now: now)
        var snapshot = SnapshotBuilder.make(from: state, now: now)
        snapshot.exerciseDoneSets = nil
        let data = try StrengthJSON.makeEncoder().encode(snapshot)
        // Remove the keys a build without moments never wrote.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["exerciseDoneSets", "exerciseSetCount", "moment", "superset", "plates", "coachTip", "finish"] {
            object.removeValue(forKey: key)
        }
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try StrengthJSON.makeDecoder().decode(WorkoutSnapshot.self, from: legacy)
        XCTAssertNil(decoded.moment)
        XCTAssertNil(decoded.finish)
        XCTAssertEqual(decoded.workoutID, snapshot.workoutID)
    }

    func testMomentsRoundTripInsideTheSnapshot() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let state = WorkoutFactory.makeWorkout(from: SampleData.templates(now: now)[0], now: now)
        var snapshot = SnapshotBuilder.make(from: state, now: now)
        snapshot.moment = PRMoment(exerciseName: "Bench Press", weightText: "85", repsText: "5", estimated1RM: 99, deltaKg: 4, expiresAt: now.addingTimeInterval(4))
        snapshot.plates = PlateBrief(totalKg: 85, barKg: 20, perSide: [20, 10, 2.5], leftoverKg: 0, summary: "20 + 10 + 2.5")
        let data = try StrengthJSON.makeEncoder().encode(snapshot)
        let decoded = try StrengthJSON.makeDecoder().decode(WorkoutSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }
}
