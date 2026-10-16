import XCTest
@testable import PulseStrengthCore

final class WalkthroughTests: XCTestCase {

    // MARK: Steps

    func testStepsHaveUniqueIdsAndText() {
        let steps = Walkthrough.steps
        XCTAssertGreaterThanOrEqual(steps.count, 3)
        XCTAssertEqual(Set(steps.map { $0.id }).count, steps.count, "step ids must be unique")
        for step in steps {
            XCTAssertFalse(step.id.isEmpty)
            XCTAssertFalse(step.title.isEmpty, step.id)
            XCTAssertFalse(step.message.isEmpty, step.id)
            XCTAssertFalse(step.symbol.isEmpty, step.id)
            XCTAssertLessThanOrEqual(step.points.count, 3, step.id + ": a page shows at most three tips")
            for point in step.points {
                XCTAssertFalse(point.isEmpty, step.id)
            }
        }
    }

    func testTourStartsWithWelcomeAndEndsWithMore() {
        XCTAssertEqual(Walkthrough.steps.first?.id, "welcome")
        XCTAssertEqual(Walkthrough.steps.last?.id, "more")
    }

    func testUndoTipUsesTheAppsOwnUndoWindow() {
        XCTAssertEqual(Walkthrough.undoSeconds, Int(WorkoutReducer.undoWindow.rounded()))
        guard let shape = Walkthrough.steps.first(where: { $0.id == "shape" }) else {
            return XCTFail("the tour has no 'shape' step")
        }
        let tip = shape.points.first { $0.contains("Undo") }
        XCTAssertNotNil(tip, "the 'shape' step explains Undo")
        XCTAssertTrue(tip?.contains("\(Walkthrough.undoSeconds) seconds") ?? false, "the tip names the app's undo window")
    }

    // MARK: When to show

    func testShownToSomeoneWhoNeverSawIt() {
        XCTAssertTrue(Walkthrough.shouldShow(seenVersion: nil))
    }

    func testNotShownAgainOnceTheCurrentVersionWasSeen() {
        XCTAssertFalse(Walkthrough.shouldShow(seenVersion: Walkthrough.version))
    }

    func testShownAgainWhenTheTourWasRevised() {
        XCTAssertTrue(Walkthrough.shouldShow(seenVersion: Walkthrough.version - 1))
        XCTAssertFalse(Walkthrough.shouldShow(seenVersion: Walkthrough.version + 1))
    }

    // MARK: Progress

    func testProgressStartsOnTheFirstPage() {
        let progress = WalkthroughProgress(count: 4)
        XCTAssertEqual(progress.index, 0)
        XCTAssertTrue(progress.isFirst)
        XCTAssertFalse(progress.isLast)
        XCTAssertEqual(progress.positionText, "1 of 4")
    }

    func testAdvanceWalksToTheLastPageThenStops() {
        var progress = WalkthroughProgress(count: 3)
        XCTAssertTrue(progress.advance())
        XCTAssertTrue(progress.advance())
        XCTAssertEqual(progress.index, 2)
        XCTAssertTrue(progress.isLast)
        XCTAssertEqual(progress.positionText, "3 of 3")
        XCTAssertFalse(progress.advance(), "advancing past the last page reports that the tour is over")
        XCTAssertEqual(progress.index, 2)
    }

    func testGoBackStopsAtTheFirstPage() {
        var progress = WalkthroughProgress(count: 3, index: 2)
        XCTAssertTrue(progress.goBack())
        XCTAssertTrue(progress.goBack())
        XCTAssertFalse(progress.goBack())
        XCTAssertEqual(progress.index, 0)
    }

    func testGoToClampsIntoTheRange() {
        var progress = WalkthroughProgress(count: 5)
        progress.go(to: 3)
        XCTAssertEqual(progress.index, 3)
        progress.go(to: 99)
        XCTAssertEqual(progress.index, 4)
        progress.go(to: -7)
        XCTAssertEqual(progress.index, 0)
    }

    func testInitialIndexIsClamped() {
        XCTAssertEqual(WalkthroughProgress(count: 3, index: 10).index, 2)
        XCTAssertEqual(WalkthroughProgress(count: 3, index: -1).index, 0)
    }

    func testAnEmptyTourIsHarmless() {
        var progress = WalkthroughProgress(count: 0)
        XCTAssertEqual(progress.index, 0)
        XCTAssertTrue(progress.isFirst)
        XCTAssertTrue(progress.isLast)
        XCTAssertEqual(progress.positionText, "")
        XCTAssertFalse(progress.advance())
        XCTAssertFalse(progress.goBack())
        progress.go(to: 4)
        XCTAssertEqual(progress.index, 0)
    }

    func testASinglePageTourIsFirstAndLast() {
        let progress = WalkthroughProgress(count: 1)
        XCTAssertTrue(progress.isFirst)
        XCTAssertTrue(progress.isLast)
    }
}
