#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

/// The foreground cue for the end of a rest: a success haptic and a VoiceOver announcement.
///
/// The system notification at the rest end is suppressed while the app is in the foreground
/// (`StrengthNotificationDelegate`), so this is what tells the user, wherever the rest dock is not the thing on screen:
/// `ActiveWorkoutView` calls it while the workout screen is open, and `PulseStrengthRootView` calls it while the
/// workout is minimised and the in-progress bar is showing. The two are never on screen together, so it fires once.
@MainActor
enum RestEndFeedback {
    /// Fires when the dock phase turns from `.running` to `.finished`, the app is active and the workout has
    /// "Alert when rest ends" on (a missing workout counts as on, like the setting's default).
    static func playIfRestEnded(
        from oldPhase: ActiveWorkoutPresentation.DockPhase?,
        to newPhase: ActiveWorkoutPresentation.DockPhase?,
        scenePhase: ScenePhase,
        alertsEnabled: Bool
    ) {
        guard oldPhase == .running, newPhase == .finished else { return }
        guard scenePhase == .active else { return }
        guard alertsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: "Rest over")
    }
}
#endif
