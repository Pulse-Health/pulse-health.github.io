import XCTest
@testable import PulseStrengthCore

#if canImport(Combine) || PULSE_COMBINE_SHIM
#if canImport(Combine)
import Combine
#endif

/// Services that record what they were asked and answer from a script. A call can be held until the test lets it go, to look at the
/// model while it is waiting.
@MainActor
private final class ScriptedServices: OnboardingServices {
    var calls: [String] = []
    var authFailure: OnboardingAuthError?
    var unexpectedFailure = false
    var health = true
    var notifications = true
    /// While true, the next account call waits in `held` until the test resumes it.
    var holdNextCall = false
    private(set) var held: CheckedContinuation<Void, Never>?

    struct Unexpected: Error {}

    private func waitIfHeld() async {
        guard holdNextCall else { return }
        holdNextCall = false
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            held = continuation
        }
        held = nil
    }

    /// Lets the test wait until a call is being held.
    func waitUntilHeld() async {
        var attempts = 0
        while held == nil && attempts < 1000 {
            await Task.yield()
            attempts += 1
        }
    }

    func release() {
        held?.resume()
    }

    private func result() throws {
        if unexpectedFailure { throw Unexpected() }
        if let failure = authFailure { throw failure }
    }

    func authenticate(mode: AuthMode, email: String, password: String) async throws {
        calls.append("authenticate \(mode) \(email) \(password)")
        await waitIfHeld()
        try result()
    }

    func authenticateWithApple(mode: AuthMode) async throws {
        calls.append("apple \(mode)")
        await waitIfHeld()
        try result()
    }

    func sendPasswordReset(to email: String) async throws {
        calls.append("reset \(email)")
        await waitIfHeld()
        try result()
    }

    func requestHealthAccess() async -> Bool {
        calls.append("health")
        await waitIfHeld()
        return health
    }

    func requestNotificationAccess() async -> Bool {
        calls.append("notifications")
        await waitIfHeld()
        return notifications
    }
}

/// The observable model around the first-run flow (OnboardingModel.swift).
@MainActor
final class OnboardingModelTests: XCTestCase {
    private func makeModel(
        _ services: ScriptedServices? = nil,
        state: OnboardingState = OnboardingState(),
        language: OnboardingLanguage = .english
    ) -> OnboardingModel {
        OnboardingModel(services: services ?? ScriptedServices(), copy: OnboardingCopy(language: language), state: state)
    }

    // MARK: Account form: checks

    func testAnEmptyFormShowsBothErrorsAndFocusesTheEmail() async {
        let services = ScriptedServices()
        let model = makeModel(services, state: OnboardingState.preview(at: .auth))

        await model.submit()

        XCTAssertTrue(model.emailIsInvalid)
        XCTAssertTrue(model.passwordIsInvalid)
        XCTAssertEqual(model.focusRequest?.field, .email)
        XCTAssertTrue(services.calls.isEmpty, "nothing is sent while the form is wrong")
        XCTAssertEqual(model.step, .auth)
    }

    func testAShortPasswordFocusesThePasswordWhenTheEmailIsFine() async {
        let services = ScriptedServices()
        let model = makeModel(services, state: OnboardingState.preview(at: .auth))
        model.email = "robin@example.com"
        model.password = "short"

        await model.submit()

        XCTAssertFalse(model.emailIsInvalid)
        XCTAssertTrue(model.passwordIsInvalid)
        XCTAssertEqual(model.focusRequest?.field, .password)
        XCTAssertTrue(services.calls.isEmpty)
    }

    func testEachFocusRequestIsNewEvenForTheSameField() async {
        let model = makeModel(state: OnboardingState.preview(at: .auth))
        await model.submit()
        let first = model.focusRequest
        await model.submit()
        XCTAssertEqual(model.focusRequest?.field, first?.field)
        XCTAssertNotEqual(model.focusRequest, first, "a view watching the request must see the second one")
    }

    func testLoggingInOnlyNeedsAPassword() async {
        let services = ScriptedServices()
        let model = makeModel(services, state: OnboardingState.preview(at: .auth, authMode: .logIn))
        model.email = "robin@example.com"
        model.password = "x"

        await model.submit()

        XCTAssertEqual(services.calls, ["authenticate logIn robin@example.com x"])
        XCTAssertEqual(model.state.outcome, .signedIn)
    }

    func testTypingClearsTheErrorOfThatField() async {
        let model = makeModel(state: OnboardingState.preview(at: .auth))
        await model.submit()
        XCTAssertTrue(model.emailIsInvalid)
        XCTAssertTrue(model.passwordIsInvalid)

        model.fieldEdited(.email)
        XCTAssertFalse(model.emailIsInvalid)
        XCTAssertTrue(model.passwordIsInvalid, "the other field keeps its error")

        model.fieldEdited(.password)
        XCTAssertFalse(model.passwordIsInvalid)
    }

    // MARK: Account form: sending

    func testCreatingAnAccountGoesOnToTheProfileAndForgetsThePassword() async {
        let services = ScriptedServices()
        let model = makeModel(services, state: OnboardingState.preview(at: .auth))
        model.email = "  robin@example.com "
        model.password = "correct horse"
        model.isPasswordVisible = true

        await model.submit()

        XCTAssertEqual(services.calls, ["authenticate signUp robin@example.com correct horse"], "the address is trimmed")
        XCTAssertEqual(model.step, .profile)
        XCTAssertNil(model.state.outcome)
        XCTAssertEqual(model.password, "")
        XCTAssertFalse(model.isPasswordVisible)
        XCTAssertEqual(model.email, "  robin@example.com ", "the email stays for the next time")
        XCTAssertNil(model.busy)
    }

    func testLoggingInEndsTheFlowAndReportsItOnce() async {
        let services = ScriptedServices()
        let model = makeModel(services, state: OnboardingState.preview(at: .auth, authMode: .logIn))
        var outcomes: [OnboardingOutcome] = []
        model.onComplete = { outcomes.append($0) }
        model.email = "robin@example.com"
        model.password = "secret"

        await model.submit()
        await model.submit()

        XCTAssertEqual(outcomes, [.signedIn])
    }

    func testTheFormIsBusyWhileTheRequestRuns() async {
        let services = ScriptedServices()
        services.holdNextCall = true
        let model = makeModel(services, state: OnboardingState.preview(at: .auth))
        model.email = "robin@example.com"
        model.password = "correct horse"

        let running = Task { await model.submit() }
        await services.waitUntilHeld()
        XCTAssertEqual(model.busy, .submit)
        XCTAssertTrue(model.isBusy)

        // Nothing else starts, and the sheet cannot be closed or switched while the request runs.
        await model.submit()
        await model.continueWithApple()
        model.closeAuth()
        model.selectAuthMode(.logIn)
        XCTAssertEqual(services.calls.count, 1)
        XCTAssertEqual(model.step, .auth)
        XCTAssertEqual(model.authMode, .signUp)

        services.release()
        await running.value
        XCTAssertNil(model.busy)
        XCTAssertEqual(model.step, .profile)
    }

    func testAWrongPasswordIsReportedAndTheFormStaysFilled() async {
        let services = ScriptedServices()
        services.authFailure = .invalidCredentials
        let model = makeModel(services, state: OnboardingState.preview(at: .auth, authMode: .logIn))
        model.email = "robin@example.com"
        model.password = "wrong"

        await model.submit()

        XCTAssertEqual(model.authError, .invalidCredentials)
        XCTAssertEqual(model.authMessage, "Email or password is incorrect.")
        XCTAssertEqual(model.step, .auth)
        XCTAssertNil(model.state.outcome)
        XCTAssertEqual(model.password, "wrong")
        XCTAssertNil(model.busy)

        model.fieldEdited(.password)
        XCTAssertNil(model.authError, "typing clears the message")
        XCTAssertNil(model.authMessage)
    }

    func testAnExistingAccountAndOtherFailuresHaveTheirOwnMessages() async {
        let services = ScriptedServices()
        services.authFailure = .accountExists
        let model = makeModel(services, state: OnboardingState.preview(at: .auth), language: .german)
        model.email = "robin@example.com"
        model.password = "correct horse"

        await model.submit()
        XCTAssertEqual(model.authMessage, "Zu dieser E-Mail-Adresse gibt es schon ein Konto. Melde dich stattdessen an.")

        services.authFailure = nil
        services.unexpectedFailure = true
        await model.submit()
        XCTAssertEqual(model.authError, .failed, "an error that is not an OnboardingAuthError counts as a failure")
        XCTAssertEqual(model.authMessage, "Das hat nicht geklappt. Prüfe deine Verbindung und versuche es erneut.")
    }

    func testClosingTheAppleSheetSaysNothing() async {
        let services = ScriptedServices()
        services.authFailure = .cancelled
        let model = makeModel(services, state: OnboardingState.preview(at: .auth))

        await model.continueWithApple()

        XCTAssertNil(model.authError)
        XCTAssertNil(model.authMessage)
        XCTAssertEqual(model.step, .auth)
        XCTAssertNil(model.busy)
    }

    func testContinueWithAppleFollowsTheTab() async {
        let signUp = makeModel(state: OnboardingState.preview(at: .auth))
        await signUp.continueWithApple()
        XCTAssertEqual(signUp.step, .profile)

        let services = ScriptedServices()
        let logIn = makeModel(services, state: OnboardingState.preview(at: .auth, authMode: .logIn))
        await logIn.continueWithApple()
        XCTAssertEqual(services.calls, ["apple logIn"])
        XCTAssertEqual(logIn.state.outcome, .signedIn)
    }

    // MARK: The sheet

    func testSwitchingTabsClearsTheMessagesAndClosingForgetsThePassword() async {
        let model = makeModel(state: OnboardingState.preview(at: .welcome))
        model.openAuth(.signUp)
        XCTAssertEqual(model.step, .auth)

        await model.submit()
        XCTAssertTrue(model.emailIsInvalid)
        model.selectAuthMode(.logIn)
        XCTAssertEqual(model.authMode, .logIn)
        XCTAssertFalse(model.emailIsInvalid)
        XCTAssertFalse(model.passwordIsInvalid)

        model.email = "robin@example.com"
        model.password = "secret"
        model.isPasswordVisible = true
        model.closeAuth()
        XCTAssertEqual(model.step, .welcome)
        XCTAssertEqual(model.password, "")
        XCTAssertFalse(model.isPasswordVisible)
        XCTAssertEqual(model.email, "robin@example.com")
    }

    // MARK: Forgot password

    func testForgotPasswordNeedsAnEmailFirst() async {
        let services = ScriptedServices()
        let model = makeModel(services, state: OnboardingState.preview(at: .auth, authMode: .logIn))

        await model.forgotPassword()

        XCTAssertTrue(model.emailIsInvalid)
        XCTAssertEqual(model.focusRequest?.field, .email)
        XCTAssertTrue(services.calls.isEmpty)
        XCTAssertNil(model.notice)
    }

    func testForgotPasswordSendsTheLinkAndShowsANotice() async {
        let services = ScriptedServices()
        let model = makeModel(services, state: OnboardingState.preview(at: .auth, authMode: .logIn))
        model.email = " robin@example.com"

        await model.forgotPassword()

        XCTAssertEqual(services.calls, ["reset robin@example.com"])
        XCTAssertEqual(model.notice?.text, "If there is an account for this email, a reset link is on its way.")
        XCTAssertEqual(model.step, .auth)
        XCTAssertNil(model.busy)
    }

    func testForgotPasswordIsOnlyForLoggingIn() async {
        let services = ScriptedServices()
        let model = makeModel(services, state: OnboardingState.preview(at: .auth, authMode: .signUp))
        model.email = "robin@example.com"
        await model.forgotPassword()
        XCTAssertTrue(services.calls.isEmpty)
    }

    func testAFailedResetShowsTheMessageUnderTheForm() async {
        let services = ScriptedServices()
        services.authFailure = .failed
        let model = makeModel(services, state: OnboardingState.preview(at: .auth, authMode: .logIn))
        model.email = "robin@example.com"

        await model.forgotPassword()

        XCTAssertEqual(model.authError, .failed)
        XCTAssertNil(model.notice)
    }

    // MARK: Notices

    func testANewerNoticeIsNotHiddenByTheTimerOfAnOlderOne() {
        let model = makeModel()
        model.showNotice("one")
        let first = model.notice
        model.showNotice("two")
        let second = model.notice
        XCTAssertNotEqual(first?.id, second?.id)

        model.dismissNotice(id: first?.id ?? -1)
        XCTAssertEqual(model.notice?.text, "two")
        model.dismissNotice(id: second?.id ?? -1)
        XCTAssertNil(model.notice)
    }

    // MARK: Setup steps

    func testTheSetupStepsCollectTheAnswers() async {
        let services = ScriptedServices()
        let model = makeModel(services, state: OnboardingState.preview(at: .profile))
        var outcomes: [OnboardingOutcome] = []
        model.onComplete = { outcomes.append($0) }

        model.continueFromProfile()
        XCTAssertEqual(model.step, .profile, "a goal and a level are needed first")
        model.selectGoal(.recover)
        model.selectLevel(.beginner)
        model.continueFromProfile()
        XCTAssertEqual(model.step, .health)

        await model.connectHealth()
        XCTAssertEqual(model.step, .coach)
        XCTAssertEqual(model.answers.healthConnected, true)

        model.answerCoach(true)
        XCTAssertEqual(model.step, .notify)
        XCTAssertEqual(model.answers.aiCoachingEnabled, true)

        await model.enableNotifications()
        XCTAssertEqual(model.step, .done)
        XCTAssertEqual(model.answers.notificationsEnabled, true)
        XCTAssertEqual(services.calls, ["health", "notifications"])
        XCTAssertTrue(outcomes.isEmpty, "the flow ends with the last button")

        model.finish()
        let expected = OnboardingAnswers(
            goal: .recover, level: .beginner, healthConnected: true, aiCoachingEnabled: true, notificationsEnabled: true
        )
        XCTAssertEqual(outcomes, [.finished(expected)])
        model.finish()
        XCTAssertEqual(outcomes.count, 1, "reported once")
    }

    func testWhatTheSystemSaysIsWhatIsRecorded() async {
        let services = ScriptedServices()
        services.health = false
        services.notifications = false
        let model = makeModel(services, state: OnboardingState.preview(at: .health))

        await model.connectHealth()
        XCTAssertEqual(model.answers.healthConnected, false, "the user said no in the system sheet")
        await model.enableNotifications()
        XCTAssertEqual(model.step, .coach, "not on the notifications screen yet")
        XCTAssertEqual(services.calls, ["health"])

        model.answerCoach(false)
        await model.enableNotifications()
        XCTAssertEqual(model.answers.notificationsEnabled, false)
        XCTAssertEqual(model.step, .done)
    }

    func testNotNowAsksTheSystemForNothing() async {
        let services = ScriptedServices()
        let model = makeModel(services, state: OnboardingState.preview(at: .health))

        model.skipHealth()
        XCTAssertEqual(model.answers.healthConnected, false)
        model.answerCoach(false)
        model.skipNotifications()

        XCTAssertEqual(model.step, .done)
        XCTAssertEqual(model.answers.notificationsEnabled, false)
        XCTAssertEqual(model.answers.aiCoachingEnabled, false)
        XCTAssertTrue(services.calls.isEmpty)
    }

    func testAPermissionSheetBlocksTheOtherButtons() async {
        let services = ScriptedServices()
        services.holdNextCall = true
        let model = makeModel(services, state: OnboardingState.preview(at: .health))

        let running = Task { await model.connectHealth() }
        await services.waitUntilHeld()
        XCTAssertEqual(model.busy, .health)

        model.skipHealth()
        model.goBack()
        await model.connectHealth()
        XCTAssertEqual(model.step, .health, "nothing moves while the system sheet is up")
        XCTAssertEqual(services.calls, ["health"])

        services.release()
        await running.value
        XCTAssertEqual(model.step, .coach)
    }

    func testBackReturnsToTheEarlierSetupStep() {
        let model = makeModel(state: OnboardingState.preview(at: .notify))
        model.goBack()
        XCTAssertEqual(model.step, .coach)
        model.goBack()
        XCTAssertEqual(model.step, .health)
    }

    // MARK: Summary and restart

    func testTheSummaryFollowsTheAnswers() {
        let model = makeModel(state: OnboardingState.preview(at: .done))
        XCTAssertEqual(
            model.summary.map { $0.text },
            ["Build strength", "Intermediate", "Apple Health connected", "AI Coaching off", "Notifications on"]
        )
    }

    func testRestartStartsOverAndAllowsTheOutcomeToBeReportedAgain() {
        let model = makeModel(state: OnboardingState.preview(at: .done))
        var outcomes: [OnboardingOutcome] = []
        model.onComplete = { outcomes.append($0) }
        model.email = "robin@example.com"
        model.password = "secret"
        model.finish()
        XCTAssertEqual(outcomes.count, 1)

        model.restart()
        XCTAssertEqual(model.state, OnboardingState())
        XCTAssertEqual(model.email, "")
        XCTAssertEqual(model.password, "")

        model.send(.openAuth(.logIn))
        model.email = "robin@example.com"
        model.password = "secret"
        XCTAssertEqual(outcomes.count, 1)
    }

    // MARK: Motion

    func testThePauseButtonToggles() {
        let model = makeModel()
        XCTAssertFalse(model.isMotionPaused)
        model.toggleMotion()
        XCTAssertTrue(model.isMotionPaused)
        model.toggleMotion()
        XCTAssertFalse(model.isMotionPaused)
    }
}

#endif
