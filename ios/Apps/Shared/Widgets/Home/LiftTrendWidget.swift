// LiftTrendWidget.swift
//
// HS-09 Lift trend (systemMedium): the estimated 1RM of one lift over its last sessions. The only Home Screen widget with a user choice, so
// it is an `AppIntentConfiguration`: the intent's parameter is a `LiftTrendEntity`, one of `WidgetSnapshot.lifts` (the most trained lifts of
// the last 90 days). Nothing chosen, or a lift that dropped out of that list, shows the first lift. The big number is the best estimate, the
// gold point on the line is the record, and a tap opens the exercise.

#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit
import PulseStrengthCore

// MARK: - Configuration

/// A lift the widget can plot.
struct LiftTrendEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Lift")
    static let defaultQuery = LiftTrendEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    /// The lifts of the stored snapshot, most trained first.
    static func available() -> [LiftTrendEntity] {
        SnapshotLoading.current().lifts.map { LiftTrendEntity(id: $0.exerciseID, name: $0.name) }
    }
}

struct LiftTrendEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [LiftTrendEntity] {
        LiftTrendEntity.available().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [LiftTrendEntity] {
        LiftTrendEntity.available()
    }

    func defaultResult() async -> LiftTrendEntity? {
        LiftTrendEntity.available().first
    }
}

struct LiftTrendConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Lift"
    static let description = IntentDescription("Choose the exercise whose estimated one-rep max the widget plots. Without a choice it shows your most trained lift.")

    @Parameter(title: "Lift")
    var lift: LiftTrendEntity?
}

// MARK: - Timeline

struct LiftTrendEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// The `exerciseID` of the chosen lift; nil shows the most trained one.
    let liftID: String?
    /// True for the gallery / redacted placeholder (the preview snapshot, never live data).
    var isPlaceholder: Bool = false
}

struct LiftTrendProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> LiftTrendEntry {
        LiftTrendEntry(date: Date(), snapshot: .preview, liftID: nil, isPlaceholder: true)
    }

    func snapshot(for configuration: LiftTrendConfigurationIntent, in context: Context) async -> LiftTrendEntry {
        if context.isPreview {
            return LiftTrendEntry(date: Date(), snapshot: .preview, liftID: configuration.lift?.id, isPlaceholder: true)
        }
        return LiftTrendEntry(date: Date(), snapshot: SnapshotLoading.current(), liftID: configuration.lift?.id)
    }

    func timeline(for configuration: LiftTrendConfigurationIntent, in context: Context) async -> Timeline<LiftTrendEntry> {
        let base = SnapshotLoading.timeline(for: SnapshotLoading.current())
        let entries = base.entries.map { LiftTrendEntry(date: $0.date, snapshot: $0.snapshot, liftID: configuration.lift?.id) }
        return Timeline(entries: entries, policy: base.policy)
    }
}

// MARK: - Widget

struct LiftTrendWidget: Widget {
    static let kind = "health.pulse.strength.widget.liftTrend"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: LiftTrendConfigurationIntent.self, provider: LiftTrendProvider()) { entry in
            LiftTrendView(entry: entry)
        }
        .configurationDisplayName("Lift trend")
        .description("The estimated one-rep max of a lift over its last sessions, with the record in gold. Edit the widget to choose the lift.")
        .supportedFamilies([.systemMedium])
    }
}

struct LiftTrendView: View {
    let entry: LiftTrendEntry

    /// The chosen lift, or the most trained one.
    private var lift: LiftTrend? {
        let lifts = entry.snapshot.lifts
        if let id = entry.liftID, let chosen = lifts.first(where: { $0.exerciseID == id }) { return chosen }
        return lifts.first
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCardBackground()
            .widgetURL(url)
    }

    @ViewBuilder
    private var content: some View {
        if let lift {
            LiftTrendContent(lift: lift, now: entry.date, timeZoneID: entry.snapshot.timeZoneID)
        } else {
            LiftTrendEmptyContent()
        }
    }

    private var url: URL {
        guard let lift else { return StrengthDeepLink.hub.url }
        return StrengthDeepLink.exercise(id: lift.exerciseID).url
    }
}

private struct LiftTrendContent: View {
    let lift: LiftTrend
    let now: Date
    let timeZoneID: String

    private var spoken: String {
        var sentence = lift.name + ". Estimated one-rep max " + WidgetText.kg(lift.bestE1RM)
        sentence += " over " + HomeText.sessions(lift.sessionCount) + "."
        let recent = lift.points.map { NumberText.kg($0.value) }
        if !recent.isEmpty { sentence += " Recent sessions: " + HomeText.list(recent) + " kilograms." }
        if lift.prIndex != nil { sentence += " The highest is a personal record." }
        return sentence
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(lift.name)
                        .font(WidgetTheme.text(15, .semibold))
                        .foregroundStyle(WidgetTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Estimated 1RM · " + HomeText.sessions(lift.sessionCount))
                        .font(WidgetTheme.text(12))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(NumberText.kg(lift.bestE1RM))
                        .font(WidgetTheme.number(28))
                        .foregroundStyle(WidgetTheme.ink)
                    Text("kg")
                        .font(WidgetTheme.text(13))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            }
            if lift.points.isEmpty {
                Text("Not enough sessions yet")
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LiftTrendChart(points: lift.points, prIndex: lift.prIndex, now: now, timeZoneID: timeZoneID)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

/// The sparkline with a small axis under it: the age of the first and the last session and "PR" under the record.
private struct LiftTrendChart: View {
    let points: [TrendPoint]
    let prIndex: Int?
    let now: Date
    let timeZoneID: String

    private let dotSize: CGFloat = 8
    private let labelWidth: CGFloat = 30

    private var values: [Double] { points.map { $0.value } }

    private var labels: [Int: String] {
        var result: [Int: String] = [:]
        guard !points.isEmpty else { return result }
        result[0] = age(of: points[0])
        result[points.count - 1] = age(of: points[points.count - 1])
        if let prIndex, points.indices.contains(prIndex) { result[prIndex] = "PR" }
        return result
    }

    private func age(of point: TrendPoint) -> String {
        let days = HomeDates.daysBetween(point.date, and: now, timeZoneID: timeZoneID)
        return days == 0 ? "today" : "\(days)d"
    }

    /// The x position of a point, the same as the sparkline draws it, kept inside the widget so the label is not cut off.
    private func labelX(_ index: Int, width: CGFloat) -> CGFloat {
        let shape = SparklineShape(values: values, inset: dotSize)
        let x = shape.point(at: index, in: CGRect(x: 0, y: 0, width: width, height: 1)).x
        let half = labelWidth / 2
        return min(max(x, half), max(half, width - half))
    }

    var body: some View {
        VStack(spacing: 2) {
            Sparkline(values: values, highlightIndex: prIndex, dotSize: dotSize)
                .widgetAccentable()
                .frame(maxHeight: .infinity)
            Rectangle()
                .fill(WidgetTheme.track)
                .frame(height: 1)
            labelRow
        }
    }

    private var labelRow: some View {
        GeometryReader { proxy in
            ForEach(labels.keys.sorted(), id: \.self) { index in
                Text(labels[index] ?? "")
                    .font(WidgetTheme.number(11, .regular))
                    .foregroundStyle(index == prIndex ? WidgetTheme.goldText : WidgetTheme.inkSecondary)
                    .fixedSize()
                    .position(x: labelX(index, width: proxy.size.width), y: proxy.size.height / 2)
            }
        }
        .frame(height: 14)
    }
}

/// No lift has two sessions in the last 90 days yet.
private struct LiftTrendEmptyContent: View {
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lift trend")
                    .font(WidgetTheme.text(15, .semibold))
                    .foregroundStyle(WidgetTheme.ink)
                Spacer(minLength: 4)
                Text("No lifts to chart yet")
                    .font(WidgetTheme.text(17, .bold))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("Log weighted exercises and the trend of your estimated 1RM shows up here.")
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(WidgetTheme.track)
                .frame(maxWidth: 80)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lift trend. No lifts to chart yet. Log weighted exercises to see the trend of your estimated one-rep max.")
    }
}
#endif
