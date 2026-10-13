#if os(iOS)
import SwiftUI
import PulseStrengthCore

/// The floating rest dock at the bottom of the active-workout screen: draining ring, label and
/// countdown, -15 / +15 / Skip (or Dismiss once the rest is over) and the "Reps left" selector
/// for the set that was just logged.
public struct RestDockView: View {
    public var dock: ActiveWorkoutPresentation.Dock
    /// Adds (positive) or removes (negative) seconds from the running rest.
    public var onAdjust: (Int) -> Void
    /// Skips the rest / dismisses the "Go" state.
    public var onSkip: () -> Void
    /// A "Reps left" chip was tapped (0...4, 4 meaning "4+"); the caller toggles it on the last logged set.
    public var onSelectRIR: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        dock: ActiveWorkoutPresentation.Dock,
        onAdjust: @escaping (Int) -> Void,
        onSkip: @escaping () -> Void,
        onSelectRIR: @escaping (Int) -> Void
    ) {
        self.dock = dock
        self.onAdjust = onAdjust
        self.onSkip = onSkip
        self.onSelectRIR = onSelectRIR
    }

    private static let rirOptions: [(value: Int, title: String)] = [
        (value: 0, title: "0"),
        (value: 1, title: "1"),
        (value: 2, title: "2"),
        (value: 3, title: "3"),
        (value: 4, title: "4+")
    ]

    private var isFinished: Bool { dock.phase == .finished }

    private var ringColor: Color { isFinished ? PulseTheme.green : PulseTheme.recoveryGood }

    private var labelColor: Color { isFinished ? PulseTheme.greenText : PulseTheme.inkSecondary }

    private var labelText: String {
        if isFinished { return "Rest over" }
        return dock.isPaused ? "Rest · paused" : "Rest"
    }

    private var ringFraction: CGFloat {
        let value = isFinished ? 1.0 : dock.fraction
        return CGFloat(min(1, max(0, value)))
    }

    public var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                countdownBlock
                if isFinished {
                    dismissButton
                } else {
                    adjustButtons
                }
            }
            if dock.showsRIR {
                rirRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(dockBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    /// Two stacked plates so each shadow is cast by the plate itself (not by the other shadow).
    private var dockBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(PulseTheme.card)
                .shadow(color: Color.black.opacity(0.12), radius: 15, x: 0, y: 10)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(PulseTheme.card)
                .shadow(color: Color.black.opacity(0.06), radius: 1.5, x: 0, y: 1)
        }
    }

    // MARK: Ring and countdown

    private var countdownBlock: some View {
        HStack(spacing: 12) {
            ring
            VStack(alignment: .leading, spacing: 0) {
                Text(labelText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                Text(dock.remainingText)
                    .font(PulseFont.number(30, .bold))
                    .monospacedDigit()
                    .tracking(-0.5)
                    .foregroundStyle(PulseTheme.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(spokenRemaining)
        .accessibilityHint(dock.nextSetText)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(PulseTheme.progressTrack, lineWidth: 5)
            if ringFraction > 0.001 {
                Circle()
                    .trim(from: 0, to: ringFraction)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: "timer")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ringColor)
        }
        .frame(width: 44, height: 44)
        .frame(width: 52, height: 52)
        .animation(reduceMotion ? nil : .linear(duration: 1), value: ringFraction)
    }

    private var spokenLabel: String {
        if isFinished { return "Rest over" }
        return dock.isPaused ? "Rest timer, paused" : "Rest timer"
    }

    private var spokenRemaining: String {
        if isFinished { return "Go" }
        let minutes = dock.remainingSeconds / 60
        let seconds = dock.remainingSeconds % 60
        var parts: [String] = []
        if minutes > 0 {
            parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes")
        }
        if seconds > 0 || minutes == 0 {
            parts.append(seconds == 1 ? "1 second" : "\(seconds) seconds")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Buttons

    private var adjustButtons: some View {
        HStack(spacing: 6) {
            adjustButton(title: "\u{2212}15", seconds: -15, label: "Subtract 15 seconds")
            adjustButton(title: "+15", seconds: 15, label: "Add 15 seconds")
            skipButton
        }
    }

    private func adjustButton(title: String, seconds: Int, label: String) -> some View {
        Button {
            onAdjust(seconds)
        } label: {
            Text(title)
                .font(PulseFont.number(15, .semibold))
                .monospacedDigit()
                .foregroundStyle(PulseTheme.ink)
                .frame(width: 46, height: 44)
                .background(PulseTheme.cellFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityLabel(label)
    }

    private var skipButton: some View {
        Button(action: onSkip) {
            Text("Skip")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PulseTheme.onGreen)
                .frame(width: 58, height: 44)
                .background(PulseTheme.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityHint("Skips the rest timer")
    }

    private var dismissButton: some View {
        Button(action: onSkip) {
            Text("Dismiss")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PulseTheme.onGreen)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(PulseTheme.green, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PulsePlainButtonStyle())
    }

    // MARK: Reps left

    private var rirBinding: Binding<Int> {
        Binding<Int>(
            get: { dock.rirSelection ?? -1 },
            set: { newValue in onSelectRIR(newValue) }
        )
    }

    private var rirRow: some View {
        HStack(spacing: 8) {
            Text("Reps left")
                .font(.system(size: 12))
                .foregroundStyle(PulseTheme.inkSecondary)
                .frame(width: 54, alignment: .leading)
            PulseSegmented(options: RestDockView.rirOptions, selection: rirBinding)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Reps in reserve")
        }
    }
}
#endif
