// PlateauWidget.swift
//
// WI-10 Plateau watch (systemMedium). The lifts of `plateaus` (the most trained ones, at least three sessions each): a status dot, the lift
// and the trend in words ("rising", "flat 3×", "falling"), and the one-line fix the builder attaches to the first flat lift. Dot colour and
// words say the same thing. When the widget is not tall enough for everything, rows are dropped from the bottom, but the lift that
// carries the tip always stays.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct PlateauWidget: Widget {
    static let kind = "health.pulse.strength.widget.plateau"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            PlateauView(entry: entry)
        }
        .configurationDisplayName("Plateau watch")
        .description("Flags lifts whose estimated max has stalled, with one fix to try.")
        .supportedFamilies([.systemMedium])
    }
}

struct PlateauView: View {
    let entry: SnapshotEntry

    private var plateaus: [PlateauFlag] { entry.snapshot.plateaus }

    /// The lift that carries a tip.
    private var tipped: PlateauFlag? {
        plateaus.first { !($0.tip ?? "").isEmpty }
    }

    /// A tap opens the first lift that is not rising, or the hub when every lift climbs.
    private var target: URL {
        if let flagged = plateaus.first(where: { $0.status != .rising }) {
            return StrengthDeepLink.exercise(id: flagged.exerciseID).url
        }
        return StrengthDeepLink.hub.url
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCardBackground()
            .widgetURL(target)
    }

    @ViewBuilder
    private var content: some View {
        if plateaus.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                header
                ExtrasEmptyState(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: "Not enough history yet",
                    message: "Once a lift has three logged workouts, its trend shows up here.",
                    arrangement: .beside
                )
            }
        } else {
            populated
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Plateau watch")
                .font(WidgetTheme.text(15, .semibold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("recent sessions")
                .font(WidgetTheme.text(12))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(1)
        }
    }

    /// Four rows and the tip if they fit, then fewer rows; the tip goes before the third row does.
    private var populated: some View {
        ViewThatFits(in: .vertical) {
            list(rowLimit: 4, showsTip: true)
            list(rowLimit: 3, showsTip: true)
            list(rowLimit: 3, showsTip: false)
            list(rowLimit: 2, showsTip: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    private func list(rowLimit: Int, showsTip: Bool) -> some View {
        let rows = visibleRows(limit: rowLimit)
        return VStack(alignment: .leading, spacing: 10) {
            header
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows.indices, id: \.self) { index in
                    PlateauRow(flag: rows[index])
                }
            }
            if showsTip, let tip = tipped?.tip, !tip.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(WidgetTheme.goldText)
                        .accessibilityHidden(true)
                    Text(tip)
                        .font(WidgetTheme.text(12))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }
        }
    }

    /// The first `limit` lifts; when the lift with the tip is further down it takes the place of the last one.
    private func visibleRows(limit: Int) -> [PlateauFlag] {
        guard plateaus.count > limit else { return plateaus }
        var rows = Array(plateaus.prefix(limit))
        if let tipped, !rows.contains(tipped) { rows[limit - 1] = tipped }
        return rows
    }

    private var spokenSummary: String {
        var parts = ["Plateau watch."]
        for flag in plateaus {
            parts.append(flag.name + ": " + PlateauRow.spokenStatus(of: flag) + ".")
        }
        if let tip = tipped?.tip { parts.append("Tip: " + tip) }
        return parts.joined(separator: " ")
    }
}

/// Status dot, lift and trend in words.
private struct PlateauRow: View {
    let flag: PlateauFlag

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(flag.name)
                .font(WidgetTheme.text(14))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(statusText)
                .font(WidgetTheme.number(14, .semibold))
                .foregroundStyle(statusColor)
                .lineLimit(1)
        }
    }

    private var dotColor: Color {
        switch flag.status {
        case .rising: return WidgetTheme.ready
        case .flat: return WidgetTheme.recovering
        case .falling: return WidgetTheme.worked
        }
    }

    private var statusColor: Color {
        switch flag.status {
        case .rising: return WidgetTheme.greenText
        case .flat: return WidgetTheme.goldText
        case .falling: return WidgetTheme.heart
        }
    }

    /// "rising", "flat 3×", "falling".
    private var statusText: String {
        flag.status == .flat ? "flat \(flag.flatSessions)\u{00D7}" : flag.status.rawValue
    }

    static func spokenStatus(of flag: PlateauFlag) -> String {
        switch flag.status {
        case .rising: return "rising"
        case .flat: return "flat for " + ExtrasText.count(flag.flatSessions, "session")
        case .falling: return "falling"
        }
    }
}
#endif
