// HeartRateWatchWidget.swift
//
// WA-09 set-by-set heart rate. The last finished session as up to 16 bars (`SessionSummary.heartRateBars`): bright red for the buckets above
// the session mean (the working sets) and faded for the recovery between them, so the effort rhythm shows at a glance. Effort and recovery
// differ in opacity and in height, never in colour alone. Average and peak sit beside the bars.
// Compiled into the watchOS widget extension.

#if os(watchOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct HeartRateWatchWidget: Widget {
    static let kind = WatchWidgetTopic.heartRate.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchProvider(topic: .heartRate)) { entry in
            HeartRateWatchView(entry: entry)
        }
        .configurationDisplayName("Heart rate by set")
        .description("The effort rhythm of your last session: sets bright, rests faded.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct HeartRateWatchView: View {
    let entry: WatchEntry

    private var session: SessionSummary? { entry.snapshot.lastSession }

    var body: some View {
        content
            .widgetURL(StrengthDeepLink.hub.url)
            .widgetBackground(WidgetTheme.card)
    }

    @ViewBuilder
    private var content: some View {
        if let session {
            if session.heartRateBars.isEmpty {
                WatchRectMessage(
                    eyebrow: "LAST SESSION",
                    title: session.name,
                    detail: "No heart rate recorded",
                    tint: WidgetTheme.heart
                )
            } else {
                chart(session)
            }
        } else {
            WatchRectMessage(eyebrow: "HEART RATE", title: "No sessions yet", detail: "Finish a workout with your Watch", tint: WidgetTheme.heart)
        }
    }

    private func chart(_ session: SessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Last session · " + session.name)
                .font(WidgetTheme.text(11))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(1)
            HStack(alignment: .bottom, spacing: 8) {
                WatchHeartBars(bars: session.heartRateBars)
                    .frame(height: 30)
                VStack(alignment: .trailing, spacing: 0) {
                    if let average = session.averageHeartRate {
                        Text("avg \(average)")
                            .font(WidgetTheme.number(13, .bold))
                            .foregroundStyle(WidgetTheme.ink)
                    }
                    if let peak = session.peakHeartRate {
                        Text("peak \(peak)")
                            .font(WidgetTheme.number(11))
                            .foregroundStyle(WidgetTheme.inkSecondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(session))
    }

    private func spoken(_ session: SessionSummary) -> String {
        let efforts = session.heartRateBars.filter { $0.isEffort }.count
        let recoveries = session.heartRateBars.count - efforts
        var text = "Heart rate in your last session, \(session.name): \(efforts) working stretches and \(recoveries) recoveries"
        if let average = session.averageHeartRate {
            text += ", average \(average)"
        }
        if let peak = session.peakHeartRate {
            text += ", peak \(peak)"
        }
        return text + " beats per minute"
    }
}

/// The bars of a session's heart-rate curve, scaled between its lowest and highest bucket (never below a quarter of the height, so a
/// recovery bar stays visible). Effort buckets are solid, recovery buckets faded.
struct WatchHeartBars: View {
    let bars: [HeartRateBar]

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(bars.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(WidgetTheme.heart)
                        .opacity(bars[index].isEffort ? 1 : 0.45)
                        .frame(height: max(3, proxy.size.height * fraction(of: bars[index].bpm)))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .widgetAccentable()
        .accessibilityHidden(true)
    }

    /// 0.25...1 for a bucket's bpm between the lowest and the highest bucket; 0.6 when they are all the same.
    private func fraction(of bpm: Int) -> CGFloat {
        let values = bars.map { $0.bpm }
        guard let low = values.min(), let high = values.max(), high > low else { return 0.6 }
        return 0.25 + 0.75 * CGFloat(bpm - low) / CGFloat(high - low)
    }
}
#endif
