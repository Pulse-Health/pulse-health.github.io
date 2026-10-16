// MuscleFreshnessWidget.swift
//
// HS-04 Muscle freshness (systemSmall): the four muscle groups trained least recently (never trained first), each with a recovery dot and
// the days since. The dot repeats its colour in its fill level, and the whole widget is read out with the state of every row in words.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct MuscleFreshnessWidget: Widget {
    static let kind = "health.pulse.strength.widget.muscleFreshness"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            MuscleFreshnessView(entry: entry)
        }
        .configurationDisplayName("Muscle freshness")
        .description("The four muscle groups you trained least recently, with the days since each.")
        .supportedFamilies([.systemSmall])
    }
}

struct MuscleFreshnessView: View {
    let entry: SnapshotEntry

    private let rowCount = 4

    /// Never trained first, then the most days since, ties in muscle-group order.
    private var rows: [MuscleFreshness] {
        let indexed = Array(entry.snapshot.freshness.enumerated())
        let ordered = indexed.sorted { lhs, rhs in
            let left = lhs.element.daysSince ?? Int.max
            let right = rhs.element.daysSince ?? Int.max
            return left != right ? left > right : lhs.offset < rhs.offset
        }
        return ordered.prefix(rowCount).map { $0.element }
    }

    /// "Ready to train" only while the most rested group really is ready.
    private var title: String {
        rows.first?.status == .ready ? "Ready to train" : "Recovery"
    }

    private var spoken: String {
        guard !rows.isEmpty else { return "Muscle freshness. No workouts logged yet." }
        let sentences = rows.map { row -> String in
            let when = row.daysSince.map { "last trained " + WidgetText.daysAgo($0).lowercased() } ?? "never trained"
            return row.muscle.title + ": " + HomeText.spoken(row.status) + ", " + when + "."
        }
        return "Muscle freshness. " + sentences.joined(separator: " ")
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCardBackground()
            .widgetURL(StrengthDeepLink.hub.url)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HomeEyebrow(title: "Muscle freshness", color: WidgetTheme.inkSecondary, size: 12)
                Spacer(minLength: 4)
                Text("No workouts yet")
                    .font(WidgetTheme.text(17, .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("Finish a workout to see how rested each muscle is.")
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HomeEyebrow(title: title, color: WidgetTheme.inkSecondary, size: 12)
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        MuscleFreshnessRow(item: rows[index])
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

private struct MuscleFreshnessRow: View {
    let item: MuscleFreshness

    var body: some View {
        HStack(spacing: 8) {
            HomeStatusDot(status: item.status, size: 11)
                .widgetAccentable()
            Text(item.muscle.title)
                .font(WidgetTheme.text(14))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(WidgetText.daysShort(item.daysSince))
                .font(WidgetTheme.number(13, .regular))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(1)
        }
    }
}
#endif
