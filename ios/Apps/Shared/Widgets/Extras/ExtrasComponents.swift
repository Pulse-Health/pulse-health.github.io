// ExtrasComponents.swift
//
// Building blocks of the extra widgets (WI-01...WI-11): the upper-case eyebrow, the empty state, the always-dark card and two text helpers.
// The shared primitives (WidgetTheme, RingGauge, BarMeter, PillLabel ...) stay in Widgets/Common. Nothing here is shared with the other
// widget areas, so every name starts with "Extras".

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

// MARK: - Text

enum ExtrasText {
    /// "a", "a and b", "a, b and c".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    /// "1 session", "3 sessions".
    static func count(_ value: Int, _ noun: String) -> String {
        value == 1 ? "1 \(noun)" : "\(value) \(noun)s"
    }
}

// MARK: - Eyebrow

/// The small upper-case label above a card's content ("FORM CUE").
struct ExtrasEyebrow: View {
    let title: String
    var color: Color = WidgetTheme.inkSecondary
    var size: CGFloat = 12
    /// Lines the title may take before it is scaled down.
    var lines: Int = 1

    var body: some View {
        Text(title)
            .font(WidgetTheme.eyebrow(size))
            .tracking(0.5)
            .foregroundStyle(color)
            .textCase(.uppercase)
            .lineLimit(lines)
            .minimumScaleFactor(0.8)
    }
}

// MARK: - Empty state

/// What a widget shows when there is nothing to draw yet: an icon, a title and one sentence that says where the data comes from.
struct ExtrasEmptyState: View {
    enum Arrangement {
        /// The icon in a round badge beside the text (medium widgets).
        case beside
        /// The icon above the text (small widgets).
        case stacked
    }

    let systemImage: String
    let title: String
    let message: String
    var arrangement: Arrangement = .stacked

    private var isBeside: Bool { arrangement == .beside }

    var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title + ". " + message)
    }

    @ViewBuilder
    private var content: some View {
        if isBeside {
            HStack(spacing: 14) {
                icon
                    .frame(width: 52, height: 52)
                    .background(WidgetTheme.greenTint, in: Circle())
                texts
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                icon
                texts
            }
        }
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(WidgetTheme.green)
            .widgetAccentable()
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(WidgetTheme.text(isBeside ? 17 : 15, .bold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(message)
                .font(WidgetTheme.text(isBeside ? 13 : 12))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(isBeside ? 3 : 4)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Dark card

extension View {
    /// Puts the widget on a card that is dark in the light appearance too ("Year in iron"). The content is drawn in the dark appearance, so
    /// every WidgetTheme token resolves to its dark value and no colour is repeated here.
    func extrasDarkCard() -> some View {
        environment(\.colorScheme, .dark)
            .containerBackground(for: .widget) {
                WidgetTheme.card.environment(\.colorScheme, .dark)
            }
    }
}
#endif
