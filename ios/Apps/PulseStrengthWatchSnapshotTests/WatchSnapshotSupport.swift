// WatchSnapshotSupport.swift
//
// Helpers of the Apple Watch snapshot tests: the screen sizes, the catalogue of screens (which page, which fixture), the
// `ImageRenderer` wrapper, the PNG writer and the output manifest.
//
// How a screen is drawn:
//
//  * Every page view (`LogSetPage`, `RestPage`, `MetricsPage`, `WatchIdleView.pageContent`, `WatchSummaryView.pageContent`)
//    is created on its own with the snapshot/date of a fixture (see WatchSnapshotFixtures.swift), placed in a frame of the
//    Watch screen size (points) on a black background and rendered with `ImageRenderer` at scale 2 (the Watch is @2x).
//  * `ImageRenderer` cannot draw a `ScrollView` (its contents come out blank) or a vertical-page `TabView`. The idle and the
//    summary page are scroll views on the Watch, so their content is drawn WITHOUT the scroll container, aligned to the top
//    (what the Watch shows before the user scrolls), and once more at full length (taller than the screen).
//    `WatchRootView` is rendered as well, as an experiment: the tabs and the scroll views may come out blank or as the
//    "no entry" placeholder; the manifest says so.
//  * No system chrome is drawn: no status-bar time, no safe-area inset, no rounded display corners. What the image shows is
//    the page in a rectangle of the screen size.

#if os(watchOS)
import SwiftUI
import XCTest
import CoreGraphics
import ImageIO
import PulseStrengthCore
@testable import PulseStrengthWatchUI

// MARK: - Screen sizes

/// An Apple Watch screen in points. The screen is drawn at scale 2.
struct WatchScreen: Equatable {
    let name: String
    let width: CGFloat
    let height: CGFloat

    static let mm40 = WatchScreen(name: "40mm", width: 162, height: 197)
    static let mm41 = WatchScreen(name: "41mm", width: 170, height: 207)
    static let mm44 = WatchScreen(name: "44mm", width: 184, height: 224)
    static let mm45 = WatchScreen(name: "45mm", width: 198, height: 242)
    static let mm49 = WatchScreen(name: "49mm", width: 205, height: 251)

    static let all: [WatchScreen] = [mm40, mm41, mm44, mm45, mm49]

    /// The size every screen is drawn at first (Series 7/8/9 45 mm).
    static let reference: WatchScreen = mm45
}

// MARK: - Catalogue

/// One screen to draw: a name for the file and a factory for the page view (without any frame).
struct WatchShot {
    let name: String
    /// True when the page is a `ScrollView` on the Watch: it is drawn without the scroll container, top aligned.
    let scrolls: Bool
    let make: @MainActor () -> AnyView
}

@MainActor
enum WatchCatalog {
    static let referenceStart: Date = WatchFixtures.referenceStart

    // MARK: Building blocks

    /// The Watch's mirror controller (role mirror, no persistence, no side effects) showing `state`.
    static func controller(showing state: WorkoutState?) -> WorkoutController {
        let store = StrengthStore(persistence: nil)
        let controller = WorkoutController(store: store, persistence: nil, role: .mirror)
        if let state {
            controller.receive(SyncEnvelope(state: state))
        }
        return controller
    }

    /// A Watch environment around such a controller that starts nothing (no Health session, no WatchConnectivity).
    static func environment(showing state: WorkoutState?, phoneReachable: Bool, summary: WatchEndedSummary? = nil) -> WatchEnvironment {
        WatchEnvironment(
            previewController: controller(showing: state),
            isPhoneReachable: phoneReachable,
            endedSummary: summary
        )
    }

    static func logPage(_ fixture: WatchFixture) -> AnyView {
        AnyView(
            LogSetPage(
                controller: controller(showing: fixture.state),
                snapshot: fixture.snapshot,
                date: fixture.date,
                isSelected: true
            )
        )
    }

    static func restPage(_ fixture: WatchFixture) -> AnyView {
        AnyView(
            RestPage(
                controller: controller(showing: fixture.state),
                snapshot: fixture.snapshot,
                date: fixture.date
            )
        )
    }

    static func metricsPage(_ fixture: WatchFixture) -> AnyView {
        AnyView(
            MetricsPage(
                session: WatchWorkoutSession(),
                snapshot: fixture.snapshot,
                date: fixture.date
            )
        )
    }

    static func idlePage(phoneReachable: Bool) -> AnyView {
        let env = environment(showing: nil, phoneReachable: phoneReachable)
        return AnyView(WatchIdleView(environment: env).pageContent)
    }

    static func summaryPage(_ fixture: WatchFixture) -> AnyView {
        let summary = WatchEndedSummary(state: fixture.state, endedAt: fixture.date)
        return AnyView(WatchSummaryView(summary: summary, onDone: {}).pageContent)
    }

    // MARK: Pages (drawn at the reference size, then the key ones at the other sizes)

    /// The pages in file-number order (number = index + 1).
    static var pages: [WatchShot] {
        let start = referenceStart
        return [
            WatchShot(name: "log-weight-reps", scrolls: false) {
                logPage(WatchFixtures.loggingWeightReps(start: start))
            },
            WatchShot(name: "log-warm-up", scrolls: false) {
                logPage(WatchFixtures.loggingWarmup(start: start))
            },
            WatchShot(name: "log-reps-only", scrolls: false) {
                logPage(WatchFixtures.loggingRepsOnly(start: start))
            },
            WatchShot(name: "log-duration", scrolls: false) {
                logPage(WatchFixtures.loggingDuration(start: start))
            },
            WatchShot(name: "log-all-logged", scrolls: false) {
                logPage(WatchFixtures.allLogged(start: start))
            },
            WatchShot(name: "rest-running", scrolls: false) {
                restPage(WatchFixtures.restRunning(start: start))
            },
            WatchShot(name: "rest-next-exercise", scrolls: false) {
                restPage(WatchFixtures.restNextExercise(start: start))
            },
            WatchShot(name: "rest-paused", scrolls: false) {
                restPage(WatchFixtures.restPaused(start: start))
            },
            WatchShot(name: "rest-over", scrolls: false) {
                restPage(WatchFixtures.restOver(start: start))
            },
            WatchShot(name: "metrics-heart-rate", scrolls: false) {
                metricsPage(WatchFixtures.midWorkout(start: start, heartRate: true))
            },
            WatchShot(name: "metrics-no-heart-rate", scrolls: false) {
                metricsPage(WatchFixtures.midWorkout(start: start, heartRate: false))
            },
            WatchShot(name: "idle-phone-reachable", scrolls: true) {
                idlePage(phoneReachable: true)
            },
            WatchShot(name: "idle-phone-unreachable", scrolls: true) {
                idlePage(phoneReachable: false)
            },
            WatchShot(name: "summary", scrolls: true) {
                summaryPage(WatchFixtures.midWorkout(start: start, heartRate: true))
            },
        ]
    }

    /// Pages drawn again at every size other than the reference size (names from `pages`).
    static let sweepNames: [String] = [
        "log-weight-reps",
        "log-reps-only",
        "rest-next-exercise",
        "metrics-heart-rate",
        "idle-phone-unreachable",
        "summary",
    ]

    static var sweepScreens: [WatchScreen] {
        WatchScreen.all.filter { $0 != WatchScreen.reference }
    }

    /// Scrolling pages drawn at full length (names from `pages`).
    static let fullLengthNames: [String] = ["idle-phone-unreachable", "summary"]

    static func page(named name: String) -> WatchShot? {
        pages.first { $0.name == name }
    }

    // MARK: Whole screens (WatchRootView)

    /// `WatchRootView` for a mirror environment fed a state; the workout is placed relative to the real clock because the
    /// root view runs its own `TimelineView`.
    static var roots: [WatchShot] {
        [
            WatchShot(name: "root-logging", scrolls: false) {
                let fixture = WatchFixtures.anchored { WatchFixtures.loggingWeightReps(start: $0) }
                return rootView(showing: fixture.state, phoneReachable: true, summary: nil)
            },
            WatchShot(name: "root-resting", scrolls: false) {
                let fixture = WatchFixtures.anchored { WatchFixtures.restRunning(start: $0) }
                return rootView(showing: fixture.state, phoneReachable: true, summary: nil)
            },
            WatchShot(name: "root-idle", scrolls: false) {
                rootView(showing: nil, phoneReachable: false, summary: nil)
            },
            WatchShot(name: "root-summary", scrolls: false) {
                let fixture = WatchFixtures.midWorkout(start: referenceStart, heartRate: true)
                let summary = WatchEndedSummary(state: fixture.state, endedAt: fixture.date)
                return rootView(showing: nil, phoneReachable: true, summary: summary)
            },
        ]
    }

    private static func rootView(showing state: WorkoutState?, phoneReachable: Bool, summary: WatchEndedSummary?) -> AnyView {
        let env = environment(showing: state, phoneReachable: phoneReachable, summary: summary)
        return AnyView(WatchRootView(environment: env))
    }

    // MARK: File numbers (fixed by position, independent of the order the tests run in)

    static func pageNumber(_ index: Int) -> Int {
        1 + index
    }

    static func sweepNumber(shot shotIndex: Int, screen screenIndex: Int) -> Int {
        1 + pages.count + shotIndex * sweepScreens.count + screenIndex
    }

    static func fullLengthNumber(_ index: Int) -> Int {
        1 + pages.count + sweepNames.count * sweepScreens.count + index
    }

    static func rootNumber(_ index: Int) -> Int {
        1 + pages.count + sweepNames.count * sweepScreens.count + fullLengthNames.count + index
    }

    // MARK: Framing

    /// `content` on a black screen of `size` (points). A scrolling page is aligned to the top and cut at the bottom, like the
    /// Watch shows it before the user scrolls.
    static func screen<Content: View>(_ content: Content, size: WatchScreen, scrolls: Bool) -> some View {
        content
            .frame(width: size.width, height: size.height, alignment: scrolls ? Alignment.top : Alignment.center)
            .background(Color.black)
            .clipped()
            .environment(\.colorScheme, .dark)
    }

    /// `content` at its full height for a screen of `width` points.
    static func fullLength<Content: View>(_ content: Content, width: CGFloat) -> some View {
        content
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Rendering and output

/// The outcome of one saved screenshot.
struct WatchShotResult {
    let fileName: String
    let pixelWidth: Int
    let pixelHeight: Int
    /// Share of the pixels that are not (nearly) black.
    let litRatio: Double
}

@MainActor
enum WatchOutput {
    /// The Watch is @2x.
    static let scale: CGFloat = 2

    /// A page with fewer lit pixels than this is considered blank.
    static let blankThreshold: Double = 0.005

    /// Lines of `watch-manifest.txt`, by file number (all tests of the run add to it).
    private static var manifest: [Int: String] = [:]
    private static var chosenDirectory: URL?
    private static var directoryWarning: String?

    // MARK: Paths

    /// `SCREENSHOT_DIR` (CI passes it as `TEST_RUNNER_SCREENSHOT_DIR`); the temporary directory when it is not set or cannot be created.
    static var directory: URL {
        if let chosenDirectory { return chosenDirectory }
        var url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        if let requested = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !requested.isEmpty {
            let candidate = URL(fileURLWithPath: requested, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
                url = candidate
            } catch {
                directoryWarning = "SCREENSHOT_DIR '" + requested + "' cannot be created (" + String(describing: error) + "); using the temporary directory"
            }
        } else {
            directoryWarning = "SCREENSHOT_DIR is not set; using the temporary directory"
        }
        chosenDirectory = url
        return url
    }

    /// File name convention: "watch-<NN>-<kebab-name>.png".
    static func fileName(number: Int, name: String) -> String {
        let digits = String(number)
        let padded = digits.count < 2 ? "0" + digits : digits
        return "watch-" + padded + "-" + name + ".png"
    }

    // MARK: Rendering

    static func render<Content: View>(_ view: Content) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.cgImage
    }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    /// Share of the pixels whose red, green or blue value is above 32 (of 255).
    static func litRatio(of image: CGImage) -> Double {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return 0 }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        var lit = 0
        var index = 0
        while index + 2 < pixels.count {
            if pixels[index] > 32 || pixels[index + 1] > 32 || pixels[index + 2] > 32 {
                lit += 1
            }
            index += 4
        }
        return Double(lit) / Double(width * height)
    }

    private static func percentText(_ ratio: Double) -> String {
        let tenths = Int((ratio * 1000).rounded())
        return String(tenths / 10) + "." + String(tenths % 10) + "%"
    }

    // MARK: Saving

    /// Renders `view`, writes `watch-<number>-<name>.png` into `directory`, attaches it to `test` (lifetime keepAlways) and adds
    /// a line to the manifest. With `expectContent` a (nearly) black image fails the test; the image is still written.
    @discardableResult
    static func save<Content: View>(
        _ view: Content,
        number: Int,
        name: String,
        expectContent: Bool,
        test: XCTestCase,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> WatchShotResult? {
        let pngName = fileName(number: number, name: name)
        guard let image = render(view) else {
            note(number: number, text: pngName + " | NOT RENDERED (ImageRenderer returned no image)")
            XCTFail("ImageRenderer returned no image for " + pngName, file: file, line: line)
            return nil
        }

        let url = directory.appendingPathComponent(pngName)
        if !writePNG(image, to: url) {
            note(number: number, text: pngName + " | NOT WRITTEN to " + url.path)
            XCTFail("Could not write " + url.path, file: file, line: line)
            return nil
        }
        if let data = try? Data(contentsOf: url) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = pngName
            attachment.lifetime = .keepAlways
            test.add(attachment)
        }

        let ratio = litRatio(of: image)
        let isBlank = ratio < blankThreshold
        let widthPoints = Int((CGFloat(image.width) / scale).rounded())
        let heightPoints = Int((CGFloat(image.height) / scale).rounded())
        var text = pngName + " | " + String(image.width) + " x " + String(image.height) + " px"
        text += " | " + String(widthPoints) + " x " + String(heightPoints) + " pt @" + String(Int(scale)) + "x"
        text += " | lit " + percentText(ratio)
        text += isBlank ? " | BLANK (nothing but the black background was drawn)" : " | ok"
        note(number: number, text: text)

        if isBlank && expectContent {
            XCTFail(pngName + " is blank: nothing but the black background was rendered", file: file, line: line)
        }
        return WatchShotResult(fileName: pngName, pixelWidth: image.width, pixelHeight: image.height, litRatio: ratio)
    }

    private static func note(number: Int, text: String) {
        manifest[number] = text
        print("WATCH-SNAPSHOT " + text)
    }

    /// Writes `watch-manifest.txt` (every screenshot of this run so far, by number) next to the PNGs and attaches it.
    static func finish(test: XCTestCase) {
        var lines: [String] = []
        lines.append("Apple Watch snapshot tests: one line per PNG (size in pixels and points, share of non-black pixels).")
        lines.append("A BLANK line means ImageRenderer drew nothing for that screen (expected for WatchRootView: it contains a")
        lines.append("vertical-page TabView / ScrollView, which ImageRenderer cannot draw).")
        lines.append("Output directory: " + directory.path)
        if let directoryWarning {
            lines.append("WARNING: " + directoryWarning)
        }
        lines.append("")
        for number in manifest.keys.sorted() {
            if let text = manifest[number] {
                lines.append(text)
            }
        }
        let report = lines.joined(separator: "\n") + "\n"
        let manifestName = "watch-manifest.txt"
        do {
            try report.write(to: directory.appendingPathComponent(manifestName), atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Could not write " + manifestName + ": " + String(describing: error))
        }
        let attachment = XCTAttachment(string: report)
        attachment.name = manifestName
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}
#endif
