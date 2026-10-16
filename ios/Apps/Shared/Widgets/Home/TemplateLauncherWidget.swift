// TemplateLauncherWidget.swift
//
// HS-11 Template launcher (systemLarge): up to four templates, the suggested one first, each a `Link` that starts it, and an "Empty workout"
// row. A row is a tap target of its own with a 44 pt round play button; the title and the rest of the widget open the hub. The suggested
// template has the filled button and a "Next" tag, so it does not rest on colour alone.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct TemplateLauncherWidget: Widget {
    static let kind = "health.pulse.strength.widget.templateLauncher"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            TemplateLauncherView(entry: entry)
        }
        .configurationDisplayName("Template launcher")
        .description("Start any workout template, or an empty workout, with one tap. The suggested template comes first.")
        .supportedFamilies([.systemLarge])
    }
}

struct TemplateLauncherView: View {
    let entry: SnapshotEntry

    private static let maxTemplates = 4

    /// The suggested template first, then the others in the order of the app; at most four.
    private var listed: [TemplateSummary] {
        let templates = entry.snapshot.templates
        let ordered = templates.filter { $0.isSuggested } + templates.filter { !$0.isSuggested }
        return Array(ordered.prefix(Self.maxTemplates))
    }

    private var hiddenCount: Int {
        max(0, entry.snapshot.templates.count - Self.maxTemplates)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if listed.isEmpty {
                noTemplates
                separator
            }
            ForEach(listed.indices, id: \.self) { index in
                TemplateLauncherRow(template: listed[index])
                    .frame(maxHeight: .infinity)
                separator
            }
            TemplateLauncherEmptyRow()
                .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetCardBackground()
        .widgetURL(StrengthDeepLink.hub.url)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Start a workout")
                .font(WidgetTheme.text(17, .bold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            if hiddenCount > 0 {
                Text(verbatim: "+ \(hiddenCount) more")
                    .font(WidgetTheme.text(12))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.bottom, 4)
    }

    private var separator: some View {
        Rectangle()
            .fill(WidgetTheme.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    /// No templates: say what to do. "Empty workout" below still works.
    private var noTemplates: some View {
        VStack(spacing: 8) {
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(WidgetTheme.track)
                .accessibilityHidden(true)
            Text("Create a workout in Pulse Strength")
                .font(WidgetTheme.text(15, .semibold))
                .foregroundStyle(WidgetTheme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Text("Your templates will be listed here with a Start button.")
                .font(WidgetTheme.text(13))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// One template: its name (and "Next" when suggested), what it holds, and the round play button.
private struct TemplateLauncherRow: View {
    let template: TemplateSummary

    private var detail: String {
        var parts = [HomeText.planDetail(exerciseCount: template.exerciseCount, estimatedMinutes: template.estimatedMinutes)]
        if let since = HomeText.sinceShort(daysSince: template.daysSince) { parts.append(since) }
        return parts.joined(separator: " · ")
    }

    private var spoken: String {
        var sentence = "Start " + template.name + ". "
        sentence += HomeText.spokenPlanDetail(exerciseCount: template.exerciseCount, estimatedMinutes: template.estimatedMinutes)
        if let days = template.daysSince { sentence += ", last done " + WidgetText.daysAgo(days).lowercased() }
        sentence += "."
        return template.isSuggested ? sentence + " Suggested next." : sentence
    }

    var body: some View {
        Link(destination: StrengthDeepLink.start(templateID: template.templateID).url) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(template.name)
                            .font(WidgetTheme.text(15, .semibold))
                            .foregroundStyle(WidgetTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if template.isSuggested {
                            nextTag
                        }
                    }
                    Text(detail)
                        .font(WidgetTheme.text(13))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 8)
                playButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(spoken)
    }

    private var nextTag: some View {
        Text("Next")
            .font(WidgetTheme.eyebrow(10))
            .textCase(.uppercase)
            .foregroundStyle(WidgetTheme.greenText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(WidgetTheme.greenTint, in: Capsule())
            .fixedSize()
            .layoutPriority(1)
    }

    /// The suggested template has the filled button, the others a tinted one.
    private var playButton: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(template.isSuggested ? WidgetTheme.onGreen : WidgetTheme.greenText)
            .frame(width: 44, height: 44)
            .background(template.isSuggested ? WidgetTheme.green : WidgetTheme.greenTint, in: Circle())
            .widgetAccentable(template.isSuggested)
    }
}

/// "Empty workout": starts a workout without a template.
private struct TemplateLauncherEmptyRow: View {
    var body: some View {
        Link(destination: StrengthDeepLink.startEmpty(name: StrengthConfig.defaultWorkoutName).url) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Empty workout")
                        .font(WidgetTheme.text(15, .semibold))
                        .foregroundStyle(WidgetTheme.ink)
                        .lineLimit(1)
                    Text("Add exercises as you go")
                        .font(WidgetTheme.text(13))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 8)
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .frame(width: 44, height: 44)
                    .background(WidgetTheme.muted, in: Circle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Start an empty workout. Add exercises as you go.")
    }
}
#endif
