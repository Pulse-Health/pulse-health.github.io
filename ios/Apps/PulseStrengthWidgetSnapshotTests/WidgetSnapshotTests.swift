// WidgetSnapshotTests.swift
//
// Snapshot tests of the Home Screen, StandBy, Lock Screen and extra widgets of widgets/SPEC.md (the Apple Watch widgets have their own bundle,
// PulseStrengthWatchWidgetSnapshotTests). Each test draws the views of one area with `ImageRenderer` and writes one PNG per widget, data
// variant and appearance:
//
//   <SCREENSHOT_DIR>/widget-<id>-<name>-<variant>-<light|dark>.png
//
// `SCREENSHOT_DIR` is read from the test process environment; xcodebuild forwards variables prefixed with `TEST_RUNNER_`, so CI sets
// `TEST_RUNNER_SCREENSHOT_DIR=/path`. Every PNG is also attached to the test result.
//
// What the images show: layout, colours, fonts and text of the views for the idealised preview snapshot and for the empty state. They do NOT
// show the system's widget background, the Lock Screen material, the StandBy night tint, the timeline behaviour or the buttons (App Intents).

#if os(iOS)
import SwiftUI
import WidgetKit
import XCTest
import PulseStrengthCore

@MainActor
final class WidgetSnapshotTests: XCTestCase {

    // MARK: Home Screen and StandBy

    func testHomeScreenWidgets() throws {
        let small = WidgetMetrics.small
        let medium = WidgetMetrics.medium
        let large = WidgetMetrics.large
        let standBy = HomeSurface(showsContainerBackground: false)
        let night = HomeSurface(showsContainerBackground: false, isLuminanceReduced: true)

        let shots: [WidgetShot] = [
            WidgetShot("HS-01", "next-up-small", size: small) { AnyView(NextUpLayout(entry: $0, surface: HomeSurface())) },
            WidgetShot("HS-07", "next-up-medium", size: medium) { AnyView(NextUpLayout(entry: $0, surface: HomeSurface(family: .systemMedium))) },
            WidgetShot("SB-01", "stand-by-next-up", size: small, backdrop: .black) { AnyView(NextUpLayout(entry: $0, surface: standBy)) },
            WidgetShot("SB-01", "stand-by-weekly-goal", size: small, backdrop: .black) { AnyView(WeeklyGoalLayout(entry: $0, surface: standBy)) },
            WidgetShot("SB-04", "night-next-up", size: small, backdrop: .black) { AnyView(NextUpLayout(entry: $0, surface: night)) },
            WidgetShot("SB-04", "night-weekly-goal", size: small, backdrop: .black) { AnyView(WeeklyGoalLayout(entry: $0, surface: night)) },
            WidgetShot("HS-02", "weekly-goal", size: small) { AnyView(WeeklyGoalLayout(entry: $0, surface: HomeSurface())) },
            WidgetShot("HS-06", "weekly-goal-tinted", size: small) { AnyView(WeeklyGoalLayout(entry: $0, surface: HomeSurface(renderingMode: .accented))) },
            WidgetShot("HS-03", "pr-spotlight", size: small, backdrop: .gold) { AnyView(PRSpotlightView(entry: $0)) },
            WidgetShot("HS-04", "muscle-freshness", size: small) { AnyView(MuscleFreshnessView(entry: $0)) },
            WidgetShot("HS-05", "beat-last-time", size: small, backdrop: .darkCard) { AnyView(OverloadView(entry: $0)) },
            WidgetShot("HS-08", "weekly-sets", size: medium) { AnyView(WeeklySetsView(entry: $0)) },
            WidgetShot("HS-09", "lift-trend", size: medium) {
                AnyView(LiftTrendView(entry: LiftTrendEntry(date: $0.date, snapshot: $0.snapshot, liftID: nil)))
            },
            WidgetShot("HS-10", "training-week", size: large) { AnyView(TrainingWeekView(entry: $0)) },
            WidgetShot("HS-11", "template-launcher", size: large) { AnyView(TemplateLauncherView(entry: $0)) },
            WidgetShot("HS-12", "month-heatmap", size: large) { AnyView(MonthHeatmapView(entry: $0)) },
            WidgetShot("SB-03", "training-block", size: WidgetMetrics.extraLarge) { AnyView(TrainingBlockView(entry: $0)) },
        ]
        try renderWidgetShots(shots, test: self)
    }

    // MARK: Lock Screen

    func testLockScreenAccessories() throws {
        let circular = WidgetMetrics.circular
        let rectangular = WidgetMetrics.rectangular
        let inline = WidgetMetrics.inline

        let shots: [WidgetShot] = [
            WidgetShot("LS-01", "weekly-goal-gauge", size: circular, backdrop: .accessory(.accessoryCircular)) {
                AnyView(WeeklyGoalAccessoryView(entry: $0, familyOverride: .accessoryCircular))
            },
            WidgetShot("LS-09", "weekly-goal-inline", size: inline, backdrop: .accessory(.accessoryInline)) {
                AnyView(WeeklyGoalAccessoryView(entry: $0, familyOverride: .accessoryInline))
            },
            WidgetShot("LS-02", "days-since", size: circular, backdrop: .accessory(.accessoryCircular)) { AnyView(DaysSinceAccessoryView(entry: $0)) },
            WidgetShot("LS-03", "streak", size: circular, backdrop: .accessory(.accessoryCircular)) { AnyView(StreakAccessoryView(entry: $0)) },
            WidgetShot("LS-04", "quick-start", size: circular, backdrop: .accessory(.accessoryCircular)) {
                AnyView(NextUpAccessoryView(entry: $0, familyOverride: .accessoryCircular))
            },
            WidgetShot("LS-05", "next-workout", size: rectangular, backdrop: .accessory(.accessoryRectangular)) {
                AnyView(NextUpAccessoryView(entry: $0, familyOverride: .accessoryRectangular))
            },
            WidgetShot("LS-10", "split-inline", size: inline, backdrop: .accessory(.accessoryInline)) {
                AnyView(NextUpAccessoryView(entry: $0, familyOverride: .accessoryInline))
            },
            WidgetShot("LS-06", "volume", size: rectangular, backdrop: .accessory(.accessoryRectangular)) { AnyView(WeeklySetsAccessoryView(entry: $0)) },
            WidgetShot("LS-07", "latest-record", size: rectangular, backdrop: .accessory(.accessoryRectangular)) { AnyView(PRAccessoryView(entry: $0)) },
            WidgetShot("LS-08", "overload", size: rectangular, backdrop: .accessory(.accessoryRectangular)) { AnyView(OverloadAccessoryView(entry: $0)) },
        ]
        try renderWidgetShots(shots, test: self)
    }

    // MARK: Extras

    func testExtraWidgets() throws {
        let small = WidgetMetrics.small
        let medium = WidgetMetrics.medium
        // The log-set widget is the one that follows a running workout: draw it idle, logging and resting.
        let logSetVariants: [(label: String, entry: @MainActor () -> SnapshotEntry?)] = WidgetShot.previewAndEmpty + [
            (label: "logging", entry: { WidgetFixtures.running("logging-weight") }),
            (label: "resting", entry: { WidgetFixtures.running("resting") }),
        ]

        let shots: [WidgetShot] = [
            WidgetShot("WI-01", "body-map", size: medium) { AnyView(BodyMapView(entry: $0)) },
            WidgetShot("WI-02", "log-set", size: medium, entries: logSetVariants) { AnyView(LogSetView(entry: $0)) },
            WidgetShot("WI-03", "gym-partner", size: medium) { AnyView(PartnerView(entry: $0)) },
            WidgetShot("WI-04", "form-cue", size: small) { AnyView(FormCueView(entry: $0)) },
            WidgetShot("WI-05", "loaded-bar", size: small) { AnyView(LoadedBarView(entry: $0)) },
            WidgetShot("WI-06", "rest-day", size: small) { AnyView(RestDayView(entry: $0)) },
            WidgetShot("WI-07", "strength-ratio", size: small) { AnyView(StrengthRatioView(entry: $0)) },
            WidgetShot("WI-08", "year-in-iron", size: small, backdrop: .darkCard) { AnyView(YearInIronView(entry: $0)) },
            WidgetShot("WI-09", "readiness", size: medium) { AnyView(ReadinessView(entry: $0)) },
            WidgetShot("WI-10", "plateau-watch", size: medium) { AnyView(PlateauView(entry: $0)) },
            WidgetShot("WI-11", "session-timeline", size: medium) { AnyView(SessionTimelineView(entry: $0)) },
        ]
        try renderWidgetShots(shots, test: self)
    }

    // MARK: Fixtures

    /// The snapshot every image starts from is the one the widgets show in the gallery, so a change of the contract shows up here first.
    func testPreviewSnapshotHasEverySection() {
        let preview = WidgetSnapshot.preview
        XCTAssertEqual(preview.week.days.count, 7)
        XCTAssertNotNil(preview.nextUp)
        XCTAssertNil(preview.active)
        XCTAssertNotNil(WidgetFixtures.running("logging-weight")?.snapshot.active)
        XCTAssertNotNil(WidgetFixtures.running("resting")?.snapshot.active)
    }
}
#endif
