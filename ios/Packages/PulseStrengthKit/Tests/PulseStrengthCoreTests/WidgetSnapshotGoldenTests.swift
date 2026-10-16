import Foundation
import XCTest
@testable import PulseStrengthCore

/// The snapshot of the demo data against `widgets/fixtures/golden-sample.json`, the file the Kotlin implementation is tested against
/// (widgets/SPEC.md section 2). It is the builder's output for `StrengthData.demo(now:)` at 2026-10-16T09:41:00Z in UTC with a weekly
/// goal of 4 and no body weight, so it holds no wall-clock value.
///
/// After a deliberate change of a rule, rewrite the file with
/// `UPDATE_GOLDEN=1 swift test --filter WidgetSnapshotGoldenTests` and commit it together with the Kotlin change.
final class WidgetSnapshotGoldenTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_792_143_660)   // 2026-10-16T09:41:00Z, a Friday

    private func demoSnapshot() -> WidgetSnapshot {
        WidgetSnapshotBuilder.build(data: StrengthData.demo(now: Self.now), context: WidgetContext(timeZoneID: "UTC"), now: Self.now)
    }

    /// `widgets/fixtures/golden-sample.json` of the repository this file is in.
    private func goldenURL() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            let fixtures = directory.appendingPathComponent("widgets/fixtures", isDirectory: true)
            if FileManager.default.fileExists(atPath: fixtures.path) {
                return fixtures.appendingPathComponent("golden-sample.json")
            }
            directory.deleteLastPathComponent()
        }
        throw XCTSkip("widgets/fixtures was not found above \(#filePath)")
    }

    /// Pretty-printed with sorted keys: the same encoder as the app's files, only laid out for reading and diffs.
    private func goldenText(_ snapshot: WidgetSnapshot) throws -> String {
        let encoder = StrengthJSON.makeEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(snapshot), as: UTF8.self) + "\n"
    }

    func testTheSnapshotOfTheDemoDataMatchesTheGoldenFile() throws {
        let data = StrengthData.demo(now: Self.now)
        XCTAssertNil(data.activePlan, "the golden file assumes the demo data has no training plan")
        XCTAssertTrue(data.bodyWeights.isEmpty, "the golden file assumes the demo data has no body weight")
        let snapshot = demoSnapshot()
        let url = try goldenURL()

        if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1" {
            try goldenText(snapshot).write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let stored = try XCTUnwrap(try? Data(contentsOf: url), "golden-sample.json is missing; write it with UPDATE_GOLDEN=1")
        let golden = try StrengthJSON.makeDecoder().decode(WidgetSnapshot.self, from: stored)
        XCTAssertEqual(golden, snapshot, "the builder no longer produces widgets/fixtures/golden-sample.json (UPDATE_GOLDEN=1 rewrites it)")
    }

    func testTheGoldenFileIsPrettyPrintedWithSortedKeys() throws {
        let stored = try String(contentsOf: try goldenURL(), encoding: .utf8)
        XCTAssertTrue(stored.hasPrefix("{\n"))
        XCTAssertTrue(stored.hasSuffix("}\n"))
        let keys = stored.split(separator: "\n").filter { $0.hasPrefix("  \"") }.compactMap { line -> String? in
            guard let end = line.dropFirst(3).firstIndex(of: "\"") else { return nil }
            return String(line[line.index(line.startIndex, offsetBy: 3)..<end])
        }
        XCTAssertEqual(keys, keys.sorted(), "the top level keys are sorted")
        XCTAssertTrue(keys.contains("week"))
    }

    func testBuildingTwiceGivesTheSameSnapshotAndTheSameText() throws {
        let first = demoSnapshot()
        let second = demoSnapshot()
        XCTAssertEqual(first, second)
        XCTAssertEqual(try goldenText(first), try goldenText(second))
    }

    func testNoValueOfTheGoldenFileComesFromTheWallClock() {
        let snapshot = demoSnapshot()
        XCTAssertEqual(snapshot.generatedAt, Self.now)
        XCTAssertEqual(snapshot.timeZoneID, "UTC")
        XCTAssertEqual(snapshot.week.goal, 4)
        XCTAssertNil(snapshot.strengthRatio?.bodyweightKg)
        XCTAssertNil(snapshot.readiness)
        XCTAssertTrue(snapshot.partners.isEmpty)
        XCTAssertNil(snapshot.active)
    }
}
