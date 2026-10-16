import Foundation

// The first-run flow of the app (welcome, sign up / log in, profile, Apple Health, AI Coaching, notifications, done), ported from
// the design prototype in design/. This file holds the platform-neutral model; OnboardingFlow.swift is the pure state machine,
// OnboardingCopy.swift the words, and PulseStrengthIOS/Onboarding the SwiftUI screens.

/// The product name shown in the onboarding. One place to change when the product is renamed again.
public enum OnboardingBrand {
    public static let name = "Rebase"
}

/// The screens of the flow, in order. `welcome` and `auth` sit on the hero video; `profile` ... `notify` are the four numbered
/// setup steps on the veiled backdrop; `done` closes the flow.
public enum OnboardingStep: String, CaseIterable, Codable, Hashable, Sendable {
    case welcome
    case auth
    case profile
    case health
    case coach
    case notify
    case done

    /// The numbered setup steps, in order. `done` is not one of them.
    public static let setupSteps: [OnboardingStep] = [.profile, .health, .coach, .notify]

    /// 1-based position among the numbered setup steps; nil for welcome, auth and done.
    public var setupNumber: Int? {
        guard let index = OnboardingStep.setupSteps.firstIndex(of: self) else { return nil }
        return index + 1
    }

    /// True for the screens on the veiled backdrop (profile ... done); the hero video rests there.
    public var isSetup: Bool {
        self != .welcome && self != .auth
    }

    /// The screen the Back button leads to; nil where there is no Back (welcome, auth, the first setup step and done).
    public var previous: OnboardingStep? {
        switch self {
        case .health: return .profile
        case .coach: return .health
        case .notify: return .coach
        case .welcome, .auth, .profile, .done: return nil
        }
    }

    /// The screen after this one on the sign-up path; nil after `done`.
    public var next: OnboardingStep? {
        switch self {
        case .welcome: return .auth
        case .auth: return .profile
        case .profile: return .health
        case .health: return .coach
        case .coach: return .notify
        case .notify: return .done
        case .done: return nil
        }
    }
}

/// The two tabs of the account sheet.
public enum AuthMode: String, CaseIterable, Codable, Hashable, Sendable {
    case signUp
    case logIn
}

/// The main goal of the coaching profile (privacy policy section 7: "main goal").
public enum TrainingGoal: String, CaseIterable, Codable, Hashable, Sendable {
    case strength
    case active
    case recover
    case performance
}

/// The experience level of the coaching profile (privacy policy section 7: "experience level").
public enum ExperienceLevel: String, CaseIterable, Codable, Hashable, Sendable {
    case beginner
    case intermediate
    case advanced
}

/// What the user told the app. A nil Health / coach / notification answer means "not asked yet".
public struct OnboardingAnswers: Equatable, Hashable, Codable, Sendable {
    public var goal: TrainingGoal?
    public var level: ExperienceLevel?
    /// Whether the user allowed access to Apple Health.
    public var healthConnected: Bool?
    /// Whether the user explicitly turned on AI Coaching. Off unless the user turns it on.
    public var aiCoachingEnabled: Bool?
    /// Whether the user allowed notifications (the rest-over alert).
    public var notificationsEnabled: Bool?

    public init(
        goal: TrainingGoal? = nil,
        level: ExperienceLevel? = nil,
        healthConnected: Bool? = nil,
        aiCoachingEnabled: Bool? = nil,
        notificationsEnabled: Bool? = nil
    ) {
        self.goal = goal
        self.level = level
        self.healthConnected = healthConnected
        self.aiCoachingEnabled = aiCoachingEnabled
        self.notificationsEnabled = notificationsEnabled
    }

    /// The profile step can continue once both questions are answered.
    public var isProfileComplete: Bool {
        goal != nil && level != nil
    }
}

/// How the flow ended.
public enum OnboardingOutcome: Equatable, Hashable, Sendable {
    /// A new account went through every step.
    case finished(OnboardingAnswers)
    /// An existing account logged in: there is nothing to set up.
    case signedIn
}
