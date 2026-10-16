// YearInIronWidget.swift
//
// WI-08 Year in iron (systemSmall, dark). The tonnes lifted this calendar year (`year`), the session count and one bar per month. The card
// is dark in the light appearance too (`extrasDarkCard`); the current month is full strength, the other months are dimmed, and months
// without volume are a short grey stub, so "no data yet" is not mistaken for "a little".

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct YearInIronWidget: Widget {
    static let kind = "health.pulse.strength.widget.yearInIron"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            YearInIronView(entry: entry)
        }
        .configurationDisplayName("Year in iron")
        .description("The tonnes you have lifted this year, with a bar for every month.")
        .supportedFamilies([.systemSmall])
    }
}

struct YearInIronView: View {
    let entry: SnapshotEntry

    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    private var year: YearSummary { entry.snapshot.year }

    /// Twelve values, January first; a snapshot without the list (nothing lifted yet) counts as twelve empty months.
    private var months: [Double] {
        var values = Array(year.monthlyTonnes.prefix(12))
        while values.count < 12 { values.append(0) }
        return values
    }

    /// The month of the snapshot, in its own time zone; only when it belongs to the year shown.
    private var currentMonth: Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: entry.snapshot.timeZoneID) ?? .current
        let parts = calendar.dateComponents([.year, .month], from: entry.snapshot.generatedAt)
        guard parts.year == year.year, let month = parts.month else { return nil }
        return month - 1
    }

    private var subtitle: String {
        year.sessionCount == 0 ? "Finish a workout to start the count." : "across " + ExtrasText.count(year.sessionCount, "session")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExtrasEyebrow(title: "Lifted in " + String(year.year))
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(NumberText.kg(year.tonnes))
                        .font(WidgetTheme.number(36))
                        .foregroundStyle(WidgetTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("t")
                        .font(WidgetTheme.number(20, .semibold))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                }
                Text(subtitle)
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.green)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 6)
            YearInIronBars(values: months, highlighted: currentMonth ?? months.lastIndex(where: { $0 > 0 }))
                .frame(minHeight: 14, maxHeight: 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .extrasDarkCard()
        .widgetURL(StrengthDeepLink.hub.url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    private var spokenSummary: String {
        var text = "\(NumberText.kg(year.tonnes)) tonnes lifted in \(year.year)"
        text += year.sessionCount == 0 ? "." : " across " + ExtrasText.count(year.sessionCount, "session") + "."
        let values = months
        var busiest = 0
        for index in values.indices where values[index] > values[busiest] {
            busiest = index
        }
        if values[busiest] > 0 {
            text += " Busiest month: \(Self.monthNames[busiest]), \(NumberText.kg(values[busiest])) tonnes."
        }
        return text
    }
}

/// Twelve bars, January on the left, as tall as the month's tonnage relative to the heaviest month.
private struct YearInIronBars: View {
    let values: [Double]
    let highlighted: Int?

    var body: some View {
        GeometryReader { proxy in
            let peak = values.max() ?? 0
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(values.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(values[index] > 0 ? WidgetTheme.green : WidgetTheme.track)
                        .opacity(index == highlighted || values[index] <= 0 ? 1 : 0.5)
                        .frame(height: height(of: values[index], peak: peak, available: proxy.size.height))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    private func height(of value: Double, peak: Double, available: CGFloat) -> CGFloat {
        guard value > 0, peak > 0 else { return 3 }
        return max(3, available * CGFloat(value / peak))
    }
}
#endif
