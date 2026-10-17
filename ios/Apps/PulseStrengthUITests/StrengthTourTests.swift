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
            tourShot(11, "summary-top", settle: 6.5)   // the celebration has settled after about six seconds
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

// MARK: - Onboarding tour

/// Walks the first-run flow once, the way a new user would: the welcome screen and its highlights, the account sheet (its checks, both
/// tabs), "Continue with Apple" (the UI-test services accept it at once), profile, Apple Health (with a Back and forth), AI Coaching,
/// notifications, the last screen, and the hub behind it.
///
/// The app is launched with '-PulseUITest -PulseShowOnboarding' (see OnboardingLaunchMode): the other UI tests start at the hub, this
/// one asks for the flow. No system dialog appears (no live services) and no text is typed (it needs the software keyboard; the
/// checks of the form are in the unit tests of the model). Files: onboarding-<config>-NN-<name>.png and onboarding-<config>-flow-log.txt
/// in the directory of SCREENSHOT_DIR, like the tour. Run by `visual` (all UI tests) and by `matrix` (dark, large text, iPhone SE, iOS 17).
final class OnboardingTourTests: XCTestCase {

    @MainActor
    func testOnboardingTour() {
        continueAfterFailure = true
        let config = tourConfigName()
        let output = FlowOutput(suite: "onboarding-" + config, testCase: self)
        let tour = OnboardingTour(app: XCUIApplication(), output: output)
        tour.run(config: config)
    }
}

@MainActor
final class OnboardingTour: UIDriver {

    /// The name of the configuration ('default', 'dark', 'xxl', 'se', 'ios17').
    private var config = "default"

    /// The 'xxl' configuration sets accessibility text sizes: the welcome screen, the sheet and the setup steps scroll there, and
    /// things that sit side by side at the default size sit one below the other.
    private var isLargeText: Bool {
        config == "xxl"
    }

    func run(config: String) {
        self.config = config
        launchArguments = ["-PulseUITest", "-PulseShowOnboarding", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        output.log("Onboarding tour '" + config + "', iOS " + ProcessInfo.processInfo.operatingSystemVersionString)
        output.log("TOUR_CONFIG=" + (ProcessInfo.processInfo.environment["TOUR_CONFIG"] ?? "(not set)"))
        relaunch()

        welcomeStep()
        highlightsStep()
        motionStep()
        accountSheetStep()
        checksStep()
        logInTabStep()
        appleStep()
        profileStep()
        healthStep()
        backStep()
        coachStep()
        notifyStep()
        doneStep()
        hubStep()

        output.log(
            "SUMMARY: " + String(okSteps) + " steps OK, " + String(failedSteps) + " FAILED, " + String(skippedSteps)
                + " skipped, " + String(output.screenshotCount) + " screenshots, " + String(failureCount) + " recorded failures"
        )
        output.attachLog()
    }

    // MARK: Welcome

    private func welcomeStep() {
        step("Welcome screen", checkApp: false) {
            if waitFor(.button("onboarding.start"), timeout: 40) == nil {
                fail("The welcome screen did not appear within 40 s: no 'onboarding.start' button")
                shot("welcome-missing")
                return
            }
            for identifier in ["onboarding.login", "onboarding.highlight.1", "onboarding.highlight.2", "onboarding.highlight.3", "onboarding.motion"] {
                if !exists(.button(identifier)) {
                    fail("Missing on the welcome screen: the button '" + identifier + "'")
                }
            }
            checkPreviewCards()
            shot("welcome", settle: 2.5)
        }
    }

    /// Phones shorter than 760 pt (the iPhone SE) drop the preview cards of the welcome screen and the subtitles of the goals, and so does
    /// a screen with accessibility text sizes (the cards). The cards are left out of the view tree then, so they are not found.
    private var expectsCompactLayout: Bool {
        app.frame.height < 760
    }

    private func checkPreviewCards() {
        let hasCards = exists(.text("Today · Recommended"))
        if (expectsCompactLayout || isLargeText) && hasCards {
            fail("The welcome screen shows its preview cards although the screen is short or the text is large (" + String(Int(app.frame.height)) + " pt tall)")
        }
        if !expectsCompactLayout && !isLargeText && !hasCards {
            fail("The welcome screen has no preview cards on a tall screen")
        }
    }

    private func highlightsStep() {
        step("The three highlights") {
            let highlights: [(button: String, title: String, name: String)] = [
                ("onboarding.highlight.2", "Every set, on your wrist.", "welcome-2-rest"),
                ("onboarding.highlight.3", "Progress, made visible.", "welcome-3-record"),
                ("onboarding.highlight.1", "Train with intent.", "welcome-1-plan"),
            ]
            for highlight in highlights {
                if !tap(.button(highlight.button)) {
                    continue
                }
                // The titles of all three highlights are in the tree at all times (the ones that are not shown are only hidden from
                // VoiceOver), so what proves that the bar did its job is that it is the selected one.
                if !waitUntilSelected(.button(highlight.button), timeout: 5) {
                    fail("After tapping '" + highlight.button + "' that bar did not become the selected one")
                }
                if !exists(.text(highlight.title)) {
                    fail("The title '" + highlight.title + "' of the highlight is missing")
                }
                shot(highlight.name, settle: 1.4)
            }
        }
    }

    private func motionStep() {
        step("Pause and play the background video") {
            if !tap(.button("onboarding.motion")) {
                return
            }
            if waitFor(.button("Play background video"), timeout: 3) == nil {
                fail("After tapping the pause button its label did not become 'Play background video'")
            }
            tap(.button("onboarding.motion"), required: false)
            if waitFor(.button("Pause background video"), timeout: 3) == nil {
                fail("After tapping the play button its label did not become 'Pause background video'")
            }
        }
    }

    // MARK: Account sheet

    private func accountSheetStep() {
        step("Account sheet opens on the sign-up tab") {
            // At accessibility text sizes the welcome screen scrolls and the button is below the fold.
            if !tap(.button("onboarding.start"), scrollUp: true) {
                return
            }
            if waitFor(.button("onboarding.submit"), timeout: 10) == nil {
                fail("The account sheet did not open: no 'onboarding.submit' button within 10 s")
                shot("signup-missing")
                return
            }
            pause(1.2)
            checkSheetHeight()
            if !exists(.text("Create your account")) {
                fail("The sheet does not show the sign-up title 'Create your account'")
            }
            for identifier in ["onboarding.apple", "onboarding.close", "onboarding.tab.signup", "onboarding.tab.login"] {
                if !exists(.button(identifier)) {
                    fail("Missing in the account sheet: the button '" + identifier + "'")
                }
            }
            shot("signup-sheet", settle: 1.2)
        }
    }

    /// The sheet opens as tall as its form: the button that sends it is on the screen without scrolling or pulling the sheet up.
    /// (At accessibility text sizes the form is taller than any sheet; there it is only written to the log.)
    private func checkSheetHeight() {
        guard let submit = find(.button("onboarding.submit")) else {
            return
        }
        let frame = submit.frame
        let screenHeight = app.frame.height
        note("sheet: the send button is at y " + String(Int(frame.minY)) + " to " + String(Int(frame.maxY)) + " of " + String(Int(screenHeight)))
        // The sheet follows the measured height of its form. A sheet that never got it is as tall as its minimum, which is enough at the
        // default text size, so the position of the button cannot tell: the probe (an invisible element in a UI-test launch) can.
        if let probe = find(.element("onboarding.sheet.measured")) {
            note("sheet: the measured height of the form is " + probe.label + " pt")
            if (Int(probe.label) ?? 0) <= 0 {
                fail("The account sheet never received the measured height of its form (the probe reads '" + probe.label + "')")
            }
        } else {
            note("sheet: no measurement probe in the tree")
        }
        if !isLargeText && frame.maxY > screenHeight - 4 {
            fail("The account sheet opens too short: its send button ends at y " + String(Int(frame.maxY)) + " of " + String(Int(screenHeight)) + ", below the visible part")
        }
    }

    private func checkKeyboardDoesNotHideTheEmailField() {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else {
            note("no software keyboard appeared (a hardware keyboard is connected?): the check of the field is skipped")
            return
        }
        pause(0.8)
        shot("signup-keyboard", settle: 0.3)
        guard let email = find(.field("onboarding.email")) else {
            fail("The email field is not in the tree while the keyboard is up")
            return
        }
        let fieldBottom = email.frame.maxY
        let keyboardTop = keyboard.frame.minY
        note("keyboard: the email field ends at y " + String(Int(fieldBottom)) + ", the keyboard starts at y " + String(Int(keyboardTop)))
        if fieldBottom > keyboardTop {
            fail("The keyboard hides the email field (the field ends at y " + String(Int(fieldBottom)) + ", the keyboard starts at y " + String(Int(keyboardTop)) + ")")
        }
    }

    private func checksStep() {
        step("Sending an empty form shows the errors") {
            if !tap(.button("onboarding.submit")) {
                return
            }
            if waitFor(.text("Enter a valid email address."), timeout: 5) == nil {
                fail("No email error appeared after sending an empty form")
            }
            if !exists(.text("Use at least 8 characters.")) {
                fail("The password rule is not shown")
            }
            // The error moved the focus to the email field, which opens the keyboard: the field must stay above it.
            checkKeyboardDoesNotHideTheEmailField()
            // Then close the keyboard (its Done button), so that it does not cover what the next steps tap.
            // On iOS 18 XCTest finds no point to tap on this toolbar button (its text is a child with the same frame).
            tap(.button("onboarding.keyboardDone"), timeout: 3, required: false, coordinateFallback: true)
            pause(0.6)
            shot("signup-errors", settle: 0.6)
        }
    }

    private func logInTabStep() {
        step("Log-in tab, and back") {
            if !tap(.button("onboarding.tab.login")) {
                return
            }
            if waitFor(.text("Welcome back"), timeout: 5) == nil {
                fail("The log-in tab does not show 'Welcome back'")
            }
            if !exists(.button("onboarding.forgot")) {
                fail("The log-in tab has no 'Forgot password?' button")
            }
            if exists(.text("Enter a valid email address.")) {
                fail("The email error of the sign-up tab is still showing after switching to the log-in tab")
            }
            shot("login-tab", settle: 1.0)
            tap(.button("onboarding.tab.signup"), required: false)
            if waitFor(.text("Create your account"), timeout: 5) == nil {
                fail("Switching back to the sign-up tab did not show 'Create your account'")
            }
        }
    }

    // MARK: Setup

    private func appleStep() {
        step("Continue with Apple leads to the profile") {
            if !tap(.button("onboarding.apple")) {
                return
            }
            if waitFor(.text("What are you training for?"), timeout: 15) == nil {
                fail("The profile step did not appear within 15 s of tapping 'Continue with Apple'")
                shot("profile-missing")
                return
            }
            if let next = waitFor(.button("onboarding.profile.continue"), timeout: 5), next.isEnabled {
                fail("'Continue' is enabled although no goal and no experience level were chosen")
            }
            shot("profile-empty", settle: 1.2)
        }
    }

    private func profileStep() {
        step("Profile: main goal and experience") {
            let hasSubtitles = exists(.text("Plan, log and progress your lifts"))
            if expectsCompactLayout && hasSubtitles {
                fail("The goals show their subtitles on a short screen (" + String(Int(app.frame.height)) + " pt tall): the compact layout is not on")
            }
            if !expectsCompactLayout && !hasSubtitles {
                fail("The goals have no subtitles on a tall screen")
            }
            tap(.button("onboarding.goal.strength"))
            tap(.button("onboarding.level.intermediate"))
            pause(0.5)
            if let next = find(.button("onboarding.profile.continue")), !next.isEnabled {
                fail("'Continue' is still disabled after choosing a goal and an experience level")
            }
            shot("profile-chosen", settle: 0.8)
            tap(.button("onboarding.profile.continue"))
        }
    }

    private func healthStep() {
        step("Apple Health step") {
            if waitFor(.button("onboarding.health.connect"), timeout: 10) == nil {
                fail("The Apple Health step did not appear within 10 s")
                shot("health-missing")
                return
            }
            if !exists(.button("onboarding.health.later")) {
                fail("The Apple Health step has no 'Not now' button")
            }
            shot("health", settle: 1.2)
        }
    }

    private func backStep() {
        step("Back keeps the answers") {
            // XCTest finds no point to tap on this button (its icon is a child with the same frame): tap it by coordinate.
            if !tap(.button("onboarding.back"), coordinateFallback: true) {
                return
            }
            if waitFor(.text("What are you training for?"), timeout: 8) == nil {
                fail("Back did not return to the profile step")
                return
            }
            if waitFor(.element("Setup progress, step 1 of 4"), timeout: 5) == nil {
                fail("After Back the setup progress does not say 'step 1 of 4'")
            }
            if let next = waitFor(.button("onboarding.profile.continue"), timeout: 5), !next.isEnabled {
                fail("The goal and the experience level were forgotten after Back")
            }
            tap(.button("onboarding.profile.continue"), required: false)
            if waitFor(.button("onboarding.health.connect"), timeout: 8) == nil {
                fail("Continue after Back did not lead to the Apple Health step again")
                return
            }
            tap(.button("onboarding.health.connect"))
        }
    }

    private func coachStep() {
        step("AI Coaching: both answers are equally easy") {
            guard let accept = waitFor(.button("onboarding.coach.on"), timeout: 10) else {
                fail("The AI Coaching step did not appear within 10 s")
                shot("coach-missing")
                return
            }
            guard let decline = find(.button("onboarding.coach.off")) else {
                fail("The AI Coaching step has no 'No thanks' button")
                return
            }
            let acceptFrame = accept.frame
            let declineFrame = decline.frame
            // The widths are always equal. The heights are too, except at accessibility text sizes, where a longer label wraps.
            let widthsDiffer = abs(acceptFrame.width - declineFrame.width) > 1
            let heightsDiffer = !isLargeText && abs(acceptFrame.height - declineFrame.height) > 1
            if widthsDiffer || heightsDiffer {
                fail("'Turn on AI Coaching' and 'No thanks' differ in size: " + String(describing: acceptFrame.size) + " and " + String(describing: declineFrame.size))
            }
            shot("coach", settle: 1.2)
            tap(.button("onboarding.coach.off"))
        }
    }

    private func notifyStep() {
        step("Notifications step") {
            if waitFor(.button("onboarding.notify.later"), timeout: 10) == nil {
                fail("The notifications step did not appear within 10 s")
                shot("notify-missing")
                return
            }
            shot("notify", settle: 1.6)
            tap(.button("onboarding.notify.later"))
        }
    }

    private func doneStep() {
        step("Last screen sums up the answers") {
            if waitFor(.button("onboarding.finish"), timeout: 10) == nil {
                fail("The last screen did not appear within 10 s")
                shot("done-missing")
                return
            }
            // The answers of this walk. (The goal and the level are left out: the hidden profile screen has buttons with the same
            // labels, so they would be found whatever the last screen shows.)
            for chip in ["Apple Health connected", "AI Coaching off", "Notifications: later"] {
                if !exists(.element(chip)) {
                    fail("The summary has no '" + chip + "' chip")
                }
            }
            shot("done", settle: 2.0)
            tap(.button("onboarding.finish"), scrollUp: true)
        }
    }

    /// Waits until the target is selected (the 'Selected' accessibility trait: the bar of the highlight on screen).
    private func waitUntilSelected(_ target: Target, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let element = find(target), element.isSelected {
                return true
            }
            if Date() >= deadline {
                return false
            }
            pause(0.3)
        }
    }

    private func hubStep() {
        step("The hub is behind the onboarding") {
            if waitFor(.button("Start Workout"), timeout: 20) == nil {
                fail("The hub did not appear within 20 s of 'Start training'")
                shot("hub-missing")
                return
            }
            if !waitUntilGone(.button("onboarding.finish"), timeout: 8) {
                fail("The onboarding is still on screen 8 s after 'Start training'")
            }
            shot("hub", settle: 1.0)
        }
    }
}
