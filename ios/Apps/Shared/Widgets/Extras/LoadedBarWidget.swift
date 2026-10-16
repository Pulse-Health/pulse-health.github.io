// LoadedBarWidget.swift
//
// WI-05 Loaded bar (systemSmall). Today's heaviest barbell set (`loadedBar`) drawn as one side of the bar: the plates from the centre
// outwards, each as tall as its weight suggests and coloured like competition plates, then the total and `LoadedBar.summary`. The drawing
// scales down to fit when many plates are loaded. A tap opens the plate calculator.

#if os(iOS)
import SwiftUI
import WidgetKit
import PulseStrengthCore

struct LoadedBarWidget: Widget {
    static let kind = "health.pulse.strength.widget.loadedBar"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SnapshotProvider()) { entry in
            LoadedBarView(entry: entry)
        }
        .configurationDisplayName("Loaded bar")
        .description("The plates for today's top set, colour-coded and drawn on the bar.")
        .supportedFamilies([.systemSmall])
    }
}

struct LoadedBarView: View {
    let entry: SnapshotEntry

    private var loadedBar: LoadedBar? { entry.snapshot.loadedBar }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCardBackground()
            .widgetURL(loadedBar == nil ? StrengthDeepLink.hub.url : StrengthDeepLink.plates.url)
    }

    @ViewBuilder
    private var content: some View {
        if let bar = loadedBar {
            populated(bar)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ExtrasEyebrow(title: "Top set today")
                ExtrasEmptyState(
                    systemImage: "dumbbell.fill",
                    title: "No barbell lift",
                    message: "Plates show up when your next workout has a barbell lift."
                )
            }
        }
    }

    private func populated(_ bar: LoadedBar) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ExtrasEyebrow(title: "Top set today")
            LoadedBarDrawing(plates: bar.platesPerSide)
                .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(WidgetText.kg(bar.totalKg))
                    .font(WidgetTheme.number(22))
                    .foregroundStyle(WidgetTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(caption(of: bar))
                    .font(WidgetTheme.text(12))
                    .foregroundStyle(WidgetTheme.inkSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if bar.leftoverKg > 0.004 {
                    Text(NumberText.kg(bar.leftoverKg) + " kg left over")
                        .font(WidgetTheme.text(11, .semibold))
                        .foregroundStyle(WidgetTheme.goldText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary(of: bar))
    }

    private func plateTexts(_ bar: LoadedBar) -> [String] {
        bar.platesPerSide.map { NumberText.kg($0) }
    }

    /// "20 + 10 + 2.5 a side", or "Just the bar".
    private func caption(of bar: LoadedBar) -> String {
        if bar.platesPerSide.isEmpty { return "Just the bar" }
        let summary = bar.summary.isEmpty ? plateTexts(bar).joined(separator: " + ") : bar.summary
        return summary + " a side"
    }

    private func spokenSummary(of bar: LoadedBar) -> String {
        var text = "\(bar.exerciseName), top set today: \(NumberText.kg(bar.totalKg)) kilograms. "
        if bar.platesPerSide.isEmpty {
            text += "Just the \(NumberText.kg(bar.barKg)) kilogram bar."
        } else {
            text += "\(ExtrasText.list(plateTexts(bar))) kilograms on each side of the \(NumberText.kg(bar.barKg)) kilogram bar."
        }
        if bar.leftoverKg > 0.004 {
            text += " \(NumberText.kg(bar.leftoverKg)) kilograms cannot be loaded with the available plates."
        }
        return text
    }
}

// MARK: - Drawing

/// One side of the bar: the narrow part of the shaft, the plates (heaviest first, next to the centre) and the sleeve end. The natural size
/// is measured in points; `LoadedBarDrawing` shrinks the whole thing to the room it gets.
private struct LoadedBarDrawing: View {
    let plates: [Double]

    private static let gap: CGFloat = 3
    private static let shaftWidth: CGFloat = 22
    private static let sleeveWidth: CGFloat = 30
    private static let barThickness: CGFloat = 6

    private var naturalSize: CGSize {
        let platesWidth = plates.reduce(CGFloat(0)) { $0 + LoadedBarPlate.width($1) }
        let count = CGFloat(plates.count + 1)
        let height = plates.map { LoadedBarPlate.height($0) }.max() ?? Self.barThickness
        return CGSize(width: Self.shaftWidth + platesWidth + Self.sleeveWidth + Self.gap * count, height: max(height, Self.barThickness))
    }

    var body: some View {
        GeometryReader { proxy in
            let natural = naturalSize
            let unit = min(proxy.size.width / natural.width, proxy.size.height / natural.height, 1.15)
            HStack(spacing: Self.gap * unit) {
                bar(width: Self.shaftWidth * unit, unit: unit)
                ForEach(plates.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2.5 * unit, style: .continuous)
                        .fill(LoadedBarPlate.color(for: plates[index]))
                        .frame(
                            width: LoadedBarPlate.width(plates[index]) * unit,
                            height: LoadedBarPlate.height(plates[index]) * unit
                        )
                }
                bar(width: Self.sleeveWidth * unit, unit: unit)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func bar(width: CGFloat, unit: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2 * unit, style: .continuous)
            .fill(WidgetTheme.inkTertiary)
            .frame(width: width, height: Self.barThickness * unit)
    }
}

/// Size and colour of a plate. The canvas draws 20 kg at 52 pt, 10 kg at 42 pt and 2.5 kg at 26 pt; height grows with weight to the power
/// 0.31, which reproduces those. Colours follow the competition plates (25 red, 20 blue, 15 yellow, 10 green, 5 white, 2.5 red).
private enum LoadedBarPlate {
    static func height(_ weightKg: Double) -> CGFloat {
        CGFloat(max(16, 20.6 * pow(max(weightKg, 0), 0.31)))
    }

    static func width(_ weightKg: Double) -> CGFloat {
        CGFloat(5 + 6 * pow(min(max(weightKg, 0), 25) / 25, 0.4))
    }

    static func color(for weightKg: Double) -> Color {
        switch weightKg {
        case 22.5...: return WidgetTheme.heart
        case 17.5..<22.5: return WidgetTheme.blue
        case 12.5..<17.5: return WidgetTheme.recovering
        case 7.5..<12.5: return WidgetTheme.green
        case 3.75..<7.5: return WidgetTheme.trackStrong
        case 1.875..<3.75: return WidgetTheme.heart
        default: return WidgetTheme.inkSecondary
        }
    }
}
#endif
