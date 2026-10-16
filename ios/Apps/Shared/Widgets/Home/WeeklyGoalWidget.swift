// WeeklyGoalWidget.swift
//
// HS-02 Weekly goal, HS-06 (the same widget in the system's tinted mode) and the Weekly goal half of SB-01 (StandBy). This file is the
// REFERENCE for the other widgets of the app:
//   * one `Widget` with a stable `kind`, the shared `SnapshotProvider`, the families it supports;
//   * the view reads only the `WidgetSnapshot` of its `SnapshotEntry` (never the engine, never the history files);
//   * `widgetCardBackground()` puts the card colour in `containerBackground(for: .widget)` (the system swaps it in tinted / StandBy modes);
//   * figures use `WidgetTheme.number`, colours come from `WidgetTheme`, and the parts that should take the tint are `.widgetAccentable()`;
//   * `widgetURL(StrengthDeepLink...)` makes the whole widget open the app; real buttons use `Link` or `Button(intent:)`;
//   * every element that carries meaning has an accessibility label.
// The surface decides the look, through the environment: StandBy draws no card (`showsWidgetContainerBackground` is false) so the ring
// grows and the dark appearance is used; at night (`isLuminanceReduced`) the system tints everything red, so the ring is drawn in
// `Color.red` on black; the tinted mode (`widgetRenderingMode`) gets one accent colour, a glyph in the ring and no coloured fills.

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
        .description("Workouts finished this week against your goal. Large and readable in StandBy.")
        .supportedFamilies([.systemSmall])
    }
}

struct WeeklyGoalView: View {
    let entry: SnapshotEntry
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var week: WeekSummary { entry.snapshot.week }
    private var progress: Double { week.goal > 0 ? Double(week.completed) / Double(week.goal) : 0 }
    /// The system's tinted mode (HS-06): one accent colour for the ring and the figures, no coloured fills.
    private var isTinted: Bool { renderingMode != .fullColor }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if isLuminanceReduced {
                    Color.black
                } else {
                    WidgetTheme.card
                }
            }
            .widgetURL(StrengthDeepLink.hub.url)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(week.completed) of \(week.goal) workouts this week")
    }

    @ViewBuilder
    private var content: some View {
        if isLuminanceReduced {
            WeeklyGoalRing(
                week: week,
                progress: progress,
                lineWidth: 14,
                numeralSize: 36,
                captionSize: 13,
                fill: Color.red,
                track: Color.red.opacity(0.28),
                text: Color.red,
                secondary: Color.red.opacity(0.75)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isTinted {
            tintedContent
        } else if !showsBackground {
            WeeklyGoalRing(week: week, progress: progress, lineWidth: 14, numeralSize: 36, captionSize: 13)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .homeDarkAppearance()
        } else {
            VStack(spacing: 8) {
                WeeklyGoalRing(week: week, progress: progress)
                    .frame(maxHeight: .infinity)
                DayDotRow(days: HomeDates.weekDays(of: week))
            }
        }
    }

    /// Tinted mode: the ring around a barbell glyph and "3 of 4" underneath. Ink at two opacities instead of two colours, so the track stays
    /// distinct from the progress whatever single colour the system maps them to.
    private var tintedContent: some View {
        VStack(spacing: 6) {
            RingGauge(progress: progress, lineWidth: 10, color: WidgetTheme.ink, track: WidgetTheme.ink.opacity(0.25)) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(WidgetTheme.ink)
            }
            .widgetAccentable()
            .frame(maxHeight: .infinity)
            Text(verbatim: "\(week.completed) of \(week.goal)")
                .font(WidgetTheme.number(15))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .widgetAccentable()
        }
    }
}

/// The ring with "3/4" and "this week" in the middle. The colours and sizes belong to the surface drawing it.
private struct WeeklyGoalRing: View {
    let week: WeekSummary
    let progress: Double
    var lineWidth: CGFloat = 10
    var numeralSize: CGFloat = 26
    var captionSize: CGFloat = 11
    var fill: Color = WidgetTheme.progress
    var track: Color = WidgetTheme.track
    var text: Color = WidgetTheme.ink
    var secondary: Color = WidgetTheme.inkSecondary

    var body: some View {
        RingGauge(progress: progress, lineWidth: lineWidth, color: fill, track: track) {
            VStack(spacing: 0) {
                Text(verbatim: "\(week.completed)/\(week.goal)")
                    .font(WidgetTheme.number(numeralSize))
                    .foregroundStyle(text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("this week")
                    .font(WidgetTheme.text(captionSize))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
            }
        }
        .widgetAccentable()
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
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
#endif
