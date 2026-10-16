// MonthHeatmapWidget.swift
//
// HS-12 Month heatmap (systemLarge): the current month as a calendar grid, Monday first, each day shaded by its volume relative to the
// month's heaviest day (`WidgetTheme.heat`), today ringed, future days outlined. The numbers in the cells and the spoken label list the days
// that were trained, so the shading is never the only carrier.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct MonthHeatmapWidget: Widget {
    static let kind = "health.pulse.strength.widget.monthHeatmap"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            MonthHeatmapView(entry: entry)
        }
        .configurationDisplayName("Month heatmap")
        .description("The month's training days, shaded by volume. Today is ringed.")
        .supportedFamilies([.systemLarge])
    }
}

struct MonthHeatmapView: View {
    let entry: SnapshotEntry

    private static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]
    private static let gap: CGFloat = 6

    private var month: MonthSummary { entry.snapshot.month }
    private var title: String { month.title.isEmpty ? "This month" : month.title }

    /// The days in rows of seven, Monday first: blanks before the 1st and after the last day.
    private var weeks: [[MonthDay?]] {
        let blanks = min(max(month.leadingBlankDays, 0), 6)
        var cells: [MonthDay?] = Array(repeating: nil, count: blanks)
        cells.append(contentsOf: month.days.map { Optional($0) })
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
    }

    private var spoken: String {
        var sentence = title + ": " + HomeText.sessions(month.sessionCount) + "."
        let trained = month.days.filter { $0.sessions > 0 }.map { String($0.day) }
        if !trained.isEmpty {
            sentence += (trained.count == 1 ? " Trained on day " : " Trained on days ") + HomeText.list(trained) + "."
        }
        if let today = month.days.first(where: { $0.isToday }) { sentence += " Today is day \(today.day)." }
        return sentence
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            weekdayHeader
            if month.days.isEmpty {
                Text("No workouts this month yet")
                    .font(WidgetTheme.text(15, .semibold))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                grid
            }
            legend
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetCardBackground()
        .widgetURL(StrengthDeepLink.hub.url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(WidgetTheme.text(17, .bold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(month.sessionCount)")
                    .font(WidgetTheme.number(13))
                    .foregroundStyle(WidgetTheme.ink)
                Text(month.sessionCount == 1 ? "session" : "sessions")
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.inkSecondary)
            }
            .lineLimit(1)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: Self.gap) {
            ForEach(Self.weekdayLetters.indices, id: \.self) { index in
                Text(Self.weekdayLetters[index])
                    .font(WidgetTheme.text(10))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: Self.gap) {
            ForEach(weeks.indices, id: \.self) { row in
                HStack(spacing: Self.gap) {
                    ForEach(weeks[row].indices, id: \.self) { column in
                        MonthHeatmapCell(day: weeks[row][column])
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("Volume")
                .font(WidgetTheme.text(11))
                .foregroundStyle(WidgetTheme.inkSecondary)
            ForEach(0..<4, id: \.self) { level in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(WidgetTheme.heat(level))
                    .frame(width: 14, height: 14)
            }
            Text("more")
                .font(WidgetTheme.text(11))
                .foregroundStyle(WidgetTheme.inkSecondary)
            Spacer(minLength: 0)
        }
    }
}

/// One day: its number in the top corner on a square shaded by volume. Nil is a blank before the 1st or after the last day.
private struct MonthHeatmapCell: View {
    let day: MonthDay?

    private let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        if let day {
            cell(day)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func cell(_ day: MonthDay) -> some View {
        let level = min(max(day.level, 0), 3)
        return Text("\(day.day)")
            .font(WidgetTheme.number(10, .regular))
            .foregroundStyle(numberColor(day, level: level))
            .padding(.top, 3)
            .padding(.trailing, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .background(day.isFuture ? Color.clear : WidgetTheme.heat(level), in: shape)
            .overlay {
                if day.isToday {
                    shape.strokeBorder(WidgetTheme.ink, lineWidth: 2)
                } else if day.isFuture {
                    shape.strokeBorder(WidgetTheme.track, lineWidth: 1)
                }
            }
    }

    /// Text that stays readable on every step: ink on the light steps, the text colour of a green fill on the darkest one.
    private func numberColor(_ day: MonthDay, level: Int) -> Color {
        if day.isFuture { return WidgetTheme.inkSecondary }
        switch level {
        case 3: return WidgetTheme.onGreen
        case 1, 2: return WidgetTheme.ink
        default: return WidgetTheme.inkSecondary
        }
    }
}
#endif
