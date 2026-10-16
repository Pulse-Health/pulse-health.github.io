import Foundation

// The state machine of the first-run flow: a value type and a pure function, like the workout reducer. The SwiftUI layer only
// renders `OnboardingState` and dispatches `OnboardingAction`s; everything that talks to the system (sign-in, Health, notifications)
// happens around the reducer and reports back with an action.

/// Which way the last navigation went; the screens slide the other way when the user goes back.
public enum NavigationDirection: Hashable, Sendable {
    case forward
    case backward
}

public struct OnboardingState: Equatable, Hashable, Sendable {
    public var step: OnboardingStep
    /// The tab of the account sheet; also remembered while the sheet is closed.
    public var authMode: AuthMode
    public var direction: NavigationDirection
    public var answers: OnboardingAnswers
    /// Set when the flow is over; the host leaves the onboarding when it sees a value here.
    public var outcome: OnboardingOutcome?

    public init(
        step: OnboardingStep = .welcome,
        authMode: AuthMode = .signUp,
        direction: NavigationDirection = .forward,
        answers: OnboardingAnswers = OnboardingAnswers(),
        outcome: OnboardingOutcome? = nil
    ) {
        self.step = step
        self.authMode = authMode
        self.direction = direction
        self.answers = answers
        self.outcome = outcome
    }

    /// The account sheet is showing.
    public var isAuthSheetOpen: Bool {
        step == .auth
    }

    /// "Continue" on the profile step needs a main goal and an experience level.
    public var canContinueFromProfile: Bool {
        answers.isProfileComplete
    }
}

public enum OnboardingAction: Equatable, Hashable, Sendable {
    /// "Get started" / "Log in" on the welcome screen: opens the account sheet on the given tab.
    case openAuth(AuthMode)
    /// A tab of the account sheet.
    case setAuthMode(AuthMode)
    /// Closes the account sheet (close button, drag down, tap outside).
    case closeAuth
    /// The identity provider accepted the credentials (or Apple). A new account goes on to the profile; an existing one is done.
    case authenticated
    case selectGoal(TrainingGoal)
    case selectLevel(ExperienceLevel)
    case continueFromProfile
    /// The answer to the Apple Health step (true when the user allowed access).
    case answerHealth(Bool)
    /// The answer to the AI Coaching step (true only when the user explicitly turned it on).
    case answerCoach(Bool)
    case answerNotifications(Bool)
    case back
    /// "Start training" on the last screen.
    case finish
    /// Back to the beginning with no answers.
    case restart
}

public enum OnboardingReducer {
    /// Applies one action. An action that does not fit the current screen leaves the state unchanged.
    public static func reduce(_ state: OnboardingState, _ action: OnboardingAction) -> OnboardingState {
        var next = state
        switch action {
        case .openAuth(let mode):
            guard state.step == .welcome else { return state }
            next.step = .auth
            next.authMode = mode
            next.direction = .forward

        case .setAuthMode(let mode):
            guard state.step == .auth else { return state }
            next.authMode = mode

        case .closeAuth:
            guard state.step == .auth else { return state }
            next.step = .welcome
            next.direction = .backward

        case .authenticated:
            guard state.step == .auth else { return state }
            switch state.authMode {
            case .signUp:
                next.step = .profile
                next.direction = .forward
            case .logIn:
                next.outcome = .signedIn
            }

        case .selectGoal(let goal):
            next.answers.goal = goal

        case .selectLevel(let level):
            next.answers.level = level

        case .continueFromProfile:
            guard state.step == .profile, state.canContinueFromProfile else { return state }
            next.step = .health
            next.direction = .forward

        case .answerHealth(let allowed):
            guard state.step == .health else { return state }
            next.answers.healthConnected = allowed
            next.step = .coach
            next.direction = .forward

        case .answerCoach(let enabled):
            guard state.step == .coach else { return state }
            next.answers.aiCoachingEnabled = enabled
            next.step = .notify
            next.direction = .forward

        case .answerNotifications(let allowed):
            guard state.step == .notify else { return state }
            next.answers.notificationsEnabled = allowed
            next.step = .done
            next.direction = .forward

        case .back:
            guard let previous = state.step.previous else { return state }
            next.step = previous
            next.direction = .backward

        case .finish:
            guard state.step == .done else { return state }
            next.outcome = .finished(state.answers)

        case .restart:
            next = OnboardingState()
        }
        return next
    }
}

public extension OnboardingState {
    /// A state at `step` with plausible answers for every screen before it. For SwiftUI previews, screenshots and tests;
    /// AI Coaching stays off, like the app's default.
    static func preview(at step: OnboardingStep, authMode: AuthMode = .signUp) -> OnboardingState {
        var answers = OnboardingAnswers()
        if step == .health || step == .coach || step == .notify || step == .done {
            answers.goal = .strength
            answers.level = .intermediate
        }
        if step == .coach || step == .notify || step == .done { answers.healthConnected = true }
        if step == .notify || step == .done { answers.aiCoachingEnabled = false }
        if step == .done { answers.notificationsEnabled = true }
        return OnboardingState(step: step, authMode: authMode, direction: .forward, answers: answers, outcome: nil)
    }
}
