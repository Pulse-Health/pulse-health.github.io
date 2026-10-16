// WeeklyGoalWidget.swift
//
// HS-02 Weekly goal (and, in the system's tinted mode, HS-06). This file is the REFERENCE for the other widgets of the app:
//   * one `Widget` with a stable `kind`, the shared `SnapshotProvider`, the families it supports;
//   * the view reads only the `WidgetSnapshot` of its `SnapshotEntry` (never the engine, never the history files);
//   * `widgetCardBackground()` puts the card colour in `containerBackground(for: .widget)` (the system swaps it in tinted / StandBy modes);
//   * figures use `WidgetTheme.number`, colours come from `WidgetTheme`, and the parts that should take the tint are `.widgetAccentable()`;
//   * `widgetURL(StrengthDeepLink...)` makes the whole widget open the app; real buttons use `Link` or `Button(intent:)`;
//   * every element that carries meaning has an accessibility label.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct WeeklyGoalWidget: Widget {
    static let kind = "health.pulse.strength.widget.weeklyGoal"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            WeeklyGoalView(entry: entry)
        }
        .configurationDisplayName("Weekly goal")
        .description("Workouts finished this week against your goal.")
        .supportedFamilies([.systemSmall])
    }
}

struct WeeklyGoalView: View {
    let entry: SnapshotEntry

    private var week: WeekSummary { entry.snapshot.week }
    private var progress: Double { week.goal > 0 ? Double(week.completed) / Double(week.goal) : 0 }

    var body: some View {
        VStack(spacing: 8) {
            RingGauge(progress: progress, lineWidth: 10) {
                VStack(spacing: 0) {
                    Text("\(week.completed)/\(week.goal)")
                        .font(WidgetTheme.number(26))
                        .foregroundStyle(WidgetTheme.ink)
                        .minimumScaleFactor(0.8)
                    Text("this week")
                        .font(WidgetTheme.text(11))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                }
            }
            .widgetAccentable()
            .frame(maxHeight: .infinity)
            DayDotRow(days: week.days)
        }
        .widgetCardBackground()
        .widgetURL(StrengthDeepLink.hub.url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(week.completed) of \(week.goal) workouts this week")
    }
}

/// Seven dots, Monday first: filled when a workout was finished that day, ringed for today, dim otherwise.
struct DayDotRow: View {
    let days: [DayCell]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(days.indices, id: \.self) { index in
                let day = days[index]
                VStack(spacing: 2) {
                    Circle()
                        .fill(day.sessions > 0 ? WidgetTheme.progress : WidgetTheme.track)
                        .overlay(Circle().strokeBorder(WidgetTheme.green, lineWidth: day.isToday && day.sessions == 0 ? 2 : 0))
                        .frame(width: 8, height: 8)
                    Text(day.letter)
                        .font(WidgetTheme.text(9, day.isToday ? .bold : .regular))
                        .foregroundStyle(day.isToday ? WidgetTheme.ink : WidgetTheme.inkSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
#endif
