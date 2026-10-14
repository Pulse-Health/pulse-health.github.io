#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

/// Header of the active-workout screen: minimise chevron, workout title with the running clock,
/// More button, blue Finish pill, the Volume / Sets / heart-rate line and the segmented progress strip.
/// The white background extends under the status bar.
public struct ActiveHeaderView: View {
    public var header: ActiveWorkoutPresentation.Header
    public var onMinimise: () -> Void
    public var onMore: () -> Void
    public var onFinish: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The running clock (15 pt rounded) grows like the other body-sized text.
    @PulseScaled(15, relativeTo: .subheadline) private var clockSize: CGFloat

    public init(
        header: ActiveWorkoutPresentation.Header,
        onMinimise: @escaping () -> Void,
        onMore: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.header = header
        self.onMinimise = onMinimise
        self.onMore = onMore
        self.onFinish = onFinish
    }

    /// Clock colour while the workout is paused (amber text).
    private static let pausedClock = Color(light: 0x9A5B00, dark: 0xFFB340)
    /// The hairline under the header (0.5 pt, the design's rgba(60,60,67,0.29)).
    private static let hairline = Color(light: 0x3C3C43, dark: 0x545458, lightAlpha: 0.29, darkAlpha: 0.65)

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                titleRow
                statsRow
                    .padding(.top, 2)
            }
            .padding(.horizontal, PulseTheme.screenInset)

            ActiveProgressStrip(segments: header.segments)
                .padding(.top, 6)
        }
        .background(
            PulseTheme.card
                .shadow(color: ActiveHeaderView.hairline, radius: 0, x: 0, y: 0.5)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: Title row

    private var titleRow: some View {
        HStack(spacing: 4) {
            minimiseButton
            titleBlock
            moreButton
            finishButton
        }
    }

    private var minimiseButton: some View {
        Button(action: onMinimise) {
            Image(systemName: "chevron.down")
                .pulseFont(17, .bold, relativeTo: .body)
                .foregroundStyle(PulseTheme.green)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .padding(.leading, -10)
        .accessibilityLabel("Minimise workout")
    }

    private var titleBlock: some View {
        VStack(spacing: 1) {
            Text(header.title)
                .pulseFont(17, .semibold, relativeTo: .headline)
                .foregroundStyle(PulseTheme.ink)
                .pulseLineLimit(1, whenLarger: 2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(header.clockText)
                .font(PulseFont.number(clockSize, .regular))
                .monospacedDigit()
                .foregroundStyle(header.isPaused ? ActiveHeaderView.pausedClock : PulseTheme.inkSecondary)
                .lineLimit(1)
                .pulseShrinkWhenLarger(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(header.title)
        .accessibilityValue(header.isPaused ? header.clockText : "Elapsed " + header.clockText)
    }

    private var moreButton: some View {
        Button(action: onMore) {
            Image(systemName: "ellipsis.circle")
                .pulseFont(22, .regular, relativeTo: .title2)
                .foregroundStyle(PulseTheme.green)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityLabel("More")
        .accessibilityIdentifier("active-more")
    }

    private var finishButton: some View {
        Button(action: onFinish) {
            Text("Finish")
        }
        .buttonStyle(PulsePillButtonStyle())
    }

    // MARK: Stats row

    private var statsRow: some View {
        statsLayout
            .frame(minHeight: 30)
    }

    /// One line (the design). With bigger text the three figures may not fit next to each other: then the heart rate
    /// moves to a second line instead of truncating. At the default size and below the single line is always used.
    @ViewBuilder
    private var statsLayout: some View {
        if dynamicTypeSize > .large {
            ViewThatFits(in: .horizontal) {
                statsSingleLine
                statsTwoLines
            }
        } else {
            statsSingleLine
        }
    }

    private var statsSingleLine: some View {
        HStack(spacing: 0) {
            volumeItem
            Spacer(minLength: 8)
            setsItem
            Spacer(minLength: 8)
            heartItem
        }
    }

    private var statsTwoLines: some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                volumeItem
                Spacer(minLength: 8)
                setsItem
            }
            HStack(spacing: 0) {
                Spacer(minLength: 8)
                heartItem
            }
        }
    }

    private var volumeItem: some View {
        statItem(label: "Volume", value: header.volumeText, unit: "kg")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Volume")
            .accessibilityValue(header.volumeText + " kilograms")
    }

    private var setsItem: some View {
        statItem(label: "Sets", value: header.setsText, unit: nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sets logged")
            .accessibilityValue(header.setsText)
    }

    private func statItem(label: String, value: String, unit: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
                .pulseFont(12, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
            Text(value)
                .pulseNumber(15, .bold, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.ink)
            if let unit = unit {
                Text(unit)
                    .pulseFont(12, relativeTo: .footnote)
                    .foregroundStyle(PulseTheme.inkSecondary)
            }
        }
        .lineLimit(1)
    }

    private var heartItem: some View {
        HStack(spacing: 5) {
            ActiveHeartBeat(isBeating: header.hasHeartRate)
            Text(header.heartRateText)
                .pulseNumber(15, .bold, relativeTo: .subheadline)
                .foregroundStyle(PulseTheme.ink)
            Text("bpm")
                .pulseFont(12, relativeTo: .footnote)
                .foregroundStyle(PulseTheme.inkSecondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate")
        .accessibilityValue(header.hasHeartRate ? header.heartRateText + " beats per minute" : "Not available")
    }
}

// MARK: - Heart

/// The small heart next to the bpm figure. Beats once a second (scale 1 -> 1.25 -> 1) while a heart
/// rate is being received, stays still and grey otherwise and when Reduce Motion is on.
private struct ActiveHeartBeat: View {
    let isBeating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The glyph (11 pt) and its frame (12 pt) grow with the text next to it.
    @PulseScaled(11, relativeTo: .caption2) private var glyphSize: CGFloat
    @PulseScaled(12, relativeTo: .caption2) private var glyphFrame: CGFloat

    init(isBeating: Bool) {
        self.isBeating = isBeating
    }

    var body: some View {
        if isBeating && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                heart(scale: ActiveHeartBeat.scale(at: context.date))
            }
        } else {
            heart(scale: 1)
        }
    }

    private func heart(scale: CGFloat) -> some View {
        Image(systemName: "heart.fill")
            .font(.system(size: glyphSize, weight: .regular))
            .foregroundStyle(isBeating ? PulseTheme.heart : PulseTheme.inkTertiary)
            .scaleEffect(scale)
            .frame(width: glyphFrame, height: glyphFrame)
    }

    /// One beat per second: up over 150 ms, back over 150 ms, then rest.
    private static func scale(at date: Date) -> CGFloat {
        let time = date.timeIntervalSinceReferenceDate
        let phase = time - time.rounded(.down)
        if phase < 0.15 {
            return 1 + 0.25 * CGFloat(smooth(phase / 0.15))
        }
        if phase < 0.30 {
            return 1.25 - 0.25 * CGFloat(smooth((phase - 0.15) / 0.15))
        }
        return 1
    }

    private static func smooth(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }
}

// MARK: - Progress strip

/// One thin bar per exercise (4 pt high, 2 pt gaps, full width); the fill is the share of logged sets.
private struct ActiveProgressStrip: View {
    let segments: [ActiveWorkoutPresentation.Segment]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments.indices, id: \.self) { index in
                segmentBar(segments[index])
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workout progress")
        .accessibilityValue(progressValue)
    }

    private func segmentBar(_ segment: ActiveWorkoutPresentation.Segment) -> some View {
        let fraction = CGFloat(min(1, max(0, segment.fraction)))
        let track = segment.isCurrent ? PulseTheme.progressTrackCurrent : PulseTheme.progressTrack
        return Rectangle()
            .fill(track)
            .frame(maxWidth: .infinity)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(PulseTheme.progress)
                        .frame(width: proxy.size.width * fraction, height: proxy.size.height)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: fraction)
                }
            }
            .clipped()
    }

    private var progressValue: String {
        let done = segments.filter { $0.fraction >= 0.999 }.count
        return "\(done) of \(segments.count) exercises complete"
    }
}
#endif
