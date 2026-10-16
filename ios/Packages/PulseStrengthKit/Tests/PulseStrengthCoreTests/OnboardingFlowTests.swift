import XCTest
@testable import PulseStrengthCore

/// The state machine of the first-run flow (OnboardingFlow.swift).
final class OnboardingFlowTests: XCTestCase {
    private func run(_ actions: [OnboardingAction], from state: OnboardingState = OnboardingState()) -> OnboardingState {
        actions.reduce(state) { OnboardingReducer.reduce($0, $1) }
    }

    // MARK: The paths through the flow

    func testNewAccountGoesThroughEveryStep() {
        var state = OnboardingState()
        XCTAssertEqual(state.step, .welcome)

        state = OnboardingReducer.reduce(state, .openAuth(.signUp))
        XCTAssertEqual(state.step, .auth)
        XCTAssertEqual(state.authMode, .signUp)
        XCTAssertTrue(state.isAuthSheetOpen)

        state = OnboardingReducer.reduce(state, .authenticated)
        XCTAssertEqual(state.step, .profile)
        XCTAssertFalse(state.isAuthSheetOpen)

        state = run([.selectGoal(.recover), .selectLevel(.advanced), .continueFromProfile], from: state)
        XCTAssertEqual(state.step, .health)

        state = OnboardingReducer.reduce(state, .answerHealth(true))
        XCTAssertEqual(state.step, .coach)

        state = OnboardingReducer.reduce(state, .answerCoach(false))
        XCTAssertEqual(state.step, .notify)

        state = OnboardingReducer.reduce(state, .answerNotifications(true))
        XCTAssertEqual(state.step, .done)
        XCTAssertNil(state.outcome, "the flow is not over before the last button")

        state = OnboardingReducer.reduce(state, .finish)
        let expected = OnboardingAnswers(
            goal: .recover,
            level: .advanced,
            healthConnected: true,
            aiCoachingEnabled: false,
            notificationsEnabled: true
        )
        XCTAssertEqual(state.outcome, .finished(expected))
    }

    func testLoggingInAsExistingUserEndsTheFlowWithoutSetup() {
        var state = OnboardingReducer.reduce(OnboardingState(), .openAuth(.logIn))
        XCTAssertEqual(state.authMode, .logIn)
        state = OnboardingReducer.reduce(state, .authenticated)
        XCTAssertEqual(state.outcome, .signedIn)
        XCTAssertEqual(state.step, .auth, "the host leaves the flow; no setup screen is shown")
    }

    func testTheSheetRemembersTheTabAndCanBeClosed() {
        var state = OnboardingReducer.reduce(OnboardingState(), .openAuth(.signUp))
        state = OnboardingReducer.reduce(state, .setAuthMode(.logIn))
        XCTAssertEqual(state.authMode, .logIn)

        state = OnboardingReducer.reduce(state, .closeAuth)
        XCTAssertEqual(state.step, .welcome)
        XCTAssertEqual(state.direction, .backward)
        XCTAssertEqual(state.authMode, .logIn, "reopening shows the tab the user was on")
    }

    // MARK: Profile gate

    func testProfileNeedsAGoalAndAnExperienceLevel() {
        var state = OnboardingState.preview(at: .profile)
        XCTAssertFalse(state.canContinueFromProfile)
        XCTAssertEqual(OnboardingReducer.reduce(state, .continueFromProfile).step, .profile)

        state = OnboardingReducer.reduce(state, .selectGoal(.strength))
        XCTAssertFalse(state.canContinueFromProfile, "a goal alone is not enough")
        XCTAssertEqual(OnboardingReducer.reduce(state, .continueFromProfile).step, .profile)

        state = OnboardingReducer.reduce(state, .selectLevel(.beginner))
        XCTAssertTrue(state.canContinueFromProfile)
        XCTAssertEqual(OnboardingReducer.reduce(state, .continueFromProfile).step, .health)
    }

    func testTheGoalIsASingleChoice() {
        let state = run([.selectGoal(.strength), .selectGoal(.performance)])
        XCTAssertEqual(state.answers.goal, .performance)
    }

    // MARK: Back

    func testBackWalksTheSetupStepsInReverseAndKeepsTheAnswers() {
        var state = OnboardingState.preview(at: .notify)
        state = OnboardingReducer.reduce(state, .back)
        XCTAssertEqual(state.step, .coach)
        XCTAssertEqual(state.direction, .backward)
        state = OnboardingReducer.reduce(state, .back)
        XCTAssertEqual(state.step, .health)
        state = OnboardingReducer.reduce(state, .back)
        XCTAssertEqual(state.step, .profile)
        XCTAssertEqual(state.answers.goal, .strength)
        XCTAssertEqual(state.answers.healthConnected, true, "going back does not forget what was answered")
    }

    func testThereIsNoBackOnTheFirstAndLastScreens() {
        for step in [OnboardingStep.welcome, .auth, .profile, .done] {
            let state = OnboardingState.preview(at: step)
            XCTAssertEqual(OnboardingReducer.reduce(state, .back), state, "\(step)")
        }
    }

    func testMovingForwardAgainAfterBackSlidesForward() {
        var state = OnboardingState.preview(at: .coach)
        state = OnboardingReducer.reduce(state, .back)
        XCTAssertEqual(state.direction, .backward)
        state = OnboardingReducer.reduce(state, .answerHealth(false))
        XCTAssertEqual(state.direction, .forward)
        XCTAssertEqual(state.answers.healthConnected, false)
    }

    // MARK: Actions that do not fit the screen

    func testActionsOnTheWrongScreenAreIgnored() {
        let welcome = OnboardingState()
        XCTAssertEqual(OnboardingReducer.reduce(welcome, .authenticated), welcome)
        XCTAssertEqual(OnboardingReducer.reduce(welcome, .setAuthMode(.logIn)), welcome)
        XCTAssertEqual(OnboardingReducer.reduce(welcome, .closeAuth), welcome)
        XCTAssertEqual(OnboardingReducer.reduce(welcome, .answerHealth(true)), welcome)
        XCTAssertEqual(OnboardingReducer.reduce(welcome, .finish), welcome)

        let notify = OnboardingState.preview(at: .notify)
        XCTAssertEqual(OnboardingReducer.reduce(notify, .finish), notify, "finish only works on the last screen")
        XCTAssertEqual(OnboardingReducer.reduce(notify, .answerHealth(true)), notify)
        XCTAssertEqual(OnboardingReducer.reduce(notify, .openAuth(.signUp)), notify)

        let done = OnboardingState.preview(at: .done)
        XCTAssertEqual(OnboardingReducer.reduce(done, .answerNotifications(false)), done)
    }

    // MARK: AI Coaching is off unless the user turns it on

    func testAICoachingIsNeverImplied() {
        XCTAssertNil(OnboardingAnswers().aiCoachingEnabled, "not asked yet")
        for step in OnboardingStep.allCases {
            let answers = OnboardingState.preview(at: step).answers
            XCTAssertNotEqual(answers.aiCoachingEnabled, true, "preview at \(step) must not switch AI Coaching on")
        }
        let declined = run([.openAuth(.signUp), .authenticated, .selectGoal(.active), .selectLevel(.beginner),
                            .continueFromProfile, .answerHealth(false), .answerCoach(false)])
        XCTAssertEqual(declined.answers.aiCoachingEnabled, false)
        XCTAssertEqual(declined.answers.healthConnected, false)

        let accepted = run([.answerCoach(true)], from: OnboardingState.preview(at: .coach))
        XCTAssertEqual(accepted.answers.aiCoachingEnabled, true)
    }

    // MARK: Restart

    func testRestartClearsEverything() {
        let state = OnboardingReducer.reduce(OnboardingState.preview(at: .done), .finish)
        XCTAssertNotNil(state.outcome)
        XCTAssertEqual(OnboardingReducer.reduce(state, .restart), OnboardingState())
    }

    // MARK: Steps

    func testStepOrderAndNumbering() {
        XCTAssertEqual(OnboardingStep.setupSteps, [.profile, .health, .coach, .notify])
        XCTAssertEqual(OnboardingStep.profile.setupNumber, 1)
        XCTAssertEqual(OnboardingStep.health.setupNumber, 2)
        XCTAssertEqual(OnboardingStep.coach.setupNumber, 3)
        XCTAssertEqual(OnboardingStep.notify.setupNumber, 4)
        XCTAssertNil(OnboardingStep.welcome.setupNumber)
        XCTAssertNil(OnboardingStep.auth.setupNumber)
        XCTAssertNil(OnboardingStep.done.setupNumber)

        XCTAssertFalse(OnboardingStep.welcome.isSetup)
        XCTAssertFalse(OnboardingStep.auth.isSetup)
        for step in [OnboardingStep.profile, .health, .coach, .notify, .done] {
            XCTAssertTrue(step.isSetup, "\(step)")
        }

        // `next` walks the whole sign-up path in order and ends at done.
        var walked: [OnboardingStep] = [.welcome]
        while let next = walked.last?.next { walked.append(next) }
        XCTAssertEqual(walked, OnboardingStep.allCases)
    }

    func testPreviewStatesHaveTheAnswersOfTheScreensBeforeThem() {
        XCTAssertNil(OnboardingState.preview(at: .welcome).answers.goal)
        XCTAssertNil(OnboardingState.preview(at: .profile).answers.goal)
        XCTAssertNotNil(OnboardingState.preview(at: .health).answers.level)
        XCTAssertEqual(OnboardingState.preview(at: .coach).answers.healthConnected, true)
        XCTAssertEqual(OnboardingState.preview(at: .notify).answers.aiCoachingEnabled, false)
        XCTAssertEqual(OnboardingState.preview(at: .done).answers.notificationsEnabled, true)
        XCTAssertEqual(OnboardingState.preview(at: .auth, authMode: .logIn).authMode, .logIn)
    }
}
