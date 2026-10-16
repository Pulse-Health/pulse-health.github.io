// PlannedSessionSnapshots.swift
//
// Snapshot tests of the pre-workout countdown (widgets/SPEC.md LA-06, PlannedSessionActivity): the Lock Screen card, the compact
// and minimal Dynamic Island and the expanded island for a session planned 25 minutes ahead, one that is due (the system marked the
// content stale at the start time), one hours ahead (the countdown shows hours) and one with long names. They are drawn with the
// same approximations as the workout activity (LiveSnapshotHarness.swift) and a static clock, so the images are reproducible:
//
//   <SCREENSHOT_DIR>/live-<NN>-planned-<surface>-<scenario>.png

#if os(iOS)
import SwiftUI
import XCTest
import PulseStrengthActivity
import PulseStrengthCore

// MARK: - Fixtures

/// One planned session to draw on every surface.
struct PlannedScenario: Identifiable {
    let slug: String
    let title: String
    let attributes: PlannedSessionAttributes
    let state: PlannedSessionAttributes.ContentState
    /// `ActivityViewContext.isStale`.
    let isStale: Bool
    /// The instant the views are drawn at (`\.activityStaticNow`).
    let now: Date

    var id: String { slug }
}

@MainActor
enum PlannedFixtures {
    /// The instant everything is drawn at.
    static var now: Date { LiveFixtures.referenceDate }

    private static let templateID = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1") ?? UUID()

    static func all() -> [PlannedScenario] {
        let attributes = PlannedSessionAttributes(templateID: templateID)
        let squat = PlannedSessionAttributes.ContentState(
            templateName: "Lower A \u{00B7} Quads",
            startsAt: now.addingTimeInterval(25 * 60),
            firstExerciseName: "Squat",
            firstSetText: "4 \u{00D7} 5 at 100 kg"
        )
        var due = squat
        due.startsAt = now.addingTimeInterval(-30)
        var hours = squat
        hours.startsAt = now.addingTimeInterval(2 * 3600 + 5 * 60)
        let long = PlannedSessionAttributes.ContentState(
            templateName: "Lower A \u{00B7} Quads \u{2014} heavy week 6 of the long program",
            startsAt: now.addingTimeInterval(25 * 60),
            firstExerciseName: "Single-arm dumbbell Romanian deadlift, 3-1-1 tempo",
            firstSetText: "4 \u{00D7} 5 at 100 kg"
        )
        return [
            PlannedScenario(slug: "in-25-min", title: "Planned 25 minutes ahead", attributes: attributes, state: squat, isStale: false, now: now),
            PlannedScenario(slug: "due", title: "Start time has come (stale content)", attributes: attributes, state: due, isStale: true, now: now),
            PlannedScenario(slug: "in-2-hours", title: "Planned 2 h 5 min ahead (hours clock)", attributes: attributes, state: hours, isStale: false, now: now),
            PlannedScenario(slug: "long-names", title: "Long template and exercise names", attributes: attributes, state: long, isStale: false, now: now),
        ]
    }
}

// MARK: - Surfaces

/// The Lock Screen card, 359 pt wide over the activity tint, as tall as its content.
struct PlannedLockCard: View {
    let scenario: PlannedScenario

    var body: some View {
        PlannedSessionLockScreenView(attributes: scenario.attributes, state: scenario.state, isStale: scenario.isStale)
            .frame(width: LiveMetrics.lockScreenWidth)
            .background(ActivityTheme.lockBackground)
            .clipShape(RoundedRectangle(cornerRadius: LiveMetrics.lockScreenCornerRadius, style: .continuous))
            .activityStaticClock(scenario.now)
    }
}

struct PlannedLockSnapshot: View {
    let scenario: PlannedScenario

    var body: some View {
        LiveCanvas(
            caption: "lock screen \u{00B7} planned session \u{00B7} " + scenario.title,
            width: LiveMetrics.lockScreenWidth + 2 * LiveMetrics.canvasPadding
        ) {
            PlannedLockCard(scenario: scenario)
        }
    }
}

/// The compact island: the clock in the leading slot, the countdown in the trailing slot (52.33 x 36.67 pt each).
struct PlannedCompactPill: View {
    let scenario: PlannedScenario

    var body: some View {
        HStack(spacing: 0) {
            PlannedClockGlyph(size: 16)
                .frame(width: LiveMetrics.compactSlotWidth, height: LiveMetrics.islandHeight)
            SensorHint()
            PlannedCountdownText(
                startsAt: scenario.state.startsAt,
                isStale: scenario.isStale,
                size: 14,
                weight: .semibold,
                color: ActivityTheme.accent,
                maximumWidth: ActivityTheme.Metrics.compactSlotWidth
            )
            .frame(width: LiveMetrics.compactSlotWidth, height: LiveMetrics.islandHeight)
        }
        .frame(width: LiveMetrics.compactIslandWidth, height: LiveMetrics.islandHeight)
        .background(Color.black, in: Capsule())
        .activityStaticClock(scenario.now)
    }
}

struct PlannedMinimalCircle: View {
    var body: some View {
        PlannedClockGlyph(size: 15)
            .frame(width: LiveMetrics.minimalDiameter, height: LiveMetrics.minimalDiameter)
            .background(Color.black, in: Circle())
    }
}

/// The expanded island with the regions `PlannedSessionActivity` declares.
struct PlannedExpandedIsland: View {
    let scenario: PlannedScenario

    var body: some View {
        ExpandedIslandFrame(
            leading: {
                PlannedIslandLeading(state: scenario.state, isStale: scenario.isStale)
            },
            trailing: {
                PlannedCountdownText(
                    startsAt: scenario.state.startsAt,
                    isStale: scenario.isStale,
                    size: 28,
                    weight: .bold,
                    color: ActivityTheme.accent,
                    maximumWidth: 110
                )
            },
            bottom: {
                PlannedIslandBottom(attributes: scenario.attributes, state: scenario.state)
            }
        )
        .activityStaticClock(scenario.now)
    }
}

// MARK: - Tests

@MainActor
final class PlannedSessionSnapshotTests: XCTestCase {

    /// Every scenario on the Lock Screen, then the compact and minimal island of all of them on one image each, then the expanded
    /// island of the first and the one that is due.
    func testPlannedSessionSurfaces() throws {
        let scenarios = PlannedFixtures.all()
        let numbers = LiveNumbers(count: LiveFixtures.all().count)
        var index = LiveExtra.plannedBase
        for scenario in scenarios {
            try LiveOutput.save(
                PlannedLockSnapshot(scenario: scenario),
                number: numbers.extra(index),
                name: "planned-lock-" + scenario.slug,
                test: self
            )
            index += 1
        }
        try LiveOutput.save(
            LiveCanvas(caption: "dynamic island compact \u{00B7} planned session \u{00B7} all scenarios", width: 320) {
                VStack(spacing: 10) {
                    ForEach(scenarios) { scenario in
                        VStack(spacing: 3) {
                            Text(scenario.slug)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.75))
                            PlannedCompactPill(scenario: scenario)
                        }
                    }
                }
            },
            number: numbers.extra(index),
            name: "planned-island-compact-all-scenarios",
            test: self
        )
        index += 1
        try LiveOutput.save(
            LiveCanvas(caption: "dynamic island minimal \u{00B7} planned session (37 pt circle)", width: 300) {
                PlannedMinimalCircle()
            },
            number: numbers.extra(index),
            name: "planned-island-minimal",
            test: self
        )
        index += 1
        for scenario in [scenarios[0], scenarios[1], scenarios[3]] {
            try LiveOutput.save(
                LiveCanvas(
                    caption: "dynamic island expanded \u{00B7} planned session \u{00B7} " + scenario.title,
                    width: LiveMetrics.expandedWidth + 2 * LiveMetrics.canvasPadding
                ) {
                    PlannedExpandedIsland(scenario: scenario)
                },
                number: numbers.extra(index),
                name: "planned-island-expanded-" + scenario.slug,
                test: self
            )
            index += 1
        }
    }

    /// The card is within the 160 pt of the Lock Screen and the expanded island within its 160 pt; the compact countdown fits its slot.
    /// Findings, as in `testGeometryAgainstSystemLimits`; set `TEST_RUNNER_STRICT_GEOMETRY=1` to turn them into failures.
    func testPlannedSessionGeometry() throws {
        let strict = ProcessInfo.processInfo.environment["STRICT_GEOMETRY"] == "1"
        var lines = ["Pre-workout countdown view sizes in points (ImageRenderer ideal size, static clock).", ""]
        var violations: [String] = []
        for scenario in PlannedFixtures.all() {
            let card = LiveOutput.idealSize(of: PlannedLockCard(scenario: scenario))
            let expanded = LiveOutput.idealSize(of: PlannedExpandedIsland(scenario: scenario))
            let trailing = LiveOutput.idealSize(
                of: PlannedCountdownText(
                    startsAt: scenario.state.startsAt,
                    isStale: scenario.isStale,
                    size: 14,
                    weight: .semibold,
                    color: ActivityTheme.accent,
                    maximumWidth: ActivityTheme.Metrics.compactSlotWidth
                )
                .activityStaticClock(scenario.now)
            )
            lines.append(scenario.slug + "  (" + scenario.title + ")")
            lines.append("  lock card          " + LiveMeasurement.describe(card))
            lines.append("  compact trailing   " + LiveMeasurement.describe(trailing))
            lines.append("  expanded island    " + LiveMeasurement.describe(expanded))
            if let height = card?.height, height > LiveMetrics.lockScreenMaxHeight + 0.5 {
                violations.append(scenario.slug + ": lock card " + LiveMeasurement.points(height) + " pt tall")
            }
            if let height = expanded?.height, height > LiveMetrics.expandedMaxHeight + 0.5 {
                violations.append(scenario.slug + ": expanded island " + LiveMeasurement.points(height) + " pt tall")
            }
            if let width = trailing?.width, width > LiveMetrics.compactSlotWidth + 0.5 {
                violations.append(scenario.slug + ": compact trailing " + LiveMeasurement.points(width) + " pt wide")
            }
        }
        lines.append("")
        lines.append(violations.isEmpty ? "No violations." : violations.map { "VIOLATION: " + $0 }.joined(separator: "\n"))
        let report = lines.joined(separator: "\n")
        try LiveOutput.saveText(report, fileName: "live-planned-measurements.txt", test: self)
        print(report)
        if strict {
            XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
        }
    }

    /// The words of the card: the first-set line, the plan from a template, and the shared rules of `PlannedSessionPlan`.
    func testPlannedSessionTexts() throws {
        let scenarios = PlannedFixtures.all()
        XCTAssertEqual(scenarios[0].state.firstLine, "Squat first: 4 \u{00D7} 5 at 100 kg")
        var bare = scenarios[0].state
        bare.firstSetText = ""
        XCTAssertEqual(bare.firstLine, "Squat first")
        bare.firstExerciseName = ""
        XCTAssertNil(bare.firstLine, "a template without an exercise has no first set")

        let squat = Exercise.custom(name: "Squat", muscle: .legs, equipment: .barbell, tracking: .weightReps)
        let entry = TemplateEntry(
            exercise: squat,
            plannedSets: [
                PlannedSet(type: .warmup, weightKg: 60, reps: 8),
                PlannedSet(weightKg: 100, reps: 5), PlannedSet(weightKg: 100, reps: 5),
                PlannedSet(weightKg: 100, reps: 5), PlannedSet(weightKg: 100, reps: 5),
            ],
            restSeconds: 150
        )
        XCTAssertEqual(PlannedSessionPlan.setText(for: entry), "4 \u{00D7} 5 at 100 kg", "warm-ups are not counted")
        let template = WorkoutTemplate(name: "Lower A \u{00B7} Quads", entries: [entry])
        let plan = PlannedSessionPlan(template: template, startsAt: PlannedFixtures.now)
        XCTAssertEqual(plan.templateID, template.id)
        XCTAssertEqual(plan.state.firstLine, "Squat first: 4 \u{00D7} 5 at 100 kg")
        XCTAssertEqual(plan.moved(to: PlannedFixtures.now.addingTimeInterval(600)).startsAt, PlannedFixtures.now.addingTimeInterval(600))
        let decoded = try JSONDecoder().decode(PlannedSessionPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(decoded, plan, "the plan survives the UserDefaults round trip")
        XCTAssertNil(PlannedSessionPlan(template: WorkoutTemplate(name: "Empty", entries: []), startsAt: PlannedFixtures.now).state.firstLine)
    }
}
#endif
