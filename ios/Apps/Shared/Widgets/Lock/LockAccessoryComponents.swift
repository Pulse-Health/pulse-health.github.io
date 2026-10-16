// LockAccessoryComponents.swift
//
// The building blocks the Lock Screen accessory widgets share. The system draws everything on the Lock Screen in one vibrant colour, so the
// hierarchy is made of size, weight and the system's `.secondary` level, never of hue. The primary figure of each widget is
// `.widgetAccentable()` so a tinted rendering has something to tint; the rest keeps the system's default group.

#if os(iOS)
import SwiftUI
import WidgetKit

extension View {
    /// iOS 17 asks every widget for a container background. The Lock Screen supplies its own plate (`AccessoryWidgetBackground`, drawn by the
    /// view) and treats the widget as one vibrant layer, so the container itself stays clear.
    func lockContainerBackground() -> some View {
        containerBackground(for: .widget) { Color.clear }
    }
}

/// The rounded plate of the rectangular family with the design's 8 x 12 pt of padding around left-aligned content.
struct LockAccessoryCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .leading) {
            AccessoryWidgetBackground()
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The three lines of a rectangular card: a small upper-case label ("NEXT UP"), the bold title, and a detail one level dimmer.
/// Every line stays on one line and shrinks a little before it is cut.
struct LockAccessoryLines<Title: View>: View {
    let eyebrow: String
    let detail: String
    var detailFont: Font = WidgetTheme.text(13)
    @ViewBuilder var title: () -> Title

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(eyebrow)
                .font(WidgetTheme.text(12, .bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            title()
            Text(detail)
                .font(detailFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The bold title of a card: a name, one line, shrunk a little before it is cut.
struct LockAccessoryTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(WidgetTheme.text(16, .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

/// A bold title made of a name that may be cut and a figure that never is: "Bench Press 85 × 5", "Incline Dumbbell Pr… 28 × 10".
struct LockAccessoryHeadline: View {
    let name: String
    let figure: String

    var body: some View {
        HStack(spacing: 4) {
            Text(name).lineLimit(1)
            Text(figure).lineLimit(1).layoutPriority(1)
        }
        .font(WidgetTheme.text(16, .bold))
        .minimumScaleFactor(0.75)
    }
}
#endif
