import Foundation

/// What the app remembers once the onboarding is over: that it ran, when, and what the user answered. The answer to the AI Coaching
/// question is the record of the user's consent (privacy policy section 7), so it is kept with the date it was given.
public struct OnboardingRecord: Codable, Equatable, Hashable, Sendable {
    public var completedAt: Date
    /// False when an existing account logged in: none of the setup steps ran on this device.
    public var isNewAccount: Bool
    /// The answers of the setup steps; empty for an existing account.
    public var answers: OnboardingAnswers

    public init(completedAt: Date, isNewAccount: Bool, answers: OnboardingAnswers) {
        self.completedAt = completedAt
        self.isNewAccount = isNewAccount
        self.answers = answers
    }

    public init(completedAt: Date, outcome: OnboardingOutcome) {
        switch outcome {
        case .finished(let answers):
            self.init(completedAt: completedAt, isNewAccount: true, answers: answers)
        case .signedIn:
            self.init(completedAt: completedAt, isNewAccount: false, answers: OnboardingAnswers())
        }
    }

    /// True when the setup steps already asked for Apple Health and notifications, so the app must not ask again at launch.
    public var askedForPermissions: Bool {
        isNewAccount
    }
}

/// Keeps the `OnboardingRecord` in `UserDefaults`.
public struct OnboardingRecordStore {
    /// `UserDefaults` key of the record (JSON).
    public static let defaultKey = "health.pulse.strength.onboardingRecord"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = OnboardingRecordStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    /// The saved record; nil when the onboarding has not been completed (or the saved data cannot be read).
    public func load() -> OnboardingRecord? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OnboardingRecord.self, from: data)
    }

    public func save(_ record: OnboardingRecord) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record) else { return }
        defaults.set(data, forKey: key)
    }

    /// Forgets the record, so the onboarding runs again at the next launch.
    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
