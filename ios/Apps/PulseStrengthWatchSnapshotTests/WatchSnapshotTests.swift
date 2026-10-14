// WatchSnapshotTests.swift
//
// Screenshots of the Apple Watch app for people who cannot run a simulator. The tests draw the real Watch screens
// (PulseStrengthWatchUI) with `ImageRenderer` and write one PNG per screen:
//
//   <SCREENSHOT_DIR>/watch-<NN>-<name>.png          (and watch-manifest.txt: one line per PNG)
//
// `SCREENSHOT_DIR` is read from the test process environment. xcodebuild forwards variables prefixed with `TEST_RUNNER_`, so
// CI sets `TEST_RUNNER_SCREENSHOT_DIR=/path`; without it the files go to NSTemporaryDirectory(). Every PNG is also attached to
// the test result (lifetime keepAlways). The simulator shares the host's file system, so an absolute host path works.
//
// What is drawn (see WatchSnapshotSupport.swift for the details and the limits of ImageRenderer):
//
//   testPagesAtReferenceSize       every page at 45 mm (198 x 242 pt, 396 x 484 px):
//                                  Log set (weight x reps, warm-up, reps only, timed, all sets logged), Rest (running, next
//                                  exercise named, paused, over), Metrics (with and without heart rate), Idle (iPhone
//                                  reachable / not), Summary.
//   testKeyPagesAtOtherSizes       six key pages at 40, 41, 44 and 49 mm (162 x 197, 170 x 207, 184 x 224, 205 x 251 pt).
//   testScrollingPagesAtFullLength the idle and the summary page without the screen height limit (they scroll on the Watch).
//   testWatchRootView              WatchRootView itself for a mirror environment fed a state (experimental: it contains a
//                                  vertical-page TabView and scroll views, which ImageRenderer may leave blank).
//   testFixturesAreWhatTheyClaim   plain assertions on the fixtures, so a change of the reducer cannot silently change what
//                                  the screenshots show.
//
// The workouts come from the real reducer (WatchSnapshotFixtures.swift) and reach the views through the real
// `WorkoutController.receive(SyncEnvelope)` of a mirror controller. The Digital Crown and the clocks do not matter for a
// still image, so the fixtures are static: the pages get a fixed date.

#if os(watchOS)
import XCTest
import SwiftUI
import PulseStrengthCore
@testable import PulseStrengthWatchUI

@MainActor
final class WatchSnapshotTests: XCTestCase {

    // MARK: Pages

    /// Every page at the reference size (45 mm).
    func testPagesAtReferenceSize() {
        let size = WatchScreen.reference
        for (index, shot) in WatchCatalog.pages.enumerated() {
            let view = WatchCatalog.screen(shot.make(), size: size, scrolls: shot.scrolls)
            WatchOutput.save(
                view,
                number: WatchCatalog.pageNumber(index),
                name: shot.name + "-" + size.name,
                expectContent: true,
                test: self
            )
        }
        WatchOutput.finish(test: self)
    }

    /// The key pages at the other four sizes (the smallest screen is where the layout is tightest).
    func testKeyPagesAtOtherSizes() {
        for (shotIndex, name) in WatchCatalog.sweepNames.enumerated() {
            guard let shot = WatchCatalog.page(named: name) else {
                XCTFail("No page called " + name + " in the catalogue")
                continue
            }
            for (screenIndex, size) in WatchCatalog.sweepScreens.enumerated() {
                let view = WatchCatalog.screen(shot.make(), size: size, scrolls: shot.scrolls)
                WatchOutput.save(
                    view,
                    number: WatchCatalog.sweepNumber(shot: shotIndex, screen: screenIndex),
                    name: shot.name + "-" + size.name,
                    expectContent: true,
                    test: self
                )
            }
        }
        WatchOutput.finish(test: self)
    }

    /// The pages that scroll on the Watch, drawn at their full height (the reference width), so nothing is cut off.
    func testScrollingPagesAtFullLength() {
        let size = WatchScreen.reference
        for (index, name) in WatchCatalog.fullLengthNames.enumerated() {
            guard let shot = WatchCatalog.page(named: name) else {
                XCTFail("No page called " + name + " in the catalogue")
                continue
            }
            let view = WatchCatalog.fullLength(shot.make(), width: size.width)
            WatchOutput.save(
                view,
                number: WatchCatalog.fullLengthNumber(index),
                name: shot.name + "-full-length-" + size.name,
                expectContent: true,
                test: self
            )
        }
        WatchOutput.finish(test: self)
    }

    // MARK: Whole screen

    /// `WatchRootView` for a mirror environment. Experimental: the root view is a vertical-page TabView (logging, resting) or
    /// a ScrollView (idle, summary), which `ImageRenderer` may not draw; a blank result is reported in the manifest, it does
    /// not fail the test.
    func testWatchRootView() {
        let size = WatchScreen.reference
        for (index, shot) in WatchCatalog.roots.enumerated() {
            let view = WatchCatalog.screen(shot.make(), size: size, scrolls: shot.scrolls)
            WatchOutput.save(
                view,
                number: WatchCatalog.rootNumber(index),
                name: shot.name + "-" + size.name,
                expectContent: false,
                test: self
            )
        }
        WatchOutput.finish(test: self)
    }

    // MARK: Fixtures

    /// The screenshots are only meaningful if the fixtures are what their names say.
    func testFixturesAreWhatTheyClaim() {
        let start = WatchFixtures.referenceStart

        let logging = WatchFixtures.loggingWeightReps(start: start).snapshot
        XCTAssertEqual(logging.phase, .logging)
        XCTAssertEqual(logging.exerciseName, "Barbell bench press")
        XCTAssertEqual(logging.setLabel, "Set 3 of 5")
        XCTAssertEqual(logging.weightText, "82.5")
        XCTAssertEqual(logging.repsText, "6")
        XCTAssertTrue(logging.showsWeight)

        let warmup = WatchFixtures.loggingWarmup(start: start).snapshot
        XCTAssertEqual(warmup.setLabel, "Warm-up · Set 1 of 5")

        let repsOnly = WatchFixtures.loggingRepsOnly(start: start).snapshot
        XCTAssertEqual(repsOnly.tracking, .repsOnly)
        XCTAssertFalse(repsOnly.showsWeight)

        let duration = WatchFixtures.loggingDuration(start: start).snapshot
        XCTAssertEqual(duration.tracking, .duration)
        XCTAssertEqual(duration.repsUnit, "sec")

        let done = WatchFixtures.allLogged(start: start).snapshot
        XCTAssertEqual(done.phase, .complete)
        XCTAssertEqual(done.loggedSets, done.totalSets)
        XCTAssertGreaterThan(done.totalSets, 0)

        let runningFixture = WatchFixtures.restRunning(start: start)
        let running = runningFixture.snapshot
        XCTAssertEqual(running.phase, .resting)
        XCTAssertEqual(running.restEndsAt?.timeIntervalSince(runningFixture.date) ?? -1, 72, accuracy: 0.001)
        XCTAssertEqual(running.restTotalSeconds, 150)

        let nextExercise = WatchFixtures.restNextExercise(start: start)
        XCTAssertEqual(nextExercise.snapshot.phase, .resting)
        XCTAssertNotEqual(nextExercise.state.lastLogged?.exerciseID, nextExercise.snapshot.targetExerciseID)

        let paused = WatchFixtures.restPaused(start: start).snapshot
        XCTAssertTrue(paused.isPaused)
        XCTAssertEqual(paused.restFrozenRemaining, 90)

        let over = WatchFixtures.restOver(start: start).snapshot
        XCTAssertEqual(over.phase, .restOver)

        let withHeartRate = WatchFixtures.midWorkout(start: start, heartRate: true).snapshot
        XCTAssertEqual(withHeartRate.heartRate, 142)
        XCTAssertEqual(withHeartRate.volumeText, "1,780")
        XCTAssertEqual(withHeartRate.loggedSets, 6)
        XCTAssertEqual(withHeartRate.totalSets, 20)

        let withoutHeartRate = WatchFixtures.midWorkout(start: start, heartRate: false).snapshot
        XCTAssertNil(withoutHeartRate.heartRate)
    }

    /// The mirror controller adopts the envelope, and the preview environment starts nothing.
    func testMirrorControllerShowsTheFixtureState() {
        let fixture = WatchFixtures.restRunning(start: WatchFixtures.referenceStart)
        let controller = WatchCatalog.controller(showing: fixture.state)
        XCTAssertEqual(controller.role, .mirror)
        XCTAssertEqual(controller.state, fixture.state)

        let environment = WatchCatalog.environment(showing: fixture.state, phoneReachable: true)
        XCTAssertEqual(environment.controller.state, fixture.state)
        XCTAssertTrue(environment.isPhoneReachable)
        XCTAssertFalse(environment.session.isRecording)
        XCTAssertNil(environment.endedSummary)
    }
}
#endif
