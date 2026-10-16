// WidgetSnapshotHarness.swift
//
// Rendering helpers of the widget snapshot tests: the sizes of the widget families, the backdrop the system draws behind a widget, the PNG
// writer and the fixture entries.
//
// A widget cannot be screenshotted on a CI runner, so these tests draw the SwiftUI views the widgets use (Apps/Shared/Widgets, compiled into
// this bundle as its own sources) with `ImageRenderer` at @3x. `ImageRenderer` does not draw the container background and not
// `AccessoryWidgetBackground`, and `widgetFamily` is read-only in the environment, so this file puts the backdrop and the margin around each
// view itself and the views that depend on the family take it as an explicit value (`familyOverride`, `HomeSurface`).
//
// Everything here is an APPROXIMATION of what the system does around the views; the sizes are those of an iPhone 16 Pro (402 pt wide) and
// live in `WidgetMetrics` so they can be corrected in one place.

#if os(iOS)
import SwiftUI
import UIKit
import XCTest
import WidgetKit
import PulseStrengthCore

// MARK: - Geometry

enum WidgetMetrics {
    /// Output scale of every PNG (an iPhone 16 Pro is @3x).
    static let scale: CGFloat = 3

    /// The margin the system keeps around the content of a `system*` widget that has a container background.
    static let contentMargin: CGFloat = 16
    static let cornerRadius: CGFloat = 22
    /// Space around the artwork inside a PNG.
    static let canvasPadding: CGFloat = 12

    static let small = CGSize(width: 170, height: 170)
    static let medium = CGSize(width: 364, height: 170)
    static let large = CGSize(width: 364, height: 382)
    static let extraLarge = CGSize(width: 715, height: 382)

    static let circular = CGSize(width: 76, height: 76)
    static let rectangular = CGSize(width: 172, height: 76)
    static let inline = CGSize(width: 258, height: 26)
}

/// What the system draws behind a widget.
enum WidgetBackdrop {
    /// The adaptive card (`containerBackground` of most widgets).
    case card
    /// The gold fill of the record widgets.
    case gold
    /// StandBy by day and at night: no card, black ground.
    case black
    /// A card that is dark in both appearances (the widgets that force the dark scheme).
    case darkCard
    /// A Lock Screen accessory over a wallpaper, with the translucent plate of `AccessoryWidgetBackground` drawn by the harness.
    case accessory(WidgetFamily)
}

// MARK: - Fixtures

@MainActor
enum WidgetFixtures {
    /// "Now" of every image: the instant of the idealised preview snapshot.
    static var now: Date { WidgetSnapshot.preview.generatedAt }

    static var preview: SnapshotEntry {
        SnapshotEntry(date: now, snapshot: WidgetSnapshot.preview)
    }

    static var empty: SnapshotEntry {
        SnapshotEntry(date: now, snapshot: WidgetSnapshot.empty(now: now))
    }

    /// The preview snapshot with the running workout of a Live Activity scenario ("logging-weight", "resting", ...).
    static func running(_ slug: String) -> SnapshotEntry? {
        guard let scenario = LiveFixtures.all().first(where: { $0.slug == slug }) else { return nil }
        var snapshot = WidgetSnapshot.preview
        snapshot.active = scenario.snapshot
        return SnapshotEntry(date: scenario.now, snapshot: snapshot)
    }
}

// MARK: - Canvas

/// One widget in its frame on a neutral canvas, with a caption underneath.
struct WidgetCanvas<Content: View>: View {
    let caption: String
    let size: CGSize
    let backdrop: WidgetBackdrop
    let scheme: ColorScheme
    let content: Content

    init(caption: String, size: CGSize, backdrop: WidgetBackdrop, scheme: ColorScheme, @ViewBuilder content: () -> Content) {
        self.caption = caption
        self.size = size
        self.backdrop = backdrop
        self.scheme = scheme
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            widget
            Text(caption)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
                .frame(width: max(size.width, 160), alignment: .leading)
        }
        .padding(WidgetMetrics.canvasPadding)
        .background(Color(white: scheme == .dark ? 0.12 : 0.9))
        .environment(\.colorScheme, scheme)
    }

    @ViewBuilder
    private var widget: some View {
        switch backdrop {
        case .card:
            framed(WidgetTheme.card, margin: WidgetMetrics.contentMargin)
        case .gold:
            framed(WidgetTheme.goldFill, margin: WidgetMetrics.contentMargin)
        case .black:
            framed(Color.black, margin: WidgetMetrics.contentMargin)
                .environment(\.colorScheme, .dark)
        case .darkCard:
            framed(WidgetTheme.card.environment(\.colorScheme, .dark), margin: WidgetMetrics.contentMargin)
        case .accessory(let family):
            accessory(family)
        }
    }

    private func framed<Fill: View>(_ fill: Fill, margin: CGFloat) -> some View {
        content
            .padding(margin)
            .frame(width: size.width, height: size.height)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: WidgetMetrics.cornerRadius, style: .continuous))
    }

    /// The Lock Screen draws accessories in one vibrant colour over the wallpaper; circular and rectangular ones sit on a translucent plate.
    @ViewBuilder
    private func accessory(_ family: WidgetFamily) -> some View {
        let wallpaper = LinearGradient(
            colors: [Color(red: 0.12, green: 0.16, blue: 0.35), Color(red: 0.35, green: 0.16, blue: 0.42), Color(red: 0.06, green: 0.29, blue: 0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        ZStack {
            wallpaper
            plate(family)
            content
                .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width + 24, height: size.height + 24)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func plate(_ family: WidgetFamily) -> some View {
        switch family {
        case .accessoryCircular:
            Circle().fill(Color.white.opacity(0.2)).frame(width: size.width, height: size.height)
        case .accessoryRectangular:
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.2)).frame(width: size.width, height: size.height)
        default:
            EmptyView()
        }
    }
}

// MARK: - Output

enum WidgetSnapshotError: LocalizedError {
    case renderFailed(String)
    case encodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .renderFailed(let name): return "ImageRenderer returned no image for \(name)"
        case .encodeFailed(let name): return "Could not encode \(name) as PNG"
        }
    }
}

/// Renders views to PNG files in `SCREENSHOT_DIR` and attaches them to the test result.
@MainActor
enum WidgetOutput {
    /// `SCREENSHOT_DIR` (CI passes it as `TEST_RUNNER_SCREENSHOT_DIR`); the temporary directory when it is not set.
    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    static func fileName(_ name: String) -> String {
        "widget-" + name + ".png"
    }

    /// Opaque @3x rendering of `view` at its ideal size.
    static func render<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = WidgetMetrics.scale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Renders `view`, writes `widget-<name>.png` into `directory` and attaches it to `test`.
    static func save<V: View>(_ view: V, name: String, test: XCTestCase) throws {
        let file = fileName(name)
        guard let rendered = render(view) else { throw WidgetSnapshotError.renderFailed(file) }
        guard let data = rendered.pngData() else { throw WidgetSnapshotError.encodeFailed(file) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(file), options: .atomic)

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = file
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}

// MARK: - Catalogue

/// One widget view to draw for the catalogue id `id`.
struct WidgetShot {
    let id: String
    /// kebab-case name used in the file names ("next-up-small").
    let name: String
    let size: CGSize
    let backdrop: WidgetBackdrop
    /// The entry variants to draw (preview data, empty data, a running workout).
    let entries: [(label: String, entry: @MainActor () -> SnapshotEntry?)]
    let make: @MainActor (SnapshotEntry) -> AnyView

    /// The usual pair: the idealised preview and the empty state.
    static let previewAndEmpty: [(label: String, entry: @MainActor () -> SnapshotEntry?)] = [
        ("preview", { WidgetFixtures.preview }),
        ("empty", { WidgetFixtures.empty }),
    ]

    init(
        _ id: String,
        _ name: String,
        size: CGSize,
        backdrop: WidgetBackdrop = .card,
        entries: [(label: String, entry: @MainActor () -> SnapshotEntry?)] = WidgetShot.previewAndEmpty,
        make: @escaping @MainActor (SnapshotEntry) -> AnyView
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.backdrop = backdrop
        self.entries = entries
        self.make = make
    }

    /// Light and dark appearance, except where the widget draws itself in one (the Lock Screen and StandBy are dark).
    var schemes: [ColorScheme] {
        switch backdrop {
        case .black, .accessory: return [.dark]
        default: return [.light, .dark]
        }
    }
}

/// Draws every shot of a catalogue area and writes `widget-<id>-<name>-<variant>-<scheme>.png`.
@MainActor
func renderWidgetShots(_ shots: [WidgetShot], test: XCTestCase) throws {
    for shot in shots {
        for variant in shot.entries {
            guard let entry = variant.entry() else {
                XCTFail("Missing fixture '\(variant.label)' for \(shot.id) \(shot.name)")
                continue
            }
            for scheme in shot.schemes {
                let canvas = WidgetCanvas(
                    caption: "\(shot.id) \u{00B7} \(shot.name) \u{00B7} \(variant.label) \u{00B7} \(scheme == .dark ? "dark" : "light")",
                    size: shot.size,
                    backdrop: shot.backdrop,
                    scheme: scheme
                ) {
                    shot.make(entry)
                }
                try WidgetOutput.save(
                    canvas,
                    name: "\(shot.id)-\(shot.name)-\(variant.label)-\(scheme == .dark ? "dark" : "light")",
                    test: test
                )
            }
        }
    }
}
#endif
