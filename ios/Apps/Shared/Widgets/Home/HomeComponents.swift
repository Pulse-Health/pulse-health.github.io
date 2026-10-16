// HomeComponents.swift
//
// Drawing shared by the Home Screen widgets and not offered by Widgets/Common: the eyebrow label, the recovery dot, a stat tile, the week
// strip, the gold trophy tile, a Start link, and the two appearance helpers (a card that is dark in every appearance, a soft panel inside a
// card). Every type is prefixed `Home` so it cannot collide with the helpers of the other widget areas, which compile into the same target.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

// MARK: - Labels

/// The small upper-case label above a value ("NEXT UP").
struct HomeEyebrow: View {
    let title: String
    var color: Color = WidgetTheme.greenText
    var size: CGFloat = 11

    var body: some View {
        Text(title)
            .font(WidgetTheme.eyebrow(size))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// A value with an optional unit and a caption underneath ("51 min / Duration"). Reads as "Duration: 51 minutes"; `spokenValue` and
/// `spokenUnit` replace the printed ones where they would be read badly ("10 / 12", "t").
struct HomeStatTile: View {
    let value: String
    var unit: String?
    var spokenValue: String?
    var spokenUnit: String?
    let caption: String
    var valueSize: CGFloat = 20

    private var spoken: String {
        let suffix = (spokenUnit ?? unit).map { " " + $0 } ?? ""
        return caption + ": " + (spokenValue ?? value) + suffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(WidgetTheme.number(valueSize))
                    .foregroundStyle(WidgetTheme.ink)
                if let unit {
                    Text(unit)
                        .font(WidgetTheme.number(12, .medium))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(caption)
                .font(WidgetTheme.text(11))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

// MARK: - Recovery dot

/// A muscle's recovery as a dot. The colour comes from `WidgetTheme` and the fill level repeats it, so the state never rests on colour
/// alone: full when ready, half while recovering, an empty ring right after a session. The rows that use it also say the state in words.
struct HomeStatusDot: View {
    let status: FreshnessStatus
    var size: CGFloat = 11

    private var color: Color {
        switch status {
        case .ready: return WidgetTheme.ready
        case .recovering: return WidgetTheme.recovering
        case .worked: return WidgetTheme.worked
        }
    }

    var body: some View {
        ZStack {
            Circle().strokeBorder(color, lineWidth: 1.5)
            switch status {
            case .ready:
                Circle().fill(color)
            case .recovering:
                Circle().trim(from: 0.25, to: 0.75).fill(color).padding(1.5)
            case .worked:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Week strip

/// One weekday: its letter over a circle that is filled with the initials of the day's workout, dashed for today, dim otherwise.
struct HomeWeekDayCell: View {
    let day: DayCell
    let size: CGFloat

    private var initials: String? {
        guard let label = day.label, !label.isEmpty else { return nil }
        return label
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(day.letter)
                .font(WidgetTheme.text(11, day.isToday ? .bold : .regular))
                .foregroundStyle(day.isToday ? WidgetTheme.ink : WidgetTheme.inkSecondary)
            circle
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var circle: some View {
        if day.sessions > 0 {
            ZStack {
                Circle().fill(WidgetTheme.green)
                if let initials {
                    Text(initials)
                        .font(WidgetTheme.text(11, .bold))
                        .foregroundStyle(WidgetTheme.onGreen)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WidgetTheme.onGreen)
                }
            }
            .frame(width: size, height: size)
        } else {
            Circle()
                .fill(WidgetTheme.muted)
                .overlay {
                    if day.isToday {
                        Circle().strokeBorder(WidgetTheme.green, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    }
                }
                .frame(width: size, height: size)
        }
    }
}

/// The seven days of the week, Monday first, as one VoiceOver element ("Monday: 1 workout. Tuesday: no workout. ...").
struct HomeWeekStrip: View {
    let days: [DayCell]
    var circleSize: CGFloat = 34

    private var spoken: String {
        let parts = days.indices.map { index -> String in
            let day = days[index]
            let name = index < HomeDates.weekdayNames.count ? HomeDates.weekdayNames[index] : day.letter
            if day.sessions > 0 {
                return name + ": " + (day.sessions == 1 ? "1 workout" : "\(day.sessions) workouts")
            }
            if day.isToday { return name + ": today, no workout yet" }
            return name + (day.isFuture ? ": upcoming" : ": no workout")
        }
        return parts.joined(separator: ". ")
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(days.indices, id: \.self) { index in
                HomeWeekDayCell(day: days[index], size: circleSize)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

// MARK: - Records

/// The gold rounded tile with a trophy that marks a personal record.
struct HomeTrophyTile: View {
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: "trophy.fill")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(WidgetTheme.goldText)
            .frame(width: size, height: size)
            .background(WidgetTheme.gold.opacity(0.24), in: RoundedRectangle(cornerRadius: size * 0.29, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Links

/// A Start button for the medium and larger families, where a `Link` is a tap target of its own. (A small widget has one tap target, the
/// whole widget through `widgetURL`, so it draws a plain `PillLabel` instead.)
struct HomeStartLink: View {
    let destination: URL
    let title: String
    let spokenTitle: String
    var height: CGFloat = 36

    var body: some View {
        Link(destination: destination) {
            PillLabel(title: title, systemImage: "play.fill", height: height)
        }
        .accessibilityLabel(spokenTitle)
    }
}

// MARK: - Appearance

/// Draws the content in the dark appearance when `forced` is true: StandBy without a card, and the dark "Beat last time" card. The colours stay
/// the `WidgetTheme` tokens; only the scheme they resolve in changes.
private struct HomeDarkAppearance: ViewModifier {
    let forced: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, forced ? .dark : colorScheme)
    }
}

extension View {
    /// The view in the dark appearance when `forced`, otherwise in the system's.
    func homeDarkAppearance(_ forced: Bool = true) -> some View {
        modifier(HomeDarkAppearance(forced: forced))
    }

    /// A card that is dark in every appearance: the dark card colour behind the widget, and the dark values of every token inside it.
    func homeDarkCard() -> some View {
        homeDarkAppearance()
            .containerBackground(for: .widget) { WidgetTheme.card.environment(\.colorScheme, .dark) }
    }

    /// The soft rounded panel inside a card (the last session, a stat tile).
    func homeInsetCard(padding: CGFloat = 12, cornerRadius: CGFloat = WidgetTheme.cornerRadius) -> some View {
        self.padding(padding)
            .background(WidgetTheme.rowFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
#endif
