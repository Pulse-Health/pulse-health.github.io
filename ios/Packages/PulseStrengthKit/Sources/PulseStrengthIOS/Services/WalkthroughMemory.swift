#if os(iOS)
import Foundation
import PulseStrengthCore

/// Remembers which version of the walkthrough the user has seen, so the tour that follows onboarding shows once.
/// Lives in `UserDefaults` (a single integer): it is a convenience, not data worth syncing or backing up with the workouts.
struct WalkthroughMemory {
    /// `UserDefaults` key of the last seen `Walkthrough.version`.
    static let key = "health.pulse.strength.walkthrough.seenVersion"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The version of the tour the user last saw or skipped; nil when never.
    var seenVersion: Int? {
        defaults.object(forKey: WalkthroughMemory.key) as? Int
    }

    /// True when the tour should open by itself (never seen, or revised since).
    var shouldShow: Bool {
        Walkthrough.shouldShow(seenVersion: seenVersion)
    }

    /// Records the current version as seen (the tour was finished, skipped or swiped away).
    func markSeen() {
        defaults.set(Walkthrough.version, forKey: WalkthroughMemory.key)
    }
}
#endif
