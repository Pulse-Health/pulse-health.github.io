// SessionTimelineWidget.swift
//
// WI-11 Session timeline (systemMedium). How the time of the last workout was spent: one bar of `lastSession.timeline` with a block for
// every stretch of lifting, rest and long rest (over three minutes), a legend, and "51 min · 38% under tension · 1 long break". Long rests
// are striped as well as yellow, so the three kinds differ without colour. Workouts from before the app stamped set times have no
// timeline: the widget then says that times are recorded from the next workout. Tinted mode keeps only alpha, so there the kinds differ by
// alpha and stripes instead of colour.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct SessionTimelineWidget: Widget {
    static let kind = "health.pulse.strength.widget.sessionTimeline"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            SessionTimelineView(entry: entry)
        }
        .configurationDisplayName("Session timeline")
        .description("How the time of your last workout was spent: lifting, rest and long breaks.")
        .supportedFamilies([.systemMedium])
    }
}

struct SessionTimelineView: View {
    let entry: SnapshotEntry

    private var session: SessionSummary? { entry.snapshot.lastSession }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCardBackground()
            .widgetURL(StrengthDeepLink.hub.url)
    }

    @ViewBuilder
    private var content: some View {
        if let session, !session.timeline.isEmpty {
            populated(session)
        } else {
            empty
        }
    }

    private func header(name: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Session timeline")
                .font(WidgetTheme.text(15, .semibold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            if let name {
                Text(name)
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func populated(_ session: SessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(name: session.name)
            SessionTimelineBar(segments: session.timeline)
                .accessibilityHidden(true)
            SessionTimelineLegend()
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Text(verbatim: "\(session.durationMinutes) min")
                    .font(WidgetTheme.number(13, .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(verbatim: " \u{00B7} " + details(of: session))
                    .font(WidgetTheme.number(13, .regular))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary(of: session))
    }

    /// "38% under tension · 1 long break".
    private func details(of session: SessionSummary) -> String {
        var parts: [String] = []
        if let percent = session.underTensionPercent { parts.append("\(percent)% under tension") }
        switch session.longBreakCount {
        case 0: parts.append("no long breaks")
        case 1: parts.append("1 long break")
        default: parts.append("\(session.longBreakCount) long breaks")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func minutes(of kind: TimelineKind, in session: SessionSummary) -> Int {
        let seconds = session.timeline.filter { $0.kind == kind }.reduce(0) { $0 + $1.seconds }
        return Int((Double(seconds) / 60).rounded())
    }

    private func spokenSummary(of session: SessionSummary) -> String {
        var text = "Session timeline for \(session.name). \(ExtrasText.count(session.durationMinutes, "minute"))"
        if let percent = session.underTensionPercent { text += ", \(percent) percent under tension" }
        text += session.longBreakCount == 0 ? ", no long breaks." : ", " + ExtrasText.count(session.longBreakCount, "long break") + "."
        text += " Lifting \(ExtrasText.count(minutes(of: .lifting, in: session), "minute")),"
        text += " rest \(ExtrasText.count(minutes(of: .rest, in: session), "minute")),"
        text += " long rest \(ExtrasText.count(minutes(of: .longRest, in: session), "minute"))."
        return text
    }

    // MARK: Empty

    /// No timeline: either no workout yet, or one from before set times were recorded.
    private var empty: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(name: session?.name)
            SessionTimelineEmptyBar()
                .accessibilityHidden(true)
            Text("Set times are recorded from your next workout")
                .font(WidgetTheme.text(13))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if let session {
                Text(verbatim: "\(session.durationMinutes) min \u{00B7} " + ExtrasText.count(session.loggedSets, "set"))
                    .font(WidgetTheme.number(13, .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(emptySpokenSummary)
    }

    private var emptySpokenSummary: String {
        var text = "Session timeline. Set times are recorded from your next workout."
        if let session {
            text += " Last workout, \(session.name): \(ExtrasText.count(session.durationMinutes, "minute")), "
            text += ExtrasText.count(session.loggedSets, "set") + "."
        }
        return text
    }
}

// MARK: - Drawing

/// One block per stretch, as wide as its share of the session; a one-point gap keeps neighbours apart.
private struct SessionTimelineBar: View {
    let segments: [TimelineSegment]

    private static let gap: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let drawn = segments.filter { $0.seconds > 0 }
            let total = CGFloat(drawn.reduce(0) { $0 + $1.seconds })
            let usable = max(0, proxy.size.width - Self.gap * CGFloat(max(0, drawn.count - 1)))
            HStack(spacing: Self.gap) {
                ForEach(drawn.indices, id: \.self) { index in
                    SessionTimelineBlock(kind: drawn[index].kind)
                        .frame(width: total > 0 ? usable * CGFloat(drawn[index].seconds) / total : 0)
                }
            }
        }
        .frame(height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct SessionTimelineLegend: View {
    private static let items: [(kind: TimelineKind, title: String)] = [
        (.lifting, "Lifting"),
        (.rest, "Rest"),
        (.longRest, "Long rest"),
    ]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Self.items.indices, id: \.self) { index in
                HStack(spacing: 5) {
                    SessionTimelineBlock(kind: Self.items[index].kind)
                        .frame(width: 10, height: 10)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    Text(Self.items[index].title)
                        .font(WidgetTheme.text(12))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A block of the bar and the swatch of the legend: green for lifting, grey for rest, yellow with stripes for a long rest. In tinted mode
/// lifting is the accented block, rest a faint one, and a long rest a fainter one with strong stripes.
private struct SessionTimelineBlock: View {
    let kind: TimelineKind

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ExtrasPalette { ExtrasPalette(renderingMode: renderingMode, colorScheme: colorScheme) }

    private var fill: Color {
        switch kind {
        case .lifting: return WidgetTheme.green
        case .rest: return palette.track
        case .longRest: return palette.isTinted ? WidgetTheme.ink.opacity(0.3) : WidgetTheme.recovering
        }
    }

    private var stripeColor: Color {
        palette.isTinted ? WidgetTheme.ink.opacity(0.9) : WidgetTheme.card.opacity(0.7)
    }

    var body: some View {
        Rectangle()
            .fill(fill)
            .overlay(stripes)
            .clipped()
            .widgetAccentable(kind == .lifting)
    }

    @ViewBuilder
    private var stripes: some View {
        if kind == .longRest {
            SessionTimelineStripes()
                .stroke(stripeColor, lineWidth: 1.5)
        }
    }
}

/// The bar of a session without set times: an empty, dashed track.
private struct SessionTimelineEmptyBar: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ExtrasPalette { ExtrasPalette(renderingMode: renderingMode, colorScheme: colorScheme) }

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.step, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .frame(height: 26)
    }
}

/// Diagonal lines across the rectangle.
private struct SessionTimelineStripes: Shape {
    var spacing: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}
#endif
