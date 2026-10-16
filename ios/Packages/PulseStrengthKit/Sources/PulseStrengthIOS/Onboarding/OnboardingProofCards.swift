#if os(iOS)
import SwiftUI
import PulseStrengthCore

// The three previews under the highlights of the welcome screen. They are drawn from the same pieces as the real screens (the readiness
// ring and muscle chips of the hub, the rest dock with live heart rate, a personal-record pill), so the welcome screen shows what the
// app looks like. Decorative: hidden from VoiceOver, and they do not follow Dynamic Type (the card is a fixed 112 pt).

/// A ring that fills from the top. When `isActive` turns true it grows in again.
@MainActor
private struct OnboardingRing: View {
    let progress: Double
    let color: Color
    let size: CGFloat
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = true

    var body: some View {
        let lineWidth = size * 5 / 48
        ZStack {
            Circle().stroke(OnboardingTheme.progressTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown ? CGFloat(min(max(progress, 0.0001), 1)) : 0.0001)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .task(id: isActive) {
            guard isActive, !reduceMotion else {
                shown = true
                return
            }
            shown = false
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(Animation.easeOut(duration: 1.1).delay(0.15)) {
                shown = true
            }
        }
    }
}

/// The small rounded button of the rest dock ("−15", "+15", "Skip").
private struct OnboardingMiniButton: View {
    let text: String
    var isGreen = false

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isGreen ? OnboardingTheme.green : Color.white)
            .padding(.horizontal, 10)
            .frame(minWidth: 40, minHeight: 34)
            .background(OnboardingTheme.chipFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Today's plan

/// "Today · Recommended / Upper Body A", three muscle groups with their recovery colour and the readiness ring.
@MainActor
struct OnboardingPlanCard: View {
    let copy: OnboardingCopy
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(copy.text(.previewPlanEyebrow))
                    .font(.system(size: 13))
                    .foregroundStyle(OnboardingTheme.inkSecondary)
                    .lineLimit(1)
                Text(copy.text(.previewPlanTitle))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .padding(.top, 2)
                HStack(spacing: 6) {
                    chip(copy.text(.previewPlanChest), OnboardingTheme.recoveryGood)
                    chip(copy.text(.previewPlanBack), OnboardingTheme.recoveryFair)
                    chip(copy.text(.previewPlanArms), OnboardingTheme.recoveryGood)
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 3) {
                ZStack {
                    OnboardingRing(progress: 0.82, color: OnboardingTheme.recoveryGood, size: 54, isActive: isActive)
                    Text("82")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                }
                Text(copy.text(.previewPlanReadiness))
                    .font(.system(size: 11))
                    .foregroundStyle(OnboardingTheme.inkSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .onboardingGlass()
    }

    private func chip(_ text: String, _ dot: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(OnboardingTheme.chipFill, in: Capsule())
    }
}

// MARK: - Rest dock with heart rate

/// The rest timer counting down while its highlight is on screen, with the live heart rate under it.
@MainActor
struct OnboardingRestCard: View {
    let copy: OnboardingCopy
    let isActive: Bool
    /// False while the user paused the motion.
    let isAnimating: Bool

    @State private var secondsLeft = OnboardingRestCard.startSeconds

    private static let startSeconds = 84
    private static let totalSeconds = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    OnboardingRing(
                        progress: Double(secondsLeft) / Double(OnboardingRestCard.totalSeconds),
                        color: OnboardingTheme.recoveryGood,
                        size: 46,
                        isActive: isActive
                    )
                    Image(systemName: "timer")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.recoveryGood)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(copy.text(.previewRestLabel))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.inkSecondary)
                    Text(clock)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    OnboardingMiniButton(text: "−15")
                    OnboardingMiniButton(text: "+15")
                    OnboardingMiniButton(text: copy.text(.previewRestSkip), isGreen: true)
                }
            }
            heartRateLine
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .onboardingGlass()
        .task(id: isActive && isAnimating) {
            if !isActive {
                secondsLeft = OnboardingRestCard.startSeconds
            }
            guard isActive, isAnimating else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                secondsLeft = max(0, secondsLeft - 1)
            }
        }
    }

    private var clock: String {
        String(format: "%d:%02d", secondsLeft / 60, secondsLeft % 60)
    }

    private var heartRateLine: some View {
        HStack(spacing: 5) {
            OnboardingHeartbeat(isAnimating: isActive && isAnimating)
            Text("142")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white)
            Text(copy.text(.previewRestBpm))
            Text("·").opacity(0.6)
            Text(copy.text(.previewRestMeta)).lineLimit(1)
        }
        .font(.system(size: 12))
        .foregroundStyle(OnboardingTheme.inkSecondary)
        .lineLimit(1)
    }
}

/// A heart that beats twice a second-ish while the preview is on screen.
private struct OnboardingHeartbeat: View {
    let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating || reduceMotion)) { context in
            Image(systemName: "heart.fill")
                .font(.system(size: 12))
                .foregroundStyle(OnboardingTheme.heart)
                .scaleEffect(scale(at: context.date))
        }
    }

    /// Two beats of 0.31 s (a big one and a smaller one) every 1.1 s, the rest of the time at rest.
    private func scale(at date: Date) -> CGFloat {
        if reduceMotion || !isAnimating { return 1 }
        let period = 1.1
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        func bump(from start: Double, amount: Double) -> Double {
            guard phase >= start && phase < start + 0.28 else { return 0 }
            return amount * sin((phase - start) / 0.28 * Double.pi)
        }
        return CGFloat(1 + bump(from: 0, amount: 0.22) + bump(from: 0.28, amount: 0.14))
    }
}

// MARK: - Personal record

/// The "New PR" pill with the lift and a sparkline that draws itself.
@MainActor
struct OnboardingRecordCard: View {
    let copy: OnboardingCopy
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = true

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "trophy.fill").font(.system(size: 11, weight: .bold))
                    Text(copy.text(.previewRecordPill)).font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(OnboardingTheme.prText)
                .padding(.leading, 7)
                .padding(.trailing, 9)
                .padding(.vertical, 3)
                .background(OnboardingTheme.prFill, in: Capsule())
                Text(copy.text(.previewRecordTitle))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .padding(.top, 8)
                Text(copy.text(.previewRecordMeta))
                    .font(.system(size: 13, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(OnboardingTheme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            OnboardingSparkline(drawn: drawn)
                .frame(width: 100, height: 52)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .onboardingGlass()
        .task(id: isActive) {
            guard isActive, !reduceMotion else {
                drawn = true
                return
            }
            drawn = false
            try? await Task.sleep(nanoseconds: 60_000_000)
            withAnimation(Animation.easeOut(duration: 1.1).delay(0.2)) {
                drawn = true
            }
        }
    }
}

/// A rising line chart on a 100 x 52 grid: the line draws itself, the area under it fades in, the last point pops.
private struct OnboardingSparkline: View {
    let drawn: Bool

    private static let points: [CGPoint] = [
        CGPoint(x: 2, y: 44), CGPoint(x: 18, y: 38), CGPoint(x: 34, y: 40), CGPoint(x: 50, y: 30),
        CGPoint(x: 66, y: 31), CGPoint(x: 82, y: 18), CGPoint(x: 96, y: 8),
    ]

    var body: some View {
        ZStack {
            SparkArea(points: OnboardingSparkline.points)
                .fill(
                    LinearGradient(
                        colors: [OnboardingTheme.green.opacity(0.35), OnboardingTheme.green.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(drawn ? 1 : 0)
                .animation(Animation.easeOut(duration: 0.8).delay(0.6), value: drawn)
            SparkLine(points: OnboardingSparkline.points)
                .trim(from: 0, to: drawn ? 1 : 0.0001)
                .stroke(OnboardingTheme.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .animation(Animation.easeOut(duration: 1.1).delay(0.2), value: drawn)
            Circle()
                .fill(OnboardingTheme.green)
                .frame(width: 7, height: 7)
                .scaleEffect(drawn ? 1 : 0.0001)
                .animation(Animation.spring(response: 0.45, dampingFraction: 0.6).delay(0.95), value: drawn)
                .position(x: 96, y: 8)
        }
        .frame(width: 100, height: 52)
    }
}

private struct SparkLine: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

private struct SparkArea: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: last.x, y: 52))
        path.addLine(to: CGPoint(x: first.x, y: 52))
        path.closeSubpath()
        return path
    }
}
#endif
