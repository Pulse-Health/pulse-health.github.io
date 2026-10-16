// NextUpWidget.swift
//
// HS-01 Next up (systemSmall), HS-07 Next workout, previewed (systemMedium), SB-01 (the small widget in StandBy: no card, dark appearance,
// larger type) and SB-04 (StandBy at night: tomorrow's plan in red on black).
//
// Tap targets: a small widget has exactly one, the whole widget, so it starts the next workout through `widgetURL` and draws Start as a
// plain pill. The medium widget has a Start `Link` of its own and opens the Strength hub everywhere else.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct NextUpWidget: Widget {
    static let kind = "health.pulse.strength.widget.nextUp"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            NextUpView(entry: entry)
        }
        .configurationDisplayName("Next up")
        .description("The next workout in your rotation with a Start button. In StandBy at night it shows tomorrow's plan.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextUpView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var isMedium: Bool { family == .systemMedium }
    /// StandBy at night: the system tints the widget red, so tomorrow's plan replaces the Start button.
    private var isNight: Bool { isLuminanceReduced && !isMedium }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if isNight {
                    Color.black
                } else {
                    WidgetTheme.card
                }
            }
            .widgetURL(tapTarget)
    }

    @ViewBuilder
    private var content: some View {
        if isNight {
            NextUpNightContent(tomorrow: snapshot.tomorrow)
        } else if let nextUp = snapshot.nextUp {
            if isMedium {
                NextUpMediumContent(nextUp: nextUp)
            } else {
                NextUpSmallContent(nextUp: nextUp, isStandBy: !showsBackground)
            }
        } else {
            NextUpEmptyContent(isMedium: isMedium)
        }
    }

    private var tapTarget: URL {
        if !isMedium, !isNight, snapshot.nextUp != nil { return StrengthDeepLink.startNext.url }
        return StrengthDeepLink.hub.url
    }
}

// MARK: - Small

private struct NextUpSmallContent: View {
    let nextUp: NextUpSummary
    /// True when the system draws the widget without its card (StandBy): the dark appearance and larger type.
    let isStandBy: Bool

    private var spoken: String {
        let detail = HomeText.spokenPlanDetail(exerciseCount: nextUp.exerciseCount, estimatedMinutes: nextUp.estimatedMinutes)
        return "Next up: " + nextUp.name + ". " + detail + "."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HomeEyebrow(title: "Next up", size: isStandBy ? 13 : 11)
            Text(nextUp.name)
                .font(WidgetTheme.text(isStandBy ? 20 : 17, .bold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(HomeText.planDetail(exerciseCount: nextUp.exerciseCount, estimatedMinutes: nextUp.estimatedMinutes))
                .font(WidgetTheme.text(isStandBy ? 13 : 12))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            PillLabel(title: "Start", systemImage: "play.fill", height: isStandBy ? 38 : 34)
                .widgetAccentable()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .homeDarkAppearance(isStandBy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Starts this workout")
    }
}

// MARK: - Medium

private struct NextUpMediumContent: View {
    let nextUp: NextUpSummary

    private let shownCount = 3

    private var shown: [PlannedExerciseBrief] {
        Array(nextUp.exercises.prefix(shownCount))
    }

    /// "+ 3 more · ~55 min": what the listed rows leave out.
    private var footer: String? {
        var parts: [String] = []
        let more = nextUp.exercises.count - shownCount
        if more > 0 { parts.append("+ \(more) more") }
        if nextUp.estimatedMinutes > 0 { parts.append(WidgetText.minutes(nextUp.estimatedMinutes)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            summaryColumn
            Rectangle()
                .fill(WidgetTheme.separator)
                .frame(width: 1)
                .accessibilityHidden(true)
            exerciseColumn
        }
        .accessibilityElement(children: .contain)
    }

    private var summaryColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            HomeEyebrow(title: "Next up")
            Text(nextUp.name)
                .font(WidgetTheme.text(17, .bold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(HomeText.lastDone(daysSince: nextUp.daysSince))
                .font(WidgetTheme.text(12))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 4)
            HomeStartLink(
                destination: StrengthDeepLink.startNext.url,
                title: "Start",
                spokenTitle: "Start " + nextUp.name,
                height: 34
            )
            .widgetAccentable()
        }
        .frame(width: 120, alignment: .leading)
    }

    private var exerciseColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            if shown.isEmpty {
                Text("No exercises yet")
                    .font(WidgetTheme.text(14))
                    .foregroundStyle(WidgetTheme.inkSecondary)
            }
            ForEach(shown.indices, id: \.self) { index in
                NextUpExerciseRow(exercise: shown[index])
            }
            if let footer {
                Text(footer)
                    .font(WidgetTheme.text(12))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Bench Press ........ 4 × 80": an exercise of the template with its working sets and heaviest weight.
private struct NextUpExerciseRow: View {
    let exercise: PlannedExerciseBrief

    var body: some View {
        HStack(spacing: 8) {
            Text(exercise.name)
                .font(WidgetTheme.text(14))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text(exercise.summary)
                .font(WidgetTheme.number(13, .regular))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Night (StandBy)

/// Tomorrow's plan in red on black. StandBy at night tints everything red, so only `Color.red` is used and the widget never relies on hue.
private struct NextUpNightContent: View {
    let tomorrow: TomorrowPlan?

    private func whenLine(_ plan: TomorrowPlan) -> String {
        guard let minute = plan.plannedMinuteOfDay else { return plan.weekday }
        return plan.weekday + " · " + WidgetText.timeOfDay(minutes: minute)
    }

    private func spoken(_ plan: TomorrowPlan) -> String {
        var sentence = "Tomorrow: " + plan.templateName + ", " + plan.weekday
        if let minute = plan.plannedMinuteOfDay { sentence += " at " + WidgetText.timeOfDay(minutes: minute) }
        sentence += "."
        return plan.note.isEmpty ? sentence : sentence + " " + plan.note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tomorrow")
                .font(WidgetTheme.eyebrow(13))
                .tracking(0.4)
                .textCase(.uppercase)
            if let tomorrow {
                Text(tomorrow.templateName)
                    .font(WidgetTheme.text(19, .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(whenLine(tomorrow))
                    .font(WidgetTheme.text(14, .medium))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !tomorrow.note.isEmpty {
                    Text(tomorrow.note)
                        .font(WidgetTheme.text(13))
                        .foregroundStyle(Color.red.opacity(0.7))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            } else {
                Text("Nothing planned")
                    .font(WidgetTheme.text(19, .bold))
                    .lineLimit(2)
                Text("Create a workout in Pulse Strength")
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(Color.red.opacity(0.7))
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.red)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tomorrow.map { spoken($0) } ?? "Nothing planned. Create a workout in Pulse Strength.")
    }
}

// MARK: - Empty

/// No templates yet: say what to do; the whole widget opens the Strength hub.
private struct NextUpEmptyContent: View {
    let isMedium: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HomeEyebrow(title: "Next up")
                Text("Create a workout in Pulse Strength")
                    .font(WidgetTheme.text(isMedium ? 18 : 15, .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(4)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                PillLabel(title: "Open", systemImage: nil, height: 34)
                    .frame(maxWidth: isMedium ? 140 : CGFloat.infinity)
            }
            if isMedium {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(WidgetTheme.track)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Next up: no workouts yet. Create a workout in Pulse Strength.")
        .accessibilityHint("Opens Pulse Strength")
    }
}
#endif
