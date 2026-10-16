// PartnerWidget.swift
//
// WI-03 Gym partner (systemMedium). Your own week (`week`) above the weeks of up to two training partners (`partners`, supplied by the Pulse
// app): an avatar, a progress bar and "3/4" per row, then one sentence about who closed the week. There is no ranking: partners keep the
// order the host gave them. Without partners the widget explains where they come from.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct PartnerWidget: Widget {
    static let kind = "health.pulse.strength.widget.partner"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            PartnerView(entry: entry)
        }
        .configurationDisplayName("Gym partner")
        .description("Your weekly goal next to your training partners'. Partners come from the Pulse app.")
        .supportedFamilies([.systemMedium])
    }
}

struct PartnerView: View {
    let entry: SnapshotEntry

    private var week: WeekSummary { entry.snapshot.week }
    private var partners: [PartnerWeek] { entry.snapshot.partners }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCardBackground()
            .widgetURL(StrengthDeepLink.hub.url)
    }

    @ViewBuilder
    private var content: some View {
        if partners.isEmpty {
            ExtrasEmptyState(
                systemImage: "person.2.fill",
                title: "Invite a partner",
                message: "Training partners come from the Pulse app. Invite one there to share your weekly goal.",
                arrangement: .beside
            )
        } else {
            populated
        }
    }

    private var populated: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Training partners \u{00B7} this week")
                .font(WidgetTheme.text(15, .semibold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            // Rows come first, the sentence goes when the widget is not tall enough for it.
            ViewThatFits(in: .vertical) {
                list(partnerLimit: 2, showsStatus: true)
                list(partnerLimit: 2, showsStatus: false)
                list(partnerLimit: 1, showsStatus: true)
                list(partnerLimit: 1, showsStatus: false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    private func list(partnerLimit: Int, showsStatus: Bool) -> some View {
        let shown = Array(partners.prefix(partnerLimit))
        return VStack(alignment: .leading, spacing: 8) {
            PartnerRow(badge: "You", isYou: true, completed: week.completed, goal: week.goal)
            ForEach(shown.indices, id: \.self) { index in
                PartnerRow(
                    badge: Self.badge(for: shown[index]),
                    isYou: false,
                    completed: shown[index].completed,
                    goal: shown[index].goal
                )
            }
            if showsStatus, let status = statusLine {
                Text(status)
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    /// The initials the host gave, or the first letter of the name.
    private static func badge(for partner: PartnerWeek) -> String {
        let initials = partner.initials.trimmingCharacters(in: .whitespacesAndNewlines)
        if !initials.isEmpty { return String(initials.prefix(2)).uppercased() }
        return String(partner.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    /// Who closed the week, from the point of view of the person looking: nil when nothing needs saying.
    private var statusLine: String? {
        let closed = partners.filter { $0.closedWeek }
        let youClosed = week.completed >= week.goal
        if !youClosed, let first = closed.first {
            let others = closed.count - 1
            let names = others == 0 ? first.name : "\(first.name) and \(others) more"
            return "\(names) closed their week. Your turn."
        }
        guard youClosed else { return nil }
        if closed.count == partners.count { return "Everyone closed their week." }
        if let open = partners.first(where: { !$0.closedWeek }) {
            return "You closed your week. \(open.name) has \(max(0, open.goal - open.completed)) to go."
        }
        return nil
    }

    private var spokenSummary: String {
        var parts = ["Training partners this week.", "You: \(week.completed) of \(week.goal) workouts."]
        for partner in partners {
            let closed = partner.closedWeek ? ", closed the week" : ""
            parts.append("\(partner.name): \(partner.completed) of \(partner.goal) workouts\(closed).")
        }
        if let status = statusLine { parts.append(status) }
        return parts.joined(separator: " ")
    }
}

/// Avatar, progress bar and "3/4". The person looking is green and in the accent group (tinted mode); partners are blue.
private struct PartnerRow: View {
    let badge: String
    let isYou: Bool
    let completed: Int
    let goal: Int

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ExtrasPalette { ExtrasPalette(renderingMode: renderingMode, colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 10) {
            Text(badge)
                .font(WidgetTheme.text(badge.count > 1 ? 12 : 14, .bold))
                .foregroundStyle(isYou ? WidgetTheme.onGreen : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 30, height: 30)
                .background {
                    Circle()
                        .fill(isYou ? WidgetTheme.green : palette.other)
                        .widgetAccentable(isYou)
                }
            ExtrasProgressBar(
                fraction: goal > 0 ? Double(completed) / Double(goal) : 0,
                color: isYou ? WidgetTheme.progress : WidgetTheme.blue,
                height: 10,
                isAccented: isYou
            )
            Text(verbatim: "\(completed)/\(goal)")
                .font(WidgetTheme.number(14))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 36, alignment: .trailing)
        }
    }
}
#endif
