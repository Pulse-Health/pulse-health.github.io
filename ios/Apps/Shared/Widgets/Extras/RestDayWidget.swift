// RestDayWidget.swift
//
// WI-06 Rest-day swap (systemSmall). On a rest day (`restDay != nil`) the slot shows a short recovery routine on a green card, and "Start"
// opens it as an empty workout with the routine's name. On a training day the same slot shows the next workout instead ("Training day"),
// so the widget never has to be swapped by hand.
//
// A small widget has one tap target (`widgetURL`), so the whole card starts the workout; the `Link` around the "Start" label is the same
// destination for the families that give a `Link` its own target.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct RestDayWidget: Widget {
    static let kind = "health.pulse.strength.widget.restDay"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            RestDayView(entry: entry)
        }
        .configurationDisplayName("Rest day")
        .description("A short recovery routine on rest days, your next workout on training days.")
        .supportedFamilies([.systemSmall])
    }
}

struct RestDayView: View {
    let entry: SnapshotEntry

    private var restDay: RestDaySuggestion? { entry.snapshot.restDay }
    private var nextUp: NextUpSummary? { entry.snapshot.nextUp }

    /// A rest day starts the routine as an empty workout of that name; a training day starts the next template, or an empty workout when
    /// there is no template to start.
    private var destination: StrengthDeepLink {
        if let restDay { return .startEmpty(name: restDay.title) }
        return nextUp == nil ? .startEmpty(name: StrengthConfig.defaultWorkoutName) : .startNext
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetBackground(restDay == nil ? WidgetTheme.card : WidgetTheme.greenTint)
            .widgetURL(destination.url)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenSummary)
            .accessibilityHint("Starts the workout")
    }

    @ViewBuilder
    private var content: some View {
        if let restDay {
            card(
                eyebrow: restDay.reason.isEmpty ? "Rest day" : restDay.reason,
                title: restDay.title,
                detail: restDay.focus,
                detailColor: WidgetTheme.greenText,
                pillFill: WidgetTheme.card,
                pillText: WidgetTheme.greenText
            )
        } else if let nextUp {
            card(
                eyebrow: "Training day",
                title: nextUp.name,
                detail: WidgetText.exercises(nextUp.exerciseCount) + " \u{00B7} " + WidgetText.minutes(nextUp.estimatedMinutes),
                detailColor: WidgetTheme.inkSecondary,
                pillFill: WidgetTheme.green,
                pillText: WidgetTheme.onGreen
            )
        } else {
            card(
                eyebrow: "Training day",
                title: "No workout planned",
                detail: "Start an empty one and log as you go.",
                detailColor: WidgetTheme.inkSecondary,
                pillFill: WidgetTheme.green,
                pillText: WidgetTheme.onGreen
            )
        }
    }

    private func card(
        eyebrow: String,
        title: String,
        detail: String,
        detailColor: Color,
        pillFill: Color,
        pillText: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ExtrasEyebrow(title: eyebrow, color: WidgetTheme.greenText)
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WidgetTheme.text(17, .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(detailColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 4)
            Link(destination: destination.url) {
                PillLabel(title: "Start", systemImage: nil, fill: pillFill, foreground: pillText, height: 36)
            }
        }
    }

    private var spokenSummary: String {
        if let restDay {
            return "\(restDay.reason.isEmpty ? "Rest day" : restDay.reason). \(restDay.title), \(restDay.focus)."
        }
        if let nextUp {
            return "Training day. Next up: \(nextUp.name), \(WidgetText.exercises(nextUp.exerciseCount)), about \(nextUp.estimatedMinutes) minutes."
        }
        return "Training day. No workout planned."
    }
}
#endif
