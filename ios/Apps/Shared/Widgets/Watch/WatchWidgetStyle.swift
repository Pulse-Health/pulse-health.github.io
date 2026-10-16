// WatchWidgetStyle.swift
//
// The few colours, controls and text blocks the Watch widgets share. Colours come from WidgetTheme (its adaptive colours resolve to the dark
// values on the Watch, which is always dark); this file adds the two the canvas uses that the Home Screen does not, the rest/countdown
// views that keep running by themselves inside a widget, and the button that falls back to a plain label before watchOS 11.
// Compiled into the watchOS widget extension.

#if os(watchOS)
import AppIntents
import SwiftUI
import WidgetKit
import PulseStrengthCore

// MARK: - Tokens

enum WatchStyle {
    /// Background of the Next up card (the dark green of Watch.dc.html).
    static let greenCard = WidgetTheme.hex(0x0E2A19)
    /// The streak flame.
    static let flame = WidgetTheme.hex(0xFF9F0A)
    /// The smallest size of a control (points).
    static let touchTarget: CGFloat = 44
}

// MARK: - Clock override

private struct WatchStaticNowKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    /// Snapshot tests only (nil in production): draw rest rings and countdowns for this instant instead of the live timer views, which an
    /// image renderer cannot run.
    var watchWidgetStaticNow: Date? {
        get { self[WatchStaticNowKey.self] }
        set { self[WatchStaticNowKey.self] = newValue }
    }
}

// MARK: - Countdown

/// The countdown of a running rest. In a widget `Text(timerInterval:countsDown:)` counts down by itself; it is greedy in width, so every use
/// gives it a `width`.
struct WatchCountdownText: View {
    let interval: ClosedRange<Date>
    var size: CGFloat
    var weight: Font.Weight = .bold
    var color: Color = WidgetTheme.progress
    var width: CGFloat?
    var alignment: Alignment = .leading
    @Environment(\.watchWidgetStaticNow) private var staticNow

    var body: some View {
        label
            .font(WidgetTheme.number(size, weight))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: width, alignment: alignment)
    }

    private var label: Text {
        if let now = staticNow {
            let remaining = max(0, interval.upperBound.timeIntervalSince(now)).rounded(.up)
            return Text(NumberText.clock(seconds: Int(remaining)))
        }
        return Text(timerInterval: interval, countsDown: true, showsHours: false)
    }
}

/// A ring that drains over `interval` (a live `ProgressView(timerInterval:)`), or a fixed ring at `fixedFraction` when no countdown runs.
/// The ring is `diameter` points wide; the live ring's line weight is the system's, the fixed ring's is `lineWidth`.
struct WatchRestRing: View {
    let interval: ClosedRange<Date>?
    var fixedFraction: Double = 0
    var diameter: CGFloat = WatchStyle.touchTarget
    var lineWidth: CGFloat = 4.5
    @Environment(\.watchWidgetStaticNow) private var staticNow

    var body: some View {
        ring
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var ring: some View {
        if let interval, staticNow == nil {
            ProgressView(timerInterval: interval, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(WidgetTheme.progress)
        } else {
            RingGauge(progress: staticFraction, lineWidth: lineWidth, color: WidgetTheme.progress, track: WidgetTheme.track)
        }
    }

    /// The share of the rest that is left at the override instant, or the fixed share.
    private var staticFraction: Double {
        guard let interval, let now = staticNow else { return fixedFraction }
        let total = interval.upperBound.timeIntervalSince(interval.lowerBound)
        guard total > 0 else { return 0 }
        return min(1, max(0, interval.upperBound.timeIntervalSince(now) / total))
    }
}

// MARK: - Buttons

/// A button that runs an App Intent. Interactive widgets exist from watchOS 11; before that the label is drawn as it is and a tap on the
/// widget opens the Watch app through `widgetURL`. The first button of the top Smart Stack widget is the target of the double-tap gesture.
struct WatchIntentButton<Intent: AppIntent, Content: View>: View {
    let intent: Intent
    let label: Content

    init(intent: Intent, @ViewBuilder label: () -> Content) {
        self.intent = intent
        self.label = label()
    }

    var body: some View {
        if #available(watchOS 11, *) {
            Button(intent: intent) {
                label
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }
}

/// The round face of a widget button: a glyph or a short title on a filled circle (44 pt, the smallest touch target).
struct WatchRoundButtonLabel: View {
    var systemImage: String?
    var title: String?
    var fill: Color
    var foreground: Color

    var body: some View {
        ZStack {
            Circle().fill(fill)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
            }
            if let title {
                Text(title)
                    .font(WidgetTheme.number(14, .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(foreground)
        .frame(width: WatchStyle.touchTarget, height: WatchStyle.touchTarget)
        .contentShape(Circle())
    }
}

// MARK: - Text blocks

/// The three-line block of a rectangular widget: a small coloured heading, a title and a detail line.
struct WatchRectMessage: View {
    let eyebrow: String
    let title: String
    let detail: String
    var tint: Color = WidgetTheme.green

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(eyebrow)
                .font(WidgetTheme.eyebrow(11))
                .foregroundStyle(tint)
                .lineLimit(1)
                .widgetAccentable()
            Text(title)
                .font(WidgetTheme.text(15, .bold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(WidgetTheme.text(12))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// An inline complication: the first wording that fits the width of the slot, with an optional glyph in front. (The slot offers one line of
/// text; the face sets its font and colour.) `spoken` is what VoiceOver reads; a countdown inside a wording keeps counting.
struct WatchInlineText: View {
    let long: Text
    let medium: Text
    let short: Text
    let spoken: String
    var systemImage: String?

    init(long: Text, medium: Text, short: Text, spoken: String, systemImage: String? = nil) {
        self.long = long
        self.medium = medium
        self.short = short
        self.spoken = spoken
        self.systemImage = systemImage
    }

    /// Plain wordings; the longest one is also what VoiceOver reads.
    init(long: String, medium: String, short: String, systemImage: String? = nil) {
        self.init(
            long: Text(verbatim: long),
            medium: Text(verbatim: medium),
            short: Text(verbatim: short),
            spoken: long,
            systemImage: systemImage
        )
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(long)
            line(medium)
            line(short)
        }
        .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private func line(_ text: Text) -> some View {
        if let systemImage {
            Label {
                text
            } icon: {
                Image(systemName: systemImage)
            }
        } else {
            text
        }
    }
}
#endif
