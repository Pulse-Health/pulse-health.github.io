#if os(iOS)
import SwiftUI
import PulseStrengthCore

// MARK: - Dumbbell glyph

/// The dumbbell icon of the design (24 x 24 grid, round caps), drawn as a shape so it can be stroked at any size.
struct StrengthDumbbellShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let originX = rect.midX - 12 * scale
        let originY = rect.midY - 12 * scale
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }
        var path = Path()
        // Plates (inner pair, then outer pair) and the bar.
        path.move(to: point(6.5, 7))
        path.addLine(to: point(6.5, 17))
        path.move(to: point(17.5, 7))
        path.addLine(to: point(17.5, 17))
        path.move(to: point(3.5, 9.5))
        path.addLine(to: point(3.5, 14.5))
        path.move(to: point(20.5, 9.5))
        path.addLine(to: point(20.5, 14.5))
        path.move(to: point(6.5, 12))
        path.addLine(to: point(17.5, 12))
        return path
    }
}

/// The dumbbell icon at a given size. `strokeWidth` is in the design's 24 pt grid (the design uses 2 to 2.2).
struct StrengthDumbbellGlyph: View {
    let size: CGFloat
    let color: Color
    let strokeWidth: CGFloat

    init(size: CGFloat, color: Color, strokeWidth: CGFloat = 2) {
        self.size = size
        self.color = color
        self.strokeWidth = strokeWidth
    }

    var body: some View {
        StrengthDumbbellShape()
            .stroke(color, style: StrokeStyle(lineWidth: strokeWidth * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Bar

/// The floating "workout in progress" bar shown while a workout runs and its screen is minimised
/// (design: the Strength hub with a running workout). It only renders the presentation it is given;
/// the owner redraws it every second so the clock keeps running.
@MainActor
public struct WorkoutInProgressBar: View {
    private let presentation: ActiveWorkoutPresentation
    private let onResume: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(presentation: ActiveWorkoutPresentation, onResume: @escaping () -> Void) {
        self.presentation = presentation
        self.onResume = onResume
    }

    public var body: some View {
        Button(action: onResume) {
            content
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityLabel("Resume workout in progress")
        .accessibilityValue(presentation.header.title + ", " + subtitle)
    }

    // MARK: Content

    private var content: some View {
        HStack(spacing: 12) {
            WorkoutBarBadge(isAnimated: !reduceMotion)
            labels
            resumePill
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 64)
        .background(barBackground)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(presentation.header.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PulseTheme.ink)
                .lineLimit(1)
            Text(subtitle)
                .font(PulseFont.number(12, .regular))
                .monospacedDigit()
                .foregroundStyle(PulseTheme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resumePill: some View {
        Text("Resume")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(PulseTheme.onGreen)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(PulseTheme.green, in: Capsule())
    }

    private var barBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(PulseTheme.card.opacity(0.97))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.05, darkAlpha: 0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 15, x: 0, y: 10)
            .shadow(color: Color.black.opacity(0.06), radius: 1.5, x: 0, y: 1)
    }

    /// "Exercise 1 of 6 · 24:18 · 7 of 19 sets" (no exercise part for an empty workout; the clock reads
    /// "Paused · 24:18" while paused).
    private var subtitle: String {
        var parts: [String] = []
        if let navigator = presentation.navigator {
            parts.append("Exercise \(navigator.position) of \(navigator.total)")
        }
        parts.append(presentation.header.clockText)
        parts.append(presentation.header.setsText + " sets")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Badge

/// The 40 pt green circle with the dumbbell, which beats like the heart icon of the design
/// (1.2 s loop, scale 1 -> 1.25 -> 1 in the first 30 %). Static with Reduce Motion.
private struct WorkoutBarBadge: View {
    let isAnimated: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(light: 0x1B8448, dark: 0x30D158, lightAlpha: 0.12, darkAlpha: 0.20))
            glyph
        }
        .frame(width: 40, height: 40)
    }

    @ViewBuilder
    private var glyph: some View {
        if isAnimated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                StrengthDumbbellGlyph(size: 20, color: PulseTheme.green, strokeWidth: 2.2)
                    .scaleEffect(WorkoutBarBeat.scale(at: context.date))
            }
        } else {
            StrengthDumbbellGlyph(size: 20, color: PulseTheme.green, strokeWidth: 2.2)
        }
    }
}

private enum WorkoutBarBeat {
    static let period: Double = 1.2

    static func scale(at date: Date) -> CGFloat {
        let seconds = date.timeIntervalSinceReferenceDate
        let phase = seconds.truncatingRemainder(dividingBy: period) / period
        if phase < 0.15 {
            return 1 + 0.25 * ease(phase / 0.15)
        }
        if phase < 0.30 {
            return 1 + 0.25 * (1 - ease((phase - 0.15) / 0.15))
        }
        return 1
    }

    /// Smooth ease-in-out between 0 and 1.
    private static func ease(_ t: Double) -> CGFloat {
        CGFloat(t * t * (3 - 2 * t))
    }
}
#endif
