// BodyMapWidget.swift
//
// WI-01 Body map (systemMedium). Front and back silhouettes drawn from rounded rectangles (the canvas' SVG, split into the six muscle
// groups of the app), each region shaded by the sets of its group this week (`bodyMap.levels`, `WidgetTheme.heat`), and the builder's
// `bodyMap.message` on the right.
//
// Colour is never the only carrier: a region without sets is also drawn with a dashed outline, the legend names the set ranges, and the
// accessibility label lists every group with its range.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct BodyMapWidget: Widget {
    static let kind = "health.pulse.strength.widget.bodyMap"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            BodyMapView(entry: entry)
        }
        .configurationDisplayName("Body map")
        .description("Front and back silhouettes shaded by this week's sets, so muscles you have not trained jump out.")
        .supportedFamilies([.systemMedium])
    }
}

struct BodyMapView: View {
    let entry: SnapshotEntry

    private static let columnSpacing: CGFloat = 12

    private var bodyMap: BodyMap { entry.snapshot.bodyMap }
    private var message: BodyMapMessage { BodyMapMessage(bodyMap.message) }

    /// The level of every group the snapshot lists; a group it leaves out counts as untrained.
    private var levels: [MuscleGroup: Int] {
        var result: [MuscleGroup: Int] = [:]
        for item in bodyMap.levels where result[item.muscle] == nil {
            result[item.muscle] = min(3, max(0, item.level))
        }
        return result
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = BodyMapGeometry.scale(fitting: proxy.size)
            let figuresWidth = BodyMapGeometry.pairWidth * scale
            HStack(alignment: .top, spacing: Self.columnSpacing) {
                BodyMapFigures(levels: levels, scale: scale)
                    .frame(width: figuresWidth, height: proxy.size.height, alignment: .topLeading)
                BodyMapText(message: message)
                    .frame(
                        width: max(0, proxy.size.width - figuresWidth - Self.columnSpacing),
                        height: proxy.size.height,
                        alignment: .topLeading
                    )
            }
        }
        .widgetCardBackground()
        .widgetURL(StrengthDeepLink.hub.url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    /// "Body map for this week. Chest 10 or more sets, Back 5 to 9 sets ... Legs untouched. Lower A is next in line."
    private var spokenSummary: String {
        let groups = MuscleGroup.allCases.map { group in
            group.title + " " + BodyMapGeometry.spokenRange(level: levels[group] ?? 0)
        }
        return "Body map for this week. " + groups.joined(separator: ", ") + ". " + message.spoken
    }
}

// MARK: - Message

/// The builder's message as a bold headline and a grey detail: "Legs untouched." and "Lower A is next in line.".
private struct BodyMapMessage {
    let headline: String
    let detail: String

    init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            headline = "Nothing trained yet."
            detail = "Finish a workout to fill the map."
        } else if let split = trimmed.range(of: ". ") {
            headline = String(trimmed[trimmed.startIndex..<split.lowerBound]) + "."
            detail = String(trimmed[split.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            headline = trimmed
            detail = ""
        }
    }

    var spoken: String {
        detail.isEmpty ? headline : headline + " " + detail
    }
}

private struct BodyMapText: View {
    let message: BodyMapMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("This week")
                .font(WidgetTheme.text(15, .semibold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(1)
            Text("Front and back")
                .font(WidgetTheme.text(13))
                .foregroundStyle(WidgetTheme.inkSecondary)
                .lineLimit(1)
            BodyMapLegend()
                .padding(.top, 6)
            Spacer(minLength: 6)
            Text(message.headline)
                .font(WidgetTheme.text(13, .bold))
                .foregroundStyle(WidgetTheme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if !message.detail.isEmpty {
                Text(message.detail)
                    .font(WidgetTheme.text(13))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
    }
}

/// The four shades with the set range each stands for. The first swatch carries the dashed outline of an untrained region.
private struct BodyMapLegend: View {
    private static let labels = ["0", "1\u{2013}4", "5\u{2013}9", "10+ sets"]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Self.labels.indices, id: \.self) { level in
                HStack(spacing: 3) {
                    BodyMapSwatch(level: level)
                    Text(Self.labels[level])
                        .font(WidgetTheme.text(10))
                        .foregroundStyle(WidgetTheme.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }
}

private struct BodyMapSwatch: View {
    let level: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(BodyMapGeometry.fill(level: level))
            .overlay(BodyMapOutline(cornerRadius: 2.5, isShown: level == 0))
            .frame(width: 9, height: 9)
    }
}

// MARK: - Figures

/// Two figures side by side, drawn at `scale` points per design unit.
private struct BodyMapFigures: View {
    let levels: [MuscleGroup: Int]
    let scale: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: BodyMapGeometry.figureGap * scale) {
            BodyMapFigure(regions: BodyMapGeometry.front, levels: levels, scale: scale)
            BodyMapFigure(regions: BodyMapGeometry.back, levels: levels, scale: scale)
        }
    }
}

private struct BodyMapFigure: View {
    let regions: [BodyMapRegion]
    let levels: [MuscleGroup: Int]
    let scale: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(regions.indices, id: \.self) { index in
                BodyMapRegionView(region: regions[index], level: level(of: regions[index]), scale: scale)
            }
        }
        .frame(
            width: BodyMapGeometry.figureSize.width * scale,
            height: BodyMapGeometry.figureSize.height * scale,
            alignment: .topLeading
        )
    }

    private func level(of region: BodyMapRegion) -> Int {
        guard let muscle = region.muscle else { return 0 }
        return levels[muscle] ?? 0
    }
}

private struct BodyMapRegionView: View {
    let region: BodyMapRegion
    let level: Int
    let scale: CGFloat

    private var isMuscle: Bool { region.muscle != nil }

    var body: some View {
        RoundedRectangle(cornerRadius: region.radius * scale, style: .continuous)
            .fill(BodyMapGeometry.fill(level: isMuscle ? level : 0))
            .overlay(BodyMapOutline(cornerRadius: region.radius * scale, isShown: isMuscle && level == 0))
            .frame(width: region.rect.width * scale, height: region.rect.height * scale)
            .offset(x: region.rect.minX * scale, y: region.rect.minY * scale)
            .widgetAccentable(level >= 2)
    }
}

/// The dashed outline that marks a region without sets.
private struct BodyMapOutline: View {
    let cornerRadius: CGFloat
    let isShown: Bool

    var body: some View {
        if isShown {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(WidgetTheme.inkTertiary, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
        }
    }
}

// MARK: - Geometry

/// One drawn region of a silhouette, in the design grid. `muscle` is nil for the head.
private struct BodyMapRegion {
    let muscle: MuscleGroup?
    let rect: CGRect
    let radius: CGFloat
}

/// The silhouettes of the canvas in a grid of 60 x 134 per figure (head on top, legs at the bottom). The torso, arms and legs keep the
/// canvas' rectangles; the arm is split into a shoulder cap and the rest so that all six groups of the app have a region. The front shows
/// chest and core, the back the whole torso as "Back" (the lower back is part of it).
private enum BodyMapGeometry {
    static let figureSize = CGSize(width: 60, height: 134)
    static let figureGap: CGFloat = 12
    static var pairWidth: CGFloat { figureSize.width * 2 + figureGap }

    private static let head = BodyMapRegion(muscle: nil, rect: CGRect(x: 21, y: 1, width: 18, height: 18), radius: 9)
    private static let chest = BodyMapRegion(muscle: .chest, rect: CGRect(x: 12, y: 22, width: 36, height: 22), radius: 8)
    private static let core = BodyMapRegion(muscle: .core, rect: CGRect(x: 15, y: 46, width: 30, height: 24), radius: 6)
    private static let backTorso = BodyMapRegion(muscle: .back, rect: CGRect(x: 12, y: 22, width: 36, height: 48), radius: 8)

    /// Left and right of each pair share the muscle group.
    private static let shoulders = [
        BodyMapRegion(muscle: .shoulders, rect: CGRect(x: 2, y: 22, width: 9, height: 12), radius: 4.5),
        BodyMapRegion(muscle: .shoulders, rect: CGRect(x: 49, y: 22, width: 9, height: 12), radius: 4.5),
    ]
    private static let arms = [
        BodyMapRegion(muscle: .arms, rect: CGRect(x: 2, y: 36, width: 9, height: 26), radius: 4.5),
        BodyMapRegion(muscle: .arms, rect: CGRect(x: 49, y: 36, width: 9, height: 26), radius: 4.5),
    ]
    private static let legs = [
        BodyMapRegion(muscle: .legs, rect: CGRect(x: 14, y: 72, width: 14, height: 62), radius: 6),
        BodyMapRegion(muscle: .legs, rect: CGRect(x: 32, y: 72, width: 14, height: 62), radius: 6),
    ]

    static let front: [BodyMapRegion] = {
        var regions = [head, chest, core]
        regions.append(contentsOf: shoulders)
        regions.append(contentsOf: arms)
        regions.append(contentsOf: legs)
        return regions
    }()

    static let back: [BodyMapRegion] = {
        var regions = [head, backTorso]
        regions.append(contentsOf: shoulders)
        regions.append(contentsOf: arms)
        regions.append(contentsOf: legs)
        return regions
    }()

    /// Points per design unit: the figures fill the height they get, but never more than 45 % of the width.
    static func scale(fitting size: CGSize) -> CGFloat {
        let byHeight = size.height / figureSize.height
        let byWidth = size.width * 0.45 / pairWidth
        return max(0.1, min(byHeight, byWidth))
    }

    /// The canvas shows regions without sets in the track grey: `WidgetTheme.heat(0)` is almost white and would vanish on the card.
    static func fill(level: Int) -> Color {
        level <= 0 ? WidgetTheme.track : WidgetTheme.heat(level)
    }

    static func spokenRange(level: Int) -> String {
        switch level {
        case 3: return "10 or more sets"
        case 2: return "5 to 9 sets"
        case 1: return "1 to 4 sets"
        default: return "no sets"
        }
    }
}
#endif
