// LiftTrendWatchWidget.swift
//
// WA-08 the lift trend complication: the best estimated 1RM of the most trained lift, and its estimated 1RM over the last sessions as a
// sparkline with the personal-record session in gold (the board of Watch.dc.html shows the best value over a sparkline that dips after it).
// The lift is the first of `WidgetSnapshot.lifts` (they are ranked by how often they were trained in the last 90 days).
// Compiled into the watchOS widget extension.

#if os(watchOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct LiftTrendWatchWidget: Widget {
    static let kind = WatchWidgetTopic.liftTrend.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchProvider(topic: .liftTrend)) { entry in
            LiftTrendWatchView(entry: entry)
        }
        .configurationDisplayName("Lift trend")
        .description("The best estimated 1RM of your most trained lift, and how it moved over its last sessions.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct LiftTrendWatchView: View {
    let entry: WatchEntry

    private var lift: LiftTrend? { entry.snapshot.lifts.first }

    var body: some View {
        content
            .widgetURL(lift.map { StrengthDeepLink.exercise(id: $0.exerciseID).url } ?? StrengthDeepLink.hub.url)
            .widgetBackground(WidgetTheme.card)
    }

    @ViewBuilder
    private var content: some View {
        if let lift, lift.points.count >= 2 {
            trend(lift)
        } else {
            WatchRectMessage(
                eyebrow: "LIFT TREND",
                title: lift?.name ?? "No lifts yet",
                detail: lift == nil ? "Finish a few workouts first" : "Log it again to see a trend"
            )
        }
    }

    /// "BENCH PRESS E1RM" and the best value (the gold dot of the sparkline when the best is the newest record), the sparkline under it.
    private func trend(_ lift: LiftTrend) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(lift.name.uppercased() + " E1RM")
                    .font(WidgetTheme.eyebrow(11))
                    .foregroundStyle(WidgetTheme.green)
                    .lineLimit(1)
                    .widgetAccentable()
                Spacer(minLength: 2)
                Text(NumberText.kg(lift.bestE1RM))
                    .font(WidgetTheme.number(13, .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
            }
            Sparkline(
                values: lift.points.map { $0.value },
                highlightIndex: lift.prIndex,
                lineColor: WidgetTheme.green,
                lineWidth: 2.5,
                dotSize: 6
            )
            .frame(height: 30)
            .widgetAccentable()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(lift))
    }

    private func spoken(_ lift: LiftTrend) -> String {
        let values = lift.points.map { NumberText.kg($0.value) }.joined(separator: ", ")
        var text = "\(lift.name) estimated one rep max, best \(NumberText.kg(lift.bestE1RM)) kilograms. "
        text += "Last \(lift.points.count) sessions: \(values) kilograms"
        if lift.deltaKg > 0.005 {
            text += ". Up \(NumberText.kg(lift.deltaKg)) since the previous session"
        } else if lift.deltaKg < -0.005 {
            text += ". Down \(NumberText.kg(-lift.deltaKg)) since the previous session"
        }
        if let index = lift.prIndex, lift.points.indices.contains(index) {
            text += ". Personal record in session \(index + 1)"
        }
        return text
    }
}
#endif
