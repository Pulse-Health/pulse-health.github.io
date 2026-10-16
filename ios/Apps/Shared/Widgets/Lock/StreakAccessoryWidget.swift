// StreakAccessoryWidget.swift
//
// LS-03 Week streak (accessoryCircular): the flame over "6 wk", from `snapshot.week.streakWeeks` (consecutive weeks that met the goal).
// Without a streak the flame is drawn as an outline and the count reads "0 wk", so the difference does not rest on brightness alone.
// A tap opens the Strength hub.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct StreakAccessoryWidget: Widget {
    static let kind = "health.pulse.strength.widget.streakAccessory"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            StreakAccessoryView(entry: entry)
        }
        .configurationDisplayName("Week streak")
        .description("How many weeks in a row you have met your workout goal.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct StreakAccessoryView: View {
    let entry: SnapshotEntry

    private var week: WeekSummary { entry.snapshot.week }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: week.streakWeeks > 0 ? "flame.fill" : "flame")
                    .font(.system(size: 22))
                    .widgetAccentable()
                Text(LockAccessoryText.streakFigure(week.streakWeeks))
                    .font(WidgetTheme.number(17))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
            }
            .padding(.horizontal, 8)
        }
        .lockContainerBackground()
        .widgetURL(StrengthDeepLink.hub.url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LockAccessoryText.streakSentence(week))
    }
}
#endif
