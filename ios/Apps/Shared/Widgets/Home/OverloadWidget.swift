// OverloadWidget.swift
//
// HS-05 Beat last time (systemSmall): what the first weighted exercise of the next workout did last time and the target for today. The card
// is dark in every appearance (`homeDarkCard`), as in the design. A tap opens the exercise.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct OverloadWidget: Widget {
    static let kind = "health.pulse.strength.widget.overload"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            OverloadView(entry: entry)
        }
        .configurationDisplayName("Beat last time")
        .description("What you lifted last time and the target to beat today, on a dark card.")
        .supportedFamilies([.systemSmall])
    }
}

struct OverloadView: View {
    let entry: SnapshotEntry

    private var target: OverloadTarget? { entry.snapshot.overload }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .homeDarkCard()
            .widgetURL(url)
    }

    @ViewBuilder
    private var content: some View {
        if let target {
            OverloadContent(target: target)
        } else {
            OverloadEmptyContent()
        }
    }

    private var url: URL {
        guard let target else { return StrengthDeepLink.hub.url }
        return StrengthDeepLink.exercise(id: target.exerciseID).url
    }
}

/// The green rounded square with a barbell, the brand mark of the card.
private struct OverloadBadge: View {
    var body: some View {
        Image(systemName: "dumbbell.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(WidgetTheme.onGreen)
            .frame(width: 30, height: 30)
            .background(WidgetTheme.green, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}

private struct OverloadContent: View {
    let target: OverloadTarget

    private var spoken: String {
        var sentence = "Beat last time: " + target.exerciseName + ". Last time "
        sentence += WidgetText.kg(target.lastWeightKg) + " for " + HomeText.reps(target.lastReps)
        if let days = target.lastDaysAgo { sentence += ", " + WidgetText.daysAgo(days).lowercased() }
        sentence += ". Try " + WidgetText.kg(target.targetWeightKg) + " for " + HomeText.reps(target.targetReps) + " today."
        return sentence
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                OverloadBadge()
                Spacer(minLength: 4)
                if let ago = HomeText.sinceShort(daysSince: target.lastDaysAgo) {
                    Text(ago)
                        .font(WidgetTheme.number(13, .regular))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("Last time · " + target.exerciseName)
                    .font(WidgetTheme.text(12))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(WidgetText.weightReps(target.lastWeightKg, target.lastReps))
                    .font(WidgetTheme.number(24))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Try " + WidgetText.weightReps(target.targetWeightKg, target.targetReps))
                    .font(WidgetTheme.text(14, .semibold))
                    .foregroundStyle(WidgetTheme.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .widgetAccentable()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// No target yet: it needs a next workout and a weighted exercise that was done before.
private struct OverloadEmptyContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OverloadBadge()
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("Beat last time")
                    .font(WidgetTheme.text(12))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
                Text("Nothing to beat yet")
                    .font(WidgetTheme.text(17, .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("Finish a workout to get a target.")
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.green)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Beat last time. Nothing to beat yet. Finish a workout to get a target.")
    }
}
#endif
