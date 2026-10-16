// PRSpotlightWidget.swift
//
// HS-03 PR spotlight (systemSmall): the newest personal record on a gold card. "New PR" within 24 hours of the record (`isFresh`),
// "Latest PR" with its age afterwards. A tap opens the exercise.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct PRSpotlightWidget: Widget {
    static let kind = "health.pulse.strength.widget.prSpotlight"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            PRSpotlightView(entry: entry)
        }
        .configurationDisplayName("PR spotlight")
        .description("Your latest personal record on a gold card, marked new for the first day.")
        .supportedFamilies([.systemSmall])
    }
}

struct PRSpotlightView: View {
    let entry: SnapshotEntry

    private var record: PRSummary? { entry.snapshot.latestPR }

    var body: some View {
        content
            .widgetBackground(WidgetTheme.goldFill)
            .widgetURL(url)
    }

    @ViewBuilder
    private var content: some View {
        if let record {
            PRSpotlightContent(record: record, now: entry.date, timeZoneID: entry.snapshot.timeZoneID)
        } else {
            PRSpotlightEmptyContent()
        }
    }

    private var url: URL {
        guard let record else { return StrengthDeepLink.hub.url }
        return StrengthDeepLink.exercise(id: record.exerciseID).url
    }
}

private struct PRSpotlightContent: View {
    let record: PRSummary
    let now: Date
    let timeZoneID: String

    private var daysAgo: Int {
        HomeDates.daysBetween(record.achievedAt, and: now, timeZoneID: timeZoneID)
    }

    /// "12d ago" for a record that is no longer new.
    private var age: String? {
        record.isFresh ? nil : HomeText.sinceShort(daysSince: daysAgo)
    }

    /// "e1RM 99 kg · +4"; the gain is left out for a first record (there was nothing to beat).
    private var estimateLine: String {
        let estimate = "e1RM " + WidgetText.kg(record.estimated1RM)
        guard record.deltaKg > 0 else { return estimate }
        return estimate + " · " + WidgetText.signed(record.deltaKg)
    }

    private var spoken: String {
        var sentence = record.isFresh ? "New personal record: " : "Latest personal record: "
        sentence += record.exerciseName + ", " + WidgetText.kg(record.weightKg) + " for " + HomeText.reps(record.reps) + ". "
        sentence += "Estimated one-rep max " + WidgetText.kg(record.estimated1RM)
        if record.deltaKg > 0 { sentence += ", up " + WidgetText.kg(record.deltaKg) }
        sentence += "."
        if !record.isFresh { sentence += " " + WidgetText.daysAgo(daysAgo) + "." }
        return sentence
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .widgetAccentable()
                Text(record.isFresh ? "New PR" : "Latest PR")
                    .font(WidgetTheme.eyebrow(11))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if let age {
                    Text(age)
                        .font(WidgetTheme.number(11, .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(WidgetTheme.goldText)
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.exerciseName)
                    .font(WidgetTheme.text(15, .semibold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(WidgetText.weightReps(record.weightKg, record.reps))
                    .font(WidgetTheme.number(30))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
                Text(estimateLine)
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.goldText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// No record yet: the same card, saying how to get one.
private struct PRSpotlightEmptyContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .widgetAccentable()
                Text("Latest PR")
                    .font(WidgetTheme.eyebrow(11))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .lineLimit(1)
            }
            .foregroundStyle(WidgetTheme.goldText)
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text("No records yet")
                    .font(WidgetTheme.text(17, .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("Finish a workout to set your first one.")
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.goldText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("No personal records yet. Finish a workout to set your first one.")
    }
}
#endif
