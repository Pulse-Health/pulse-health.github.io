#if os(iOS)
import SwiftUI
import Foundation
import PulseStrengthCore

/// The green "Coach · ..." suggestion block at the bottom of the exercise card
/// (Active.dc.html: 8 pt / 10 pt padding, 10 pt radius, 8 % green wash, 18 pt head icon, 13 pt text).
struct CoachTipView: View {
    let text: String

    /// The 13 pt tip text, its 18 pt icon (the stroke follows the icon) grow with Dynamic Type; both equal the design at the default size.
    @PulseScaled(13, relativeTo: .footnote) private var textSize: CGFloat
    @PulseScaled(18, relativeTo: .footnote) private var iconSize: CGFloat

    init(text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
            tipText
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            PulseTheme.coachTipFill,
            in: RoundedRectangle(cornerRadius: PulseTheme.rowRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        ExerciseCardCoachIcon()
            .stroke(
                PulseTheme.green,
                style: StrokeStyle(lineWidth: 1.9 * iconSize / 24, lineCap: .round, lineJoin: .round)
            )
            .frame(width: iconSize, height: iconSize)
            .padding(.top, 1)
            .accessibilityHidden(true)
    }

    private var tipText: some View {
        let label: Text = Text("Coach · ").fontWeight(.semibold) + Text(verbatim: text)
        return label
            .font(.system(size: textSize))
            .foregroundStyle(PulseTheme.ink)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Icon

/// The "coach" glyph of the design: a head profile with a question mark, drawn in the design's
/// 24 x 24 coordinate space and scaled into the proposed rectangle.
private struct ExerciseCardCoachIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()

        // Head outline.
        let top = CGPoint(x: 13, y: 3.2)
        let leftTemple = CGPoint(x: 5.2, y: 9.8)
        p.move(to: top)
        p.addSmallArc(from: top, to: leftTemple, radius: 7, positiveSweep: false)
        p.addCurve(
            to: CGPoint(x: 6.5, y: 14),
            control1: CGPoint(x: 5.1, y: 11.4),
            control2: CGPoint(x: 5.6, y: 12.8)
        )
        p.addLine(to: CGPoint(x: 6.5, y: 21))
        p.addLine(to: CGPoint(x: 13, y: 21))
        p.addLine(to: CGPoint(x: 13, y: 18.4))
        p.addLine(to: CGPoint(x: 15.3, y: 18.4))
        let chinStart = CGPoint(x: 15.3, y: 18.4)
        let chinEnd = CGPoint(x: 17.3, y: 16.4)
        p.addSmallArc(from: chinStart, to: chinEnd, radius: 2, positiveSweep: false)
        p.addLine(to: CGPoint(x: 17.3, y: 14.1))
        p.addLine(to: CGPoint(x: 19.2, y: 13.5))
        let nose = CGPoint(x: 17.6, y: 10.3)
        p.addLine(to: nose)
        p.addSmallArc(from: nose, to: top, radius: 7, positiveSweep: false)
        p.closeSubpath()

        // Question mark hook.
        p.move(to: CGPoint(x: 10, y: 9.6))
        p.addCurve(
            to: CGPoint(x: 12.4, y: 7.6),
            control1: CGPoint(x: 10.2, y: 8.4),
            control2: CGPoint(x: 11.2, y: 7.6)
        )
        p.addCurve(
            to: CGPoint(x: 14.8, y: 9.9),
            control1: CGPoint(x: 13.7, y: 7.6),
            control2: CGPoint(x: 14.8, y: 8.6)
        )
        p.addCurve(
            to: CGPoint(x: 13.5, y: 11.9),
            control1: CGPoint(x: 14.8, y: 10.8),
            control2: CGPoint(x: 14.3, y: 11.5)
        )

        // Question mark dot.
        p.move(to: CGPoint(x: 11.5, y: 13.5))
        p.addLine(to: CGPoint(x: 13, y: 13.5))

        let scale = min(rect.width, rect.height) / 24
        return p
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

private extension Path {
    /// A circular arc of at most 180 degrees from `start` to `end`, with the SVG sweep convention
    /// (`positiveSweep` = increasing angle in the y-down coordinate space = clockwise on screen).
    /// Appended as cubic segments, so no platform-specific arc direction semantics are involved.
    mutating func addSmallArc(from start: CGPoint, to end: CGPoint, radius: CGFloat, positiveSweep: Bool) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let chord = (dx * dx + dy * dy).squareRoot()
        guard chord > 0 else { return }
        let half = chord / 2
        let height = max(0, radius * radius - half * half).squareRoot()
        let sign: CGFloat = positiveSweep ? 1 : -1
        let centerX: CGFloat = (start.x + end.x) / 2 + sign * (-dy / chord) * height
        let centerY: CGFloat = (start.y + end.y) / 2 + sign * (dx / chord) * height

        let startAngle: Double = atan2(Double(start.y - centerY), Double(start.x - centerX))
        var endAngle: Double = atan2(Double(end.y - centerY), Double(end.x - centerX))
        if positiveSweep {
            while endAngle < startAngle { endAngle += 2 * Double.pi }
        } else {
            while endAngle > startAngle { endAngle -= 2 * Double.pi }
        }

        let total: Double = endAngle - startAngle
        let steps: Int = max(1, Int((abs(total) / (Double.pi / 2)).rounded(.up)))
        let delta: Double = total / Double(steps)
        let handle: CGFloat = CGFloat(4.0 / 3.0 * tan(delta / 4.0)) * radius

        var angle: Double = startAngle
        for _ in 0..<steps {
            let next: Double = angle + delta
            let sinA = CGFloat(sin(angle))
            let cosA = CGFloat(cos(angle))
            let sinB = CGFloat(sin(next))
            let cosB = CGFloat(cos(next))
            let p0 = CGPoint(x: centerX + radius * cosA, y: centerY + radius * sinA)
            let p1 = CGPoint(x: centerX + radius * cosB, y: centerY + radius * sinB)
            let c1 = CGPoint(x: p0.x - handle * sinA, y: p0.y + handle * cosA)
            let c2 = CGPoint(x: p1.x + handle * sinB, y: p1.y - handle * cosB)
            addCurve(to: p1, control1: c1, control2: c2)
            angle = next
        }
    }
}
#endif
