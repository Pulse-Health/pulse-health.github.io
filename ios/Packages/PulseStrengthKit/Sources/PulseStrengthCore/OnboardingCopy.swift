import Foundation

// The words of the onboarding. The plain strings are in OnboardingCopyTables.swift (one exhaustive switch per language);
// this file has the language handling, the texts with parameters, and the sentences that contain links or bold parts.

/// The two languages of the onboarding. Anything else falls back to English.
public enum OnboardingLanguage: String, CaseIterable, Hashable, Sendable {
    case english = "en"
    case german = "de"

    /// The first supported language in the user's order of preference (for example `Locale.preferredLanguages`), English if none is.
    public static func resolve(preferredLanguages: [String]) -> OnboardingLanguage {
        for identifier in preferredLanguages {
            let lowered = identifier.lowercased()
            let code = lowered.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? lowered
            if let language = OnboardingLanguage(rawValue: code) {
                return language
            }
        }
        return .english
    }
}

/// A legal document the onboarding links to.
public enum LegalDocument: String, CaseIterable, Hashable, Sendable {
    case terms
    case privacy
}

/// A run of text inside a sentence: plain, bold, or a link to a legal document.
public struct OnboardingRun: Equatable, Hashable, Sendable {
    public enum Style: Equatable, Hashable, Sendable {
        case plain
        case bold
        case link(LegalDocument)
    }

    public let text: String
    public let style: Style

    public init(_ text: String, _ style: Style = .plain) {
        self.text = text
        self.style = style
    }

    public static func plain(_ text: String) -> OnboardingRun { OnboardingRun(text, .plain) }
    public static func bold(_ text: String) -> OnboardingRun { OnboardingRun(text, .bold) }
    public static func link(_ text: String, _ document: LegalDocument) -> OnboardingRun { OnboardingRun(text, .link(document)) }
}

public extension Array where Element == OnboardingRun {
    /// The sentence without any styling (for accessibility labels and tests).
    var plainText: String {
        map { $0.text }.joined()
    }
}

/// Where the legal pages live: the website of this repository (GitHub Pages).
public enum OnboardingLegal {
    /// Replace when the site moves.
    public static let baseURL = URL(string: "https://pulse-health.github.io/")!

    /// The English pages are `terms.html` and `privacy-policy.html`, the German ones `agb.html` and `datenschutz.html`.
    public static func url(for document: LegalDocument, language: OnboardingLanguage) -> URL {
        let page: String
        switch (document, language) {
        case (.terms, .english): page = "terms.html"
        case (.privacy, .english): page = "privacy-policy.html"
        case (.terms, .german): page = "agb.html"
        case (.privacy, .german): page = "datenschutz.html"
        }
        return baseURL.appendingPathComponent(page)
    }
}

public struct OnboardingCopy: Equatable, Hashable, Sendable {
    public let language: OnboardingLanguage

    public init(language: OnboardingLanguage) {
        self.language = language
    }

    /// The language of the user's preferred languages (English when none is supported).
    public init(preferredLanguages: [String] = Locale.preferredLanguages) {
        self.language = OnboardingLanguage.resolve(preferredLanguages: preferredLanguages)
    }

    /// A plain string.
    public func text(_ key: OnboardingText) -> String {
        switch language {
        case .english: return english(key)
        case .german: return german(key)
        }
    }

    public func callAsFunction(_ key: OnboardingText) -> String {
        text(key)
    }

    public func legalURL(_ document: LegalDocument) -> URL {
        OnboardingLegal.url(for: document, language: language)
    }

    // MARK: Texts with parameters

    /// "1 of 3": the position of a highlight, spoken by VoiceOver.
    public func highlightPosition(_ number: Int, of total: Int) -> String {
        switch language {
        case .english: return "\(number) of \(total)"
        case .german: return "\(number) von \(total)"
        }
    }

    /// "Show highlight 2 of 3": the label of a bar of the pager.
    public func showHighlight(_ number: Int, of total: Int) -> String {
        switch language {
        case .english: return "Show highlight \(number) of \(total)"
        case .german: return "Highlight \(number) von \(total) anzeigen"
        }
    }

    /// "Setup progress, step 2 of 4".
    public func setupProgress(_ number: Int, of total: Int) -> String {
        switch language {
        case .english: return "Setup progress, step \(number) of \(total)"
        case .german: return "Einrichtung, Schritt \(number) von \(total)"
        }
    }

    // MARK: Account messages
    //
    // Not in the prototype, which is connected to nothing: what the form says when the account service says no.

    /// The line under the form after a failed request; nil when there is nothing to say (the user closed the Apple sheet).
    public func authMessage(for error: OnboardingAuthError) -> String? {
        switch (error, language) {
        case (.cancelled, _):
            return nil
        case (.invalidCredentials, .english):
            return "Email or password is incorrect."
        case (.invalidCredentials, .german):
            return "E-Mail oder Passwort ist nicht korrekt."
        case (.accountExists, .english):
            return "There is already an account with this email. Try logging in."
        case (.accountExists, .german):
            return "Zu dieser E-Mail-Adresse gibt es schon ein Konto. Melde dich stattdessen an."
        case (.failed, .english):
            return "That didn’t work. Check your connection and try again."
        case (.failed, .german):
            return "Das hat nicht geklappt. Prüfe deine Verbindung und versuche es erneut."
        }
    }

    /// The button above the keyboard that closes it.
    public var keyboardDone: String {
        switch language {
        case .english: return "Done"
        case .german: return "Fertig"
        }
    }

    /// The notice after "Forgot password?" (it does not say whether the account exists).
    public var authForgotSent: String {
        switch language {
        case .english: return "If there is an account for this email, a reset link is on its way."
        case .german: return "Falls es ein Konto zu dieser E-Mail-Adresse gibt, ist ein Link zum Zurücksetzen unterwegs."
        }
    }

    // MARK: Sentences with links or bold parts

    /// Under the buttons of the welcome screen.
    public var legalWelcome: [OnboardingRun] {
        switch language {
        case .english:
            return [.plain("By continuing you agree to our "), .link("Terms", .terms),
                    .plain(" and acknowledge our "), .link("Privacy Policy", .privacy), .plain(".")]
        case .german:
            return [.plain("Wenn du fortfährst, akzeptierst du unsere "), .link("AGB", .terms),
                    .plain(" und nimmst die "), .link("Datenschutzerklärung", .privacy), .plain(" zur Kenntnis.")]
        }
    }

    /// Under the "Create account" button.
    public var legalSignup: [OnboardingRun] {
        switch language {
        case .english:
            return [.plain("By creating an account you agree to our "), .link("Terms", .terms),
                    .plain(" and acknowledge our "), .link("Privacy Policy", .privacy), .plain(".")]
        case .german:
            return [.plain("Mit der Kontoerstellung akzeptierst du unsere "), .link("AGB", .terms),
                    .plain(" und nimmst die "), .link("Datenschutzerklärung", .privacy), .plain(" zur Kenntnis.")]
        }
    }

    /// Above the "Connect Apple Health" button: the data stays on the iPhone (privacy summary: "bleiben immer auf deinem iPhone").
    public var healthNote: [OnboardingRun] {
        switch language {
        case .english:
            return [.plain("Your Apple Health readings stay on your iPhone, and \(brand) only uses what you allow. "
                           + "Change this anytime in Settings › Health. "), .link("Privacy details", .privacy)]
        case .german:
            return [.plain("Deine Apple-Health-Messwerte bleiben auf deinem iPhone, und \(brand) nutzt nur, was du erlaubst. "
                           + "Das kannst du jederzeit unter Einstellungen › Health ändern. "), .link("Datenschutz-Details", .privacy)]
        }
    }

    /// Above the AI Coaching buttons: the explicit consent (privacy policy section 7, Art. 9(2)(a) GDPR).
    public var coachConsent: [OnboardingRun] {
        switch language {
        case .english:
            return [.plain("By turning on AI Coaching you explicitly consent to your health data being processed for it. "
                           + "You can withdraw this anytime in Settings. "), .link("Details", .privacy)]
        case .german:
            return [.plain("Mit dem Einschalten willigst du ausdrücklich ein, dass deine Gesundheitsdaten für das KI-Coaching "
                           + "verarbeitet werden. Du kannst das jederzeit in den Einstellungen widerrufen. "), .link("Details", .privacy)]
        }
    }

    /// The example notification on the notifications step.
    public var notifyBody: [OnboardingRun] {
        switch language {
        case .english: return [.bold("Rest over."), .plain(" Bench Press, set 3 of 4. Go!")]
        case .german: return [.bold("Pause vorbei."), .plain(" Bankdrücken, Satz 3 von 4. Los!")]
        }
    }
}
