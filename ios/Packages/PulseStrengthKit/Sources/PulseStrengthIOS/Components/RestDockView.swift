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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Design sizes that grow with Dynamic Type; each equals the design value at the default size.
    /// The big countdown figures (30 pt rounded).
    @PulseScaled(30, relativeTo: .largeTitle) private var countdownSize: CGFloat
    /// The "-15" / "+15" / "Skip" label size, and the widths of the two fixed-width buttons.
    @PulseScaled(15, relativeTo: .subheadline) private var buttonTextSize: CGFloat
    @PulseScaled(46, relativeTo: .subheadline) private var adjustWidth: CGFloat
    @PulseScaled(58, relativeTo: .subheadline) private var skipWidth: CGFloat
    /// The ring: 44 pt circle inside a 52 pt frame (it grows with the countdown figures it sits next to).
    @PulseScaled(44, relativeTo: .largeTitle) private var ringDiameter: CGFloat
    @PulseScaled(52, relativeTo: .largeTitle) private var ringFrame: CGFloat
    /// Width of the "Reps left" caption (54 pt).
    @PulseScaled(54, relativeTo: .footnote) private var repsLabelWidth: CGFloat

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
            mainRows
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
    /// The design's plate is 97 % opaque (rgba(255,255,255,0.97)), like the in-progress bar.
    private var dockBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(PulseTheme.card.opacity(0.97))
                .shadow(color: Color.black.opacity(0.12), radius: 15, x: 0, y: 10)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(PulseTheme.card.opacity(0.97))
                .shadow(color: Color.black.opacity(0.06), radius: 1.5, x: 0, y: 1)
        }
    }

    // MARK: Main rows

    /// The design: countdown block and buttons on one line. With bigger text the line may be too narrow for both
    /// (the buttons grow with the text): then the buttons move under the countdown and share the full width.
    /// At the default size and below the single line is always used.
    @ViewBuilder
    private var mainRows: some View {
        if dynamicTypeSize > .large {
            ViewThatFits(in: .horizontal) {
                singleRow
                stackedRows
            }
        } else {
            singleRow
        }
    }

    private var singleRow: some View {
        HStack(spacing: 12) {
            countdownBlock
            if isFinished {
                dismissButton(fills: false)
            } else {
                adjustButtons(fills: false)
            }
        }
    }

    private var stackedRows: some View {
        VStack(spacing: 10) {
            countdownBlock
            if isFinished {
                dismissButton(fills: true)
            } else {
                adjustButtons(fills: true)
            }
        }
    }

    // MARK: Ring and countdown

    private var countdownBlock: some View {
        HStack(spacing: 12) {
            ring
            VStack(alignment: .leading, spacing: 0) {
                Text(labelText)
                    .pulseFont(12, .semibold, relativeTo: .footnote)
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                Text(dock.remainingText)
                    .font(PulseFont.number(countdownSize, .bold))
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
                .pulseFont(18, .semibold, relativeTo: .largeTitle)
                .foregroundStyle(ringColor)
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .frame(width: ringFrame, height: ringFrame)
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

    /// `fills`: the buttons share the full width of their own line (stacked layout); otherwise they keep the design's
    /// widths (46 / 46 / 58 pt, scaled with the text).
    private func adjustButtons(fills: Bool) -> some View {
        HStack(spacing: 6) {
            adjustButton(title: "\u{2212}15", seconds: -15, label: "Subtract 15 seconds", fills: fills)
            adjustButton(title: "+15", seconds: 15, label: "Add 15 seconds", fills: fills)
            skipButton(fills: fills)
        }
    }

    /// The 44 pt tall (scaled) box of a dock button: a fixed width, or the full width of the line.
    @ViewBuilder
    private func buttonBox<Content: View>(_ content: Content, width: CGFloat?, fills: Bool) -> some View {
        if fills {
            content
                .frame(maxWidth: .infinity)
                .pulseScaledFrame(minHeight: 44, relativeTo: PulseDynamicType.controlHeightStyle)
        } else if let width = width {
            content
                .frame(width: width)
                .pulseScaledFrame(minHeight: 44, relativeTo: PulseDynamicType.controlHeightStyle)
        } else {
            content
                .pulseScaledFrame(minHeight: 44, relativeTo: PulseDynamicType.controlHeightStyle)
        }
    }

    private func adjustButton(title: String, seconds: Int, label: String, fills: Bool) -> some View {
        Button {
            onAdjust(seconds)
        } label: {
            buttonBox(
                Text(title)
                    .font(PulseFont.number(buttonTextSize, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(PulseTheme.ink),
                width: max(46, adjustWidth),
                fills: fills
            )
            .background(PulseTheme.cellFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityLabel(label)
    }

    private func skipButton(fills: Bool) -> some View {
        Button(action: onSkip) {
            buttonBox(
                Text("Skip")
                    .pulseFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.onGreen),
                width: max(58, skipWidth),
                fills: fills
            )
            .background(PulseTheme.green, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityHint("Skips the rest timer")
    }

    private func dismissButton(fills: Bool) -> some View {
        Button(action: onSkip) {
            buttonBox(
                Text("Dismiss")
                    .pulseFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(PulseTheme.onGreen)
                    .padding(.horizontal, 16),
                width: nil,
                fills: fills
            )
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
                .pulseFont(12, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
                .lineLimit(1)
                .pulseShrinkWhenLarger(0.8)
                .frame(width: repsLabelWidth, alignment: .leading)
            PulseSegmented(options: RestDockView.rirOptions, selection: rirBinding)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Reps in reserve")
        }
    }
}
#endif
