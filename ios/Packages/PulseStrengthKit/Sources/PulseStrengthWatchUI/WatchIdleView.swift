#if os(watchOS)
import SwiftUI
import PulseStrengthCore

/// Shown while no workout is running: "Start a workout on your iPhone", whether the iPhone can be reached, and a button
/// that asks the phone for its current state.
@MainActor
struct WatchIdleView: View {
    @ObservedObject var environment: WatchEnvironment

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var palette: WatchPalette { WatchPalette(reduced: isLuminanceReduced) }

    private var hintText: String {
        environment.isPhoneReachable
            ? "Your iPhone is connected."
            : "Your iPhone isn't reachable. Open Pulse on it and keep it nearby."
    }

    private var hintColor: Color {
        environment.isPhoneReachable ? palette.accent : palette.secondary
    }

    var body: some View {
        ScrollView {
            pageContent
        }
    }

    /// The page without its scroll container. Internal (not private) only so that the snapshot tests can draw it:
    /// `ImageRenderer` leaves the contents of a `ScrollView` blank.
    var pageContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text("Start a workout on your iPhone")
                .font(WatchFont.text(16, .semibold))
                .foregroundStyle(palette.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(hintText)
                .font(WatchFont.text(12.5, .regular))
                .foregroundStyle(hintColor)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            checkButton
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private var checkButton: some View {
        Button(action: { checkAgain() }) {
            Text("Check again")
                .font(WatchFont.text(15, .semibold))
                .foregroundStyle(isLuminanceReduced ? palette.accent : palette.onAccent)
        }
        .buttonStyle(
            WatchCapsuleButtonStyle(
                fill: isLuminanceReduced ? Color.clear : WatchTheme.green,
                outline: isLuminanceReduced ? palette.accent : Color.clear,
                outlineWidth: isLuminanceReduced ? 1.5 : 0,
                height: 40
            )
        )
        .accessibilityHint("Asks your iPhone for the current workout")
    }

    private func checkAgain() {
        environment.requestStateFromPhone()
        WatchHaptics.click()
    }
}
#endif
