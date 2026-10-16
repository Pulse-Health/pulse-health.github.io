// WatchWidgetSnapshotTests.swift
//
// Snapshot tests of the Apple Watch widgets of widgets/SPEC.md (WA-01...WA-10). The SwiftUI views the widgets use (Apps/Shared/Widgets/Watch and
// Common, compiled into this bundle as its own sources) are drawn with `ImageRenderer` at @2x and written as
//
//   <SCREENSHOT_DIR>/watchwidget-<id>-<name>.png
//
// `SCREENSHOT_DIR` is read from the test process environment; xcodebuild forwards variables prefixed with `TEST_RUNNER_`, so CI sets
// `TEST_RUNNER_SCREENSHOT_DIR=/path`. Every PNG is also attached to the test result.
//
// What the images show: the layout, colours, fonts and text of the views for the sample entry of each widget, in the size of the complication
// slot, over the card the Smart Stack draws. `ImageRenderer` cannot run the system timers, so the views are drawn with a static clock
// (`\.watchWidgetStaticNow`); `AccessoryWidgetBackground`, the corner `widgetLabel` and the double-tap highlight are not drawn.

#if os(watchOS)
import SwiftUI
import WidgetKit
import XCTest
import CoreGraphics
import ImageIO
import PulseStrengthCore

/// Sizes of the Watch widget slots in points (45 mm).
enum WatchWidgetMetrics {
    static let scale: CGFloat = 2
    static let circular = CGSize(width: 50, height: 50)
    static let rectangular = CGSize(width: 160, height: 68)
    static let inline = CGSize(width: 180, height: 22)
    static let canvasPadding: CGFloat = 8
}

/// What the Smart Stack draws behind a widget.
enum WatchWidgetBackdrop {
    case clear
    case greenCard
    case card
    case gold
}

/// One widget view to draw.
struct WatchWidgetShot {
    let id: String
    let name: String
    let size: CGSize
    let backdrop: WatchWidgetBackdrop
    let topic: WatchWidgetTopic
    let make: @MainActor (WatchEntry) -> AnyView
}

/// The widget in its slot on a black canvas, with a caption underneath.
struct WatchWidgetCanvas: View {
    let caption: String
    let size: CGSize
    let backdrop: WatchWidgetBackdrop
    let content: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
                .frame(width: size.width, height: size.height)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: backdrop == .clear ? 0 : 12, style: .continuous))
            Text(caption)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(Color.gray)
                .lineLimit(2)
                .frame(width: max(size.width, 120), alignment: .leading)
        }
        .padding(WatchWidgetMetrics.canvasPadding)
        .background(Color.black)
    }

    @ViewBuilder
    private var fill: some View {
        switch backdrop {
        case .clear: Color.clear
        case .greenCard: WatchStyle.greenCard
        case .card: WidgetTheme.card
        case .gold: WidgetTheme.goldFill
        }
    }
}

@MainActor
final class WatchWidgetSnapshotTests: XCTestCase {

    func testWatchWidgets() throws {
        let circular = WatchWidgetMetrics.circular
        let rectangular = WatchWidgetMetrics.rectangular
        let inline = WatchWidgetMetrics.inline

        let shots: [WatchWidgetShot] = [
            WatchWidgetShot(id: "WA-01", name: "next-up-rectangular", size: rectangular, backdrop: .greenCard, topic: .nextUp) {
                AnyView(NextUpWatchView(entry: $0, familyOverride: .accessoryRectangular))
            },
            WatchWidgetShot(id: "WA-10", name: "next-up-inline", size: inline, backdrop: .clear, topic: .nextUp) {
                AnyView(NextUpWatchView(entry: $0, familyOverride: .accessoryInline))
            },
            WatchWidgetShot(id: "WA-01", name: "weekly-goal-circular", size: circular, backdrop: .clear, topic: .goal) {
                AnyView(WeeklyGoalWatchView(entry: $0, familyOverride: .accessoryCircular))
            },
            WatchWidgetShot(id: "WA-10", name: "weekly-goal-inline", size: inline, backdrop: .clear, topic: .goal) {
                AnyView(WeeklyGoalWatchView(entry: $0, familyOverride: .accessoryInline))
            },
            WatchWidgetShot(id: "WA-01", name: "days-since-circular", size: circular, backdrop: .clear, topic: .daysSince) {
                AnyView(DaysSinceWatchView(entry: $0, familyOverride: .accessoryCircular))
            },
            WatchWidgetShot(id: "WA-01", name: "start-circular", size: circular, backdrop: .clear, topic: .start) {
                AnyView(StartWatchView(entry: $0))
            },
            WatchWidgetShot(id: "WA-10", name: "streak-circular", size: circular, backdrop: .clear, topic: .streak) {
                AnyView(StreakWatchView(entry: $0, familyOverride: .accessoryCircular))
            },
            WatchWidgetShot(id: "WA-10", name: "weekly-sets-circular", size: circular, backdrop: .clear, topic: .weeklySets) {
                AnyView(WeeklySetsWatchView(entry: $0, familyOverride: .accessoryCircular))
            },
            WatchWidgetShot(id: "WA-08", name: "lift-trend", size: rectangular, backdrop: .card, topic: .liftTrend) {
                AnyView(LiftTrendWatchView(entry: $0))
            },
            WatchWidgetShot(id: "WA-09", name: "heart-rate-by-set", size: rectangular, backdrop: .card, topic: .heartRate) {
                AnyView(HeartRateWatchView(entry: $0))
            },
            WatchWidgetShot(id: "WA-02", name: "rest-rectangular", size: rectangular, backdrop: .greenCard, topic: .rest) {
                AnyView(RestWidgetView(entry: $0, familyOverride: .accessoryRectangular))
            },
            WatchWidgetShot(id: "WA-02", name: "rest-circular", size: circular, backdrop: .clear, topic: .rest) {
                AnyView(RestWidgetView(entry: $0, familyOverride: .accessoryCircular))
            },
            WatchWidgetShot(id: "WA-05", name: "rest-controls", size: rectangular, backdrop: .card, topic: .restControls) {
                AnyView(RestWatchView(entry: $0))
            },
            WatchWidgetShot(id: "WA-04", name: "log-set", size: rectangular, backdrop: .card, topic: .logSet) {
                AnyView(LogSetWatchView(entry: $0))
            },
            WatchWidgetShot(id: "WA-06", name: "record", size: rectangular, backdrop: .gold, topic: .record) {
                AnyView(RecordWatchView(entry: $0))
            },
        ]

        for shot in shots {
            let now = WidgetSnapshot.preview.generatedAt
            let entry = WatchEntry.sample(for: shot.topic, now: now)
            let canvas = WatchWidgetCanvas(
                caption: shot.id + " \u{00B7} " + shot.name,
                size: shot.size,
                backdrop: shot.backdrop,
                content: AnyView(shot.make(entry).environment(\.watchWidgetStaticNow, now))
            )
            try save(canvas, name: shot.id + "-" + shot.name)
        }
    }

    // MARK: Output

    /// `SCREENSHOT_DIR`, or the temporary directory when it is not set.
    private var directory: URL {
        if let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    private func save<V: View>(_ view: V, name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = WatchWidgetMetrics.scale
        renderer.isOpaque = true
        guard let image = renderer.cgImage else {
            XCTFail("ImageRenderer returned no image for " + name)
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("watchwidget-" + name + ".png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            XCTFail("Could not create " + url.lastPathComponent)
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), let data = try? Data(contentsOf: url) else {
            XCTFail("Could not write " + url.lastPathComponent)
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = url.lastPathComponent
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
