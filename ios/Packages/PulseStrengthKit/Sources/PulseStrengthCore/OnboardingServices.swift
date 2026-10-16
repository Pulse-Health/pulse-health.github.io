import Foundation

// What the onboarding needs from the outside world: an identity provider for the account and the system for two permissions.
// The flow only talks to `OnboardingServices`, so the same screens run against the real services in the app, against
// `SimulatedOnboardingServices` in previews and UI tests, and against a script in the unit tests.

/// Why an account request failed.
public enum OnboardingAuthError: Error, Equatable, Hashable, Sendable {
    /// Log in: the email or the password is wrong.
    case invalidCredentials
    /// Sign up: there is already an account with this email.
    case accountExists
    /// The user closed the Apple sheet. Nothing to tell them.
    case cancelled
    /// Anything else: no connection, the service is down.
    case failed
}

/// The account service and the two permission prompts of the onboarding. All calls happen on the main actor.
///
/// The tab the user is on decides what happens next (a new account goes on to the profile, an existing one is done), so
/// an account service that is unsure whether an account exists, like Sign in with Apple, simply signs the user in.
@MainActor
public protocol OnboardingServices: AnyObject {
    /// Creates an account (`.signUp`) or logs in (`.logIn`) with an email and a password. Throws `OnboardingAuthError`.
    func authenticate(mode: AuthMode, email: String, password: String) async throws

    /// "Continue with Apple" on either tab. Throws `OnboardingAuthError` (`.cancelled` when the user closes the sheet).
    func authenticateWithApple(mode: AuthMode) async throws

    /// Sends a reset link to `email`. Throws `OnboardingAuthError`.
    func sendPasswordReset(to email: String) async throws

    /// Shows the system Apple Health sheet. Returns true when the user may be treated as connected: Health is available
    /// and sharing was not denied. (HealthKit never tells whether reading was allowed.)
    func requestHealthAccess() async -> Bool

    /// Shows the system notification prompt. Returns true when alerts are allowed.
    func requestNotificationAccess() async -> Bool
}

/// Services that answer the way they are told to, after a short pretend delay. For previews, UI tests, and the app until an
/// account service is connected: it accepts every email and password and asks the system for nothing.
@MainActor
public final class SimulatedOnboardingServices: OnboardingServices {
    /// Seconds each account call takes (the prototype used 0.95 s for the form and 0.65 s for Apple).
    public var latency: TimeInterval
    /// When set, every account call throws it.
    public var failure: OnboardingAuthError?
    public var healthAnswer: Bool
    public var notificationAnswer: Bool

    public init(
        latency: TimeInterval = 0.8,
        failure: OnboardingAuthError? = nil,
        healthAnswer: Bool = true,
        notificationAnswer: Bool = true
    ) {
        self.latency = latency
        self.failure = failure
        self.healthAnswer = healthAnswer
        self.notificationAnswer = notificationAnswer
    }

    public func authenticate(mode: AuthMode, email: String, password: String) async throws {
        try await respond()
    }

    public func authenticateWithApple(mode: AuthMode) async throws {
        try await respond()
    }

    public func sendPasswordReset(to email: String) async throws {
        try await respond()
    }

    public func requestHealthAccess() async -> Bool {
        await pause()
        return healthAnswer
    }

    public func requestNotificationAccess() async -> Bool {
        await pause()
        return notificationAnswer
    }

    private func respond() async throws {
        await pause()
        if let failure = failure {
            throw failure
        }
    }

    private func pause() async {
        guard latency > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(latency * 1_000_000_000))
    }
}
