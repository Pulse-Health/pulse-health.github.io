import XCTest
@testable import PulseStrengthCore

/// The clock of the welcome screen's story-style highlights (HighlightPlayback.swift).
final class HighlightPlaybackTests: XCTestCase {
    func testStartsOnTheFirstHighlightWithEmptyBars() {
        let playback = HighlightPlayback()
        XCTAssertEqual(playback.count, 3)
        XCTAssertEqual(playback.index, 0)
        for segment in 0..<3 {
            XCTAssertEqual(playback.fill(of: segment), 0, accuracy: 1e-9)
        }
    }

    func testTheCurrentBarFillsWhileTheEarlierOnesAreFullAndTheLaterOnesEmpty() {
        var playback = HighlightPlayback(count: 3, segmentDuration: 4)
        playback.select(1)
        playback.advance(by: 0.5)
        playback.advance(by: 0.5)
        XCTAssertEqual(playback.fill(of: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(playback.fill(of: 1), 0.25, accuracy: 1e-9)
        XCTAssertEqual(playback.fill(of: 2), 0, accuracy: 1e-9)
    }

    func testMovesToTheNextHighlightWhenTheBarIsFull() {
        var playback = HighlightPlayback(count: 3, segmentDuration: 1)
        XCTAssertFalse(playback.advance(by: 0.5))
        XCTAssertTrue(playback.advance(by: 0.5))
        XCTAssertEqual(playback.index, 1)
        XCTAssertEqual(playback.elapsed, 0, accuracy: 1e-9)
    }

    func testTheDefaultDurationIsSixAndAHalfSeconds() {
        var playback = HighlightPlayback()
        var changed = false
        for _ in 0..<12 { changed = playback.advance(by: 0.5) || changed }
        XCTAssertFalse(changed, "6 s is not enough")
        XCTAssertTrue(playback.advance(by: 0.5), "6.5 s is")
        XCTAssertEqual(playback.index, 1)
    }

    func testTheRemainderCarriesOverToTheNextBar() {
        var playback = HighlightPlayback(count: 3, segmentDuration: 1)
        playback.advance(by: 0.4)
        playback.advance(by: 0.4)
        XCTAssertTrue(playback.advance(by: 0.4))
        XCTAssertEqual(playback.index, 1)
        XCTAssertEqual(playback.elapsed, 0.2, accuracy: 1e-9)
    }

    func testWrapsAroundAfterTheLastHighlight() {
        var playback = HighlightPlayback(count: 3, segmentDuration: 1)
        playback.select(2)
        playback.advance(by: 0.5)
        XCTAssertTrue(playback.advance(by: 0.5))
        XCTAssertEqual(playback.index, 0)
    }

    func testALongPauseDoesNotSkipHighlights() {
        var playback = HighlightPlayback(count: 3, segmentDuration: 6.5)
        playback.advance(by: 120)
        XCTAssertEqual(playback.index, 0)
        XCTAssertEqual(playback.elapsed, HighlightPlayback.maximumStep, accuracy: 1e-9)
    }

    func testIgnoresZeroAndNegativeTime() {
        var playback = HighlightPlayback()
        XCTAssertFalse(playback.advance(by: 0))
        XCTAssertFalse(playback.advance(by: -3))
        XCTAssertEqual(playback.elapsed, 0, accuracy: 1e-9)
    }

    func testSelectingRestartsTheBarAndWrapsOutOfRangeValues() {
        var playback = HighlightPlayback(count: 3, segmentDuration: 4)
        playback.advance(by: 0.5)
        playback.select(2)
        XCTAssertEqual(playback.index, 2)
        XCTAssertEqual(playback.elapsed, 0, accuracy: 1e-9)

        playback.select(-1)
        XCTAssertEqual(playback.index, 2)
        playback.select(3)
        XCTAssertEqual(playback.index, 0)
        playback.select(7)
        XCTAssertEqual(playback.index, 1)
    }

    func testNextAndPreviousWrap() {
        var playback = HighlightPlayback(count: 3, segmentDuration: 4)
        playback.selectPrevious()
        XCTAssertEqual(playback.index, 2)
        playback.selectNext()
        XCTAssertEqual(playback.index, 0)
        playback.selectNext()
        XCTAssertEqual(playback.index, 1)
    }

    func testDegenerateInitialValuesAreClamped() {
        let playback = HighlightPlayback(count: 0, segmentDuration: 0)
        XCTAssertEqual(playback.count, 1)
        XCTAssertGreaterThan(playback.segmentDuration, 0)
    }
}
