#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

// MARK: - Palette

/// The colours of the finish celebration. They are the same in light and dark mode: white text sits on the deep green.
private enum SummaryCelebrationPalette {
    static let backdropCenter = Color(light: 0x25814D, dark: 0x25814D)
    static let backdrop = Color(light: 0x0F5C33, dark: 0x0F5C33)
    static let backdropEdge = Color(light: 0x0B4426, dark: 0x0B4426)
    /// The ring around the medal and the soft light behind it (the design's light green).
    static let ring = PulseTheme.toastAction
    static let check = Color(light: 0x187A42, dark: 0x187A42)
    static let star = Color(light: 0xFFF1A8, dark: 0xFFF1A8)
    /// One entry per `ConfettiPiece.colorIndex`.
    static let confetti: [Color] = ([0x30D158, 0x7BE495, 0xFFD60A, 0xFFFFFF, 0xFF9F0A, 0x64D2FF] as [UInt32]).map { (hex: UInt32) -> Color in
        Color(light: hex, dark: hex)
    }
}

// MARK: - Backdrop

/// The green behind the celebration. While the stats sheet comes up it gives way to the plain screen background, so the sheet's
/// rounded top corners and the strip behind the status bar do not show green on the stats page.
struct WorkoutSummaryBackdrop: View {
    /// 0 over the celebration, 1 once the sheet has come all the way up.
    let scrollProgress: Double

    var body: some View {
        ZStack {
            PulseTheme.ground
            RadialGradient(
                gradient: Gradient(stops: [
                    Gradient.Stop(color: SummaryCelebrationPalette.backdropCenter, location: 0),
                    Gradient.Stop(color: SummaryCelebrationPalette.backdrop, location: 0.6),
                    Gradient.Stop(color: SummaryCelebrationPalette.backdropEdge, location: 1),
                ]),
                center: UnitPoint(x: 0.5, y: 0.26),
                startRadius: 0,
                endRadius: 640
            )
            .opacity(SummaryCelebration.backdropOpacity(scrollProgress: scrollProgress))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - The celebration

/// The celebration at the top of the summary: a medal that springs in while its ring and check draw themselves, ripples, sparks and
/// confetti at the impact, the title, and the three big figures counting up. The scene is a pure function of the time since it began
/// (`SummaryCelebration` holds the curves), drawn by a `TimelineView` for the few seconds the motion lasts; with Reduce Motion, and
/// once the motion is over, it is the finished picture.
///
/// VoiceOver gets the title and the three final figures, never the numbers while they count and never the decoration.
@MainActor
struct WorkoutSummaryHero: View {
    let subtitle: String
    let figures: SummaryFigures
    /// What VoiceOver reads as the duration and the volume ("1 hour 15 minutes", "5,064 kilograms").
    let spokenDuration: String
    let spokenVolume: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var settled = false

    /// Room kept free at the bottom for the scroll cue.
    static let cueReserve: CGFloat = 84

    var body: some View {
        Group {
            if reduceMotion || settled {
                scene(at: SummaryCelebration.settleTime + 1)
            } else {
                TimelineView(.animation) { context in
                    scene(at: context.date.timeIntervalSince(start) - SummaryCelebration.appearDelay)
                }
            }
        }
        .dynamicTypeSize(PulseDynamicType.activeWorkoutRange)
        .task {
            await settleWhenDone()
        }
    }

    /// Stops the timeline once nothing moves any more (the last confetti piece is gone), so the screen is not redrawn for nothing.
    private func settleWhenDone() async {
        guard !reduceMotion else { return }
        let seconds = SummaryCelebration.settleTime + SummaryCelebration.appearDelay + 0.2
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        if !Task.isCancelled {
            settled = true
        }
    }

    // MARK: Scene

    private func scene(at t: TimeInterval) -> some View {
        GeometryReader { proxy in
            let medal = min(168, max(104, proxy.size.height * 0.2))
            VStack(spacing: 0) {
                Spacer(minLength: 12)
                SummaryMedal(size: medal, t: t)
                    .anchorPreference(key: SummaryMedalCenterKey.self, value: .center) { (anchor: Anchor<CGPoint>) -> Anchor<CGPoint>? in
                        anchor
                    }
                titleBlock(at: t)
                    .padding(.top, 10)
                subtitleLine(at: t)
                    .padding(.top, 10)
                figuresPanel(at: t)
                    .padding(.top, 28)
                Spacer(minLength: 12)
                Color.clear
                    .frame(height: WorkoutSummaryHero.cueReserve)
            }
            .padding(.horizontal, 24)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlayPreferenceValue(SummaryMedalCenterKey.self) { (anchor: Anchor<CGPoint>?) in
                GeometryReader { overlay in
                    SummaryConfetti(
                        t: t,
                        burstOrigin: anchor.map { (point: Anchor<CGPoint>) -> CGPoint in overlay[point] }
                            ?? CGPoint(x: overlay.size.width / 2, y: overlay.size.height * 0.3)
                    )
                    .frame(width: overlay.size.width, height: overlay.size.height)
                }
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: Title

    private func titleBlock(at t: TimeInterval) -> some View {
        VStack(spacing: 0) {
            titleLine("Workout", index: 0, at: t)
            titleLine("Complete", index: 1, at: t)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout Complete")
        .accessibilityAddTraits(.isHeader)
    }

    private func titleLine(_ text: LocalizedStringKey, index: Int, at t: TimeInterval) -> some View {
        let rise = SummaryCelebration.rise(
            at: t,
            start: SummaryCelebration.titleStart + SummaryCelebration.titleStagger * Double(index)
        )
        return Text(text)
            .tracking(-0.8)
            .pulseFont(40, .heavy, relativeTo: .largeTitle)
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .scaleEffect(CGFloat(0.94 + 0.06 * rise))
            .offset(y: CGFloat(1 - rise) * 28)
            .opacity(min(1, rise))
    }

    private func subtitleLine(at t: TimeInterval) -> some View {
        Text(verbatim: subtitle)
            .pulseFont(17, relativeTo: .body)
            .foregroundStyle(Color.white.opacity(0.84))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(SummaryCelebration.fade(at: t, start: SummaryCelebration.subtitleStart))
    }

    // MARK: Figures

    private func figuresPanel(at t: TimeInterval) -> some View {
        let counted = SummaryCelebration.countProgress(at: t)
        let panel = SummaryCelebration.fade(at: t, start: SummaryCelebration.panelStart, duration: 0.8)
        let totals = figures.counted
        return HStack(spacing: 0) {
            figureColumn(
                title: "Duration",
                now: figures.duration(at: counted),
                finished: totals.duration,
                spoken: spokenDuration,
                index: 0,
                at: t
            )
            figureColumn(
                title: "Volume",
                now: figures.volume(at: counted),
                finished: totals.volume,
                spoken: spokenVolume,
                index: 1,
                at: t
            )
            figureColumn(
                title: "Sets",
                now: figures.setCount(at: counted),
                finished: totals.sets,
                spoken: totals.sets.value,
                index: 2,
                at: t
            )
        }
        .padding(.vertical, 18)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: PulseTheme.cardRadius, style: .continuous))
        .offset(y: CGFloat(1 - panel) * 26)
        .opacity(panel)
    }

    /// One figure: the number counting up (the finished number sits invisible behind it, so the column keeps its width and the
    /// digits grow leftwards like an odometer), its unit and its title.
    private func figureColumn(
        title: String,
        now: SummaryFigures.Figure,
        finished: SummaryFigures.Figure,
        spoken: String,
        index: Int,
        at t: TimeInterval
    ) -> some View {
        let rise = SummaryCelebration.rise(
            at: t,
            start: SummaryCelebration.figureStart + SummaryCelebration.figureStagger * Double(index)
        )
        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                ZStack(alignment: .trailing) {
                    Text(verbatim: finished.value)
                        .opacity(0)
                    Text(verbatim: now.value)
                }
                .pulseNumber(28, .bold, relativeTo: .title)
                if !finished.unit.isEmpty {
                    Text(verbatim: finished.unit)
                        .pulseFont(15, .semibold, relativeTo: .subheadline)
                }
            }
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(verbatim: title)
                .pulseFont(13, relativeTo: .footnote)
                .foregroundStyle(Color.white.opacity(0.8))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            if index > 0 {
                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 0.5)
                    .padding(.vertical, 2)
            }
        }
        .offset(y: CGFloat(1 - rise) * 26)
        .opacity(min(1, rise))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(spoken)
    }
}

/// The centre of the medal, in the celebration's own space: where the first confetti bursts from.
private struct SummaryMedalCenterKey: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil

    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = nextValue() ?? value
    }
}

// MARK: - Medal

/// The medal: a white disc with a green check, a ring that draws around it, a soft light behind, and ripples and sparks at the impact.
/// `size` is the diameter of the ring; everything is scaled from the 168 pt of the design.
private struct SummaryMedal: View {
    let size: CGFloat
    let t: TimeInterval

    /// Where the stars blink, as (x, y, size) in the 208 pt box of the design, and when.
    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, delay: TimeInterval)] = [
        (6, 30, 22, 1.45),
        (178, 14, 28, 1.6),
        (190, 130, 18, 1.75),
        (-6, 150, 26, 1.55),
        (92, -14, 16, 1.85),
        (40, 196, 18, 1.95),
    ]

    var body: some View {
        let k = size / 168
        let box = size * 208 / 168
        let pose = SummaryCelebration.medalPose(at: t)
        let thump = SummaryCelebration.thumbScale(at: t)
        let glow = SummaryCelebration.glow(at: t)
        let ring = SummaryCelebration.ringProgress(at: t)
        let check = SummaryCelebration.checkProgress(at: t)
        let sparks = SummaryCelebration.sparks(at: t)

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [SummaryCelebrationPalette.ring.opacity(0.85), SummaryCelebrationPalette.ring.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.78
                    )
                )
                .frame(width: size * 1.6, height: size * 1.6)
                .scaleEffect(CGFloat(glow.scale))
                .opacity(glow.opacity)

            ripple(index: 0)
            ripple(index: 1)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 6 * k)
                    .padding(8 * k)
                Circle()
                    .trim(from: 0, to: CGFloat(ring))
                    .stroke(SummaryCelebrationPalette.ring, style: StrokeStyle(lineWidth: 6 * k, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(8 * k)
                    .opacity(ring > 0 ? 1 : 0)
                Circle()
                    .fill(Color.white)
                    .padding(22 * k)
                SummaryCheckShape()
                    .trim(from: 0, to: CGFloat(check))
                    .stroke(
                        SummaryCelebrationPalette.check,
                        style: StrokeStyle(lineWidth: 12 * k, lineCap: .round, lineJoin: .round)
                    )
                    .opacity(check > 0 ? 1 : 0)
            }
            .frame(width: size, height: size)
            .scaleEffect(CGFloat(pose.scale * thump))
            .rotationEffect(.degrees(pose.rotation))
            .opacity(pose.opacity)

            SummarySparksShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 3 * k, lineCap: .round))
                .frame(width: box, height: box)
                .scaleEffect(CGFloat(sparks.scale))
                .opacity(sparks.opacity)
        }
        .frame(width: box, height: box)
        .overlay {
            ZStack {
                ForEach(0..<SummaryMedal.stars.count, id: \.self) { (index: Int) in
                    star(index: index, box: box)
                }
            }
        }
        .background {
            SummaryRays(t: t)
        }
        .accessibilityHidden(true)
    }

    private func ripple(index: Int) -> some View {
        let burst = SummaryCelebration.ripple(at: t, index: index)
        return Circle()
            .strokeBorder(Color.white.opacity(0.6), lineWidth: 3)
            .frame(width: size, height: size)
            .scaleEffect(CGFloat(burst.scale))
            .opacity(burst.opacity)
    }

    private func star(index: Int, box: CGFloat) -> some View {
        let spec = SummaryMedal.stars[index]
        let unit = box / 208
        let twinkle = SummaryCelebration.twinkle(at: t, delay: spec.delay)
        return SummarySparkleShape()
            .fill(SummaryCelebrationPalette.star)
            .frame(width: spec.size * unit, height: spec.size * unit)
            .scaleEffect(CGFloat(twinkle.scale))
            .rotationEffect(.degrees(twinkle.rotation))
            .opacity(twinkle.opacity)
            .position(
                x: (spec.x + spec.size / 2) * unit,
                y: (spec.y + spec.size / 2) * unit
            )
    }
}

/// The sunburst behind the medal: thin wedges that fade towards the edge, turning slowly until the motion is over.
private struct SummaryRays: View {
    let t: TimeInterval

    var body: some View {
        let rays = SummaryCelebration.rays(at: t)
        return SummaryRaysShape()
            .fill(
                RadialGradient(
                    colors: [Color.white.opacity(0.11), Color.white.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 450
                )
            )
            .frame(width: 900, height: 900)
            .rotationEffect(.degrees(rays.rotation))
            .scaleEffect(CGFloat(rays.scale))
            .opacity(rays.opacity)
            .allowsHitTesting(false)
    }
}

private struct SummaryRaysShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        var angle = 0.0
        while angle < 360 {
            path.move(to: center)
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(angle),
                endAngle: .degrees(angle + 4),
                clockwise: false
            )
            path.closeSubpath()
            angle += 14
        }
        return path
    }
}

/// The check mark on a 168 x 168 grid.
private struct SummaryCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 168
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.midX + (x - 84) * scale, y: rect.midY + (y - 84) * scale)
        }
        var path = Path()
        path.move(to: point(56, 86))
        path.addLine(to: point(77, 107))
        path.addLine(to: point(114, 63))
        return path
    }
}

/// Twelve short rays around the medal, on a 208 x 208 grid.
private struct SummarySparksShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 208
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        for index in 0..<12 {
            let angle = Double(index) * Double.pi / 6
            let dx = CGFloat(cos(angle))
            let dy = CGFloat(sin(angle))
            path.move(to: CGPoint(x: center.x + dx * 90 * scale, y: center.y + dy * 90 * scale))
            path.addLine(to: CGPoint(x: center.x + dx * 102 * scale, y: center.y + dy * 102 * scale))
        }
        return path
    }
}

/// A four-pointed star on a 24 x 24 grid.
private struct SummarySparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: point(12, 0))
        path.addCurve(to: point(24, 12), control1: point(12.6, 7.4), control2: point(16.6, 11.4))
        path.addCurve(to: point(12, 24), control1: point(16.6, 12.6), control2: point(12.6, 16.6))
        path.addCurve(to: point(0, 12), control1: point(11.4, 16.6), control2: point(7.4, 12.6))
        path.addCurve(to: point(12, 0), control1: point(7.4, 11.4), control2: point(11.4, 7.4))
        path.closeSubpath()
        return path
    }
}

// MARK: - Confetti

/// The confetti: a burst from the medal at the impact and a spray from each lower corner a little later. One `Canvas` draws every
/// piece from its `ConfettiPiece.pose`; a piece turns over (its height follows the cosine of its tumble) as it falls.
private struct SummaryConfetti: View {
    let t: TimeInterval
    /// Where the burst starts, in this view's space.
    let burstOrigin: CGPoint

    var body: some View {
        Canvas { context, size in
            let scaleX = size.width / 390
            let scaleY = max(0.6, min(1.3, size.height / 760))
            for piece in ConfettiPiece.standardSet {
                guard let pose = piece.pose(at: t) else { continue }
                let origin: CGPoint
                switch piece.launcher {
                case .burst:
                    origin = burstOrigin
                case .cannonLeading:
                    origin = CGPoint(x: -4, y: size.height * 0.8)
                case .cannonTrailing:
                    origin = CGPoint(x: size.width + 4, y: size.height * 0.8)
                }
                let turn = max(0.12, abs(cos(pose.flip * Double.pi / 180)))
                var layer = context
                layer.translateBy(x: origin.x + CGFloat(pose.x) * scaleX, y: origin.y + CGFloat(pose.y) * scaleY)
                layer.rotate(by: .degrees(pose.rotation))
                layer.scaleBy(x: CGFloat(pose.scale), y: CGFloat(pose.scale * turn))
                layer.opacity = pose.opacity
                let rect = CGRect(
                    x: -CGFloat(piece.width) / 2,
                    y: -CGFloat(piece.height) / 2,
                    width: CGFloat(piece.width),
                    height: CGFloat(piece.height)
                )
                let shape: Path = piece.shape == .dot ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 2)
                layer.fill(shape, with: .color(SummaryCelebrationPalette.confetti[piece.colorIndex]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Scroll cue

/// "All Stats" and a chevron that bobs a few times: the hint that the full results are one scroll (or one tap) away. It fades in
/// when the celebration is nearly done and gives way to the stats as the sheet comes up.
@MainActor
struct WorkoutSummaryScrollCue: View {
    /// 1 over the celebration, 0 once the sheet covers it.
    let visibility: Double
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    @State private var bobbing = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text("All Stats")
                    .pulseFont(13, .semibold, relativeTo: .footnote)
                    .foregroundStyle(Color.white.opacity(0.9))
                Image(systemName: "chevron.down")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.white)
                    .offset(y: bobbing ? 7 : 0)
                    .frame(minWidth: 56, minHeight: 44)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .dynamicTypeSize(PulseDynamicType.activeWorkoutRange)
        .opacity((arrived ? 1 : 0) * visibility)
        .allowsHitTesting(arrived && visibility > 0.3)
        .accessibilityLabel("Show all stats")
        .accessibilityIdentifier("summary.scrollCue")
        .padding(.bottom, 14)
        .onAppear {
            arrive()
        }
    }

    private func arrive() {
        guard !reduceMotion else {
            arrived = true
            return
        }
        let delay = SummaryCelebration.appearDelay + SummaryCelebration.cueStart
        withAnimation(Animation.easeOut(duration: SummaryCelebration.cueDuration).delay(delay)) {
            arrived = true
        }
        // A finite number of bobs: the cue draws the eye while it is new and then stays still.
        withAnimation(Animation.easeInOut(duration: 0.85).delay(delay).repeatCount(8, autoreverses: true)) {
            bobbing = true
        }
    }
}

// MARK: - Done button

/// The Done button: a see-through pill over the celebration that becomes the solid green button of the stats page as the sheet
/// comes up (`progress` 0 to 1).
struct WorkoutSummaryDoneButtonStyle: ButtonStyle {
    let progress: Double

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pulseFont(17, .semibold, relativeTo: .headline)
            .foregroundStyle(progress > 0.5 ? PulseTheme.onGreen : Color.white)
            .frame(maxWidth: .infinity)
            .pulseScaledFrame(minHeight: 52, relativeTo: PulseDynamicType.controlHeightStyle)
            .background {
                ZStack {
                    Color.white.opacity(0.18)
                    PulseTheme.green.opacity(progress)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
#endif
