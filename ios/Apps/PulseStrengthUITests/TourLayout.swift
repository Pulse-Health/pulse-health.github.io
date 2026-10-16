// TourLayout.swift
//
// Layout measurements of the screenshot tour (StrengthTourTests.swift): where the header, the exercise navigator, the
// exercise card and the rest dock of the active-workout screen are, in points, and whether any of them leaves the screen.
// The result is the text file 'tour-<config>-layout.txt' in SCREENSHOT_DIR (attached to the test result as well).
//
// Why it exists: the design wants the active-workout screen to fit WITHOUT page scrolling (header, navigator, a flexible
// exercise card, the rest dock) on every iPhone, down to the iPhone SE (3rd generation, 375 x 667 pt). A screenshot shows
// that only when somebody looks at it; this file says it in numbers and prints 'LAYOUT VIOLATION' lines.
//
// How: the app has no accessibility identifiers for these containers, so each region is the union of the frames of its
// labelled children (the buttons and elements the flow test also finds by label). Every part is listed with its own frame
// and whether it can be hit, so a wrong match (a hidden copy of a label that a screen behind a cover keeps in the tree)
// shows up as an odd line instead of silently bending a number.
//
// Nothing here uses an API that the flow test does not use already, except XCUIScreen.main.screenshot().image (to read the
// screen size in points when the window frame is unusable) and XCUIElementQuery.scrollViews / tables / collectionViews.
// The measurements never fail the test: they only write the report.

import XCTest
import UIKit

// MARK: - Number formatting

/// 12.0 -> "12", 12.34 -> "12.3". Never traps: a value that is not finite (CGRect.null) prints "?".
func tourNumber(_ value: CGFloat) -> String {
    let number = Double(value)
    guard number.isFinite, abs(number) < 1_000_000 else {
        return "?"
    }
    let rounded = (number * 10).rounded() / 10
    if rounded == rounded.rounded() {
        return String(Int(rounded))
    }
    return String(rounded)
}

/// Concatenates the pieces: a flat call instead of a long chain of `+`, which Swift's type checker handles slowly.
func tourText(_ pieces: String...) -> String {
    pieces.joined()
}

/// "393 x 852".
func tourSize(_ width: CGFloat, _ height: CGFloat) -> String {
    tourNumber(width) + " x " + tourNumber(height)
}

/// "x=0 y=20 w=393 h=106 (maxX=393 maxY=126)".
func tourRect(_ rect: CGRect) -> String {
    let parts: [String] = [
        "x=" + tourNumber(rect.minX),
        "y=" + tourNumber(rect.minY),
        "w=" + tourNumber(rect.width),
        "h=" + tourNumber(rect.height),
        "(maxX=" + tourNumber(rect.maxX),
        "maxY=" + tourNumber(rect.maxY) + ")"
    ]
    return parts.joined(separator: " ")
}

// MARK: - What is measured

/// One element of the active-workout screen to look for: the first target that exists wins.
struct TourSpec {
    let name: String
    let targets: [Target]
    /// True for controls the user can tap (they take part in the 'bottom-most interactive element' check).
    let interactive: Bool
}

/// One element that was found.
struct TourPart {
    let region: String
    let name: String
    let frame: CGRect
    let hittable: Bool
    let interactive: Bool
}

/// Elements that must follow each other from left to right without overlapping.
struct TourRowCheck {
    let label: String
    let names: [String]
}

/// The elements of the active-workout screen (labels as in Components/ActiveHeaderView, NavigatorBar, ExerciseCardView and
/// RestDockView). A missing element is not an error: the screen state decides what exists (a dock only while a rest runs).
enum TourRegions {
    static let header: [TourSpec] = [
        TourSpec(name: "Minimise workout", targets: [.button("Minimise workout")], interactive: true),
        TourSpec(name: "More", targets: [.button("active-more"), .button("More")], interactive: true),
        TourSpec(name: "Finish", targets: [.button("Finish")], interactive: true),
        TourSpec(name: "Volume", targets: [.element("Volume")], interactive: false),
        TourSpec(name: "Sets logged", targets: [.element("Sets logged")], interactive: false),
        TourSpec(name: "Heart rate", targets: [.element("Heart rate")], interactive: false),
        TourSpec(name: "Workout progress", targets: [.element("Workout progress")], interactive: false)
    ]

    static let navigator: [TourSpec] = [
        TourSpec(name: "Previous exercise", targets: [.button("Previous exercise")], interactive: true),
        TourSpec(name: "Exercise position", targets: [.element("Exercise [0-9]+ of [0-9]+", .regex)], interactive: false),
        TourSpec(name: "Next exercise", targets: [.button("Next exercise")], interactive: true),
        TourSpec(name: "Edit", targets: [.button("Edit", .loose)], interactive: true)
    ]

    static let card: [TourSpec] = [
        TourSpec(name: "Show form demo", targets: [.button("Show form demo")], interactive: true),
        TourSpec(name: "Exercise options", targets: [.button("Exercise options")], interactive: true),
        TourSpec(name: "Add Set", targets: [.button("Add Set", .loose)], interactive: true),
        TourSpec(name: "Rest timer", targets: [.button("Rest timer")], interactive: true),
        TourSpec(name: "Exercise note", targets: [.button("Exercise note")], interactive: true),
        TourSpec(name: "Next time", targets: [.element("Next time", .prefix)], interactive: false),
        TourSpec(name: "Apply suggestion", targets: [.button("coach-apply")], interactive: true),
        TourSpec(name: "Coach tip", targets: [.element("Coach", .prefix)], interactive: false)
    ]

    /// The rest dock: the countdown block (an element, not a button) and its buttons. 'Skip' becomes 'Dismiss' when the
    /// rest is over; 'Reps in reserve' only shows after a working set was logged.
    static let dock: [TourSpec] = [
        TourSpec(
            name: "Rest countdown",
            targets: [
                Target("Rest timer", type: .other, mode: .prefix),
                Target("Rest timer", type: .staticText, mode: .prefix),
                Target("Rest over", type: .other, mode: .prefix),
                Target("Rest over", type: .staticText, mode: .prefix)
            ],
            interactive: false
        ),
        TourSpec(name: "Subtract 15 seconds", targets: [.button("Subtract 15 seconds")], interactive: true),
        TourSpec(name: "Add 15 seconds", targets: [.button("Add 15 seconds")], interactive: true),
        TourSpec(name: "Skip", targets: [.button("Skip")], interactive: true),
        TourSpec(name: "Dismiss", targets: [.button("Dismiss")], interactive: true),
        TourSpec(name: "Reps in reserve", targets: [.element("Reps in reserve")], interactive: true)
    ]

    /// Elements whose vertical position says whether the whole page moves when the screen is swiped.
    static let anchors: [TourSpec] = [
        TourSpec(name: "Minimise workout", targets: [.button("Minimise workout")], interactive: true),
        TourSpec(name: "Next exercise", targets: [.button("Next exercise")], interactive: true),
        TourSpec(name: "Add Set", targets: [.button("Add Set", .loose)], interactive: true)
    ]

    static let rowChecks: [TourRowCheck] = [
        TourRowCheck(label: "title row", names: ["Minimise workout", "More", "Finish"]),
        TourRowCheck(label: "stats row", names: ["Volume", "Sets logged", "Heart rate"]),
        TourRowCheck(label: "navigator", names: ["Previous exercise", "Exercise position", "Next exercise", "Edit"]),
        TourRowCheck(label: "card controls", names: ["Add Set", "Rest timer", "Exercise note"]),
        TourRowCheck(label: "dock row", names: ["Rest countdown", "Subtract 15 seconds", "Add 15 seconds", "Skip"])
    ]
}

// MARK: - The report

@MainActor
final class TourLayout {
    private let driver: UIDriver
    private let testCase: XCTestCase
    private let config: String

    /// 'tour-<config>-layout.txt' next to the screenshots.
    let fileURL: URL

    /// The window of the app in points (the screen of the phone).
    private(set) var screen = CGRect.zero
    /// True when a swipe moved the header, the navigator and the card; nil when it could not be tested.
    private(set) var pageScrolls: Bool?
    /// False as soon as an interactive element of the active-workout screen leaves the screen; nil when not measured yet.
    private(set) var bottomInside: Bool?
    private(set) var violations: [String] = []
    /// One line about the last measurement, for the step log.
    private(set) var lastSummary = ""

    private var screenshotLine = ""
    private var sections: [String] = []
    private var bottomLines: [String] = []

    init(driver: UIDriver, output: FlowOutput, testCase: XCTestCase, config: String) {
        self.driver = driver
        self.testCase = testCase
        self.config = config
        self.fileURL = output.directory.appendingPathComponent("tour-" + config + "-layout.txt")
    }

    var screenText: String {
        tourSize(screen.width, screen.height) + " pt"
    }

    // MARK: Screen

    /// Reads the size of the window (the screen of the phone, in points).
    func readScreen() {
        let window = driver.app.windows.element(boundBy: 0)
        if window.exists {
            let frame = window.frame
            if frame.width > 0 && frame.height > 0 {
                screen = frame
            }
        }
        let image = XCUIScreen.main.screenshot().image
        screenshotLine = tourText("screenshot: ", tourSize(image.size.width, image.size.height), " pt, scale ", tourNumber(image.scale))
        if screen.width <= 0 || screen.height <= 0 {
            screen = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        }
    }

    // MARK: Measuring the active-workout screen

    /// Measures header, navigator, card and dock in the current state of the screen and checks them against the screen.
    /// `scanButtons` additionally looks at every button that can be hit (the screen behind a cover is skipped).
    func measureActive(state: String, scanButtons: Bool) {
        if screen.width <= 0 || screen.height <= 0 {
            readScreen()
        }
        var lines: [String] = ["", "=== " + state + " ==="]

        let header = collect("header", TourRegions.header, &lines)
        let navigator = collect("navigator", TourRegions.navigator, &lines)
        let card = collect("card", TourRegions.card, &lines)
        let dock = collect("dock", TourRegions.dock, &lines)
        let rows = collectRows(&lines)
        let allParts = header + navigator + card + dock
        let violationsBefore = violations.count

        // 1. Nothing may leave the screen.
        for part in allParts {
            checkInside(part.frame, what: part.region + " / " + part.name, state: state)
        }

        // 2. The regions must not overlap each other (they are stacked: header, navigator, card, dock).
        let headerRect = unionOf(header)
        let navigatorRect = unionOf(navigator)
        let cardRect = unionOf(card)
        let dockRect = unionOf(dock)
        if let upper = headerRect, let lower = navigatorRect, upper.maxY > lower.minY + 1 {
            violate(tourText("[", state, "] the header overlaps the navigator by ", tourNumber(upper.maxY - lower.minY), " pt"))
        }
        if let upper = navigatorRect, let lower = cardRect, upper.maxY > lower.minY + 1 {
            violate(tourText("[", state, "] the navigator overlaps the exercise card by ", tourNumber(upper.maxY - lower.minY), " pt"))
        }
        if let upper = cardRect, let lower = dockRect {
            let gap = lower.minY - upper.maxY
            lines.append("gap between the card and the rest dock: " + tourNumber(gap) + " pt (design: about 34)")
            if gap < 12 {
                violate(tourText("[", state, "] the exercise card runs into the rest dock (gap ", tourNumber(gap), " pt, the design has about 34)"))
            }
        } else if let upper = cardRect {
            let below = screen.maxY - upper.maxY
            lines.append("space below the card: " + tourNumber(below) + " pt (design: about 42, no dock)")
            if below < 12 {
                violate(tourText("[", state, "] the exercise card ends only ", tourNumber(below), " pt above the bottom edge of the screen"))
            }
        }

        if let dockBox = dockRect {
            let margin = screen.maxY - dockBox.maxY
            lines.append(tourText("space below the rest dock: ", tourNumber(margin), " pt (design: about 34)"))
            if margin < 12 {
                violate(tourText("[", state, "] the rest dock ends only ", tourNumber(margin), " pt above the bottom edge of the screen (the design has about 34)"))
            }
        }

        // 3. Controls that belong in one row must not overlap horizontally.
        for check in TourRegions.rowChecks {
            var previous: TourPart?
            for name in check.names {
                guard let part = allParts.first(where: { $0.name == name }) else {
                    continue
                }
                if let before = previous, part.frame.minX < before.frame.maxX - 1 {
                    let overlap = tourNumber(before.frame.maxX - part.frame.minX)
                    violate(tourText("[", state, "] ", check.label, ": '", before.name, "' and '", part.name, "' overlap by ", overlap, " pt"))
                }
                previous = part
            }
        }

        // 4. The bottom-most interactive element (set rows count when they can be hit: rows scrolled out of a table do not).
        var bottom: TourPart?
        for part in allParts + rows where part.interactive {
            if let current = bottom {
                if part.frame.maxY > current.frame.maxY {
                    bottom = part
                }
            } else {
                bottom = part
            }
        }
        if let lowest = bottom {
            let inside = problems(of: lowest.frame).isEmpty
            let verdict = inside ? "inside the screen" : "OUTSIDE the screen"
            let pieces: [String] = [
                "bottom-most interactive element: '" + lowest.name + "' (" + lowest.region + ")",
                "maxY " + tourNumber(lowest.frame.maxY) + " of " + tourNumber(screen.height),
                "-> " + verdict
            ]
            let line = pieces.joined(separator: ", ")
            lines.append(line)
            bottomLines.append("[" + state + "] " + line)
            bottomInside = (bottomInside ?? true) && inside
        } else {
            lines.append("bottom-most interactive element: none found")
        }

        if scanButtons {
            scan(state: state, lines: &lines)
        }

        // 5. A hint whether the text follows the content size: heights of text-bearing controls. They must grow in a run
        //    with an accessibility content size; identical numbers mean fixed-size fonts.
        var probe: [String] = []
        for name in ["Finish", "Edit", "Add Set", "Minimise workout", "Sets logged"] {
            if let part = allParts.first(where: { $0.name == name }) {
                probe.append(name + " h=" + tourNumber(part.frame.height))
            }
        }
        if let firstRow = rows.first {
            probe.append("set row h=" + tourNumber(firstRow.frame.height))
        }
        lines.append("text-size probe (compare with the other runs): " + probe.joined(separator: ", "))

        sections.append(contentsOf: lines)
        let added = violations.count - violationsBefore
        var bottomText = "no bottom element"
        if let lowest = bottom {
            bottomText = "bottom-most '" + lowest.name + "' maxY " + tourNumber(lowest.frame.maxY)
        }
        let summaryParts: [String] = [
            "layout '" + state + "': " + String(allParts.count) + " parts",
            String(rows.count) + " set rows",
            String(added) + " violation(s)",
            bottomText + " of " + tourNumber(screen.height)
        ]
        lastSummary = summaryParts.joined(separator: ", ")
        flush()
    }

    /// Finds the elements of one region and lists them. Returns the parts that were found.
    private func collect(_ region: String, _ specs: [TourSpec], _ lines: inout [String]) -> [TourPart] {
        var parts: [TourPart] = []
        var partLines: [String] = []
        for spec in specs {
            guard let element = locate(spec.targets) else {
                partLines.append("    " + pad(spec.name, 22) + "not found")
                continue
            }
            let frame = element.frame
            if !usable(frame) {
                partLines.append("    " + pad(spec.name, 22) + "frame not usable: " + tourRect(frame))
                continue
            }
            let hittable = element.isHittable
            parts.append(TourPart(region: region, name: spec.name, frame: frame, hittable: hittable, interactive: spec.interactive))
            let hitText = hittable ? "  hittable" : "  not hittable"
            partLines.append(tourText("    ", pad(spec.name, 22), tourRect(frame), hitText))
        }
        var regionText = "not found"
        if let union = unionOf(parts) {
            regionText = tourRect(union)
        }
        lines.append(pad(region, 10) + regionText)
        lines.append(contentsOf: partLines)
        return parts
    }

    /// The set rows ('Set 3, working set, 82.5 kilograms, 6 reps, not logged'): listed, not part of the card's union (the
    /// rows of a long table scroll inside the card and may lie outside the screen without being a problem).
    private func collectRows(_ lines: inout [String]) -> [TourPart] {
        let format = "label BEGINSWITH 'Set ' AND label ENDSWITH 'logged'"
        let matches = driver.app.descendants(matching: .any).matching(NSPredicate(format: format))
        let total = matches.count
        var parts: [TourPart] = []
        var rowLines: [String] = []
        var index = 0
        var visible = 0
        while index < total && index < 12 {
            let row = matches.element(boundBy: index)
            index += 1
            guard row.exists else {
                continue
            }
            let frame = row.frame
            if !usable(frame) {
                continue
            }
            let hittable = row.isHittable
            if hittable {
                visible += 1
            }
            let name = "Set row " + String(index)
            parts.append(TourPart(region: "set rows", name: name, frame: frame, hittable: hittable, interactive: hittable))
            let note = hittable ? "  hittable" : "  not hittable (scrolled out of the table)"
            rowLines.append("    " + pad(name, 22) + tourRect(frame) + note)
        }
        lines.append(tourText("set rows  ", String(total), " in the tree, ", String(visible), " of the first ", String(parts.count), " can be hit"))
        lines.append(contentsOf: rowLines)
        return parts
    }

    /// Every button that can be hit (topmost first, at most 60, at most 6 s): none may leave the screen. A button that is
    /// completely off screen cannot be hit and is not found here; the named parts above cover those.
    private func scan(state: String, lines: inout [String]) {
        let buttons = driver.app.buttons
        let total = buttons.count
        let deadline = Date().addingTimeInterval(6)
        var index = total - 1
        var checked = 0
        var hittableCount = 0
        var flagged = 0
        while index >= 0 && checked < 60 && Date() < deadline {
            let button = buttons.element(boundBy: index)
            index -= 1
            checked += 1
            guard button.exists, button.isHittable else {
                continue
            }
            hittableCount += 1
            let frame = button.frame
            if !usable(frame) {
                continue
            }
            if !problems(of: frame).isEmpty {
                flagged += 1
                bottomInside = false
                checkInside(frame, what: "button '" + button.label + "'", state: state)
            }
        }
        lines.append(tourText("button scan: ", String(total), " buttons in the tree, ", String(checked), " checked, ", String(hittableCount), " can be hit, ", String(flagged), " leave the screen"))
    }

    // MARK: Does the page scroll?

    /// Swipes the screen up and measures whether the header, the navigator and the card moved (a page that scrolls), then
    /// swipes back. The set table may scroll inside the card; that does not move these anchors.
    func measurePageScroll(state: String) {
        if screen.width <= 0 || screen.height <= 0 {
            readScreen()
        }
        var lines: [String] = ["", "=== does the page scroll? (" + state + ") ==="]

        let scrollViews = driver.app.scrollViews
        let total = scrollViews.count
        var pageSized = 0
        var index = 0
        while index < total && index < 12 {
            let view = scrollViews.element(boundBy: index)
            index += 1
            guard view.exists else {
                continue
            }
            let frame = view.frame
            let hittable = view.isHittable
            let wide = frame.width >= screen.width * 0.9
            let tall = frame.height >= screen.height * 0.5
            if wide && tall && hittable {
                pageSized += 1
            }
            let hitText = hittable ? "  hittable" : "  not hittable"
            let sizeText = (wide && tall) ? "  page-sized" : ""
            lines.append(tourText("    scrollView[", String(index - 1), "] ", tourRect(frame), hitText, sizeText))
        }
        let tableCount = driver.app.tables.count
        let collectionCount = driver.app.collectionViews.count
        lines.append(tourText("scroll views in the tree: ", String(total), " (", String(pageSized), " visible and as large as the page); tables: ", String(tableCount), ", collection views: ", String(collectionCount)))

        let before = anchorPositions()
        if before.isEmpty {
            lines.append("pageScrolls: unknown (none of the anchor elements was found)")
            sections.append(contentsOf: lines)
            lastSummary = "page scroll test: no anchor element found"
            flush()
            return
        }
        driver.app.swipeUp()
        driver.pause(1.0)
        let during = anchorPositions()
        driver.app.swipeDown()
        driver.pause(1.0)
        let after = anchorPositions()

        var moved: CGFloat = 0
        var notRestored = false
        for name in before.keys.sorted() {
            guard let start = before[name] else {
                continue
            }
            let up = during[name] ?? start
            let back = after[name] ?? start
            moved = max(moved, abs(up - start))
            if abs(back - start) > 2 {
                notRestored = true
            }
            lines.append(tourText("    ", pad(name, 22), "y ", tourNumber(start), " -> ", tourNumber(up), " after a swipe up -> ", tourNumber(back), " after a swipe down"))
        }
        let scrolls = moved > 2
        pageScrolls = scrolls
        let scrollsText = scrolls ? "true" : "false"
        lines.append(tourText("pageScrolls: ", scrollsText, " (largest move of an anchor: ", tourNumber(moved), " pt)"))
        if notRestored {
            lines.append("note: the screen did not return to its position after swiping back")
        }
        if scrolls {
            violate(tourText("[", state, "] the active-workout page scrolls (an anchor moved ", tourNumber(moved), " pt on a swipe up); the design fits header, navigator, card and dock into the screen"))
        }
        sections.append(contentsOf: lines)
        lastSummary = tourText("page scroll test: pageScrolls=", scrollsText, ", largest move ", tourNumber(moved), " pt")
        flush()
    }

    private func anchorPositions() -> [String: CGFloat] {
        var result: [String: CGFloat] = [:]
        for spec in TourRegions.anchors {
            guard let element = locate(spec.targets) else {
                continue
            }
            let frame = element.frame
            if usable(frame) {
                result[spec.name] = frame.minY
            }
        }
        return result
    }

    // MARK: Output

    /// Writes the report. Called after every measurement, so a crash or an early end of the test leaves what was measured.
    func flush() {
        var out: [String] = []
        out.append("Pulse Strength tour: layout of the active-workout screen")
        out.append("config: " + config)
        out.append("os: " + ProcessInfo.processInfo.operatingSystemVersionString)
        out.append("screen (points): " + tourSize(screen.width, screen.height) + "   window frame " + tourRect(screen))
        if !screenshotLine.isEmpty {
            out.append(screenshotLine)
        }
        out.append("pageScrolls: " + word(pageScrolls))
        out.append("bottomMostInteractiveInsideScreen: " + word(bottomInside))
        out.append("violations: " + String(violations.count))
        out.append(contentsOf: violations)
        if !bottomLines.isEmpty {
            out.append("")
            out.append(contentsOf: bottomLines)
        }
        out.append(contentsOf: sections)
        let text = out.joined(separator: "\n") + "\n"
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Writes the report one last time and attaches it to the test result.
    func finish() {
        flush()
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let attachment = XCTAttachment(string: text)
        attachment.name = "tour-" + config + "-layout.txt"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    // MARK: Helpers

    private func word(_ value: Bool?) -> String {
        switch value {
        case .some(true):
            return "true"
        case .some(false):
            return "false"
        case .none:
            return "unknown"
        }
    }

    private func violate(_ message: String) {
        violations.append("LAYOUT VIOLATION: " + message)
    }

    private func pad(_ text: String, _ width: Int) -> String {
        if text.count >= width {
            return text + " "
        }
        return text + String(repeating: " ", count: width - text.count)
    }

    /// The first target that has a match (UIDriver.find only returns an element it has just counted).
    private func locate(_ targets: [Target]) -> XCUIElement? {
        for target in targets {
            if let element = driver.find(target) {
                return element
            }
        }
        return nil
    }

    private func usable(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && !frame.isEmpty
    }

    private func unionOf(_ parts: [TourPart]) -> CGRect? {
        guard var result = parts.first?.frame else {
            return nil
        }
        for part in parts.dropFirst() {
            result = result.union(part.frame)
        }
        return result
    }

    /// Which edges of the screen the rectangle crosses (empty when it lies inside). Half a point of tolerance.
    private func problems(of rect: CGRect) -> [String] {
        let tolerance: CGFloat = 0.5
        var result: [String] = []
        if rect.minX < screen.minX - tolerance {
            result.append("minX " + tourNumber(rect.minX) + " < " + tourNumber(screen.minX))
        }
        if rect.maxX > screen.maxX + tolerance {
            result.append("maxX " + tourNumber(rect.maxX) + " > " + tourNumber(screen.maxX))
        }
        if rect.minY < screen.minY - tolerance {
            result.append("minY " + tourNumber(rect.minY) + " < " + tourNumber(screen.minY))
        }
        if rect.maxY > screen.maxY + tolerance {
            result.append("maxY " + tourNumber(rect.maxY) + " > " + tourNumber(screen.maxY))
        }
        return result
    }

    private func checkInside(_ rect: CGRect, what: String, state: String) {
        let found = problems(of: rect)
        if found.isEmpty {
            return
        }
        violate(tourText("[", state, "] ", what, " leaves the screen (", tourSize(screen.width, screen.height), " pt): ", found.joined(separator: ", "), "; frame ", tourRect(rect)))
    }
}
