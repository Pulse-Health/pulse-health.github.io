// ReadinessWidget.swift
//
// WI-09 Readiness to load (systemMedium). The readiness score of the wider Pulse app (`readiness`, supplied by the host) as a ring with
// the score and its label in the middle, and the one-sentence advice beside it. The ring is green from a score of 67, yellow from 34 and
// red below; the number and the label carry the same meaning in words. Without readiness (the standalone build) the widget asks to connect
// Pulse.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct ReadinessWidget: Widget {
    static let kind = "health.pulse.strength.widget.readiness"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            ReadinessView(entry: entry)
        }
        .configurationDisplayName("Readiness")
        .description("Your Pulse readiness for today, next to the plan for your lifts.")
        .supportedFamilies([.systemMedium])
    }
}

struct ReadinessView: View {
    let entry: SnapshotEntry

    private var readiness: ReadinessSummary? { entry.snapshot.readiness }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetCardBackground()
            .widgetURL(StrengthDeepLink.hub.url)
    }

    @ViewBuilder
    private var content: some View {
        if let readiness {
            populated(readiness)
        } else {
            connect
        }
    }

    private func populated(_ readiness: ReadinessSummary) -> some View {
        let score = min(100, max(0, readiness.score))
        return HStack(spacing: 16) {
            ReadinessRing(score: score, label: readiness.label)
            VStack(alignment: .leading, spacing: 6) {
                ExtrasEyebrow(title: "Pulse readiness", color: WidgetTheme.greenText)
                if !readiness.message.isEmpty {
                    Text(readiness.message)
                        .font(WidgetTheme.text(17, .bold))
                        .foregroundStyle(WidgetTheme.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                }
                if !readiness.source.isEmpty {
                    Text("From " + readiness.source)
                        .font(WidgetTheme.text(13))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(readiness, score: score))
    }

    private func spoken(_ readiness: ReadinessSummary, score: Int) -> String {
        var text = "Pulse readiness \(score) out of 100"
        text += readiness.label.isEmpty ? "." : ", " + readiness.label + "."
        if !readiness.message.isEmpty { text += " " + readiness.message }
        if !readiness.source.isEmpty { text += " From " + readiness.source + "." }
        return text
    }

    private var connect: some View {
        HStack(spacing: 16) {
            ReadinessRing(score: nil, label: "")
            VStack(alignment: .leading, spacing: 6) {
                ExtrasEyebrow(title: "Pulse readiness", color: WidgetTheme.greenText)
                Text("Connect Pulse")
                    .font(WidgetTheme.text(17, .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Readiness comes from your Pulse sleep and HRV.")
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pulse readiness. Connect Pulse. Readiness comes from your Pulse sleep and HRV.")
    }
}

/// The score ring; `score` nil draws the empty track with a dash. It is drawn here rather than with `RingGauge` because only the arc may be
/// accented: with the track in the accent group too, the arc would not stand out from it in tinted mode.
private struct ReadinessRing: View {
    let score: Int?
    let label: String

    private static let lineWidth: CGFloat = 10

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ExtrasPalette { ExtrasPalette(renderingMode: renderingMode, colorScheme: colorScheme) }

    /// Recovery colours: good from 67, fair from 34, low below.
    private var color: Color {
        guard let score else { return WidgetTheme.progress }
        if score >= 67 { return WidgetTheme.ready }
        return score >= 34 ? WidgetTheme.recovering : WidgetTheme.worked
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.track, lineWidth: Self.lineWidth)
            if let score, score > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(min(score, 100)) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
            VStack(spacing: 0) {
                Text(score.map { String($0) } ?? "\u{2013}")
                    .font(WidgetTheme.number(24))
                    .foregroundStyle(score == nil ? WidgetTheme.inkTertiary : WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !label.isEmpty {
                    Text(label)
                        .font(WidgetTheme.text(11))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(Self.lineWidth / 2)
        .frame(width: 100, height: 100)
    }
}
#endif
