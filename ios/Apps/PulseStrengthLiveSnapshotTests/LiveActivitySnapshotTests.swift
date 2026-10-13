// LiveActivitySnapshotTests.swift
//
// Snapshot tests of the Lock Screen Live Activity and the Dynamic Island views of Pulse Strength.
//
// A Live Activity cannot be screenshotted on a CI runner, so these tests draw the SwiftUI views the widget uses
// (Apps/Shared/LiveActivity, compiled into this bundle as its own sources) with `ImageRenderer` at @3x and write one
// PNG per surface and scenario:
//
//   <SCREENSHOT_DIR>/live-<NN>-<surface>-<scenario>.png
//
// `SCREENSHOT_DIR` is read from the test process environment. xcodebuild forwards variables prefixed with
// `TEST_RUNNER_`, so CI sets `TEST_RUNNER_SCREENSHOT_DIR=/path`; without it the files go to NSTemporaryDirectory().
// Every PNG is also attached to the test result (lifetime keepAlways).
//
// By default the timer views are the static variants selected by `\.activityStaticNow` (see ActivityTheme.swift): the
// same text and ring at a fixed instant, so the images are identical on every run. The second class in this file draws
// a few views with the production system timer views to show what `ImageRenderer` makes of them.
//
// Limits of this approach, stated once: it shows layout, colours, fonts and text of the views. It does NOT show the
// system's real Lock Screen material, the real island animation, the real region layout of the Dynamic Island
// (approximated in LiveSnapshotHarness.swift) or the behaviour of the buttons (App Intents).

#if os(iOS)
import SwiftUI
import XCTest
import PulseStrengthCore

@MainActor
final class LiveActivitySnapshotTests: XCTestCase {

    // MARK: Lock Screen

    /// Every scenario on a dark gradient wallpaper (the card is the translucent activity tint over it).
    func testLockScreenOnDarkWallpaper() throws {
        let scenarios = LiveFixtures.all()
        let numbers = LiveNumbers(count: scenarios.count)
        for (index, scenario) in scenarios.enumerated() {
            try LiveOutput.save(
                LockScreenSnapshot(scenario: scenario, wallpaper: .dark),
                number: numbers.lock(index),
                name: "lock-" + scenario.slug,
                test: self
            )
        }
    }

    /// Contrast check: the same card over a bright wallpaper (the tint is only 78% opaque).
    func testLockScreenOnLightWallpaper() throws {
        let scenarios = LiveFixtures.all()
        let numbers = LiveNumbers(count: scenarios.count)
        let wanted: [(slug: String, extra: Int)] = [
            ("logging-weight", LiveExtra.lockLightLogging),
            ("resting", LiveExtra.lockLightResting),
        ]
        for item in wanted {
            guard let scenario = scenarios.first(where: { $0.slug == item.slug }) else {
                XCTFail("Missing scenario \(item.slug)")
                continue
            }
            try LiveOutput.save(
                LockScreenSnapshot(scenario: scenario, wallpaper: .light),
                number: numbers.extra(item.extra),
                name: "lock-" + scenario.slug + "-on-light-wallpaper",
                test: self
            )
        }
    }

    // MARK: Dynamic Island

    func testDynamicIslandCompact() throws {
        let scenarios = LiveFixtures.all()
        let numbers = LiveNumbers(count: scenarios.count)
        for (index, scenario) in scenarios.enumerated() {
            try LiveOutput.save(
                CompactSnapshot(scenario: scenario),
                number: numbers.compact(index),
                name: "island-compact-" + scenario.slug,
                test: self
            )
        }
        try LiveOutput.save(
            CompactSheetSnapshot(scenarios: scenarios),
            number: numbers.extra(LiveExtra.compactSheet),
            name: "island-compact-all-scenarios",
            test: self
        )
    }

    func testDynamicIslandMinimal() throws {
        let scenarios = LiveFixtures.all()
        let numbers = LiveNumbers(count: scenarios.count)
        for (index, scenario) in scenarios.enumerated() {
            try LiveOutput.save(
                MinimalSnapshot(scenario: scenario),
                number: numbers.minimal(index),
                name: "island-minimal-" + scenario.slug,
                test: self
            )
        }
        try LiveOutput.save(
            MinimalSheetSnapshot(scenarios: scenarios),
            number: numbers.extra(LiveExtra.minimalSheet),
            name: "island-minimal-all-scenarios",
            test: self
        )
    }

    func testDynamicIslandExpanded() throws {
        let scenarios = LiveFixtures.all()
        let numbers = LiveNumbers(count: scenarios.count)
        for (index, scenario) in scenarios.enumerated() {
            try LiveOutput.save(
                ExpandedSnapshot(scenario: scenario),
                number: numbers.expanded(index),
                name: "island-expanded-" + scenario.slug,
                test: self
            )
        }
    }

    // MARK: Fixtures and the static clock

    /// The fixtures really are the states they claim to be (so an image never silently shows the wrong phase).
    func testFixturesMatchIntendedPhases() throws {
        let scenarios = LiveFixtures.all()
        XCTAssertEqual(scenarios.count, 11)
        XCTAssertEqual(Set(scenarios.map { $0.slug }).count, scenarios.count, "slugs must be unique")

        for scenario in scenarios {
            let shown = scenario.snapshot.displayPhase(isStale: scenario.isStale, staticNow: scenario.now)
            XCTAssertEqual(shown, scenario.expectedDisplayPhase, "\(scenario.slug): phase the views draw")
        }

        func fixture(_ slug: String) throws -> LiveScenario {
            try XCTUnwrap(scenarios.first(where: { $0.slug == slug }), "missing scenario \(slug)")
        }

        let logging = try fixture("logging-weight").snapshot
        XCTAssertEqual(logging.phase, .logging)
        XCTAssertEqual(logging.setLabel, "Set 3 of 5")
        XCTAssertEqual(logging.weightText, "82.5")
        XCTAssertEqual(logging.repsText, "6")
        XCTAssertTrue(logging.showsWeight)
        XCTAssertEqual(logging.heartRate, 128)
        XCTAssertNotNil(logging.logSetIntent)

        let bodyweight = try fixture("logging-bodyweight").snapshot
        XCTAssertFalse(bodyweight.showsWeight)
        XCTAssertEqual(bodyweight.weightText, "BW")
        XCTAssertEqual(bodyweight.repsUnit, "reps")
        XCTAssertNil(bodyweight.heartRate)

        let duration = try fixture("logging-duration").snapshot
        XCTAssertFalse(duration.showsWeight)
        XCTAssertEqual(duration.repsUnit, "sec")

        let restingScenario = try fixture("resting")
        let resting = restingScenario.snapshot
        XCTAssertEqual(resting.phase, .resting)
        XCTAssertEqual(resting.restTotalSeconds, 150)
        XCTAssertEqual(resting.nextLine, "Next \u{00B7} Set 4 \u{00B7} 82.5 kg \u{00D7} 6")
        let restEnd = try XCTUnwrap(resting.restEndsAt)
        XCTAssertEqual(restEnd.timeIntervalSince(restingScenario.now), 72, accuracy: 0.001, "1:12 left")

        let stale = try fixture("rest-over-stale")
        XCTAssertEqual(stale.snapshot.phase, .resting, "the app's last snapshot still says resting")
        XCTAssertTrue(stale.isStale)

        let complete = try fixture("complete").snapshot
        XCTAssertEqual(complete.phase, .complete)
        XCTAssertEqual(complete.loggedSets, complete.totalSets)
        XCTAssertTrue(complete.progressLine.hasPrefix("20 of 20 sets"), complete.progressLine)

        let pausedLogging = try fixture("paused-logging").snapshot
        XCTAssertTrue(pausedLogging.isPaused)
        XCTAssertEqual(pausedLogging.elapsedWhenPaused, 1458)
        let pausedResting = try fixture("paused-resting").snapshot
        XCTAssertTrue(pausedResting.isPaused)
        XCTAssertEqual(pausedResting.restFrozenRemaining, 72)

        let longNames = try fixture("long-names-logging").snapshot
        XCTAssertEqual(longNames.setLabel, "Warm-up \u{00B7} Set 1 of 5")

        let longSession = try fixture("long-session-logging")
        XCTAssertEqual(longSession.now.timeIntervalSince(longSession.snapshot.activeStart), 4325, accuracy: 0.001)
    }

    /// `displayPhase(isStale:staticNow:)` follows the fixed clock and ignores the wall clock.
    func testStaticClockDrivesDisplayPhase() throws {
        let scenarios = LiveFixtures.all()
        let resting = try XCTUnwrap(scenarios.first(where: { $0.slug == "resting" }))
        let paused = try XCTUnwrap(scenarios.first(where: { $0.slug == "paused-resting" }))
        let end = try XCTUnwrap(resting.snapshot.restEndsAt)

        XCTAssertEqual(resting.snapshot.displayPhase(isStale: false, staticNow: end.addingTimeInterval(-10)), .resting)
        XCTAssertEqual(resting.snapshot.displayPhase(isStale: false, staticNow: end.addingTimeInterval(1)), .restOver)
        XCTAssertEqual(resting.snapshot.displayPhase(isStale: true, staticNow: end.addingTimeInterval(-10)), .restOver)
        XCTAssertEqual(paused.snapshot.displayPhase(isStale: true, staticNow: end.addingTimeInterval(500)), .resting,
                       "a paused rest never turns into rest over")
    }

    // MARK: Measurements

    /// Measures every view against the limits of the surfaces and writes `live-measurements.txt`.
    ///
    /// The numbers are findings, not pass/fail criteria: a violation means the system would cut or scale the view, which
    /// is exactly what a screenshot review is for. Set `TEST_RUNNER_STRICT_GEOMETRY=1` to turn violations into failures.
    func testGeometryAgainstSystemLimits() throws {
        let strict = ProcessInfo.processInfo.environment["STRICT_GEOMETRY"] == "1"
        var lines: [String] = [
            "Live Activity view sizes in points (ImageRenderer ideal size, static clock).",
            "Limits: Lock Screen card <= 160 tall; compact slot <= 52.33 x 36.67; minimal <= 45 x 36.67; expanded island <= 160 tall.",
            "Expanded side column beside the camera (assumed layout): " + LiveMeasurement.points(LiveMetrics.expandedSideColumn) + " pt.",
            "",
        ]
        var violations: [String] = []

        for scenario in LiveFixtures.all() {
            let measurement = LiveGeometry.measure(scenario)
            lines.append(scenario.slug + "  (" + scenario.title + ")")
            lines.append("  lock card          " + LiveMeasurement.describe(measurement.lockCard))
            lines.append("  compact leading    " + LiveMeasurement.describe(measurement.compactLeading))
            lines.append("  compact trailing   " + LiveMeasurement.describe(measurement.compactTrailing))
            lines.append("  minimal            " + LiveMeasurement.describe(measurement.minimal))
            lines.append("  expanded leading   " + LiveMeasurement.describe(measurement.expandedLeading))
            lines.append("  expanded trailing  " + LiveMeasurement.describe(measurement.expandedTrailing))
            lines.append("  expanded island    " + LiveMeasurement.describe(measurement.expandedTotal))
            for violation in measurement.violations {
                lines.append("  VIOLATION: " + violation)
                violations.append(scenario.slug + ": " + violation)
            }
            for note in measurement.notes {
                lines.append("  note: " + note)
            }
        }

        lines.append("")
        lines.append(violations.isEmpty ? "No violations." : "\(violations.count) violation(s).")
        let report = lines.joined(separator: "\n")
        try LiveOutput.saveText(report, fileName: "live-measurements.txt", test: self)
        print(report)

        if strict {
            XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
        }
    }
}

// MARK: - Production system timer views

/// Draws a few states with the PRODUCTION timer views (`Text(timerInterval:)`, `Text(_:style: .timer)`,
/// `ProgressView(timerInterval:)`) to document what `ImageRenderer` makes of them: they may come out as a snapshot of
/// "now", blank, or as a placeholder. Fixtures are relative to the real current time, so the rest is running when the
/// images are drawn. The class name sorts after `LiveActivitySnapshotTests`, so the main images are written first.
@MainActor
final class LiveActivitySystemTimerSnapshotTests: XCTestCase {

    func testProductionTimerViewsInImageRenderer() throws {
        let numbers = LiveNumbers(count: LiveFixtures.all().count)
        let scenarios = LiveFixtures.all(reference: Date()).map { $0.withSystemTimers() }
        guard let resting = scenarios.first(where: { $0.slug == "resting" }),
              let logging = scenarios.first(where: { $0.slug == "logging-weight" }) else {
            XCTFail("Missing scenarios")
            return
        }

        try LiveOutput.save(
            LockScreenSnapshot(scenario: resting),
            number: numbers.extra(LiveExtra.systemLockResting),
            name: "lock-resting-system-timers",
            test: self
        )
        try LiveOutput.save(
            LockScreenSnapshot(scenario: logging),
            number: numbers.extra(LiveExtra.systemLockLogging),
            name: "lock-logging-weight-system-timers",
            test: self
        )
        try LiveOutput.save(
            CompactSnapshot(scenario: resting),
            number: numbers.extra(LiveExtra.systemCompactResting),
            name: "island-compact-resting-system-timers",
            test: self
        )
        try LiveOutput.save(
            MinimalSnapshot(scenario: resting),
            number: numbers.extra(LiveExtra.systemMinimalResting),
            name: "island-minimal-resting-system-timers",
            test: self
        )
        try LiveOutput.save(
            ExpandedSnapshot(scenario: resting),
            number: numbers.extra(LiveExtra.systemExpandedResting),
            name: "island-expanded-resting-system-timers",
            test: self
        )
    }
}
#endif
