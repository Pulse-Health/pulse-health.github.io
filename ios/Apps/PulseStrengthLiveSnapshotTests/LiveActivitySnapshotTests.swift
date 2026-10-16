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
import PulseStrengthActivity
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

    // MARK: StandBy (bench mode)

    /// SB-02: the full-screen layout of StandBy.dc.html (`isFullscreen`) for the rest, the rest that is over, logging, a record and a
    /// finished set list. The 620 x 286 pt frame is the one of the mock-up; the real StandBy screen is larger.
    func testBenchModeStandBy() throws {
        let scenarios = LiveFixtures.all()
        let numbers = LiveNumbers(count: scenarios.count)
        let wanted: [(slug: String, extra: Int)] = [
            ("resting", LiveExtra.standbyResting),
            ("rest-over-stale", LiveExtra.standbyRestOver),
            ("logging-weight", LiveExtra.standbyLogging),
            ("record-resting", LiveExtra.standbyRecord),
            ("complete", LiveExtra.standbyComplete),
        ]
        for item in wanted {
            guard let scenario = scenarios.first(where: { $0.slug == item.slug }) else {
                XCTFail("Missing scenario \(item.slug)")
                continue
            }
            try LiveOutput.save(
                BenchSnapshot(scenario: scenario),
                number: numbers.extra(item.extra),
                name: "standby-" + scenario.slug,
                test: self
            )
        }
    }

    // MARK: Fixtures and the static clock

    /// The fixtures really are the states they claim to be (so an image never silently shows the wrong phase).
    func testFixturesMatchIntendedPhases() throws {
        let scenarios = LiveFixtures.all()
        XCTAssertEqual(scenarios.count, 21)
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
        XCTAssertFalse(complete.hasNoSets, "a workout with sets is complete, not empty")

        let empty = try fixture("empty-workout").snapshot
        XCTAssertEqual(empty.phase, .complete, "the builder has no pending set to target")
        XCTAssertEqual(empty.totalSets, 0)
        XCTAssertTrue(empty.hasNoSets, "no set: the views must not claim All sets logged")
        XCTAssertEqual(empty.emptyTitle, "No exercises yet")
        var exercisesWithoutSets = empty
        exercisesWithoutSets.exerciseCount = 2
        XCTAssertEqual(exercisesWithoutSets.emptyTitle, "No sets yet")

        let pausedLogging = try fixture("paused-logging").snapshot
        XCTAssertTrue(pausedLogging.isPaused)
        XCTAssertEqual(pausedLogging.elapsedWhenPaused, 1458)
        let pausedResting = try fixture("paused-resting").snapshot
        XCTAssertTrue(pausedResting.isPaused)
        XCTAssertEqual(pausedResting.restFrozenRemaining, 72)

        let longNames = try fixture("long-names-logging").snapshot
        XCTAssertEqual(longNames.setLabel, "Warm-up \u{00B7} Set 1 of 5")
        XCTAssertTrue(longNames.isWarmupLabel)
        XCTAssertEqual(longNames.setPositionLabel, "Set 1 of 5", "the island splits the warm-up prefix off")
        XCTAssertFalse(logging.isWarmupLabel)
        XCTAssertEqual(logging.setPositionLabel, "Set 3 of 5")

        let longSession = try fixture("long-session-logging")
        XCTAssertEqual(longSession.now.timeIntervalSince(longSession.snapshot.activeStart), 4325, accuracy: 0.001)
    }

    /// The live moments: each fixture carries the moment it claims, the Lock Screen card and the compact island follow the priorities
    /// of widgets/SPEC.md section 1 (record, then rest, then superset, then logging; finish above all on the Lock Screen), and the
    /// texts the views draw are the ones of LiveActivityNext.dc.html.
    func testLiveMomentFixturesAndPriorities() throws {
        let scenarios = LiveFixtures.all()
        func fixture(_ slug: String) throws -> LiveScenario {
            try XCTUnwrap(scenarios.first(where: { $0.slug == slug }), "missing scenario \(slug)")
        }
        func phase(_ scenario: LiveScenario) -> SnapshotPhase {
            scenario.snapshot.displayPhase(isStale: scenario.isStale, staticNow: scenario.now)
        }
        func layout(_ slug: String) throws -> LockScreenLayout {
            let scenario = try fixture(slug)
            return scenario.snapshot.lockLayout(phase: phase(scenario))
        }
        func compact(_ slug: String) throws -> IslandCompactMode {
            let scenario = try fixture(slug)
            return scenario.snapshot.compactMode(phase: phase(scenario))
        }

        // LA-01 / LA-07
        let record = try fixture("record-resting").snapshot
        let moment = try XCTUnwrap(record.moment)
        XCTAssertEqual(moment.workText, "85 \u{00D7} 5")
        XCTAssertEqual(moment.deltaText, "e1RM +4")
        XCTAssertEqual(record.phase, .resting)
        XCTAssertEqual(try layout("record-resting"), .moment)
        XCTAssertEqual(try compact("record-resting"), .record, "a record wins over the rest countdown")
        XCTAssertEqual(try fixture("record-logging").snapshot.phase, .logging)
        XCTAssertEqual(try layout("record-logging"), .moment)
        XCTAssertEqual(try compact("record-logging"), .record)

        // LA-02 / LA-09
        let superset = try XCTUnwrap(try fixture("superset-logging").snapshot.superset)
        XCTAssertEqual(superset.chipText, "Superset A \u{00B7} round 2/3")
        XCTAssertEqual(superset.members.map { $0.tag }, ["A1", "A2"])
        XCTAssertEqual(superset.members.map { $0.isDone }, [true, false])
        XCTAssertEqual(superset.members.map { $0.isCurrent }, [false, true])
        XCTAssertEqual(superset.compactTag, "A2")
        XCTAssertEqual(superset.compactRound, "2/3")
        XCTAssertEqual(try fixture("superset-logging").snapshot.logTitle, "Log A2")
        XCTAssertEqual(try fixture("superset-logging").snapshot.logSpokenTitle, "Log set A2")
        XCTAssertEqual(try layout("superset-logging"), .superset)
        XCTAssertEqual(try compact("superset-logging"), .superset)
        XCTAssertEqual(try fixture("logging-weight").snapshot.logTitle, "Log set")
        let supersetRest = try fixture("superset-resting").snapshot
        XCTAssertNotNil(supersetRest.superset)
        XCTAssertEqual(supersetRest.superset?.round, 3)
        XCTAssertEqual(supersetRest.superset?.compactTag, "A1")
        XCTAssertEqual(try compact("superset-resting"), .rest, "the rest countdown wins over the superset")
        XCTAssertEqual(try layout("superset-resting"), .standard)

        // LA-03
        let plates = try XCTUnwrap(try fixture("plates-logging").snapshot.plates)
        XCTAssertEqual(plates.displaySummary, "25 + 5 + 1.25")
        XCTAssertEqual(plates.caption, "per side")
        XCTAssertEqual(try layout("plates-logging"), .plates)
        XCTAssertEqual(try compact("plates-logging"), .logging)
        XCTAssertEqual(PlateBrief(perSide: [], summary: "").displaySummary, "Bar only")

        // LA-04
        let tipScenario = try fixture("coach-tip-resting")
        let tip = try XCTUnwrap(tipScenario.snapshot.coachTip)
        XCTAssertEqual(tip.bodyText, "Add 2.5 kg for set 4 to stay at 1\u{2013}2 RIR.")
        XCTAssertEqual(tip.targetSetID, tipScenario.snapshot.targetSetID, "the tip applies to the set the Log button logs")
        XCTAssertEqual(tip.targetExerciseID, tipScenario.snapshot.targetExerciseID)
        XCTAssertEqual(try layout("coach-tip-resting"), .coachTip)
        XCTAssertEqual(CoachTipBrief(text: "Coach: keep going", suggestedWeightText: "82.5 kg", keepWeightText: "Keep 80", targetSetID: UUID(), targetExerciseID: UUID()).bodyText, "keep going")

        // LA-05
        let finish = try XCTUnwrap(try fixture("finish").snapshot.finish)
        XCTAssertEqual(finish.title, "Upper A \u{00B7} Push done")
        XCTAssertEqual(finish.sets, 20)
        XCTAssertTrue(finish.savedToHealth)
        XCTAssertGreaterThanOrEqual(finish.personalRecordCount, 1)
        XCTAssertEqual(try layout("finish"), .finish, "the finish card wins over everything")
        XCTAssertEqual(try compact("finish"), .complete)

        // LA-08 / LA-10
        let dots = try XCTUnwrap(try fixture("dots-heart-rate").snapshot.setProgress)
        XCTAssertEqual(dots.done, 2)
        XCTAssertEqual(dots.total, 5)
        XCTAssertEqual(try fixture("dots-heart-rate").snapshot.heartRate, 142)
        XCTAssertEqual(try compact("dots-heart-rate"), .logging)
        XCTAssertEqual(ActivitySetDots.metrics(count: 4)?.size, 7)
        XCTAssertEqual(ActivitySetDots.metrics(count: 5)?.size, 6)
        XCTAssertEqual(ActivitySetDots.metrics(count: 8)?.size, 4)
        XCTAssertNil(ActivitySetDots.metrics(count: 9), "nine dots do not fit the compact slot: the text fallback")
        XCTAssertNil(ActivitySetDots.metrics(count: 0))

        // The phases without a moment keep their cards (a barbell logging state is left out: once the builder fills in the plates it
        // is the plate card).
        for slug in ["resting", "rest-over-stale", "complete", "empty-workout", "paused-resting"] {
            XCTAssertEqual(try layout(slug), .standard, slug)
        }

        // SB-02: "Next: set 4" over "82.5 kg × 6"
        let next = try fixture("resting").snapshot.benchNext
        XCTAssertEqual(next.title, "Next: set 4")
        XCTAssertEqual(next.detail, "82.5 kg \u{00D7} 6")
        XCTAssertEqual(try fixture("complete").snapshot.benchNext.title, "All sets logged")
        XCTAssertNil(try fixture("complete").snapshot.benchNext.detail)
    }

    /// ActivityKit takes 4 KB for the attributes and the content together: the longest content the app can build still fits after
    /// `ActivityContentFitting`, and ordinary content is not touched.
    func testWorstCaseContentFitsActivityKitLimit() throws {
        let now = LiveFixtures.referenceDate
        let longName = String(repeating: "\u{1F600}", count: 100)
        var snapshot = try XCTUnwrap(LiveFixtures.all().first(where: { $0.slug == "logging-weight" })).snapshot
        snapshot.workoutName = longName
        snapshot.exerciseName = longName
        snapshot.nextExerciseName = longName
        snapshot.moment = PRMoment(
            exerciseName: longName, weightText: "1000000.55", repsText: "999", estimated1RM: 1_000_000, deltaKg: 100_000,
            expiresAt: now.addingTimeInterval(4)
        )
        snapshot.superset = SupersetBrief(label: "ZZZZZZZZ", round: 12, rounds: 12, members: (0..<10).map { index in
            SupersetMember(tag: "A\(index + 1)", name: longName, detail: "1000000.55 \u{00D7} 999 \u{00D7} 999 \u{00D7} 999", isDone: index < 2, isCurrent: index == 5)
        })
        snapshot.plates = PlateBrief(
            totalKg: 100_000, barKg: 20, perSide: Array(repeating: 25.0, count: 2000), leftoverKg: 1.25,
            summary: Array(repeating: "25", count: 2000).joined(separator: " + ")
        )
        snapshot.coachTip = CoachTipBrief(
            title: longName, subtitle: longName, text: longName, suggestedWeightKg: 1_000_000.55, suggestedWeightText: longName,
            keepWeightText: longName, targetSetID: UUID(), targetExerciseID: UUID()
        )
        let fitted = ActivityContentFitting.fitting(snapshot)
        let attributes = WorkoutActivityAttributes(workoutID: UUID(), workoutName: ActivityContentFitting.clamped(longName))
        let stateBytes = try JSONEncoder().encode(fitted).count
        let attributeBytes = try JSONEncoder().encode(attributes).count
        XCTAssertLessThanOrEqual(stateBytes, ActivityContentFitting.maximumStateBytes)
        XCTAssertLessThan(stateBytes + attributeBytes, 4096, "attributes and content state together")
        XCTAssertLessThanOrEqual(fitted.superset?.members.count ?? 0, ActivityContentFitting.maximumSupersetMembers)

        var finish = snapshot
        finish.finish = FinishBrief(workoutName: longName, durationMinutes: 99_999, sets: 99_999, volumeText: "9,999,999", personalRecordCount: 99, savedToHealth: true)
        XCTAssertLessThan(try JSONEncoder().encode(ActivityContentFitting.fitting(finish)).count + attributeBytes, 4096)

        for scenario in LiveFixtures.all() {
            XCTAssertEqual(ActivityContentFitting.fitting(scenario.snapshot), scenario.snapshot, "\(scenario.slug) is ordinary content")
        }
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
