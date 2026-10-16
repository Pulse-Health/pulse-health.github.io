// LiveSnapshotHarness.swift
//
// Rendering helpers of the Live Activity snapshot tests: the geometry of the surfaces the views are drawn on, the
// frames that put a view where the system puts it (Lock Screen card over a wallpaper, Dynamic Island compact /
// minimal / expanded), the PNG writer and the size measurements.
//
// The Live Activity itself cannot be screenshotted in CI, so the SwiftUI views the widget uses
// (Apps/Shared/LiveActivity, compiled into this test bundle) are rendered directly with `ImageRenderer`.
// Everything here is an APPROXIMATION of what the system does around them; the numbers that come from Apple are marked
// "HIG", everything else is "assumed" and lives in `LiveMetrics` so it can be corrected in one place.

#if os(iOS)
import SwiftUI
import UIKit
import XCTest
import PulseStrengthCore

// MARK: - Geometry

enum LiveMetrics {
    /// Output scale of every PNG (an iPhone 15/16 Pro is @3x).
    static let scale: CGFloat = 3

    // Lock Screen
    /// Width of the Live Activity card on a 393 pt wide iPhone (as briefed). The HIG table lists 371 pt for the whole
    /// presentation including the system margin.
    static let lockScreenWidth: CGFloat = 359
    /// HIG: the Lock Screen presentation is 84...160 pt tall; the system cuts anything taller.
    static let lockScreenMaxHeight: CGFloat = 160
    /// Assumed: corner radius of the card.
    static let lockScreenCornerRadius: CGFloat = 23

    // Dynamic Island (393 pt wide iPhones: 15 / 16 Pro)
    /// HIG: height of the compact / minimal island (36.67 pt).
    static let islandHeight: CGFloat = 36.67
    /// TrueDepth camera cutout (126 pt).
    static let sensorWidth: CGFloat = 126
    /// HIG: compact leading and compact trailing are 52.33 x 36.67 pt each on a 393 pt wide screen.
    static let compactSlotWidth: CGFloat = 52.33
    /// 2 x 52.33 + 126 = 230.7 pt (HIG: the compact island is 230 pt wide).
    static let compactIslandWidth: CGFloat = 2 * LiveMetrics.compactSlotWidth + LiveMetrics.sensorWidth
    /// The width the brief asked for as a second compact rendering (the expanded width).
    static let briefedCompactWidth: CGFloat = 371
    /// Brief: minimal is drawn in a 37 x 37 pt circle (HIG: 36.67...45 x 36.67).
    static let minimalDiameter: CGFloat = 37
    static let minimalMaxWidth: CGFloat = 45
    /// HIG: expanded island 371 x 84...160 pt, corner radius 44 pt.
    static let expandedWidth: CGFloat = 371
    static let expandedMaxHeight: CGFloat = 160
    static let expandedCornerRadius: CGFloat = 44
    /// Assumed: inset of the expanded content from the left and right edge, and below the last region.
    static let expandedSideInset: CGFloat = 22
    static let expandedBottomInset: CGFloat = 18

    // StandBy bench mode (StandBy.dc.html): the mock-up draws the full-screen activity in a 620 x 286 pt frame with a 40 pt bezel.
    static let benchWidth: CGFloat = 620
    static let benchHeight: CGFloat = 286
    static let benchCornerRadius: CGFloat = 40

    /// Space around the artwork inside a PNG.
    static let canvasPadding: CGFloat = 16

    /// Width of the leading / trailing column of the expanded island: what is left of the camera on one side.
    static var expandedSideColumn: CGFloat {
        (expandedWidth - 2 * expandedSideInset - sensorWidth) / 2
    }
}

// MARK: - Numbering

/// Zero-padded sequence numbers of the PNGs: all Lock Screens, then all compact, minimal, expanded, then the extras.
/// Fixed by position so the numbers do not depend on the order the tests run in.
struct LiveNumbers {
    let count: Int

    func lock(_ index: Int) -> Int { 1 + index }
    func compact(_ index: Int) -> Int { 1 + count + index }
    func minimal(_ index: Int) -> Int { 1 + 2 * count + index }
    func expanded(_ index: Int) -> Int { 1 + 3 * count + index }
    func extra(_ index: Int) -> Int { 1 + 4 * count + index }
}

/// Indexes into `LiveNumbers.extra`.
enum LiveExtra {
    static let lockLightLogging = 0
    static let lockLightResting = 1
    static let compactSheet = 2
    static let minimalSheet = 3
    static let systemLockResting = 4
    static let systemLockLogging = 5
    static let systemCompactResting = 6
    static let systemMinimalResting = 7
    static let systemExpandedResting = 8
    static let standbyResting = 9
    static let standbyRestOver = 10
    static let standbyLogging = 11
    static let standbyRecord = 12
    static let standbyComplete = 13
    /// First index of the pre-workout countdown images (PlannedSessionSnapshots.swift): one Lock Screen card per scenario, then the
    /// compact sheet, the minimal sheet and the expanded island.
    static let plannedBase = 14
}

// MARK: - Chrome: wallpaper, canvas, sensor

enum LiveWallpaper {
    case dark
    case light

    var name: String {
        switch self {
        case .dark: return "dark"
        case .light: return "light"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .dark:
            return LinearGradient(
                colors: [ActivityTheme.hex(0x1E2A5A), ActivityTheme.hex(0x5A2A6B), ActivityTheme.hex(0x0F4A5A)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .light:
            return LinearGradient(
                colors: [ActivityTheme.hex(0xF5E1BF), ActivityTheme.hex(0xE9EDF5), ActivityTheme.hex(0x9CC4EA)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

/// A fixed-width canvas: the artwork on a wallpaper, with a caption bar underneath. Fully opaque.
struct LiveCanvas<Content: View>: View {
    let caption: String
    let wallpaper: LiveWallpaper
    let width: CGFloat
    let content: Content

    init(
        caption: String,
        wallpaper: LiveWallpaper = .dark,
        width: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.caption = caption
        self.wallpaper = wallpaper
        self.width = width
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(LiveMetrics.canvasPadding)
                .frame(width: width)
                .background(wallpaper.gradient)
            Text(caption)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 8)
                .frame(width: width, alignment: .leading)
                .padding(.vertical, 6)
                .background(Color(white: 0.08))
        }
        .frame(width: width)
    }
}

/// Faint outline of the TrueDepth camera cutout (126 x 36.67 pt) so the island regions can be judged against it.
struct SensorHint: View {
    var body: some View {
        Capsule()
            .stroke(Color.white.opacity(0.12), lineWidth: 1)
            .frame(width: LiveMetrics.sensorWidth, height: LiveMetrics.islandHeight)
    }
}

// MARK: - Lock Screen

/// The Lock Screen card exactly as the widget builds it, 359 pt wide, as tall as its content, over the activity
/// background tint (`.activityBackgroundTint(ActivityTheme.lockBackground)` in WorkoutLiveActivity). The real system
/// draws that translucent tint over the wallpaper; the canvas behind this view stands in for the wallpaper.
struct LockScreenCard: View {
    let scenario: LiveScenario

    var body: some View {
        LockScreenActivityView(
            state: scenario.snapshot,
            workoutName: scenario.workoutName,
            isStale: scenario.isStale
        )
        .frame(width: LiveMetrics.lockScreenWidth)
        .background(ActivityTheme.lockBackground)
        .clipShape(RoundedRectangle(cornerRadius: LiveMetrics.lockScreenCornerRadius, style: .continuous))
        .activityStaticClock(scenario.staticClock)
    }
}

struct LockScreenSnapshot: View {
    let scenario: LiveScenario
    var wallpaper: LiveWallpaper = .dark

    var body: some View {
        LiveCanvas(
            caption: "lock screen \u{00B7} " + scenario.title + "\nwallpaper: " + wallpaper.name,
            wallpaper: wallpaper,
            width: LiveMetrics.lockScreenWidth + 2 * LiveMetrics.canvasPadding
        ) {
            LockScreenCard(scenario: scenario)
        }
    }
}

// MARK: - StandBy (bench mode)

/// The activity in StandBy: the full-screen layout (`isFullscreen: true`) in the frame of StandBy.dc.html, on black.
struct BenchCard: View {
    let scenario: LiveScenario

    var body: some View {
        LockScreenActivityView(
            state: scenario.snapshot,
            workoutName: scenario.workoutName,
            isStale: scenario.isStale,
            isFullscreen: true
        )
        .frame(width: LiveMetrics.benchWidth, height: LiveMetrics.benchHeight)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: LiveMetrics.benchCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LiveMetrics.benchCornerRadius, style: .continuous)
                .strokeBorder(Color(white: 0.13), lineWidth: 5)
        )
        .activityStaticClock(scenario.staticClock)
    }
}

struct BenchSnapshot: View {
    let scenario: LiveScenario

    var body: some View {
        LiveCanvas(
            caption: "standby bench mode \u{00B7} " + scenario.title + "\nlayout of StandBy.dc.html (620 x 286 pt)",
            width: LiveMetrics.benchWidth + 2 * LiveMetrics.canvasPadding
        ) {
            BenchCard(scenario: scenario)
        }
    }
}

// MARK: - Dynamic Island: compact

/// Compact presentation in the island's real geometry: leading and trailing views in 52.33 x 36.67 pt slots either side
/// of the 126 pt camera, a 230.7 pt black capsule. A view wider than its slot overflows it (it is not clipped here).
struct CompactIslandPill: View {
    let scenario: LiveScenario

    var body: some View {
        HStack(spacing: 0) {
            IslandCompactLeading(state: scenario.snapshot, isStale: scenario.isStale)
                .frame(width: LiveMetrics.compactSlotWidth, height: LiveMetrics.islandHeight)
            SensorHint()
            IslandCompactTrailing(state: scenario.snapshot, isStale: scenario.isStale)
                .frame(width: LiveMetrics.compactSlotWidth, height: LiveMetrics.islandHeight)
        }
        .frame(width: LiveMetrics.compactIslandWidth, height: LiveMetrics.islandHeight)
        .background(Color.black, in: Capsule())
        .activityStaticClock(scenario.staticClock)
    }
}

/// Compact presentation as briefed: a 371 x 36.67 pt black capsule with the leading view at the left and the trailing
/// view at the right (no slot limits), the camera outline in the middle.
struct WideCompactIslandPill: View {
    let scenario: LiveScenario

    var body: some View {
        HStack(spacing: 0) {
            IslandCompactLeading(state: scenario.snapshot, isStale: scenario.isStale)
                .padding(.leading, 14)
            Spacer(minLength: 0)
            IslandCompactTrailing(state: scenario.snapshot, isStale: scenario.isStale)
                .padding(.trailing, 14)
        }
        .frame(width: LiveMetrics.briefedCompactWidth, height: LiveMetrics.islandHeight)
        .background(Color.black, in: Capsule())
        .overlay(SensorHint())
        .activityStaticClock(scenario.staticClock)
    }
}

struct CompactSnapshot: View {
    let scenario: LiveScenario

    var body: some View {
        LiveCanvas(
            caption: "dynamic island compact \u{00B7} " + scenario.title
                + "\ntop: 230.7 pt island, 52.3 pt slots (HIG) \u{00B7} bottom: 371 pt pill (as briefed)",
            width: LiveMetrics.briefedCompactWidth + 2 * LiveMetrics.canvasPadding
        ) {
            VStack(spacing: 12) {
                CompactIslandPill(scenario: scenario)
                WideCompactIslandPill(scenario: scenario)
            }
        }
    }
}

/// All compact pills (island geometry) on one image.
struct CompactSheetSnapshot: View {
    let scenarios: [LiveScenario]

    var body: some View {
        LiveCanvas(
            caption: "dynamic island compact \u{00B7} all scenarios (230.7 pt island, 52.3 pt slots)",
            width: 320
        ) {
            VStack(spacing: 10) {
                ForEach(scenarios) { scenario in
                    VStack(spacing: 3) {
                        Text(scenario.slug)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.75))
                        CompactIslandPill(scenario: scenario)
                    }
                }
            }
        }
    }
}

// MARK: - Dynamic Island: minimal

struct MinimalIslandCircle: View {
    let scenario: LiveScenario

    var body: some View {
        IslandMinimal(state: scenario.snapshot, isStale: scenario.isStale)
            .frame(width: LiveMetrics.minimalDiameter, height: LiveMetrics.minimalDiameter)
            .background(Color.black, in: Circle())
            .activityStaticClock(scenario.staticClock)
    }
}

struct MinimalSnapshot: View {
    let scenario: LiveScenario

    var body: some View {
        LiveCanvas(
            caption: "dynamic island minimal \u{00B7} " + scenario.title,
            width: 300
        ) {
            MinimalIslandCircle(scenario: scenario)
        }
    }
}

/// All minimal circles on one image, four per row.
struct MinimalSheetSnapshot: View {
    let scenarios: [LiveScenario]

    private var rows: [[LiveScenario]] {
        stride(from: 0, to: scenarios.count, by: 4).map { start in
            Array(scenarios[start..<min(start + 4, scenarios.count)])
        }
    }

    var body: some View {
        LiveCanvas(
            caption: "dynamic island minimal \u{00B7} all scenarios (37 pt circle)",
            width: 4 * 84 + 2 * LiveMetrics.canvasPadding
        ) {
            VStack(spacing: 12) {
                ForEach(0..<rows.count, id: \.self) { rowIndex in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(rows[rowIndex]) { scenario in
                            VStack(spacing: 4) {
                                MinimalIslandCircle(scenario: scenario)
                                Text(scenario.slug)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.75))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 84)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Dynamic Island: expanded

/// The expanded presentation put together the way the system arranges the four regions (Apple: `leading` and `trailing`
/// sit either side of the TrueDepth camera and wrap additional content below it, `center` sits right below the camera,
/// `bottom` sits below all of them): a 371 pt black rounded rectangle (radius 44) whose top row is as high as the camera
/// (36.67 pt), regions vertically centred in it and growing downward when taller. Widths of the side columns are what is
/// left beside the camera. `WorkoutLiveActivity` declares no `center` region, so the convenience initializer leaves it empty.
struct ExpandedIslandFrame<Leading: View, Trailing: View, Center: View, Bottom: View>: View {
    let leading: Leading
    let trailing: Trailing
    let center: Center
    let bottom: Bottom

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder center: () -> Center,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.leading = leading()
        self.trailing = trailing()
        self.center = center()
        self.bottom = bottom()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                leading
                    .frame(width: LiveMetrics.expandedSideColumn, alignment: .leading)
                    .frame(minHeight: LiveMetrics.islandHeight)
                VStack(spacing: 0) {
                    Color.clear.frame(width: LiveMetrics.sensorWidth, height: LiveMetrics.islandHeight)
                    center
                }
                .frame(width: LiveMetrics.sensorWidth)
                trailing
                    .frame(width: LiveMetrics.expandedSideColumn, alignment: .trailing)
                    .frame(minHeight: LiveMetrics.islandHeight)
            }
            bottom
                .frame(width: LiveMetrics.expandedWidth - 2 * LiveMetrics.expandedSideInset, alignment: .leading)
        }
        .padding(.horizontal, LiveMetrics.expandedSideInset)
        .padding(.bottom, LiveMetrics.expandedBottomInset)
        .frame(width: LiveMetrics.expandedWidth)
        .background(
            Color.black,
            in: RoundedRectangle(cornerRadius: LiveMetrics.expandedCornerRadius, style: .continuous)
        )
        .overlay(alignment: .top) {
            SensorHint()
        }
    }
}

extension ExpandedIslandFrame where Center == EmptyView {
    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.init(leading: leading, trailing: trailing, center: { EmptyView() }, bottom: bottom)
    }
}

/// The three regions `WorkoutLiveActivity` declares (leading, trailing, bottom), with the same arguments.
struct ExpandedIslandContent: View {
    let scenario: LiveScenario

    var body: some View {
        ExpandedIslandFrame(
            leading: {
                IslandExpandedLeading(state: scenario.snapshot, isStale: scenario.isStale)
            },
            trailing: {
                IslandExpandedTrailing(state: scenario.snapshot, isStale: scenario.isStale)
            },
            bottom: {
                IslandExpandedBottom(
                    state: scenario.snapshot,
                    workoutName: scenario.workoutName,
                    isStale: scenario.isStale
                )
            }
        )
        .activityStaticClock(scenario.staticClock)
    }
}

struct ExpandedSnapshot: View {
    let scenario: LiveScenario

    var body: some View {
        LiveCanvas(
            caption: "dynamic island expanded \u{00B7} " + scenario.title
                + "\n371 pt wide, radius 44; regions leading / trailing / bottom (no center)",
            width: LiveMetrics.expandedWidth + 2 * LiveMetrics.canvasPadding
        ) {
            ExpandedIslandContent(scenario: scenario)
        }
    }
}

// MARK: - Output

enum LiveSnapshotError: LocalizedError {
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
enum LiveOutput {
    /// `SCREENSHOT_DIR` (CI passes it as `TEST_RUNNER_SCREENSHOT_DIR`); the temporary directory when it is not set.
    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    /// File name convention: "live-<NN>-<kebab-name>.png".
    static func fileName(number: Int, name: String) -> String {
        "live-" + String(format: "%02d", number) + "-" + name + ".png"
    }

    /// Opaque @3x rendering of `view` at its ideal size.
    static func render<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = LiveMetrics.scale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Ideal size of `view` in points, measured with a 4x render; nil when nothing could be rendered.
    static func idealSize<V: View>(of view: V) -> CGSize? {
        let scale: CGFloat = 4
        let renderer = ImageRenderer(content: view.fixedSize())
        renderer.scale = scale
        guard let measured = renderer.cgImage else { return nil }
        return CGSize(width: CGFloat(measured.width) / scale, height: CGFloat(measured.height) / scale)
    }

    /// Renders `view`, writes `live-<number>-<name>.png` into `directory`, attaches it to `test` and returns its size in points.
    @discardableResult
    static func save<V: View>(_ view: V, number: Int, name: String, test: XCTestCase) throws -> CGSize {
        let file = fileName(number: number, name: name)
        guard let rendered = render(view) else { throw LiveSnapshotError.renderFailed(file) }
        guard let data = rendered.pngData() else { throw LiveSnapshotError.encodeFailed(file) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(file), options: .atomic)

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = file
        attachment.lifetime = .keepAlways
        test.add(attachment)

        let scale = LiveMetrics.scale
        let pixelWidth = CGFloat(rendered.cgImage?.width ?? 0)
        let pixelHeight = CGFloat(rendered.cgImage?.height ?? 0)
        return CGSize(width: pixelWidth / scale, height: pixelHeight / scale)
    }

    /// Writes a text file next to the PNGs and attaches it.
    static func saveText(_ text: String, fileName: String, test: XCTestCase) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try text.write(to: directory.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        let attachment = XCTAttachment(string: text)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}

// MARK: - Measurements

/// Ideal sizes (points) of the pieces of one scenario, compared with the limits of the surfaces.
struct LiveMeasurement {
    var lockCard: CGSize?
    var compactLeading: CGSize?
    var compactTrailing: CGSize?
    var minimal: CGSize?
    var expandedLeading: CGSize?
    var expandedTrailing: CGSize?
    var expandedTotal: CGSize?

    /// Tolerance for the pixel rounding of the 4x measurement render.
    private static let tolerance: CGFloat = 0.5

    /// Hard limits of the system: the Lock Screen is cut at 160 pt, the compact slots are 52.33 pt wide, the minimal
    /// island is at most 45 pt wide, the expanded island at most 160 pt tall. Empty when everything fits.
    var violations: [String] {
        var found: [String] = []
        let tolerance = LiveMeasurement.tolerance
        func check(_ size: CGSize?, _ label: String, maxWidth: CGFloat?, maxHeight: CGFloat?) {
            guard let size = size else {
                found.append("\(label): could not be measured")
                return
            }
            if let limit = maxWidth, size.width > limit + tolerance {
                found.append("\(label): \(LiveMeasurement.points(size.width)) pt wide, limit \(LiveMeasurement.points(limit)) pt")
            }
            if let limit = maxHeight, size.height > limit + tolerance {
                found.append("\(label): \(LiveMeasurement.points(size.height)) pt tall, limit \(LiveMeasurement.points(limit)) pt")
            }
        }
        check(lockCard, "lock screen card", maxWidth: nil, maxHeight: LiveMetrics.lockScreenMaxHeight)
        check(compactLeading, "compact leading", maxWidth: LiveMetrics.compactSlotWidth, maxHeight: LiveMetrics.islandHeight)
        check(compactTrailing, "compact trailing", maxWidth: LiveMetrics.compactSlotWidth, maxHeight: LiveMetrics.islandHeight)
        check(minimal, "minimal", maxWidth: LiveMetrics.minimalMaxWidth, maxHeight: LiveMetrics.islandHeight)
        check(expandedTotal, "expanded island", maxWidth: nil, maxHeight: LiveMetrics.expandedMaxHeight)
        return found
    }

    /// Soft findings: the expanded leading / trailing content is wider than the column beside the camera at its natural
    /// size, so its text has to scale down (the leading title scales to 0.7 before anything is cut off; the layouts split
    /// the longest labels over two lines or drop the badge so that this is enough).
    var notes: [String] {
        var found: [String] = []
        let column = LiveMetrics.expandedSideColumn
        if let size = expandedLeading, size.width > column + LiveMeasurement.tolerance {
            found.append("expanded leading: natural width \(LiveMeasurement.points(size.width)) pt > column \(LiveMeasurement.points(column)) pt (the views scale their text down before it would be cut off)")
        }
        if let size = expandedTrailing, size.width > column + LiveMeasurement.tolerance {
            found.append("expanded trailing: natural width \(LiveMeasurement.points(size.width)) pt > column \(LiveMeasurement.points(column)) pt (the views scale their text down before it would be cut off)")
        }
        return found
    }

    static func points(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }

    static func describe(_ size: CGSize?) -> String {
        guard let size = size else { return "n/a" }
        return points(size.width) + " x " + points(size.height)
    }
}

@MainActor
enum LiveGeometry {
    static func measure(_ scenario: LiveScenario) -> LiveMeasurement {
        let clock = scenario.staticClock
        var result = LiveMeasurement()
        result.lockCard = LiveOutput.idealSize(of: LockScreenCard(scenario: scenario))
        result.compactLeading = LiveOutput.idealSize(
            of: IslandCompactLeading(state: scenario.snapshot, isStale: scenario.isStale).activityStaticClock(clock)
        )
        result.compactTrailing = LiveOutput.idealSize(
            of: IslandCompactTrailing(state: scenario.snapshot, isStale: scenario.isStale).activityStaticClock(clock)
        )
        result.minimal = LiveOutput.idealSize(
            of: IslandMinimal(state: scenario.snapshot, isStale: scenario.isStale).activityStaticClock(clock)
        )
        result.expandedLeading = LiveOutput.idealSize(
            of: IslandExpandedLeading(state: scenario.snapshot, isStale: scenario.isStale).activityStaticClock(clock)
        )
        result.expandedTrailing = LiveOutput.idealSize(
            of: IslandExpandedTrailing(state: scenario.snapshot, isStale: scenario.isStale).activityStaticClock(clock)
        )
        result.expandedTotal = LiveOutput.idealSize(of: ExpandedIslandContent(scenario: scenario))
        return result
    }
}
#endif
