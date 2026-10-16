import Foundation

/// One page of the first-run walkthrough: what a part of the app is for and how to use it.
///
/// The text describes the app as it is; when a screen changes, change the matching step (`WalkthroughTests` pins the
/// invariants: unique ids, non-empty text, a short list of points).
public struct WalkthroughStep: Equatable, Identifiable, Sendable {
    /// Stable name of the step. The iOS layer picks the illustration by it.
    public let id: String
    public let title: String
    /// One or two sentences under the title.
    public let message: String
    /// SF Symbol shown when the step has no illustration of its own.
    public let symbol: String
    /// Short tips, one line each, shown under the message.
    public let points: [String]

    public init(id: String, title: String, message: String, symbol: String, points: [String] = []) {
        self.id = id
        self.title = title
        self.message = message
        self.symbol = symbol
        self.points = points
    }
}

/// The walkthrough shown once after onboarding: a short page-by-page tour of the Strength feature.
public enum Walkthrough {
    /// Raise it when the tour has changed enough that people who have seen it should see it again.
    public static let version = 1

    /// The pages, in order. The first one welcomes, the last one points at the places to look next.
    public static let steps: [WalkthroughStep] = [
        WalkthroughStep(
            id: "welcome",
            title: "Welcome to Strength",
            message: "Log every set, rest on a timer and watch your lifts go up. This short tour shows you around.",
            symbol: "figure.strengthtraining.traditional",
            points: []
        ),
        WalkthroughStep(
            id: "today",
            title: "Your workout for today",
            message: "The hub recommends the next workout in your rotation and tells you how ready your muscles are.",
            symbol: "calendar",
            points: [
                "Green, yellow and red dots show how recovered each muscle is.",
                "Start Workout begins it. Start Empty Workout lets you add exercises as you go.",
                "Templates and plans keep your routine in one place.",
            ]
        ),
        WalkthroughStep(
            id: "log",
            title: "Log your sets",
            message: "Tap the circle to log a set with the planned weight and reps. Tap the weight or the reps to change them.",
            symbol: "checkmark.circle.fill",
            points: [
                "Tap the badge to mark a warm-up, drop set or set to failure, and to note reps in reserve.",
                "A PR tag appears when a set beats your best estimated one-rep max.",
            ]
        ),
        WalkthroughStep(
            id: "rest",
            title: "Rest on a timer",
            message: "Logging a set starts the rest timer for you. Add or take off 15 seconds, or skip it.",
            symbol: "timer",
            points: [
                "You are alerted when the rest is over, even while the app is in the background.",
                "Log sets and control the timer from the Lock Screen and the Dynamic Island.",
                "An Apple Watch mirrors the workout and records your heart rate.",
            ]
        ),
        WalkthroughStep(
            id: "shape",
            title: "Shape the workout",
            message: "Change the plan while you train. Tap Edit to add, reorder or remove exercises.",
            symbol: "slider.horizontal.3",
            points: [
                "The options button of an exercise shows its form demo, rest timer and superset.",
                "Removed something by mistake? Tap Undo within a few seconds.",
                "Minimise the workout to look around; it keeps running in the bar at the bottom.",
            ]
        ),
        WalkthroughStep(
            id: "finish",
            title: "Finish and look back",
            message: "Tap Finish when you are done. The summary shows your volume, sets and any new personal records.",
            symbol: "trophy.fill",
            points: [
                "Changed the exercises? You can update the template or keep the change to this workout.",
                "Every finished workout is saved to your history.",
            ]
        ),
        WalkthroughStep(
            id: "more",
            title: "Find your way around",
            message: "The More button at the top of the hub has everything else. You can replay this tour from there at any time.",
            symbol: "ellipsis.circle",
            points: [
                "Exercise Library: form demos, your history and your estimated one-rep max per lift.",
                "Import Plan brings in a plan from a file.",
                "Settings: body weight, a weigh-in reminder and Apple Health sync.",
            ]
        ),
    ]

    /// Whether the tour should be shown automatically to someone who last saw version `seenVersion` (nil = never).
    public static func shouldShow(seenVersion: Int?) -> Bool {
        guard let seen = seenVersion else { return true }
        return seen < version
    }
}

/// Where the reader is in the walkthrough. Pure value logic, so the page buttons are testable off Apple platforms.
public struct WalkthroughProgress: Equatable, Sendable {
    public let count: Int
    /// The shown page, always in `0..<count` (0 when there are no pages).
    public private(set) var index: Int

    public init(count: Int, index: Int = 0) {
        self.count = max(0, count)
        self.index = WalkthroughProgress.clamp(index, count: self.count)
    }

    public var isFirst: Bool {
        index == 0
    }

    public var isLast: Bool {
        index >= count - 1
    }

    /// "2 of 7", for the page indicator's accessibility value.
    public var positionText: String {
        count == 0 ? "" : "\(index + 1) of \(count)"
    }

    /// Moves to the next page. False when already on the last page (the caller then closes the tour).
    @discardableResult
    public mutating func advance() -> Bool {
        guard !isLast else { return false }
        index += 1
        return true
    }

    /// Moves to the previous page. False when already on the first.
    @discardableResult
    public mutating func goBack() -> Bool {
        guard !isFirst else { return false }
        index -= 1
        return true
    }

    /// Jumps to a page (a swipe or a tap on the indicator); an index outside the pages is clamped.
    public mutating func go(to newIndex: Int) {
        index = WalkthroughProgress.clamp(newIndex, count: count)
    }

    private static func clamp(_ value: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(value, 0), count - 1)
    }
}
