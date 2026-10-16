// WidgetShapes.swift
//
// The few drawing primitives the widgets share: a progress ring, a sparkline, a horizontal meter and a pill.

#if os(iOS) || os(watchOS)
import SwiftUI

/// A progress ring that starts at the top and runs clockwise. `progress` is clamped to 0...1.
struct RingGauge<Center: View>: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var color: Color = WidgetTheme.progress
    var track: Color = WidgetTheme.track
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .padding(lineWidth / 2)
    }
}

extension RingGauge where Center == EmptyView {
    init(progress: Double, lineWidth: CGFloat = 8, color: Color = WidgetTheme.progress, track: Color = WidgetTheme.track) {
        self.init(progress: progress, lineWidth: lineWidth, color: color, track: track) { EmptyView() }
    }
}

/// The polyline through `values`, scaled to the rectangle with an inset so the line and its dots are not clipped.
struct SparklineShape: Shape {
    var values: [Double]
    var inset: CGFloat = 4

    func point(at index: Int, in rect: CGRect) -> CGPoint {
        let usable = rect.insetBy(dx: inset, dy: inset)
        let lowest = values.min() ?? 0
        let highest = values.max() ?? 1
        let range = max(highest - lowest, 1)
        let x = values.count > 1 ? usable.minX + usable.width * CGFloat(index) / CGFloat(values.count - 1) : usable.midX
        let y = usable.maxY - usable.height * CGFloat((values[index] - lowest) / range)
        return CGPoint(x: x, y: y)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }
        path.move(to: point(at: 0, in: rect))
        for index in values.indices.dropFirst() {
            path.addLine(to: point(at: index, in: rect))
        }
        return path
    }
}

/// A sparkline with a dot per value; `highlightIndex` gets the gold personal-record dot.
struct Sparkline: View {
    var values: [Double]
    var highlightIndex: Int?
    var lineColor: Color = WidgetTheme.green
    var lineWidth: CGFloat = 2.5
    var dotSize: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let shape = SparklineShape(values: values, inset: dotSize)
            ZStack {
                shape.stroke(lineColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                ForEach(values.indices, id: \.self) { index in
                    let position = shape.point(at: index, in: rect)
                    Circle()
                        .fill(index == highlightIndex ? WidgetTheme.gold : lineColor)
                        .frame(width: index == highlightIndex ? dotSize * 1.4 : dotSize, height: index == highlightIndex ? dotSize * 1.4 : dotSize)
                        .position(position)
                }
            }
        }
    }
}

/// A horizontal meter: `fraction` of the width in `color` over `track`.
struct BarMeter: View {
    var fraction: Double
    var color: Color = WidgetTheme.progress
    var track: Color = WidgetTheme.track
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(color)
                    .frame(width: max(height, proxy.size.width * CGFloat(min(1, max(0, fraction)))))
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
    }
}

/// A rounded "button-looking" label for places where the real control is the whole widget (`widgetURL`) or a `Link`.
struct PillLabel: View {
    var title: String
    var systemImage: String?
    var fill: Color = WidgetTheme.green
    var foreground: Color = WidgetTheme.onGreen
    var height: CGFloat = 36

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .bold)) }
            Text(title).font(WidgetTheme.text(15, .semibold)).lineLimit(1)
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Capsule().fill(fill))
    }
}
#endif
