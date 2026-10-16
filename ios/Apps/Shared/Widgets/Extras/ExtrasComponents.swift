// ExtrasComponents.swift
//
// Building blocks of the extra widgets (WI-01...WI-11): the fills that survive the system's tinted mode, an accent-aware progress bar and
// pill, the upper-case eyebrow, the empty state, the always-dark card and two text helpers. The shared primitives (WidgetTheme, RingGauge,
// BarMeter, PillLabel ...) stay in Widgets/Common. Nothing here is shared with the other widget areas, so every name starts with "Extras".
//
// Tinted mode: the system renders a widget in two groups, the accented views (`widgetAccentable`) and all others, and it "ignores the
// view's color, rendering the new colors based on the view's alpha channel" (on iOS 26 both groups are simply white). Two consequences
// drive this file: a label on a solid fill vanishes, because both are the same colour, and fills that differ only in colour (heat levels,
// kinds of rest) merge. Only alpha tells things apart in every version, so in tinted mode fills are alpha steps of one colour, and
// `widgetAccentable` is kept on the hero elements for the versions that tint the accent group.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

// MARK: - Palette

/// The fills the extra widgets draw behind and beside their content. In full colour they are the colours of `WidgetTheme`; in tinted mode
/// each one is the ink colour at its own alpha step, which the system then renders in the primary colour (or the tint, for accented views).
struct ExtrasPalette {
    let isTinted: Bool
    let isDark: Bool

    init(renderingMode: WidgetRenderingMode, colorScheme: ColorScheme) {
        isTinted = renderingMode == .accented
        isDark = colorScheme == .dark
    }

    /// A stepper or button surface on the card.
    var surface: Color { isTinted ? WidgetTheme.ink.opacity(0.14) : WidgetTheme.muted }

    /// A round button on a `surface`: white on the light grey, a lighter grey on the dark one.
    var raised: Color {
        if isTinted { return WidgetTheme.ink.opacity(0.26) }
        return isDark ? WidgetTheme.track : WidgetTheme.card
    }

    /// The empty part of a bar, ring or row of dots; the head of the silhouette.
    var track: Color { isTinted ? WidgetTheme.ink.opacity(0.18) : WidgetTheme.track }

    /// The one in between: the set that waits, a rest.
    var step: Color { isTinted ? WidgetTheme.ink.opacity(0.5) : WidgetTheme.trackStrong }

    /// The avatar of someone else: blue, or a soft fill that leaves the initials readable in tinted mode.
    var other: Color { isTinted ? WidgetTheme.ink.opacity(0.16) : WidgetTheme.blue }

    /// The fill of a button or badge behind its label: `color` in full colour, a translucent fill in tinted mode, where a solid one would
    /// swallow the label.
    func action(_ color: Color) -> Color { isTinted ? WidgetTheme.ink.opacity(0.32) : color }

    /// The soft round badge behind an icon.
    var badge: Color { isTinted ? WidgetTheme.ink.opacity(0.18) : WidgetTheme.greenTint }

    /// Body map shade of a level (0...3). The canvas draws an untrained region in the track grey: `WidgetTheme.heat(0)` is almost white and
    /// would vanish on the card.
    func heat(_ level: Int) -> Color {
        let clamped = min(3, max(0, level))
        if isTinted { return WidgetTheme.ink.opacity([0.18, 0.4, 0.7, 1][clamped]) }
        return clamped == 0 ? WidgetTheme.track : WidgetTheme.heat(clamped)
    }
}

// MARK: - Progress bar

/// A horizontal bar: `fraction` of the width in `color` over a track. In tinted mode the track is a faint alpha step, so the solid fill
/// stays apart from it; the fill is in the accent group unless `isAccented` is false (the bars of other people).
struct ExtrasProgressBar: View {
    var fraction: Double
    var color: Color = WidgetTheme.progress
    var height: CGFloat = 8
    var isAccented: Bool = true

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ExtrasPalette { ExtrasPalette(renderingMode: renderingMode, colorScheme: colorScheme) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                if fraction > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(height, proxy.size.width * CGFloat(min(1, max(0, fraction)))))
                        .widgetAccentable(isAccented)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Pill

/// A rounded "button-looking" label for places where the real control is the whole widget (`widgetURL`) or a `Link`. In tinted mode its
/// fill turns translucent, so the label stays readable on it (`PillLabel` keeps a solid fill, which swallows the label there).
struct ExtrasPill: View {
    var title: String
    var systemImage: String?
    var fill: Color = WidgetTheme.green
    var foreground: Color = WidgetTheme.onGreen
    var height: CGFloat = 36

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ExtrasPalette { ExtrasPalette(renderingMode: renderingMode, colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
            }
            Text(title)
                .font(WidgetTheme.text(15, .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background {
            Capsule().fill(palette.action(fill)).widgetAccentable()
        }
    }
}

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

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ExtrasPalette { ExtrasPalette(renderingMode: renderingMode, colorScheme: colorScheme) }
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
                    .background(palette.badge, in: Circle())
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
