// FlowSupport.swift
//
// Support code of the Pulse Strength UI flow test (StrengthFlowTests.swift): finding elements by label,
// tapping them, waiting, taking screenshots and writing the step log.
//
// Nothing here knows the app. The flow test never lets one missing element stop the walk: every helper records
// a failure with XCTFail (the test runs with continueAfterFailure = true) and returns, so the next step still runs.
//
// Screenshots are written to the directory in the environment variable SCREENSHOT_DIR (CI sets
// TEST_RUNNER_SCREENSHOT_DIR, xcodebuild forwards it without the prefix) or to NSTemporaryDirectory(),
// and are attached to the test result as well (XCTAttachment, lifetime keepAlways).

import XCTest

/// "7" -> "07".
func twoDigits(_ value: Int) -> String {
    value < 10 ? "0" + String(value) : String(value)
}

// MARK: - Targets

/// How an element label is compared with the wanted text.
enum MatchMode {
    /// The label (or the accessibility identifier) equals the text.
    case exact
    /// The label begins with the text.
    case prefix
    /// The label contains the text.
    case contains
    /// The whole label matches the regular expression.
    case regex
    /// Exact, then prefix, then contains. For buttons whose label SwiftUI assembles from several children
    /// (an icon name plus a text), where the exact label is not known for sure.
    case loose
}

/// An element to find by label: its type and how its label is compared.
struct Target {
    let label: String
    let type: XCUIElement.ElementType
    let mode: MatchMode

    init(_ label: String, type: XCUIElement.ElementType, mode: MatchMode = .exact) {
        self.label = label
        self.type = type
        self.mode = mode
    }

    static func button(_ label: String, _ mode: MatchMode = .exact) -> Target {
        Target(label, type: .button, mode: mode)
    }

    static func text(_ label: String, _ mode: MatchMode = .exact) -> Target {
        Target(label, type: .staticText, mode: mode)
    }

    static func field(_ label: String, _ mode: MatchMode = .exact) -> Target {
        Target(label, type: .textField, mode: mode)
    }

    /// Any element type (headings, combined accessibility elements, containers).
    static func element(_ label: String, _ mode: MatchMode = .exact) -> Target {
        Target(label, type: .any, mode: mode)
    }

    /// For failure messages: "button with label 'Done' [exact]".
    var summary: String {
        let kind: String
        switch type {
        case .button:
            kind = "button"
        case .staticText:
            kind = "text"
        case .textField:
            kind = "text field"
        case .any:
            kind = "element"
        default:
            kind = "element of type " + String(type.rawValue)
        }
        return kind + " with label '" + label + "' [" + String(describing: mode) + "]"
    }
}

// MARK: - Output: screenshots and the step log

/// Writes the numbered PNG files and the log file, and attaches both to the test result.
@MainActor
final class FlowOutput {
    /// File name prefix of the suite: "ui" (the Live Activity and Watch suites use "live" and "watch").
    let suite: String
    let directory: URL
    let logURL: URL

    private let testCase: XCTestCase
    private let startedAt = Date()
    private var lines: [String] = []
    private(set) var screenshotCount = 0

    init(suite: String, testCase: XCTestCase) {
        self.suite = suite
        self.testCase = testCase

        var chosen = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        var warning: String?
        if let requested = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !requested.isEmpty {
            let url = URL(fileURLWithPath: requested, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                chosen = url
            } catch {
                warning = "SCREENSHOT_DIR '" + requested + "' cannot be created (" + String(describing: error) + "); using the temporary directory"
            }
        } else {
            warning = "SCREENSHOT_DIR is not set; using the temporary directory"
        }
        self.directory = chosen
        self.logURL = chosen.appendingPathComponent(suite + "-flow-log.txt")

        log("Screenshot directory: " + chosen.path)
        if let warning = warning {
            log("WARNING: " + warning)
        }
    }

    /// Appends one line (with the elapsed time) and rewrites the log file, so a crash leaves a complete log of what ran.
    func log(_ message: String) {
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        let stamp = twoDigits(elapsed / 60) + ":" + twoDigits(elapsed % 60)
        lines.append("[" + stamp + "] " + message)
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: logURL, atomically: true, encoding: .utf8)
    }

    /// Takes a full-screen screenshot named "<suite>-<NN>-<name>.png", writes it and attaches it. Returns the file name.
    @discardableResult
    func screenshot(_ name: String) -> String {
        screenshotCount += 1
        let fileName = suite + "-" + twoDigits(screenshotCount) + "-" + name + ".png"
        let shot = XCUIScreen.main.screenshot()
        let url = directory.appendingPathComponent(fileName)
        do {
            try shot.pngRepresentation.write(to: url, options: .atomic)
        } catch {
            XCTFail("Could not write screenshot " + fileName + " to " + directory.path + ": " + String(describing: error))
        }
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
        return fileName
    }

    /// Attaches the whole log to the test result.
    func attachLog() {
        let attachment = XCTAttachment(string: lines.joined(separator: "\n") + "\n")
        attachment.name = suite + "-flow-log.txt"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    /// Failures XCTest has recorded for the running test so far, including the ones it records itself
    /// (a tap on a vanished element, typeText without keyboard focus).
    func recordedFailureCount() -> Int {
        Int(testCase.testRun?.totalFailureCount ?? 0)
    }
}

// MARK: - Driver

/// Generic UI driving: steps with a status line in the log, finding by label (the topmost REACHABLE match, because a
/// sheet or a full-screen cover presented over a screen leaves that screen's elements in the accessibility tree: the
/// Strength hub's toolbar button "More" is still there, behind the active workout, and has the same label as the
/// header's), waiting, tapping, typing.
///
/// XCTest ends the whole test method when an element action fails inside XCTest itself (a tap on an element without a
/// valid hit point: "Failed to scroll to visible (by AX action)"; continueAfterFailure does not help there). The
/// helpers therefore never hand XCTest an element that is gone or that cannot be hit when another match exists; they
/// record an ordinary failure instead and the walk goes on.
@MainActor
class UIDriver {
    let app: XCUIApplication
    let output: FlowOutput

    /// Arguments of every (re)launch.
    var launchArguments: [String] = []

    private(set) var failureCount = 0
    private(set) var okSteps = 0
    private(set) var failedSteps = 0
    private(set) var skippedSteps = 0

    private var stepNumber = 0
    private var stepFailures: [String] = []
    private var stepNotes: [String] = []
    private var stepSkipped = false

    init(app: XCUIApplication, output: FlowOutput) {
        self.app = app
        self.output = output
    }

    /// Called after the app was launched again; the flow forgets what it believed about the screen.
    func appDidRestart() {}

    // MARK: Steps

    /// Runs one step of the walk and logs OK / FAILED / SKIPPED with its failure messages.
    /// After a failed step the stray dialogs, alerts and sheets are closed so that the next step starts clean.
    func step(_ title: String, checkApp: Bool = true, recoverOnFailure: Bool = true, _ body: () -> Void) {
        stepNumber += 1
        let number = stepNumber
        stepFailures = []
        stepNotes = []
        stepSkipped = false
        let myFailuresBefore = failureCount
        let runFailuresBefore = output.recordedFailureCount()
        let started = Date()

        // Written before the step runs: when XCTest ends the test inside the step, the last line of the log names it.
        output.log("RUNNING " + twoDigits(number) + " " + title)
        if checkApp {
            ensureAppRunning(before: title)
        }
        body()

        let seconds = Int(Date().timeIntervalSince(started).rounded())
        let heading = twoDigits(number) + " " + title + " (" + String(seconds) + " s)"
        let myFailures = failureCount - myFailuresBefore
        let otherFailures = (output.recordedFailureCount() - runFailuresBefore) - myFailures
        if otherFailures > 0 {
            stepFailures.append("XCTest itself recorded " + String(otherFailures) + " more issue(s) in this step (see the test report for the exact message)")
        }

        if !stepFailures.isEmpty {
            failedSteps += 1
            output.log("FAILED  " + heading)
            for message in stepFailures {
                output.log("          - " + message)
            }
        } else if stepSkipped {
            skippedSteps += 1
            output.log("SKIPPED " + heading)
        } else {
            okSteps += 1
            output.log("OK      " + heading)
        }
        for text in stepNotes {
            output.log("          " + text)
        }

        if !stepFailures.isEmpty && recoverOnFailure {
            recoverOverlays()
        }
    }

    /// Records a failure of the running step (and of the test) and goes on.
    func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        failureCount += 1
        stepFailures.append(message)
        XCTFail(message, file: file, line: line)
    }

    /// Adds an informational line under the step in the log.
    func note(_ text: String) {
        stepNotes.append(text)
    }

    /// Marks the running step as skipped (not a failure: the cause was recorded by an earlier step).
    func skip(_ reason: String) {
        stepSkipped = true
        stepNotes.append("skipped: " + reason)
    }

    func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Waits `settle` seconds for animations to end, then takes the screenshot and notes its file name.
    func shot(_ name: String, settle: TimeInterval = 0.7) {
        pause(settle)
        let fileName = output.screenshot(name)
        note("screenshot " + fileName)
    }

    // MARK: Launching

    func relaunch() {
        app.launchArguments = launchArguments
        if app.state != .notRunning {
            app.terminate()
        }
        app.launch()
        appDidRestart()
    }

    private func ensureAppRunning(before title: String) {
        if app.state == .runningForeground {
            return
        }
        fail("The app is not running in the foreground (XCUIApplication.State raw value " + String(app.state.rawValue)
            + ") before the step '" + title + "'. It probably crashed. Launching it again, which resets everything to the hub.")
        relaunch()
    }

    // MARK: Finding

    private func predicate(label: String, mode: MatchMode) -> NSPredicate {
        switch mode {
        case .prefix:
            return NSPredicate(format: "label BEGINSWITH %@", label)
        case .contains:
            return NSPredicate(format: "label CONTAINS %@", label)
        case .regex:
            return NSPredicate(format: "label MATCHES %@", label)
        case .exact, .loose:
            return NSPredicate(format: "label == %@ OR identifier == %@", label, label)
        }
    }

    func query(_ target: Target, mode: MatchMode) -> XCUIElementQuery {
        app.descendants(matching: target.type).matching(predicate(label: target.label, mode: mode))
    }

    /// The match modes `find` tries, in order.
    private func modes(of target: Target) -> [MatchMode] {
        if target.mode == .loose {
            return [.exact, .prefix, .contains]
        }
        return [target.mode]
    }

    /// The topmost element that matches right now, or nil. With several matches that is the last one (in hierarchy
    /// order) that can be hit: a screen hidden by a cover or a sheet keeps its elements in the tree, and its copy of a
    /// label ("More") must not win over the visible one. When none can be hit the last match is returned.
    func find(_ target: Target) -> XCUIElement? {
        for mode in modes(of: target) {
            let matches = query(target, mode: mode)
            let count = matches.count
            if count > 0 {
                return reachable(in: matches, count: count)
            }
        }
        return nil
    }

    private func reachable(in matches: XCUIElementQuery, count: Int) -> XCUIElement {
        if count > 1 {
            var index = count - 1
            while index >= 0 {
                let candidate = matches.element(boundBy: index)
                if candidate.exists && candidate.isHittable {
                    return candidate
                }
                index -= 1
            }
        }
        return matches.element(boundBy: count - 1)
    }

    /// How many elements match the target right now (in the first match mode that matches at all).
    func matchCount(_ target: Target) -> Int {
        for mode in modes(of: target) {
            let count = query(target, mode: mode).count
            if count > 0 {
                return count
            }
        }
        return 0
    }

    func exists(_ target: Target) -> Bool {
        find(target) != nil
    }

    /// Polls until the target exists (at least one check, even with a short timeout).
    func waitFor(_ target: Target, timeout: TimeInterval = 10) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let element = find(target) {
                return element
            }
            if Date() >= deadline {
                return nil
            }
            pause(0.3)
        }
    }

    /// Polls until one of the targets exists; returns its index.
    func waitForAny(_ targets: [Target], timeout: TimeInterval = 10) -> Int? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            for (index, target) in targets.enumerated() {
                if find(target) != nil {
                    return index
                }
            }
            if Date() >= deadline {
                return nil
            }
            pause(0.3)
        }
    }

    /// Polls until the target no longer exists.
    func waitUntilGone(_ target: Target, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if find(target) == nil {
                return true
            }
            if Date() >= deadline {
                return false
            }
            pause(0.3)
        }
    }

    // MARK: Tapping

    /// Taps the element (waiting for it first). A missing element is a failure when `required`.
    /// `scrollUp` swipes the screen up (at most 6 times) until the element is hittable.
    /// `coordinateFallback`: see `press`.
    @discardableResult
    func tap(_ target: Target, timeout: TimeInterval = 10, required: Bool = true, scrollUp: Bool = false, coordinateFallback: Bool = false) -> Bool {
        guard var element = waitFor(target, timeout: timeout) else {
            if required {
                fail("Not found within " + String(Int(timeout)) + " s: " + target.summary)
            }
            return false
        }
        if scrollUp {
            var attempts = 0
            while element.exists && !element.isHittable && attempts < 6 {
                app.swipeUp()
                pause(0.5)
                if let refreshed = find(target) {
                    element = refreshed
                }
                attempts += 1
            }
        }
        // Several matches and the one found cannot be hit (an animation is still running, or only the copy of a
        // screen that a cover hides is left): wait a moment for a reachable one instead of letting XCTest fail the tap
        // (which would end the whole test). A single match is left to XCTest, which also scrolls it into view.
        if element.exists && !element.isHittable && matchCount(target) > 1 {
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                pause(0.3)
                if let refreshed = find(target), refreshed.exists, refreshed.isHittable {
                    element = refreshed
                    break
                }
            }
            if element.exists && !element.isHittable {
                if required {
                    fail("None of the " + String(matchCount(target)) + " matches can be tapped (all hidden or off screen): " + target.summary)
                }
                return false
            }
        }
        return press(element, coordinateFallback: coordinateFallback)
    }

    /// Taps the first of the targets that exists (they are tried in this order on every poll): a control with its own
    /// accessibility identifier and, as a fallback, the same control by its label.
    @discardableResult
    func tap(anyOf targets: [Target], timeout: TimeInterval = 10, required: Bool = true) -> Bool {
        guard let index = waitForAny(targets, timeout: timeout) else {
            if required {
                fail("Not found within " + String(Int(timeout)) + " s: " + targets.map { $0.summary }.joined(separator: " or "))
            }
            return false
        }
        return tap(targets[index], timeout: 3, required: required)
    }

    /// Taps an element that was found. XCTest scrolls it into view first when it sits in a scroll view; a blind tap at
    /// the centre of an element that is not hittable could land on a key of the keyboard or on the rest dock.
    /// An element that vanished since it was found (a dialog closing, a dock sliding away) would make XCTest end the
    /// test, so it is checked first. Returns false (and records a failure when `failIfGone`) in that case.
    ///
    /// `coordinateFallback`: for a control that is on the screen and not covered by anything but for which XCTest still finds no
    /// point to tap (`isHittable` is false because the control's own text or icon, a child with the same frame, covers all of it,
    /// as with a toolbar button on iOS 18), tap the middle of its frame by coordinate instead of handing it to XCTest, whose
    /// failure ends the whole test. The touch is a real one that the app hit-tests itself: a control that really is covered does
    /// not react, and the step fails on what it expected next. Only for a control whose middle is on the screen. It is not for
    /// controls inside a scroll view that may be scrolled under something else (XCTest has to scroll to those). Such a tap is
    /// written under the step in the log.
    @discardableResult
    func press(_ element: XCUIElement, failIfGone: Bool = true, coordinateFallback: Bool = false) -> Bool {
        guard element.exists else {
            if failIfGone {
                fail("The element to tap vanished between finding it and tapping it")
            }
            return false
        }
        if coordinateFallback && !element.isHittable {
            // A button that is still sliding or fading in has no hit point yet: give it a moment before tapping blind.
            pause(0.4)
            guard element.exists else {
                if failIfGone {
                    fail("The element to tap vanished while it was waited for to become hittable")
                }
                return false
            }
            let frame = element.frame
            if !element.isHittable && frame.width > 0 && frame.height > 0 && app.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                let name = element.identifier.isEmpty ? element.label : element.identifier
                note("XCTest found no point to tap on '" + name + "' (frame " + String(describing: frame) + "): tapped its middle by coordinate")
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                return true
            }
        }
        element.tap()
        return true
    }

    /// True when the target exists and can be hit right now.
    func isReachable(_ target: Target) -> Bool {
        guard let element = find(target) else {
            return false
        }
        return element.exists && element.isHittable
    }

    /// Taps a sheet's close button (Done / Cancel) and waits until `goneWhen` disappears.
    func closeSheet(_ name: String, using buttonLabel: String = "Done", goneWhen: Target) {
        if !tap(.button(buttonLabel)) {
            return
        }
        if !waitUntilGone(goneWhen, timeout: 8) {
            fail("The " + name + " sheet is still showing 8 s after tapping '" + buttonLabel + "' (" + goneWhen.summary + " still exists)")
        }
    }

    // MARK: Scrolling and navigating

    func swipeScreenUp(times: Int) {
        for _ in 0..<times {
            app.swipeUp()
            pause(0.5)
        }
    }

    func swipeScreenDown(times: Int) {
        for _ in 0..<times {
            app.swipeDown()
            pause(0.5)
        }
    }

    /// Swipes the screen up one page at a time (at most `maxPages`) and takes a screenshot named
    /// "<prefix><n>" after every page that moved the content. A swipe that changes nothing means the end of the
    /// content was reached; it is not photographed again. Returns the number of swipes made, for swiping back.
    @discardableResult
    func scrollPages(named prefix: String, maxPages: Int) -> Int {
        var swipes = 0
        var shown = 0
        var previous = XCUIScreen.main.screenshot().pngRepresentation
        while swipes < maxPages {
            app.swipeUp()
            swipes += 1
            pause(0.9)
            let current = XCUIScreen.main.screenshot().pngRepresentation
            if current == previous {
                break
            }
            previous = current
            shown += 1
            shot(prefix + String(shown), settle: 0.1)
        }
        return swipes
    }

    /// Goes back one level of a navigation stack: the leading button of the topmost navigation bar,
    /// or the edge-swipe gesture when there is none.
    func navigateBack() {
        let bars = app.navigationBars
        let count = bars.count
        if count > 0 {
            let back = bars.element(boundBy: count - 1).buttons.element(boundBy: 0)
            if back.exists && back.isHittable {
                back.tap()
                pause(0.8)
                return
            }
        }
        edgeSwipeBack()
    }

    /// The interactive-pop gesture: a drag from the left edge to 80 % of the width.
    func edgeSwipeBack() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        pause(0.8)
    }

    // MARK: Text entry

    /// The first-use keyboard onboarding ("Speed up your typing ...") covers the keyboard until "Continue" is tapped.
    func dismissKeyboardTutorial() {
        let continueButton = app.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 1.0) {
            continueButton.tap()
        }
    }

    /// Focuses the field (a tap near its right end puts the caret behind the text) and types.
    /// With `replacing` the existing text is deleted first.
    func enterText(into field: XCUIElement, text: String, replacing: Bool) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        pause(0.8)
        dismissKeyboardTutorial()
        if replacing {
            let current = (field.value as? String) ?? ""
            let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 3)
            field.typeText(deletes)
        }
        field.typeText(text)
    }

    /// Hides the software keyboard with its return key, if it is showing.
    func dismissKeyboard() {
        if app.keyboards.count == 0 {
            return
        }
        for name in ["Search", "search", "Done", "done", "Return", "return"] {
            let key = app.keyboards.buttons[name]
            if key.exists {
                key.tap()
                pause(0.5)
                return
            }
        }
    }

    // MARK: Recovery

    /// The harmless buttons that close a dialog, an alert or a sheet (never "Discard" or "Finish Workout").
    static let overlayButtons = ["Cancel", "Back to Workout", "Keep Training", "Done"]

    /// True when a dialog, alert, sheet or the keyboard is showing.
    func overlayShowing() -> Bool {
        for label in UIDriver.overlayButtons {
            if exists(.button(label)) {
                return true
            }
        }
        return app.keyboards.count > 0
    }

    /// Closes whatever dialog, alert or sheet a failed step left open, using only harmless buttons.
    func recoverOverlays() {
        for _ in 0..<4 {
            dismissKeyboard()
            var handled = false
            for label in UIDriver.overlayButtons {
                if let button = find(.button(label)) {
                    press(button, failIfGone: false)
                    pause(0.8)
                    handled = true
                    break
                }
            }
            if !handled {
                return
            }
        }
    }
}
