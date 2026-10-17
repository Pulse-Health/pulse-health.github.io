import Foundation

/// The clock of the story-style highlights on the welcome screen: `count` segments that fill one after the other, each over
/// `segmentDuration` seconds, wrapping around after the last. A value type that the view advances from a timer, so the timing
/// rules (carry-over, wrap, a long pause not skipping highlights) can be tested without a screen.
public struct HighlightPlayback: Equatable, Hashable, Sendable {
    /// Seconds a highlight stays on screen.
    public static let defaultSegmentDuration: TimeInterval = 6.5
    /// One `advance(by:)` never moves the clock further than this, so coming back after the app was suspended shows
    /// the highlight the user left instead of skipping several.
    public static let maximumStep: TimeInterval = 0.5

    public let count: Int
    public let segmentDuration: TimeInterval
    public private(set) var index: Int
    /// Seconds spent on the current highlight.
    public private(set) var elapsed: TimeInterval

    public init(count: Int = 3, segmentDuration: TimeInterval = HighlightPlayback.defaultSegmentDuration) {
        self.count = max(1, count)
        self.segmentDuration = max(0.1, segmentDuration)
        self.index = 0
        self.elapsed = 0
    }

    /// How full segment `segment` is (0 to 1): full before the current one, partly full for the current one, empty after it.
    public func fill(of segment: Int) -> Double {
        if segment < index { return 1 }
        if segment > index { return 0 }
        return min(1, max(0, elapsed / segmentDuration))
    }

    /// Moves the clock forward. Returns true when the highlight changed.
    @discardableResult
    public mutating func advance(by seconds: TimeInterval) -> Bool {
        guard seconds > 0 else { return false }
        elapsed += min(seconds, HighlightPlayback.maximumStep)
        guard elapsed >= segmentDuration else { return false }
        let carry = elapsed - segmentDuration
        index = (index + 1) % count
        elapsed = carry
        return true
    }

    /// Jumps to a highlight (a tap on its bar, a swipe) and restarts its bar. Out-of-range values wrap around.
    public mutating func select(_ segment: Int) {
        let wrapped = ((segment % count) + count) % count
        index = wrapped
        elapsed = 0
    }

    public mutating func selectNext() {
        select(index + 1)
    }

    public mutating func selectPrevious() {
        select(index - 1)
    }
}
