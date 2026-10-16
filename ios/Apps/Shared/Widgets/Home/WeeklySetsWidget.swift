// WeeklySetsWidget.swift
//
// HS-08 Weekly sets per muscle (systemMedium): one bar per major group (chest, back, shoulders, legs) and arms. A bar is full at the top of
// the target range, green on or above the bottom of it and grey below it; the count at the end of the row and the spoken label carry the
// same information in words.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct WeeklySetsWidget: Widget {
    static let kind = "health.pulse.strength.widget.weeklySets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            WeeklySetsView(entry: entry)
        }
        .configurationDisplayName("Weekly sets")
        .description("Sets per muscle group this week against the target range. Groups below target fade to grey.")
        .supportedFamilies([.systemMedium])
    }
}

struct WeeklySetsView: View {
    let entry: SnapshotEntry

    /// The majors in the order of the design, then arms; core is left out.
    private static let groups: [MuscleGroup] = [.chest, .back, .shoulders, .legs, .arms]

    private var rows: [MuscleSetsProgress] {
        let all = entry.snapshot.weeklySets.muscles
        return Self.groups.compactMap { group in all.first(where: { $0.muscle == group }) }
    }

    private var majorTarget: MuscleSetsProgress? { rows.first(where: { $0.muscle != .arms }) }

    /// Arms have their own range; it is named only when it differs from the majors'.
    private var armsTarget: MuscleSetsProgress? {
        guard let arms = rows.first(where: { $0.muscle == .arms }), let major = majorTarget else { return nil }
        let same = arms.targetLow == major.targetLow && arms.targetHigh == major.targetHigh
        return same ? nil : arms
    }

    private func range(_ row: MuscleSetsProgress, separator: String) -> String {
        "\(row.targetLow)" + separator + "\(row.targetHigh)"
    }

    /// "target 10–14 · arms 6–10"
    private var caption: String {
        guard let major = majorTarget else { return "" }
        var text = "target " + range(major, separator: "–")
        if let arms = armsTarget { text += " · arms " + range(arms, separator: "–") }
        return text
    }

    private var spoken: String {
        let sentences = rows.map { row -> String in
            let sets = row.sets == 1 ? "1 set" : "\(row.sets) sets"
            return row.muscle.title + ": " + sets + ", " + HomeText.spoken(row.status) + "."
        }
        var text = "Sets this week. " + sentences.joined(separator: " ")
        if let major = majorTarget {
            text += " Target " + range(major, separator: " to ") + " sets"
            if let arms = armsTarget { text += ", arms " + range(arms, separator: " to ") }
            text += "."
        }
        return text
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCardBackground()
            .widgetURL(StrengthDeepLink.hub.url)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(rows.isEmpty ? "Sets this week. No sets logged yet." : spoken)
    }

    @ViewBuilder
    private var content: some View {
        if rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sets this week")
                    .font(WidgetTheme.text(15, .semibold))
                    .foregroundStyle(WidgetTheme.ink)
                Spacer(minLength: 4)
                Text("No sets logged yet")
                    .font(WidgetTheme.text(17, .bold))
                    .foregroundStyle(WidgetTheme.ink)
                Text("Finish a workout to see your sets per muscle group.")
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Sets this week")
                        .font(WidgetTheme.text(15, .semibold))
                        .foregroundStyle(WidgetTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(caption)
                        .font(WidgetTheme.text(12))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        WeeklySetsRow(item: rows[index])
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// "Chest  ▬▬▬▬▬▬▬▬▬  12": the bar fills to the top of the target range.
private struct WeeklySetsRow: View {
    let item: MuscleSetsProgress

    private var fraction: Double {
        item.targetHigh > 0 ? Double(item.sets) / Double(item.targetHigh) : 0
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(item.muscle.title)
                .font(WidgetTheme.text(13))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 66, alignment: .leading)
            BarMeter(
                fraction: fraction,
                color: item.status == .under ? WidgetTheme.trackStrong : WidgetTheme.progress,
                track: WidgetTheme.track,
                height: 9
            )
            Text("\(item.sets)")
                .font(WidgetTheme.number(13))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .frame(width: 24, alignment: .trailing)
        }
    }
}
#endif
