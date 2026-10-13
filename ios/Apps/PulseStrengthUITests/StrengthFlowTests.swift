// StrengthFlowTests.swift
//
// Walks the real iPhone UI of Pulse Strength like a user and takes a screenshot at every important state, so that
// somebody who cannot run a simulator can look at the app: the files '<NN>-<name>.png' prefixed 'ui-' and the
// step log 'ui-flow-log.txt' go to the directory in SCREENSHOT_DIR (CI sets TEST_RUNNER_SCREENSHOT_DIR) and are
// attached to the test result.
//
// The app is launched with '-PulseUITest': PulseStrengthApp then uses StrengthAppEnvironment.preview(), a fresh
// temporary store with the demo templates and history and no Live Activity / Health / notification / Watch
// side effects, so every run starts from the same hub ("Upper A · Push" is the recommended template).
//
// The test never stops at the first problem. A missing element is recorded with XCTFail and a precise message and
// the walk goes on with the next step (continueAfterFailure = true; steps are closures run by UIDriver.step).
//
// The set rows of the exercise card are ONE accessibility element each (SetRowView hides its children and exposes
// the label "Set 3, working set, 82.5 kilograms, 6 reps, not logged"), so the type badge, the weight cell, the reps
// cell and the check circle cannot be found by label. They are tapped at fixed offsets inside the row, taken from
// the layout in SetRowView (10 pt inset, 36 pt badge, flexible info column, 68 pt weight, 60 pt reps, 44 pt check;
// 6 pt gaps): see RowZone.
//
// Screens that a full-screen cover hides stay in the accessibility tree, so a label can exist twice: the hub's
// toolbar button "More" (identifier "hub-more") sits behind the active workout, whose header button has the same label
// (identifier "active-more"). The first CI run tapped the hub's copy ("Failed to scroll to visible"), which makes
// XCTest end the whole test. The flow now (1) finds the header's button by its identifier, (2) lets UIDriver.find prefer
// a match that can be hit, and (3) gives every step a way back: requireActive() closes stray overlays, reopens the
// workout from the hub, or starts a new one; ensureHub() leaves the summary or restarts the app.

import XCTest

final class StrengthFlowTests: XCTestCase {

    /// The whole walk in one test, so that one app launch carries the state from the hub through a finished workout.
    @MainActor
    func testFullStrengthFlow() {
        continueAfterFailure = true
        let output = FlowOutput(suite: "ui", testCase: self)
        let flow = StrengthFlow(app: XCUIApplication(), output: output)
        flow.run()
    }
}

// MARK: - The flow

/// Where inside a set row a tap goes (offsets from the leading edge, or from the trailing edge for the cells).
private enum RowZone {
    /// The set-type badge button: 10 pt inset + half of 36 pt.
    case badge
    /// The weight cell: 44 (check) + 6 + 60 (reps) + 6 + half of 68 from the trailing edge.
    case weight
    /// The reps cell: 44 (check) + 6 + half of 60 from the trailing edge.
    case reps
    /// The check circle: half of 44 from the trailing edge.
    case check
}

private enum RowFilter {
    case pending
    case done
    case all
}

@MainActor
final class StrengthFlow: UIDriver {
    /// True while the active-workout screen is believed to be showing. A step that needs it checks, and when it is
    /// gone brings it back (reopen from the hub, else a new workout) before it gives up and skips itself.
    private var activeWorkoutVisible = false
    /// How often a new workout had to be started because the active screen was lost (at most 2 per run).
    private var rebuilds = 0
    /// True once the running workout differs from its template (exercises were added), which the 'Update template?'
    /// alert needs.
    private var templateDiffMade = false
    /// What a rebuild starts: the template (phases 1 to 3) or an empty workout (phase 4).
    private var rebuildStartsEmpty = false

    /// The active header's More button. The hub's toolbar button has the same label and stays in the accessibility
    /// tree behind the full-screen cover, hence the identifiers (Components/ActiveHeaderView.swift and
    /// Screens/StrengthHubView.swift); the label is the fallback.
    private static let activeMore: [Target] = [.button("active-more"), .button("More")]

    override func appDidRestart() {
        activeWorkoutVisible = false
        templateDiffMade = false
    }

    func run() {
        launchArguments = ["-PulseUITest", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        output.log("Pulse Strength iPhone UI flow, iOS " + ProcessInfo.processInfo.operatingSystemVersionString)

        hubSteps()
        startTemplateStep()
        restDockSteps()
        sheetSteps()
        exerciseListSteps()
        navigatorAndSupersetSteps()
        undoAndRestSteps()
        pauseAndResumeSteps()
        logEverythingStep()
        finishSteps()
        hubAfterFinishSteps()
        exerciseDetailSteps()
        emptyWorkoutSteps()

        output.log(
            "SUMMARY: " + String(okSteps) + " steps OK, " + String(failedSteps) + " FAILED, " + String(skippedSteps)
                + " skipped, " + String(output.screenshotCount) + " screenshots, " + String(failureCount) + " recorded failures"
        )
        output.attachLog()
    }

    // MARK: Recovery

    /// Makes sure the active-workout screen is showing before a step that needs it, and returns false (the step then
    /// skips itself) only when it could not be brought back.
    ///   1. Stray dialogs, alerts, sheets and the keyboard of an earlier failed step are closed (not with
    ///      `keepOverlays`, for the steps that continue in a sheet the previous step opened on purpose).
    ///   2. Lost screen: reopen it from the hub (the in-progress bar, or the hub's Resume button).
    ///   3. Still lost: start a new workout (`rebuildActiveWorkout`).
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

    /// Last resort: launches the app again (the UI-test mode starts from an empty store, so the earlier workout is
    /// gone) and starts the template, or an empty workout in phase 4. At most twice per run.
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
        let starter: Target = rebuildStartsEmpty ? .button("Start Empty Workout", .loose) : .button("Start Workout")
        if !tap(starter) {
            return false
        }
        if waitFor(.button("Minimise workout"), timeout: 20) == nil {
            fail("The rebuilt workout did not open: no 'Minimise workout' button within 20 s")
            return false
        }
        activeWorkoutVisible = true
        return true
    }

    /// The 'Update template?' alert only appears when the workout differs from its template. The walk adds exercises
    /// for it; after a rebuild one exercise is added here (More > Add exercise > Back squat).
    private func ensureTemplateDiff() {
        if templateDiffMade || rebuildStartsEmpty {
            return
        }
        note("the workout was rebuilt: adding an exercise so that it differs from its template")
        if !openMoreMenu(expecting: "Add exercise") || !tap(.button("Add exercise")) {
            return
        }
        guard waitFor(.field("Search exercises"), timeout: 10) != nil else {
            fail("The picker did not open from the More dialog: no 'Search exercises' text field within 10 s")
            return
        }
        tap(.button("Back squat"))
        if tap(.button("Add [0-9]+ exercises?", .regex)) {
            if !waitUntilGone(.field("Search exercises"), timeout: 8) {
                fail("The picker is still showing 8 s after tapping its 'Add N exercises' button")
            }
            templateDiffMade = true
        }
    }

    /// Opens the More dialog of the active workout from the header and waits for its `action` button ("Pause
    /// workout", "Resume workout", "Discard workout", ...). A dialog that does not show it is closed and the button
    /// tapped once more.
    private func openMoreMenu(expecting action: String) -> Bool {
        for attempt in 1...2 {
            if !tap(anyOf: StrengthFlow.activeMore, timeout: 10, required: true) {
                return false
            }
            if waitFor(.button(action), timeout: 6) != nil {
                return true
            }
            if attempt == 1 {
                note("the More dialog showed no '" + action + "' button 6 s after the tap; closing it and trying once more")
                recoverOverlays()
            }
        }
        fail("The More dialog did not open or offers no '" + action + "' button (the header's More button was tapped twice)")
        return false
    }

    /// True when no workout screen, summary or sheet covers the hub and its "Start Workout" button exists.
    private func hubInFront() -> Bool {
        if exists(.button("Minimise workout")) || exists(.element("Workout Complete")) {
            return false
        }
        return exists(.button("Start Workout"))
    }

    /// Brings the Strength hub to the front before a step that starts from it: leaves the summary with Done, closes
    /// stray overlays, minimises a workout screen, and as the last resort launches the app again.
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

    // MARK: Phase 1: hub

    private func hubSteps() {
        step("Launch the app in UI-test mode and wait for the Strength hub", checkApp: false) {
            relaunch()
            if waitFor(.button("Start Workout"), timeout: 40) == nil {
                fail("The hub did not appear: no 'Start Workout' button within 40 s of the launch")
            }
            let size = app.windows.element(boundBy: 0).frame.size
            note("window " + String(Int(size.width)) + " x " + String(Int(size.height)) + " pt")
            shot("hub-top", settle: 1.0)
        }

        step("Scroll through the hub") {
            // The hub is two pages long: the loop stops (and does not photograph the same page again) at its end.
            let swipes = scrollPages(named: "hub-scrolled-", maxPages: 4)
            swipeScreenDown(times: swipes)
        }
    }

    // MARK: Phase 2: the active workout

    private func startTemplateStep() {
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
            shot("active-initial", settle: 1.2)
        }
    }

    private func restDockSteps() {
        step("Log the first set: the rest dock appears") {
            guard requireActive("log the first set") else { return }
            if !logNextPendingSet() {
                return
            }
            if waitFor(.button("Skip"), timeout: 10) == nil {
                fail("The rest dock did not appear after logging a set: no 'Skip' button within 10 s")
            }
            shot("rest-dock", settle: 0.8)
        }

        step("Wait 2 s: the rest dock counts down") {
            guard requireActive("watch the rest dock") else { return }
            let before = restDockValue()
            pause(2.0)
            let after = restDockValue()
            note("rest dock value before: " + (before ?? "not readable") + ", after: " + (after ?? "not readable"))
            if let first = before, let second = after, first == second {
                fail("The rest dock value did not change in 2 s: still '" + first + "'")
            }
            shot("rest-dock-counting", settle: 0.2)
        }
    }

    private func sheetSteps() {
        step("Open the keypad on the weight of the next set and type a value") {
            guard requireActive("open the keypad") else { return }
            guard let row = firstPendingRow() else {
                fail("No pending set row found (no element labelled 'Set N, ..., not logged')")
                return
            }
            note("tapping the weight cell of: " + row.label)
            if !tapZone(.weight, of: row) {
                return
            }
            guard waitFor(.button("Next: Reps"), timeout: 10) != nil else {
                fail("The keypad did not open: no 'Next: Reps' button within 10 s")
                shot("keypad-missing")
                return
            }
            shot("keypad-weight", settle: 0.9)
            tap(.button("6"))
            tap(.button("5"))
            shot("keypad-typed", settle: 0.3)
            if tap(.button("Next: Reps")) {
                shot("keypad-reps", settle: 0.4)
            }
            closeSheet("keypad", goneWhen: .button("Increase", .prefix))
        }

        step("Open the set-detail sheet (tap the set-type badge)") {
            guard requireActive("open the set-detail sheet") else { return }
            guard let row = firstPendingRow() else {
                fail("No pending set row found (no element labelled 'Set N, ..., not logged')")
                return
            }
            if !tapZone(.badge, of: row) {
                return
            }
            guard waitFor(.button("Delete Set", .contains), timeout: 10) != nil else {
                fail("The set-detail sheet did not open: no 'Delete Set' button within 10 s")
                shot("set-detail-missing")
                return
            }
            shot("set-detail", settle: 0.8)
            if tap(.button("2 reps in reserve")) {
                shot("set-detail-reps-in-reserve", settle: 0.4)
            }
            closeSheet("set-detail", goneWhen: .button("Delete Set", .contains))
        }

        step("Open the rest-timer settings sheet") {
            guard requireActive("open the rest settings") else { return }
            if !tap(.button("Rest timer")) {
                return
            }
            guard waitFor(.element("Rest after each set", .contains), timeout: 10) != nil else {
                fail("The rest settings sheet did not open: no 'Rest after each set' line within 10 s")
                shot("rest-settings-missing")
                return
            }
            shot("rest-settings", settle: 0.8)
            closeSheet("rest settings", goneWhen: .element("Rest after each set", .contains))
        }

        step("Open the exercise options dialog") {
            guard requireActive("open the options dialog") else { return }
            if !tap(.button("Exercise options")) {
                return
            }
            if waitFor(.button("Form & instructions"), timeout: 10) == nil {
                fail("The options dialog did not open: no 'Form & instructions' button within 10 s")
                shot("options-dialog-missing")
                return
            }
            shot("options-dialog", settle: 0.8)
        }

        step("Open the form & instructions sheet") {
            // The options dialog is still open from the previous step, on purpose.
            guard requireActive("open the form sheet", keepOverlays: true) else { return }
            if !tap(.button("Form & instructions")) {
                return
            }
            guard waitFor(.element("How to"), timeout: 12) != nil else {
                fail("The form sheet did not open: no 'How to' heading within 12 s")
                shot("form-info-missing")
                return
            }
            shot("form-info", settle: 1.2)
            app.swipeUp()
            shot("form-info-scrolled", settle: 0.9)
            closeSheet("form", goneWhen: .element("How to"))
        }
    }

    private func exerciseListSteps() {
        step("Open the exercise list sheet (Edit)") {
            guard requireActive("open the exercise list") else { return }
            if !tap(.button("Edit", .loose)) {
                return
            }
            guard waitFor(.button("Add Exercise", .loose), timeout: 10) != nil else {
                fail("The exercise list sheet did not open: no 'Add Exercise' button within 10 s")
                shot("exercise-list-missing")
                return
            }
            shot("exercise-list", settle: 0.9)
        }

        step("Add-exercise picker: search 'row' and select two exercises") {
            // The exercise list sheet is still open from the previous step, on purpose.
            guard requireActive("use the exercise picker", keepOverlays: true) else { return }
            if !exists(.button("Add Exercise", .loose)) && !exists(.field("Search exercises")) {
                note("the exercise list sheet is not open; opening it again")
                tap(.button("Edit", .loose), timeout: 5, required: false)
                _ = waitFor(.button("Add Exercise", .loose), timeout: 8)
            }
            if !tap(.button("Add Exercise", .loose)) {
                return
            }
            guard let search = waitFor(.field("Search exercises"), timeout: 10) else {
                fail("The picker did not open: no 'Search exercises' text field within 10 s")
                shot("picker-missing")
                return
            }
            shot("picker", settle: 0.9)
            enterText(into: search, text: "row", replacing: false)
            pause(1.0)
            shot("picker-search-row", settle: 0.4)
            // The keyboard covers most of the result list; its Search key hides it before the rows are tapped.
            dismissKeyboard()
            pause(0.6)
            tap(.button("Barbell row"))
            tap(.button("Seated cable row"))
            shot("picker-selected", settle: 0.6)
        }

        step("Create-exercise sheet") {
            // The picker is still open from the previous step, on purpose.
            guard requireActive("open the create-exercise sheet", keepOverlays: true) else { return }
            if !exists(.field("Search exercises")) {
                skip("create an exercise: the picker is not open (an earlier step failed)")
                return
            }
            if !tap(.button("Create", .prefix)) {
                return
            }
            guard waitFor(.element("New Exercise"), timeout: 10) != nil else {
                fail("The create-exercise sheet did not open: no 'New Exercise' title within 10 s")
                shot("create-exercise-missing")
                return
            }
            shot("create-exercise", settle: 0.9)
            if let nameField = waitFor(.field("Name"), timeout: 5) {
                enterText(into: nameField, text: "Landmine press", replacing: true)
                shot("create-exercise-filled", settle: 0.5)
            } else {
                fail("The create-exercise sheet has no 'Name' text field")
            }
            if tap(.button("Save")) {
                if !waitUntilGone(.element("New Exercise"), timeout: 8) {
                    fail("The create-exercise sheet is still showing 8 s after Save")
                }
            }
        }

        step("Add the selected exercises to the workout") {
            // The picker is still open from the previous step, on purpose.
            guard requireActive("add the selected exercises", keepOverlays: true) else { return }
            if !exists(.field("Search exercises")) {
                skip("add the selected exercises: the picker is not open (an earlier step failed)")
                return
            }
            shot("picker-with-created", settle: 0.8)
            if !tap(.button("Add [0-9]+ exercises?", .regex)) {
                return
            }
            templateDiffMade = true
            if !waitUntilGone(.field("Search exercises"), timeout: 8) {
                fail("The picker is still showing 8 s after tapping its 'Add N exercises' button")
            }
            shot("exercise-list-after-add", settle: 1.0)
            closeSheet("exercise list", goneWhen: .button("Add Exercise", .loose))
        }
    }

    private func navigatorAndSupersetSteps() {
        step("Go to the next exercise with '>' and back with '<'") {
            guard requireActive("use the exercise navigator") else { return }
            if tap(.button("Next exercise")) {
                if waitFor(.element("Exercise 2 of", .contains), timeout: 8) == nil {
                    fail("After 'Next exercise' the position label 'Exercise 2 of N' did not appear within 8 s")
                }
                shot("next-exercise", settle: 0.8)
            }
            if tap(.button("Previous exercise")) {
                if waitFor(.element("Exercise 1 of", .contains), timeout: 8) == nil {
                    fail("After 'Previous exercise' the position label 'Exercise 1 of N' did not appear within 8 s")
                }
                shot("previous-exercise", settle: 0.8)
            }
        }

        step("Toggle a superset on and off") {
            guard requireActive("toggle a superset") else { return }
            // The pill reads "Superset B" (A is taken by the template's own superset). The pattern does not match the
            // dialog's own "Superset with next" button, which is still on screen while the dialog fades out.
            let pill = Target.element(".*Superset [A-Z]", .regex)
            if tap(.button("Exercise options")) && tap(.button("Superset with next")) {
                if waitFor(pill, timeout: 8) == nil {
                    fail("No 'Superset <letter>' pill appeared on the exercise card after 'Superset with next'")
                }
                shot("superset-on", settle: 0.8)
            }
            if tap(.button("Exercise options")) && tap(.button("Remove from superset")) {
                if !waitUntilGone(pill, timeout: 8) {
                    fail("The 'Superset <letter>' pill is still showing after 'Remove from superset'")
                }
                shot("superset-off", settle: 0.8)
            }
        }
    }

    private func undoAndRestSteps() {
        step("Delete a set: the undo toast appears, then Undo") {
            guard requireActive("delete a set") else { return }
            let rows = setRows(.all)
            let count = rows.count
            guard count >= 2 else {
                fail("Expected at least 2 set rows on the card, found " + String(count))
                return
            }
            let row = rows.element(boundBy: 1)
            note("deleting: " + row.label)
            if !tapZone(.badge, of: row) {
                return
            }
            if !tap(.button("Delete Set", .contains)) {
                return
            }
            guard waitFor(.button("Undo"), timeout: 6) != nil else {
                fail("The undo toast did not appear after deleting a set: no 'Undo' button within 6 s")
                shot("undo-toast-missing")
                return
            }
            shot("undo-toast", settle: 0.1)
            if tap(.button("Undo"), timeout: 3) {
                shot("undo-restored", settle: 0.7)
            }
        }

        step("Run the rest out with -15 to show the 'Rest over' dock") {
            guard requireActive("run the rest out") else { return }
            var taps = 0
            while find(.button("Dismiss")) == nil && taps < 12 {
                if !tap(.button("Subtract 15 seconds"), timeout: 3) {
                    return
                }
                taps += 1
                pause(0.4)
            }
            note("tapped -15 " + String(taps) + " times")
            guard waitFor(.button("Dismiss"), timeout: 5) != nil else {
                fail("The rest dock never reached 'Rest over' (no 'Dismiss' button)")
                return
            }
            shot("rest-over", settle: 0.6)
            tap(.button("Dismiss"))
            shot("rest-dismissed", settle: 0.8)
        }
    }

    private func pauseAndResumeSteps() {
        step("Log another set, open the More menu and pause the workout") {
            guard requireActive("pause the workout") else { return }
            if logNextPendingSet() {
                if waitFor(.button("Skip"), timeout: 10) == nil {
                    fail("The rest dock did not appear after logging a set: no 'Skip' button within 10 s")
                }
            }
            if !openMoreMenu(expecting: "Pause workout") {
                shot("more-menu-missing")
                return
            }
            shot("more-menu", settle: 0.8)
            tap(.button("Pause workout"))
            shot("paused", settle: 1.3)
        }

        step("Resume the workout") {
            guard requireActive("resume the workout") else { return }
            if !openMoreMenu(expecting: "Resume workout") {
                shot("more-menu-not-paused")
                return
            }
            shot("more-menu-paused", settle: 0.8)
            tap(.button("Resume workout"))
            shot("resumed", settle: 1.0)
        }
    }

    private func logEverythingStep() {
        step("Log every remaining set (tap each pending check)") {
            guard requireActive("log all sets") else { return }
            ensureTemplateDiff()
            logAllPendingSets()
            shot("all-sets-logged", settle: 1.0)
        }
    }

    // MARK: Phase 3: finish, summary, hub

    private func finishSteps() {
        step("Finish: the confirmation dialog") {
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
                shot("finish-dialog-missing")
                return
            }
            shot("finish-dialog", settle: 0.9)
        }

        step("Finish Workout: the 'Update template?' alert") {
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
            let templateAlert = Target.button("Update Template")
            let summary = Target.element("Workout Complete")
            guard let which = waitForAny([templateAlert, summary], timeout: 20) else {
                fail("After 'Finish Workout' neither the 'Update Template' alert nor the 'Workout Complete' summary appeared within 20 s")
                shot("finish-no-result")
                if exists(.button("Minimise workout")) {
                    // The workout is still running: the later steps can use it (recoverOverlays closes what is open).
                    activeWorkoutVisible = true
                }
                return
            }
            if which == 0 {
                shot("update-template-alert", settle: 0.8)
                tap(templateAlert)
            } else {
                note("the 'Update template?' alert did not appear (the summary came straight away)")
            }
        }

        step("Summary screen", recoverOnFailure: false) {
            guard waitFor(.element("Workout Complete"), timeout: 20) != nil else {
                fail("The summary did not appear: no 'Workout Complete' title within 20 s")
                shot("summary-missing")
                return
            }
            shot("summary-top", settle: 1.4)
            app.swipeUp()
            shot("summary-middle", settle: 0.9)
            app.swipeUp()
            shot("summary-bottom", settle: 0.9)
        }

        step("Summary: Done returns to the hub", recoverOnFailure: false) {
            if !tap(.button("Done")) {
                return
            }
            // The hub's own elements stay in the accessibility tree behind the summary, so wait for the summary to go.
            if !waitUntilGone(.element("Workout Complete"), timeout: 15) {
                fail("The summary is still showing 15 s after tapping Done")
            }
            if waitFor(.button("Start Workout"), timeout: 20) == nil {
                fail("The hub did not come back after Done: no 'Start Workout' button within 20 s")
            }
        }
    }

    private func hubAfterFinishSteps() {
        step("Hub after the workout: history updated", recoverOnFailure: false) {
            ensureHub("show the hub after the workout")
            shot("hub-after-finish", settle: 1.2)
            let swipes = scrollPages(named: "hub-after-finish-scrolled-", maxPages: 3)
            swipeScreenDown(times: swipes)
        }
    }

    private func exerciseDetailSteps() {
        step("Exercise library, then an exercise detail", recoverOnFailure: false) {
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
                shot("exercise-library-missing")
                return
            }
            shot("exercise-library", settle: 0.9)
            if !tap(bench) {
                return
            }
            guard waitFor(.element("Est. 1RM", .contains), timeout: 15) != nil else {
                fail("The exercise detail did not open: no 'Est. 1RM' tile within 15 s")
                shot("exercise-detail-missing")
                return
            }
            shot("exercise-detail-top", settle: 1.4)
            app.swipeUp()
            shot("exercise-detail-middle", settle: 1.0)
            app.swipeUp()
            shot("exercise-detail-bottom", settle: 1.0)
            navigateBack()
            if waitFor(bench, timeout: 6) == nil {
                note("the back button did not return to the exercise library; trying the edge swipe")
                edgeSwipeBack()
                if waitFor(bench, timeout: 8) == nil {
                    fail("Back from the exercise detail did not show the exercise library again")
                }
            }
            shot("exercise-library-back", settle: 0.8)
        }
    }

    // MARK: Phase 4: empty workout

    private func emptyWorkoutSteps() {
        // From here on a lost workout screen is rebuilt as an empty workout.
        rebuildStartsEmpty = true

        step("Empty workout: start it from the hub", checkApp: false) {
            // A fresh launch makes this part independent of whatever the earlier steps left behind.
            relaunch()
            if waitFor(.button("Start Workout"), timeout: 40) == nil {
                fail("The hub did not appear after the relaunch: no 'Start Workout' button within 40 s")
                return
            }
            if !tap(.button("Start Empty Workout", .loose)) {
                return
            }
            if waitFor(.element("No exercises yet"), timeout: 20) == nil {
                fail("The empty workout screen did not appear: no 'No exercises yet' text within 20 s")
                shot("empty-workout-missing")
                return
            }
            activeWorkoutVisible = true
            shot("empty-workout", settle: 1.2)
        }

        step("Empty workout: add an exercise") {
            guard requireActive("add an exercise to the empty workout") else { return }
            if !tap(.button("Add Exercise", .loose)) {
                return
            }
            guard waitFor(.field("Search exercises"), timeout: 10) != nil else {
                fail("The picker did not open: no 'Search exercises' text field within 10 s")
                shot("empty-picker-missing")
                return
            }
            shot("empty-picker", settle: 0.9)
            if tap(.button("Back squat")) {
                shot("empty-picker-selected", settle: 0.6)
            }
            if tap(.button("Add [0-9]+ exercises?", .regex)) {
                if !waitUntilGone(.field("Search exercises"), timeout: 8) {
                    fail("The picker is still showing 8 s after tapping its 'Add N exercises' button")
                }
                if waitFor(.button("Exercise options"), timeout: 10) == nil {
                    fail("The exercise card did not appear after adding an exercise: no 'Exercise options' button within 10 s")
                }
                shot("empty-workout-with-exercise", settle: 1.0)
            }
        }

        step("Discard the workout") {
            guard requireActive("discard the workout") else { return }
            if !openMoreMenu(expecting: "Discard workout") {
                shot("more-menu-missing")
                return
            }
            if !tap(.button("Discard workout")) {
                return
            }
            guard waitFor(.button("Discard"), timeout: 10) != nil else {
                fail("The discard alert did not appear: no 'Discard' button within 10 s")
                shot("discard-alert-missing")
                return
            }
            shot("discard-alert", settle: 0.8)
            tap(.button("Discard"))
            activeWorkoutVisible = false
            // The hub's own elements stay in the accessibility tree behind the workout screen, so wait for it to go.
            if !waitUntilGone(.button("Minimise workout"), timeout: 15) {
                fail("The workout screen is still showing 15 s after tapping 'Discard'")
            }
            if waitFor(.button("Start Workout"), timeout: 20) == nil {
                fail("The hub did not come back after discarding: no 'Start Workout' button within 20 s")
            }
            shot("hub-final", settle: 1.2)
        }
    }

    // MARK: Set rows

    private func setRows(_ filter: RowFilter) -> XCUIElementQuery {
        let format: String
        switch filter {
        case .pending:
            format = "label BEGINSWITH 'Set ' AND label ENDSWITH ', not logged'"
        case .done:
            format = "label BEGINSWITH 'Set ' AND label ENDSWITH ', logged'"
        case .all:
            format = "label BEGINSWITH 'Set ' AND label ENDSWITH 'logged'"
        }
        return app.descendants(matching: .any).matching(NSPredicate(format: format))
    }

    /// The first set row of the current exercise that is not logged yet (the "next" set).
    private func firstPendingRow(timeout: TimeInterval = 8) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let rows = setRows(.pending)
            if rows.count > 0 {
                return rows.element(boundBy: 0)
            }
            if Date() >= deadline {
                return nil
            }
            pause(0.3)
        }
    }

    /// Taps one control of a set row at its fixed place inside the row (see the file comment).
    private func tapZone(_ zone: RowZone, of row: XCUIElement) -> Bool {
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
        case .reps:
            x = frame.width - 80
        case .check:
            x = frame.width - 22
        }
        let origin = row.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        origin.withOffset(CGVector(dx: x, dy: frame.height / 2)).tap()
        return true
    }

    @discardableResult
    private func logNextPendingSet() -> Bool {
        guard let row = firstPendingRow() else {
            fail("No pending set row found (no element labelled 'Set N, ..., not logged')")
            return false
        }
        note("logging: " + row.label)
        return tapZone(.check, of: row)
    }

    /// The spoken remaining time of the rest dock ("58 seconds"), nil when no dock is showing.
    private func restDockValue() -> String? {
        let types: [XCUIElement.ElementType] = [.other, .staticText]
        for type in types {
            let matches = app.descendants(matching: type).matching(NSPredicate(format: "label BEGINSWITH 'Rest timer'"))
            let count = matches.count
            if count > 0 {
                return (matches.element(boundBy: count - 1).value as? String) ?? ""
            }
        }
        return nil
    }

    /// "7 of 19" from the header's Sets stat.
    private func setsProgress() -> (done: Int, total: Int)? {
        guard let element = find(.element("Sets logged")) else {
            return nil
        }
        guard let text = element.value as? String else {
            return nil
        }
        let parts = text.components(separatedBy: " of ")
        guard parts.count == 2, let done = Int(parts[0]), let total = Int(parts[1]) else {
            return nil
        }
        return (done: done, total: total)
    }

    /// Closes the rest dock (Skip, or Dismiss when the rest is over) so the set table keeps its full height.
    private func closeRestDock() {
        if let skipButton = find(.button("Skip")) {
            press(skipButton, failIfGone: false)
            pause(0.3)
            return
        }
        if let dismissButton = find(.button("Dismiss")) {
            press(dismissButton, failIfGone: false)
            pause(0.3)
        }
    }

    private func goToFirstExercise() {
        for _ in 0..<30 {
            guard let previous = find(.button("Previous exercise")), previous.isEnabled else {
                return
            }
            press(previous, failIfGone: false)
            pause(0.4)
        }
    }

    /// Taps the check of every pending set, exercise by exercise ('>' when the card has none left; supersets move
    /// the card by themselves), closing the rest dock after each one, until the header says "N of N".
    private func logAllPendingSets() {
        var tapped = 0
        var idle = 0
        var sameRow = 0
        var wraps = 0
        var lastLabel = ""
        while tapped < 150 && idle < 40 {
            if let row = firstPendingRow(timeout: 1.5) {
                idle = 0
                let label = row.label
                sameRow = (label == lastLabel) ? sameRow + 1 : 0
                if sameRow >= 3 {
                    fail("Tapping the check of '" + label + "' did not log the set after 3 tries")
                    break
                }
                lastLabel = label
                if !tapZone(.check, of: row) {
                    break
                }
                tapped += 1
                pause(0.4)
                closeRestDock()
                continue
            }
            idle += 1
            if let progress = setsProgress(), progress.done >= progress.total {
                break
            }
            if let next = find(.button("Next exercise")), next.isEnabled {
                press(next, failIfGone: false)
                pause(0.5)
            } else {
                wraps += 1
                if wraps > 3 {
                    break
                }
                goToFirstExercise()
            }
        }
        note("tapped the check of " + String(tapped) + " sets")
        if let progress = setsProgress() {
            note("header: " + String(progress.done) + " of " + String(progress.total) + " sets logged")
            if progress.done < progress.total {
                fail("Only " + String(progress.done) + " of " + String(progress.total) + " sets are logged after tapping every pending set")
            }
        } else {
            note("the header's 'Sets logged' value could not be read")
        }
    }
}
