import Foundation

#if canImport(Combine) || PULSE_COMBINE_SHIM
#if canImport(Combine)
import Combine
#endif

/// The two fields of the account form.
public enum AuthField: Hashable, Sendable {
    case email
    case password
}

/// A request to move the keyboard focus to a field of the form. The token makes two requests for the same field different values,
/// so a view that watches for changes sees both.
public struct AuthFocusRequest: Equatable, Sendable {
    public let field: AuthField
    public let token: Int

    public init(field: AuthField, token: Int) {
        self.field = field
        self.token = token
    }
}

/// What the flow is waiting for. The screens disable their controls and show a spinner while it is set.
public enum OnboardingBusy: Equatable, Sendable {
    /// The email form was sent.
    case submit
    /// "Continue with Apple".
    case apple
    /// "Forgot password?"
    case reset
    /// The Apple Health sheet is up.
    case health
    /// The notification prompt is up.
    case notifications
}

/// A short message that appears at the top of the screen for a moment (a toast).
public struct OnboardingNotice: Equatable, Identifiable, Sendable {
    public let id: Int
    public let text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

/// The observable model behind the onboarding screens: the pure `OnboardingState` plus everything around it that is not part of the
/// flow itself (the text typed in the account form, its error flags, what the flow is waiting for, the toast) and the calls to
/// `OnboardingServices`. A thin wrapper like `StrengthStore`: the screens render it and call its methods, nothing else.
@MainActor
public final class OnboardingModel: ObservableObject {
    /// Where the flow is, with the answers so far.
    @Published public private(set) var state: OnboardingState

    // The account form
    @Published public var email: String = ""
    @Published public var password: String = ""
    @Published public var isPasswordVisible: Bool = false
    @Published public private(set) var emailIsInvalid: Bool = false
    @Published public private(set) var passwordIsInvalid: Bool = false
    /// Why the last account request failed; nil when it did not, or when the user cancelled.
    @Published public private(set) var authError: OnboardingAuthError?
    @Published public private(set) var focusRequest: AuthFocusRequest?

    /// What the flow is waiting for; nil when it is not waiting.
    @Published public private(set) var busy: OnboardingBusy?
    @Published public private(set) var notice: OnboardingNotice?
    /// The pause button at the top: freezes the background video and the looping animations.
    @Published public var isMotionPaused: Bool = false

    public let copy: OnboardingCopy
    /// Called once, when the flow is over (the host leaves the onboarding).
    public var onComplete: ((OnboardingOutcome) -> Void)?

    private let services: OnboardingServices
    private var counter = 0
    private var didComplete = false

    public init(services: OnboardingServices, copy: OnboardingCopy = OnboardingCopy(), state: OnboardingState = OnboardingState()) {
        self.services = services
        self.copy = copy
        self.state = state
    }

    // MARK: Reading

    public var step: OnboardingStep { state.step }
    public var authMode: AuthMode { state.authMode }
    public var answers: OnboardingAnswers { state.answers }
    public var isBusy: Bool { busy != nil }

    /// The line under the form after a failed request.
    public var authMessage: String? {
        guard let error = authError else { return nil }
        return copy.authMessage(for: error)
    }

    /// The chips of the last screen.
    public var summary: [OnboardingSummaryItem] {
        OnboardingSummary.items(for: state.answers, copy: copy)
    }

    // MARK: State machine

    /// Applies one action to the flow. An action that does not fit the current screen changes nothing.
    public func send(_ action: OnboardingAction) {
        let before = state
        let after = OnboardingReducer.reduce(before, action)
        guard after != before else { return }
        state = after

        switch action {
        case .setAuthMode:
            clearFormMessages()
        case .closeAuth, .authenticated:
            // A password is not kept around once it has been used or the form was closed.
            password = ""
            isPasswordVisible = false
            clearFormMessages()
        default:
            break
        }

        if let outcome = after.outcome, !didComplete {
            didComplete = true
            onComplete?(outcome)
        }
    }

    /// Back to the beginning: no answers, an empty form.
    public func restart() {
        state = OnboardingState()
        email = ""
        password = ""
        isPasswordVisible = false
        busy = nil
        notice = nil
        didComplete = false
        clearFormMessages()
    }

    // MARK: Welcome and the account sheet

    public func openAuth(_ mode: AuthMode) {
        send(.openAuth(mode))
    }

    /// A tab of the sheet. Ignored while a request is running.
    public func selectAuthMode(_ mode: AuthMode) {
        guard busy == nil else { return }
        send(.setAuthMode(mode))
    }

    /// Closes the sheet. Ignored while a request is running.
    public func closeAuth() {
        guard busy == nil else { return }
        send(.closeAuth)
    }

    /// The user typed in a field: its error goes away (the next send checks it again).
    public func fieldEdited(_ field: AuthField) {
        switch field {
        case .email:
            if emailIsInvalid { emailIsInvalid = false }
        case .password:
            if passwordIsInvalid { passwordIsInvalid = false }
        }
        if authError != nil { authError = nil }
    }

    /// The submit button of the form: checks the fields, then creates the account or logs in.
    public func submit() async {
        guard busy == nil, state.step == .auth else { return }
        let mode = state.authMode
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let check = CredentialsValidator.check(email: address, password: password, mode: mode)
        emailIsInvalid = !check.emailIsValid
        passwordIsInvalid = !check.passwordIsValid
        authError = nil
        if !check.emailIsValid {
            requestFocus(.email)
            return
        }
        if !check.passwordIsValid {
            requestFocus(.password)
            return
        }

        busy = .submit
        do {
            try await services.authenticate(mode: mode, email: address, password: password)
            busy = nil
            send(.authenticated)
        } catch {
            busy = nil
            fail(with: error)
        }
    }

    /// "Continue with Apple".
    public func continueWithApple() async {
        guard busy == nil, state.step == .auth else { return }
        let mode = state.authMode
        authError = nil
        busy = .apple
        do {
            try await services.authenticateWithApple(mode: mode)
            busy = nil
            send(.authenticated)
        } catch {
            busy = nil
            fail(with: error)
        }
    }

    /// "Forgot password?" on the log-in tab: needs a valid email address, then sends the reset link.
    public func forgotPassword() async {
        guard busy == nil, state.step == .auth, state.authMode == .logIn else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        authError = nil
        guard CredentialsValidator.isValidEmail(address) else {
            emailIsInvalid = true
            requestFocus(.email)
            return
        }

        busy = .reset
        do {
            try await services.sendPasswordReset(to: address)
            busy = nil
            showNotice(copy.authForgotSent)
        } catch {
            busy = nil
            fail(with: error)
        }
    }

    // MARK: Setup

    public func selectGoal(_ goal: TrainingGoal) {
        send(.selectGoal(goal))
    }

    public func selectLevel(_ level: ExperienceLevel) {
        send(.selectLevel(level))
    }

    public func continueFromProfile() {
        send(.continueFromProfile)
    }

    /// "Connect Apple Health": shows the system sheet, then goes on with the answer.
    public func connectHealth() async {
        guard busy == nil, state.step == .health else { return }
        busy = .health
        let allowed = await services.requestHealthAccess()
        busy = nil
        send(.answerHealth(allowed))
    }

    /// "Not now" on the Apple Health step.
    public func skipHealth() {
        guard busy == nil else { return }
        send(.answerHealth(false))
    }

    /// The AI Coaching step: `true` only for the explicit "Turn on AI Coaching".
    public func answerCoach(_ enabled: Bool) {
        send(.answerCoach(enabled))
    }

    /// "Turn on notifications": shows the system prompt, then goes on with the answer.
    public func enableNotifications() async {
        guard busy == nil, state.step == .notify else { return }
        busy = .notifications
        let allowed = await services.requestNotificationAccess()
        busy = nil
        send(.answerNotifications(allowed))
    }

    /// "Not now" on the notifications step.
    public func skipNotifications() {
        guard busy == nil else { return }
        send(.answerNotifications(false))
    }

    public func goBack() {
        guard busy == nil else { return }
        send(.back)
    }

    /// "Start training".
    public func finish() {
        send(.finish)
    }

    // MARK: Toast and motion

    public func showNotice(_ text: String) {
        counter += 1
        notice = OnboardingNotice(id: counter, text: text)
    }

    /// Hides the notice with this id (a newer notice stays).
    public func dismissNotice(id: Int) {
        if notice?.id == id {
            notice = nil
        }
    }

    public func toggleMotion() {
        isMotionPaused.toggle()
    }

    // MARK: Helpers

    private func clearFormMessages() {
        emailIsInvalid = false
        passwordIsInvalid = false
        authError = nil
    }

    private func requestFocus(_ field: AuthField) {
        counter += 1
        focusRequest = AuthFocusRequest(field: field, token: counter)
    }

    private func fail(with error: Error) {
        let failure = (error as? OnboardingAuthError) ?? .failed
        authError = failure == .cancelled ? nil : failure
    }
}

#endif
