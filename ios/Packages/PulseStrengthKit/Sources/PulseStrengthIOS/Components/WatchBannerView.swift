#if os(iOS)
import SwiftUI
import PulseStrengthCore

/// The warning card under the header when the Apple Watch is not connected or Health access for
/// heart rate was denied. Renders nothing for `.connected`. The caller owns dismissal state.
public struct WatchBannerView: View {
    public var status: WatchStatus
    /// "Reconnect" (Watch not connected) or "Settings" (Health access denied).
    public var onAction: () -> Void
    public var onDismiss: () -> Void

    public init(status: WatchStatus, onAction: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.status = status
        self.onAction = onAction
        self.onDismiss = onDismiss
    }

    private struct Copy {
        var title: String
        var message: String
        var button: String
    }

    private var copy: Copy? {
        switch status {
        case .connected:
            return nil
        case .notConnected:
            return Copy(
                title: "Apple Watch not connected",
                message: "Heart rate and calories are not being recorded.",
                button: "Reconnect"
            )
        case .healthDenied:
            return Copy(
                title: "Heart rate is off",
                message: "Allow Pulse to read heart rate in the Health app.",
                button: "Settings"
            )
        }
    }

    /// Warning amber of the design (#C77700); a lighter amber in dark mode.
    private static let warning = Color(light: 0xC77700, dark: 0xFF9F0A)

    public var body: some View {
        if let copy = copy {
            banner(copy)
        }
    }

    private func banner(_ copy: Copy) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .pulseFont(18, .semibold, relativeTo: .footnote)
                .foregroundStyle(WatchBannerView.warning)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(copy.title)
                    .pulseFont(13, .semibold, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.ink)
                Text(copy.message)
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
            }
            // Both lines wrap (never truncate) when the text is bigger.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button(action: onAction) {
                Text(copy.button)
                    .pulseFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.blue)
                    .padding(.horizontal, 6)
                    .pulseScaledFrame(minHeight: 44, relativeTo: PulseDynamicType.controlHeightStyle)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PulsePlainButtonStyle())
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .pulseFont(13, .bold, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PulsePlainButtonStyle())
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 12)
        .frame(minHeight: 48)
        .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
#endif
