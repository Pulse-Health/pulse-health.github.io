// StrengthTourTests.swift
//
// A SHORT second screenshot tour of Pulse Strength (about 21 screenshots, about 4 minutes), made to be run several times
// under different conditions by the `matrix` job of the strength-ios workflow, to look at what the long flow
// (StrengthFlowTests, 55 screenshots, light mode, default phone) never looked at:
//
//   dark      the dark values of PulseTheme            (simctl ui appearance dark)
//   xxl       accessibility Dynamic Type sizes          (simctl ui content_size accessibility-extra-large)
//   se        iPhone SE (3rd generation), 375 x 667 pt  (the active screen must fit without page scrolling)
//   ios17     the oldest iOS 17+ runtime of the runner  (runtime differences)
//
// The test knows nothing about the condition: the workflow sets it on the simulator before xcodebuild starts and names it
// in TOUR_CONFIG (forwarded as TEST_RUNNER_TOUR_CONFIG; 'default' when unset). The name only goes into the file names:
//
//   tour-<config>-<NN>-<name>.png     21 screenshots, in the directory of SCREENSHOT_DIR, attached to the test result as well
//   tour-<config>-flow-log.txt        the step log (OK / FAILED / SKIPPED per step), like ui-flow-log.txt
//   tour-<config>-layout.txt          frames of header, navigator, card and rest dock of the active screen, 'pageScrolls',
//                                     'LAYOUT VIOLATION' lines (TourLayout.swift)
//
// The numbers NN are fixed per screenshot (01 hub-top ... 14 exercise-detail-top, 15-21 the seven walkthrough pages), so the
// same number can be compared between the runs. A screenshot of a failure ('...-missing') gets a number from 91 on and
// does not move the others.
//
// Same rules as the flow: the app is launched with '-PulseUITest' (fresh demo store, no live services), continueAfterFailure
// is true, every step runs through UIDriver.step and a failed step closes stray overlays; a step that needs the active
// workout screen brings it back (reopen from the hub, else start a new workout) or skips itself. The helpers of
// FlowSupport.swift are used as they are; StrengthFlowTests.swift is not touched.
//
// What is left out on purpose: text entry (it needs the software keyboard), supersets, undo, pause, rest-over, empty workout,
// the long scrolls: the flow covers those. The workout is finished with sets still unlogged, which shows the finish dialog with
// its message about unlogged sets; there is no 'Update template?' alert because the exercise list is not changed.

import XCTest

/// The value of TOUR_CONFIG as a file-name part: lower case letters, digits and '-', at most 24 characters; 'default' if empty.
func tourConfigName() -> String {
    let raw = ProcessInfo.processInfo.environment["TOUR_CONFIG"] ?? ""
    let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
    var characters: [Character] = []
    for character in raw.lowercased() {
        characters.append(allowed.contains(character) ? character : "-")
    }
    var name = String(characters)
    while name.hasPrefix("-") {
        name.removeFirst()
    }
    while name.hasSuffix("-") {
        name.removeLast()
    }
    if name.isEmpty {
        return "default"
    }
    return String(name.prefix(24))
}

final class StrengthTourTests: XCTestCase {

    /// The whole tour in one test, so that one app launch carries the state from the hub through a finished workout.
    @MainActor
    func testStrengthTour() {
        continueAfterFailure = true
        let config = tourConfigName()
        let output = FlowOutput(suite: "tour-" + config, testCase: self)
        let tour = StrengthTour(app: XCUIApplication(), output: output)
        tour.run(config: config, testCase: self)
    }
}

// MARK: - The tour

private enum TourZone {
    /// The set-type badge button: 10 pt inset + half of 36 pt.
    case badge
    /// The weight cell: 44 (check) + 6 + 60 (reps) + 6 + half of 68 from the trailing edge.
    case weight
    /// The check circle: half of 44 from the trailing edge.
    case check
}

private enum TourRowFilter {
    case pending
    case all
}

@MainActor
final class StrengthTour: UIDriver {
    private var config = "default"
    private var testCase: XCTestCase?
    private var layout: TourLayout?

    /// True while the active-workout screen is believed to be showing (see requireActive).
    private var activeWorkoutVisible = false
    /// How often a new workout had to be started because the active screen was lost (at most 2 per run).
    private var rebuilds = 0
    private var tourShots = 0
    private var failureShots = 0

    override func appDidRestart() {
        activeWorkoutVisible = false
    }

    func run(config: String, testCase: XCTestCase) {
        self.config = config
        self.testCase = testCase
        launchArguments = ["-PulseUITest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        let systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
        output.log("Pulse Strength tour '" + config + "', iOS " + systemVersion)
        output.log("TOUR_CONFIG=" + (ProcessInfo.processInfo.environment["TOUR_CONFIG"] ?? "(not set)"))
        let report = TourLayout(driver: self, output: output, testCase: testCase, config: config)
        layout = report

        hubSteps()
        startStep()
        restDockStep()
        keypadStep()
        setDetailStep()
        exerciseListStep()
        pickerStep()
        formInfoStep()
        finishDialogStep()
        summaryStep()
        hubAfterFinishStep()
        libraryStep()
        // Last on purpose: a failure here can never cost the screenshots and the layout report of the steps above.
        walkthroughStep()

        report.finish()
        output.log(
            tourText(
                "SUMMARY: ", String(okSteps), " steps OK, ", String(failedSteps), " FAILED, ", String(skippedSteps),
                " skipped, ", String(tourShots), " screenshots, ", String(failureCount), " recorded failures, ",
                String(report.violations.count), " layout violations"
            )
        )
        output.attachLog()
    }

    // MARK: Screenshots

    /// Waits for the animations, then takes the screenshot 'tour-<config>-<NN>-<name>.png' with a fixed number.
    private func tourShot(_ number: Int, _ name: String, settle: TimeInterval = 0.7) {
        pause(settle)
        writeShot(fileNumber: number, name: name)
    }

    /// A screenshot of a failure: numbered from 91, so the numbers of the regular screenshots stay put.
    private func failShot(_ name: String) {
        failureShots += 1
        writeShot(fileNumber: 90 + failureShots, name: name)
    }

    private func writeShot(fileNumber: Int, name: String) {
        let fileName = output.suite + "-" + twoDigits(fileNumber) + "-" + name + ".png"
        let shot = XCUIScreen.main.screenshot()
        let url = output.directory.appendingPathComponent(fileName)
        do {
            try shot.pngRepresentation.write(to: url, options: .atomic)
        } catch {
            fail("Could not write screenshot " + fileName + " to " + output.directory.path + ": " + String(describing: error))
        }
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        testCase?.add(attachment)
        tourShots += 1
        note("screenshot " + fileName)
    }

    // MARK: Recovery (as in the flow: every step gets its precondition back or skips itself)

    /// Makes sure the active-workout screen is showing before a step that needs it; false (the step then skips itself)
    /// only when it could not be brought back: stray overlays are closed, else it is reopened from the hub, else a new
    /// workout is started.
    private func requireActive(_ what: String, keepOverlays: Bool = false) -> Bool {
        if activeWorkoutVisible {
            if !keepOverlays && overlayShowing() {
                note("closing a dialog or sheet that was still open before '" + what + "'")
                recoverOverlays()
            }
            if exists(.button("Minimise workout")) {
                return true
            }
            note("the active workout screen is not showing before '" + what + "'; trying to bring it back")
            activeWorkoutVisible = false
        }
        if reopenActiveWorkout() {
            return true
        }
        if rebuildActiveWorkout() {
            return true
        }
        skip(what + ": the active workout screen is not available (an earlier step failed and it could not be restored)")
        return false
    }

    /// Opens the running workout again from the hub: the in-progress bar, else the hub's "Resume Workout" button.
    private func reopenActiveWorkout() -> Bool {
        let openers: [Target] = [.button("Resume workout in progress"), .button("Resume Workout")]
        for opener in openers where isReachable(opener) {
            tap(opener, timeout: 3, required: false)
            if waitFor(.button("Minimise workout"), timeout: 8) != nil {
                activeWorkoutVisible = true
                note("brought the active workout screen back with '" + opener.label + "'")
                return true
            }
        }
        return false
    }

    /// Last resort: launches the app again (the UI-test mode starts from a fresh store, so the earlier workout is gone) and
    /// starts the template. At most twice per run.
    private func rebuildActiveWorkout() -> Bool {
        if rebuilds >= 2 {
            return false
        }
        rebuilds += 1
        note("rebuilding: launching the app again and starting a new workout, because an earlier step lost the active workout screen")
        relaunch()
        if waitFor(.button("Start Workout"), timeout: 40) == nil {
            fail("The hub did not appear after launching the app again to rebuild the workout")
            return false
        }
        if !tap(.button("Start Workout")) {
            return false
        }
        if waitFor(.button("Minimise workout"), timeout: 20) == nil {
            fail("The rebuilt workout did not open: no 'Minimise workout' button within 20 s")
            return false
        }
        activeWorkoutVisible = true
        return true
    }

    /// True when no workout screen, summary or sheet covers the hub and its "Start Workout" button exists.
    private func hubInFront() -> Bool {
        if exists(.button("Minimise workout")) || exists(.element("Workout Complete")) {
            return false
        }
        return exists(.button("Start Workout"))
    }

    /// Brings the hub to the front before a step that starts from it: leaves the summary with Done, closes stray overlays,
    /// minimises a workout screen, and as the last resort launches the app again.
    private func ensureHub(_ what: String) {
        if hubInFront() {
            return
        }
        note("the hub is not in front before '" + what + "'; closing what covers it")
        if exists(.element("Workout Complete")) {
            tap(.button("Done"), timeout: 3, required: false)
            _ = waitUntilGone(.element("Workout Complete"), timeout: 10)
        }
        if overlayShowing() {
            recoverOverlays()
        }
        if hubInFront() {
            return
        }
        if exists(.button("Minimise workout")) {
            tap(.button("Minimise workout"), timeout: 3, required: false)
            pause(1.0)
        }
        if hubInFront() {
            return
        }
        note("launching the app again to get back to the hub")
        relaunch()
        if waitFor(.button("Start Workout"), timeout: 40) == nil {
            fail("The hub did not appear after launching the app again: no 'Start Workout' button within 40 s")
        }
    }

    // MARK: 01-02: hub

    private func hubSteps() {
        step("Launch the app in UI-test mode and wait for the hub", checkApp: false) {
            relaunch()
            if waitFor(.button("Start Workout"), timeout: 40) == nil {
                fail("The hub did not appear: no 'Start Workout' button within 40 s of the launch")
            }
            if let report = layout {
                report.readScreen()
                note("window " + report.screenText)
            }
            tourShot(1, "hub-top", settle: 1.0)
        }

        step("Scroll the hub one page") {
            swipeScreenUp(times: 1)
            tourShot(2, "hub-scrolled", settle: 0.6)
            swipeScreenDown(times: 1)
        }
    }

    // MARK: 15-21: the walkthrough

    /// Opens the walkthrough from the hub's More menu (the UI-test mode never opens it by itself), photographs each of its
    /// seven pages (the pictures and the tips must fit every configuration of the matrix) and closes it with "Get Started".
    ///
    /// Runs last, from a freshly launched app (the UI-test mode starts from the hub), and taps by coordinate (see `tapMiddle`):
    /// the first version tapped the toolbar's More button with `XCUIElement.tap()`, which made XCTest end the whole tour.
    private func walkthroughStep() {
        step("Walkthrough: open it from the More menu, page through it, then Get Started", checkApp: false) {
            relaunch()
            if waitFor(.button("Start Workout"), timeout: 40) == nil {
                fail("The hub did not appear after launching the app again for the walkthrough: no 'Start Workout' button within 40 s")
                return
            }
            if !tapMiddle(of: [.button("hub-more"), .button("More")]) {
                failShot("walkthrough-more-missing")
                return
            }
            let item: [Target] = [.button("App Walkthrough", .contains), .element("App Walkthrough", .contains)]
            if !tapMiddle(of: item, timeout: 8) {
                failShot("walkthrough-menu-missing")
                recoverMenu()
                return
            }
            guard waitFor(.button("Next"), timeout: 10) != nil else {
                fail("The walkthrough did not open: no 'Next' button within 10 s")
                failShot("walkthrough-missing")
                return
            }
            let pages = ["welcome", "today", "log", "rest", "shape", "finish", "more"]
            var page = 0
            while page < pages.count {
                tourShot(15 + page, "walkthrough-" + pages[page], settle: 0.9)
                if page == pages.count - 1 {
                    break
                }
                if !tapMiddle(of: [.button("Next")]) {
                    closeWalkthrough()
                    return
                }
                page += 1
            }
            guard waitFor(.button("Get Started"), timeout: 5) != nil else {
                fail("The last page of the walkthrough shows no 'Get Started' button")
                closeWalkthrough()
                return
            }
            if !tapMiddle(of: [.button("Get Started")]) {
                return
            }
            if !waitUntilGone(.button("Get Started"), timeout: 8) {
                fail("The walkthrough is still showing 8 s after tapping 'Get Started'")
                closeWalkthrough()
            }
        }
    }

    /// Taps the middle of the first of the targets that exists, by coordinate.
    ///
    /// `XCUIElement.tap()` first asks the accessibility layer to scroll the element into view. For the toolbar's More button
    /// that fails ("Failed to scroll to visible (by AX action) ... kAXErrorCannotComplete") and XCTest then ends the whole test,
    /// whatever continueAfterFailure says. A tap at a coordinate never scrolls. The element must exist and have a frame whose
    /// middle is on screen; otherwise an ordinary failure is recorded and the walk goes on.
    @discardableResult
    private func tapMiddle(of targets: [Target], timeout: TimeInterval = 10) -> Bool {
        guard let index = waitForAny(targets, timeout: timeout), let element = find(targets[index]) else {
            fail("Not found within " + String(Int(timeout)) + " s: " + targets.map { $0.summary }.joined(separator: " or "))
            return false
        }
        guard element.exists else {
            fail("The element to tap vanished between finding it and tapping it: " + targets[index].summary)
            return false
        }
        let frame = element.frame
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        guard frame.width > 1 && frame.height > 1 && app.frame.contains(middle) else {
            fail("The element to tap has frame " + String(describing: frame) + ", whose middle is not on screen: " + targets[index].summary)
            return false
        }
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        return true
    }

    /// Leaves the walkthrough with "Skip" (or "Get Started" on its last page) after a failure.
    private func closeWalkthrough() {
        if exists(.button("Skip")) {
            tapMiddle(of: [.button("Skip")], timeout: 2)
        } else if exists(.button("Get Started")) {
            tapMiddle(of: [.button("Get Started")], timeout: 2)
        }
        pause(0.8)
    }

    /// Closes the More menu when it is still open: a tap on the inert part of the navigation bar (left of the More button)
    /// dismisses a menu and does nothing otherwise.
    private func recoverMenu() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.07)).tap()
        pause(0.6)
    }

    // MARK: 03: start the template

    private func startStep() {
        step("Start the 'Upper A · Push' template") {
            if !isReachable(.button("Start Workout")) {
                // Still scrolled down from the previous step.
                swipeScreenDown(times: 4)
            }
            if tap(.button("Start Workout")) {
                if waitFor(.button("Minimise workout"), timeout: 20) != nil {
                    activeWorkoutVisible = true
                } else {
                    fail("The active workout screen did not appear: no 'Minimise workout' button within 20 s")
                }
            }
            tourShot(3, "active-initial", settle: 1.2)
            if activeWorkoutVisible, let report = layout {
                report.measureActive(state: "active workout, no rest dock", scanButtons: false)
                note(report.lastSummary)
            }
        }
    }

    // MARK: 04: rest dock

    private func restDockStep() {
        step("Log sets until the rest dock is at its tallest, then measure the layout") {
            guard requireActive("log the first set") else { return }
            if !logNextPendingSet() {
                return
            }
            if waitFor(.button("Skip"), timeout: 10) == nil {
                fail("The rest dock did not appear after logging a set: no 'Skip' button within 10 s")
            }
            // The two warm-up sets of the first exercise show no 'Reps left' row; the third set (a working set) does, which
            // is the tallest form of the dock and the worst case for a small screen.
            var logged = 1
            while logged < 3 && !exists(.element("Reps in reserve")) {
                note("no 'Reps in reserve' row in the dock yet; logging one more set (" + String(logged + 1) + ") to show it")
                pause(0.5)
                if !logNextPendingSet() {
                    break
                }
                logged += 1
            }
            pause(0.8)
            tourShot(4, "rest-dock", settle: 0.6)
            if let report = layout {
                report.measureActive(state: "active workout, rest dock showing, " + String(logged) + " sets logged", scanButtons: true)
                note(report.lastSummary)
                report.measurePageScroll(state: "active workout, rest dock showing")
                note(report.lastSummary)
            }
            // The dock takes space from the set table; skipping the rest gives the next steps the full table back.
            closeRestDock()
        }
    }

    // MARK: 05-06: keypad and set detail

    private func keypadStep() {
        step("Keypad on the weight of a set") {
            guard requireActive("open the keypad") else { return }
            guard let row = tappableRow(.pending) ?? tappableRow(.all) else {
                fail("No set row found (no element labelled 'Set N, ..., logged')")
                return
            }
            note("tapping the weight cell of: " + row.label)
            if !tapZone(.weight, of: row) {
                return
            }
            // The primary button of the keypad: 'Next: Reps' on the weight field, 'Log Set' on the reps field of a pending set.
            let markers: [Target] = [.button("Next: Reps"), .button("Log Set")]
            guard let which = waitForAny(markers, timeout: 10) else {
                fail("The keypad did not open: no 'Next: Reps' or 'Log Set' button within 10 s")
                failShot("keypad-missing")
                return
            }
            tap(.button("6"))
            tap(.button("5"))
            tourShot(5, "keypad-weight", settle: 0.9)
            closeSheet("keypad", goneWhen: markers[which])
        }
    }

    private func setDetailStep() {
        step("Set-detail sheet (tap the set-type badge)") {
            guard requireActive("open the set-detail sheet") else { return }
            guard let row = tappableRow(.pending) ?? tappableRow(.all) else {
                fail("No set row found (no element labelled 'Set N, ..., logged')")
                return
            }
            if !tapZone(.badge, of: row) {
                return
            }
            guard waitFor(.button("Delete Set", .contains), timeout: 10) != nil else {
                fail("The set-detail sheet did not open: no 'Delete Set' button within 10 s")
                failShot("set-detail-missing")
                return
            }
            tourShot(6, "set-detail", settle: 0.8)
            closeSheet("set-detail", goneWhen: .button("Delete Set", .contains))
        }
    }

    // MARK: 07-08: exercise list and picker

    private func exerciseListStep() {
        step("Exercise list sheet (Edit)") {
            guard requireActive("open the exercise list") else { return }
            if !tap(.button("Edit", .loose)) {
                return
            }
            guard waitFor(.button("Add Exercise", .loose), timeout: 10) != nil else {
                fail("The exercise list sheet did not open: no 'Add Exercise' button within 10 s")
                failShot("exercise-list-missing")
                return
            }
            tourShot(7, "exercise-list", settle: 0.9)
        }
    }

    private func pickerStep() {
        step("Add-exercise picker (no typing), then close picker and list") {
            // The exercise list sheet is still open from the previous step, on purpose.
            guard requireActive("open the exercise picker", keepOverlays: true) else { return }
            if !exists(.button("Add Exercise", .loose)) && !exists(.field("Search exercises")) {
                note("the exercise list sheet is not open; opening it again")
                tap(.button("Edit", .loose), timeout: 5, required: false)
                _ = waitFor(.button("Add Exercise", .loose), timeout: 8)
            }
            if !exists(.field("Search exercises")) {
                if !tap(.button("Add Exercise", .loose)) {
                    return
                }
            }
            guard waitFor(.field("Search exercises"), timeout: 10) != nil else {
                fail("The picker did not open: no 'Search exercises' text field within 10 s")
                failShot("picker-missing")
                return
            }
            tourShot(8, "picker", settle: 0.9)
            // The picker may have focused its search field: its Cancel button works with the keyboard up as well.
            dismissKeyboard()
            closeSheet("picker", using: "Cancel", goneWhen: .field("Search exercises"))
            if exists(.button("Add Exercise", .loose)) {
                closeSheet("exercise list", goneWhen: .button("Add Exercise", .loose))
            }
        }
    }

    // MARK: 09: form & instructions

    private func formInfoStep() {
        step("Form & instructions sheet (Exercise options)") {
            guard requireActive("open the form sheet") else { return }
            if !tap(.button("Exercise options")) {
                return
            }
            if waitFor(.button("Form & instructions"), timeout: 10) == nil {
                fail("The options dialog did not open: no 'Form & instructions' button within 10 s")
                failShot("options-dialog-missing")
                return
            }
            if !tap(.button("Form & instructions")) {
                return
            }
            guard waitFor(.element("How to"), timeout: 12) != nil else {
                fail("The form sheet did not open: no 'How to' heading within 12 s")
                failShot("form-info-missing")
                return
            }
            tourShot(9, "form-info", settle: 1.2)
            closeSheet("form", goneWhen: .element("How to"))
        }
    }

    // MARK: 10-11: finish dialog and summary

    private func finishDialogStep() {
        step("Finish with unlogged sets: the confirmation dialog") {
            guard requireActive("finish the workout") else { return }
            var opened = false
            for attempt in 1...2 {
                if !tap(.button("Finish")) {
                    return
                }
                if waitFor(.button("Finish Workout"), timeout: attempt == 1 ? 6 : 10) != nil {
                    opened = true
                    break
                }
                if attempt == 1 {
                    note("the finish dialog did not open 6 s after the first tap; closing what is open and trying once more")
                    recoverOverlays()
                }
            }
            guard opened else {
                fail("The finish dialog did not open: no 'Finish Workout' button after tapping 'Finish' twice")
                failShot("finish-dialog-missing")
                return
            }
            tourShot(10, "finish-dialog", settle: 0.9)
        }
    }

    private func summaryStep() {
        step("Finish Workout: the summary screen", recoverOnFailure: false) {
            // The finish dialog is still open from the previous step, on purpose.
            guard requireActive("confirm the finish", keepOverlays: true) else { return }
            if !exists(.button("Finish Workout")) {
                note("the finish dialog is not open; opening it again")
                tap(.button("Finish"), timeout: 5, required: false)
                _ = waitFor(.button("Finish Workout"), timeout: 6)
            }
            if !tap(.button("Finish Workout")) {
                return
            }
            activeWorkoutVisible = false
            let summary = Target.element("Workout Complete")
            let onlyThisWorkout = Target.button("Only This Workout")
            guard let which = waitForAny([summary, onlyThisWorkout], timeout: 20) else {
                fail("After 'Finish Workout' neither the summary ('Workout Complete') nor the 'Update template?' alert appeared within 20 s")
                failShot("finish-no-result")
                if exists(.button("Minimise workout")) {
                    // The workout is still running: the later steps can use it (recoverOverlays closes what is open).
                    activeWorkoutVisible = true
                }
                return
            }
            if which == 1 {
                note("the 'Update template?' alert appeared; choosing 'Only This Workout'")
                tap(onlyThisWorkout)
            }
            guard waitFor(summary, timeout: 20) != nil else {
                fail("The summary did not appear: no 'Workout Complete' title within 20 s")
                failShot("summary-missing")
                return
            }
            tourShot(11, "summary-top", settle: 1.4)
        }
    }

    // MARK: 12: hub after the workout

    private func hubAfterFinishStep() {
        step("Summary: Done, then the hub with the new history entry", recoverOnFailure: false) {
            if exists(.element("Workout Complete")) {
                if !tap(.button("Done")) {
                    return
                }
                // The hub's own elements stay in the accessibility tree behind the summary, so wait for the summary to go.
                if !waitUntilGone(.element("Workout Complete"), timeout: 15) {
                    fail("The summary is still showing 15 s after tapping Done")
                }
            }
            ensureHub("show the hub after the workout")
            tourShot(12, "hub-after-finish", settle: 1.2)
        }
    }

    // MARK: 13-14: exercise library and detail

    private func libraryStep() {
        step("Exercise library, then an exercise detail (top only)", recoverOnFailure: false) {
            ensureHub("open the exercise library")
            // The row sits at the bottom of the hub: scroll until it exists, then until it can be hit.
            let library = Target.button("Exercise Library", .contains)
            var swipes = 0
            while find(library) == nil && swipes < 6 {
                app.swipeUp()
                pause(0.5)
                swipes += 1
            }
            if !tap(library, scrollUp: true) {
                return
            }
            let bench = Target.button("Barbell bench press", .contains)
            guard waitFor(bench, timeout: 10) != nil else {
                fail("The exercise library did not open: no 'Barbell bench press' row within 10 s")
                failShot("exercise-library-missing")
                return
            }
            tourShot(13, "exercise-library", settle: 0.9)
            if !tap(bench) {
                return
            }
            guard waitFor(.element("Est. 1RM", .contains), timeout: 15) != nil else {
                fail("The exercise detail did not open: no 'Est. 1RM' tile within 15 s")
                failShot("exercise-detail-missing")
                return
            }
            tourShot(14, "exercise-detail-top", settle: 1.4)
        }
    }

    // MARK: Set rows

    private func setRows(_ filter: TourRowFilter) -> XCUIElementQuery {
        let format: String
        switch filter {
        case .pending:
            format = "label BEGINSWITH 'Set ' AND label ENDSWITH ', not logged'"
        case .all:
            format = "label BEGINSWITH 'Set ' AND label ENDSWITH 'logged'"
        }
        return app.descendants(matching: .any).matching(NSPredicate(format: format))
    }

    /// The first set row that can be hit (a row scrolled out of a long table on a small screen cannot be tapped at fixed
    /// offsets). When none can be hit within a few seconds, the first row that exists; nil when there is no row at all.
    private func tappableRow(_ filter: TourRowFilter, timeout: TimeInterval = 8) -> XCUIElement? {
        let started = Date()
        let deadline = started.addingTimeInterval(timeout)
        while true {
            let rows = setRows(filter)
            let count = min(rows.count, 12)
            var fallback: XCUIElement?
            var index = 0
            while index < count {
                let row = rows.element(boundBy: index)
                index += 1
                if !row.exists {
                    continue
                }
                if row.isHittable {
                    return row
                }
                if fallback == nil {
                    fallback = row
                }
            }
            let waited = Date().timeIntervalSince(started)
            if fallback != nil && waited > 2.5 {
                return fallback
            }
            if Date() >= deadline {
                return fallback
            }
            pause(0.3)
        }
    }

    /// Taps one control of a set row at its fixed place inside the row (see StrengthFlowTests.swift for the geometry).
    private func tapZone(_ zone: TourZone, of row: XCUIElement) -> Bool {
        guard row.exists else {
            fail("The set row vanished before it was tapped")
            return false
        }
        let frame = row.frame
        guard frame.width > 200 && frame.height > 20 else {
            fail("The set row '" + row.label + "' has an unexpected frame " + String(describing: frame))
            return false
        }
        let x: CGFloat
        switch zone {
        case .badge:
            x = 28
        case .weight:
            x = frame.width - 150
        case .check:
            x = frame.width - 22
        }
        let origin = row.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        origin.withOffset(CGVector(dx: x, dy: frame.height / 2)).tap()
        return true
    }

    @discardableResult
    private func logNextPendingSet() -> Bool {
        guard let row = tappableRow(.pending) else {
            fail("No pending set row found (no element labelled 'Set N, ..., not logged')")
            return false
        }
        note("logging: " + row.label)
        return tapZone(.check, of: row)
    }

    /// Closes the rest dock (Skip, or Dismiss when the rest is over) so the set table keeps its full height.
    private func closeRestDock() {
        if let skipButton = find(.button("Skip")) {
            press(skipButton, failIfGone: false)
            pause(0.5)
            return
        }
        if let dismissButton = find(.button("Dismiss")) {
            press(dismissButton, failIfGone: false)
            pause(0.5)
        }
    }
}
