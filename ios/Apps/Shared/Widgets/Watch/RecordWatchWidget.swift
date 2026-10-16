// RecordWatchWidget.swift
//
// WA-06 the record card. For 24 hours after a personal record (`PRSummary.isFresh`, kept current by WatchSnapshotAging and by a timeline
// entry at the end of the 24 hours) it is the gold "New record" card and ranks high in the Smart Stack; afterwards it shows the latest
// record smaller and on the plain card colour, and ranks low. Without any record it says how to earn one.
// Compiled into the watchOS widget extension.

#if os(watchOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct RecordWatchWidget: Widget {
    static let kind = WatchWidgetTopic.record.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WatchProvider(topic: .record)) { entry in
            RecordWatchView(entry: entry)
        }
        .configurationDisplayName("Record")
        .description("Your newest personal record, highlighted for 24 hours.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct RecordWatchView: View {
    let entry: WatchEntry

    private var record: PRSummary? { entry.snapshot.latestPR }

    var body: some View {
        content
            .widgetURL(record.map { StrengthDeepLink.exercise(id: $0.exerciseID).url } ?? StrengthDeepLink.hub.url)
            .widgetBackground(record?.isFresh == true ? WidgetTheme.goldFill : WidgetTheme.card)
    }

    @ViewBuilder
    private var content: some View {
        if let record {
            if record.isFresh {
                fresh(record)
            } else {
                older(record)
            }
        } else {
            WatchRectMessage(eyebrow: "RECORD", title: "No records yet", detail: "Beat a best to earn one", tint: WidgetTheme.gold)
        }
    }

    /// "NEW RECORD" with the estimated 1RM, then "85 × 5" large next to the exercise.
    private func fresh(_ record: PRSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
                Text("NEW RECORD")
                    .font(WidgetTheme.eyebrow(11))
                Spacer(minLength: 2)
                Text("e1RM " + WidgetText.kg(record.estimated1RM))
                    .font(WidgetTheme.number(11, .semibold))
            }
            .foregroundStyle(WidgetTheme.gold)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .widgetAccentable()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(WidgetText.weightReps(record.weightKg, record.reps))
                    .font(WidgetTheme.number(22, .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                Text(record.exerciseName)
                    .font(WidgetTheme.text(12, .semibold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(record, prefix: "New personal record"))
    }

    /// "LATEST RECORD" and how long ago, then the lift in the smaller type of a record that is no longer news.
    private func older(_ record: PRSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetTheme.gold)
                    .accessibilityHidden(true)
                Text("LATEST RECORD")
                    .font(WidgetTheme.eyebrow(11))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                Spacer(minLength: 2)
                Text(WatchText.recordAge(from: record.achievedAt, to: entry.date))
                    .font(WidgetTheme.text(11))
                    .foregroundStyle(WidgetTheme.inkSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(WidgetText.weightReps(record.weightKg, record.reps))
                    .font(WidgetTheme.number(17, .semibold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                Text(record.exerciseName)
                    .font(WidgetTheme.text(12))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(record, prefix: "Latest personal record"))
    }

    private func spoken(_ record: PRSummary, prefix: String) -> String {
        var text = "\(prefix): \(record.exerciseName), \(WidgetText.kg(record.weightKg)) for \(record.reps) reps, "
        text += "estimated one rep max \(WidgetText.kg(record.estimated1RM))"
        if record.deltaKg > 0 {
            text += ", up \(WidgetText.kg(record.deltaKg))"
        }
        return text
    }
}
#endif
