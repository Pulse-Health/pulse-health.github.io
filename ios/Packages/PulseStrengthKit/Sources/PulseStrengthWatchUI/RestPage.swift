#if os(watchOS)
import SwiftUI
import PulseStrengthCore

// MARK: - Ring

/// The draining rest ring with the countdown in its centre (design: 158 pt ring, 14 pt stroke, 46 pt numerals).
private struct RestRing: View {
    /// Share of the ring that is filled, 0...1.
    let fraction: Double
    let centerText: String
    let tint: Color
    let track: Color
    let textColor: Color
    /// Smooths the one-second steps of the periodic timeline.
    let animated: Bool

    private var fillAnimation: Animation? {
        animated ? Animation.linear(duration: 1) : nil
    }

    var body: some View {
        GeometryReader { proxy in
            ring(diameter: min(proxy.size.width, proxy.size.height, 130))
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func ring(diameter: CGFloat) -> some View {
        let line = diameter * (14.0 / 158.0)
        return ZStack {
            Circle()
                .stroke(track, lineWidth: line)
            if fraction > 0.002 {
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(fillAnimation, value: fraction)
            }
            Text(centerText)
                .font(WatchFont.number(diameter * 0.29, .bold))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, line * 1.2)
        }
        .padding(line / 2)
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Page

/// "Rest": draining ring with the countdown (frozen while paused), the next set, and -15 / skip / +15.
@MainActor
struct RestPage: View {
    @ObservedObject var controller: WorkoutController
    let snapshot: WorkoutSnapshot
    let date: Date

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: WatchPalette { WatchPalette(reduced: isLuminanceReduced) }

    // MARK: Derived values

    /// Seconds left (nil without a rest).
    private var remaining: TimeInterval? {
        WatchFormat.restRemaining(snapshot, at: date)
    }

    private var hasRest: Bool { remaining != nil }

    private var isOver: Bool {
        guard let remaining else { return false }
        return remaining <= 0
    }

    private var wholeSeconds: Int {
        guard let remaining else { return 0 }
        return WatchFormat.wholeSeconds(remaining)
    }

    private var countdownText: String {
        if isOver { return "Go" }
        return WatchFormat.countdownText(wholeSeconds, coarse: isLuminanceReduced)
    }

    private var countdownColor: Color {
        if !hasRest || snapshot.isPaused { return palette.secondary }
        return palette.primary
    }

    private var ringAnimated: Bool {
        !reduceMotion && !isLuminanceReduced && !snapshot.isPaused
    }

    private var titleText: String {
        snapshot.isPaused ? "Paused" : "Rest"
    }

    private var titleColor: Color {
        snapshot.isPaused ? palette.time : palette.accent
    }

    private var isComplete: Bool { snapshot.phase == .complete }

    private var nextText: String {
        isComplete ? "All sets logged" : "Next · " + WatchFormat.workText(snapshot)
    }

    /// The exercise changes with the next set (a new exercise, or the other half of a superset): name it.
    private var upcomingExerciseName: String? {
        guard !isComplete, !snapshot.exerciseName.isEmpty else { return nil }
        guard let lastLogged = controller.state?.lastLogged else { return nil }
        guard lastLogged.exerciseID != snapshot.targetExerciseID else { return nil }
        return snapshot.exerciseName
    }

    private var ringSpokenValue: String {
        if !hasRest { return "No rest running" }
        if isOver { return "Rest is over" }
        return WatchFormat.spoken(seconds: wholeSeconds) + " remaining"
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 6) {
            Text(titleText)
                .font(WatchFont.text(14, .semibold))
                .foregroundStyle(titleColor)
                .lineLimit(1)
            RestRing(
                fraction: WatchFormat.restFraction(snapshot, remaining: remaining),
                centerText: countdownText,
                tint: palette.accent,
                track: palette.accentTrack,
                textColor: countdownColor,
                animated: ringAnimated
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest timer")
            .accessibilityValue(ringSpokenValue)
            nextBlock
            buttonRow
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nextBlock: some View {
        VStack(spacing: 1) {
            Text(nextText)
                .font(WatchFont.text(12.5, .regular))
                .foregroundStyle(palette.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let name = upcomingExerciseName {
                Text(name)
                    .font(WatchFont.text(11, .regular))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    // MARK: Buttons

    private var buttonRow: some View {
        HStack(spacing: 10) {
            adjustButton(title: "−15", spoken: "Subtract 15 seconds", seconds: -15)
            skipButton
            adjustButton(title: "+15", spoken: "Add 15 seconds", seconds: 15)
        }
    }

    private func adjustButton(title: String, spoken: String, seconds: Int) -> some View {
        // Taking 15 seconds off needs a running rest; adding 15 seconds also starts one.
        let enabled = seconds > 0 || hasRest
        return Button(action: { adjustRest(seconds) }) {
            Text(title)
                .font(WatchFont.number(13, .semibold))
                .foregroundStyle(palette.primary)
        }
        .buttonStyle(WatchCircleButtonStyle(fill: palette.controlFill, diameter: 40))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(spoken)
    }

    private var skipButton: some View {
        Button(action: { skipRest() }) {
            Image(systemName: "forward.end.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isLuminanceReduced ? palette.accent : palette.onAccent)
        }
        .buttonStyle(WatchCircleButtonStyle(fill: isLuminanceReduced ? palette.accentTrack : WatchTheme.green, diameter: 40))
        .disabled(!hasRest)
        .opacity(hasRest ? 1 : 0.4)
        .accessibilityLabel("Skip rest")
    }

    // MARK: Actions

    private func adjustRest(_ seconds: Int) {
        controller.send(.adjustRest(seconds: seconds), origin: .watch)
        WatchHaptics.click()
    }

    private func skipRest() {
        controller.send(.skipRest, origin: .watch)
        WatchHaptics.click()
    }
}
#endif
