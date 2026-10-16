import XCTest
@testable import PulseStrengthCore

/// The words of the onboarding in English and German, and what is built from them (OnboardingCopy*.swift, OnboardingSummary.swift).
final class OnboardingCopyTests: XCTestCase {
    private let english = OnboardingCopy(language: .english)
    private let german = OnboardingCopy(language: .german)

    // MARK: Plain strings

    func testEveryTextExistsInBothLanguages() {
        XCTAssertGreaterThan(OnboardingText.allCases.count, 100)
        for key in OnboardingText.allCases {
            for copy in [english, german] {
                let value = copy.text(key)
                XCTAssertFalse(value.isEmpty, "\(key) in \(copy.language)")
                XCTAssertEqual(value, value.trimmingCharacters(in: .whitespacesAndNewlines), "\(key) in \(copy.language) has stray spaces")
                for forbidden in ["{", "}", "<", ">", "\\("] {
                    XCTAssertFalse(value.contains(forbidden), "\(key) in \(copy.language) contains '\(forbidden)': \(value)")
                }
            }
        }
    }

    /// A string that is the same in both languages is usually an untranslated one. These are the ones that really are the same.
    func testGermanIsTranslatedExceptWhereItReallyIsTheSame() {
        let sameInBothLanguages: Set<OnboardingText> = [.previewRestBpm, .previewRecordMeta, .healthWorkouts, .healthWatch, .healthOptional, .notifyApp]
        for key in OnboardingText.allCases {
            if sameInBothLanguages.contains(key) {
                XCTAssertEqual(english.text(key), german.text(key), "\(key) was expected to be identical")
            } else {
                XCTAssertNotEqual(english.text(key), german.text(key), "\(key) looks untranslated: \(english.text(key))")
            }
        }
    }

    func testTheBrandNameComesFromOneConstant() {
        XCTAssertEqual(OnboardingBrand.name, "Rebase")
        XCTAssertTrue(english.text(.welcomeHeading).contains(OnboardingBrand.name))
        XCTAssertTrue(german.text(.welcomeHeading).contains(OnboardingBrand.name))
        XCTAssertEqual(english.text(.notifyApp), OnboardingBrand.name)
        XCTAssertTrue(english.text(.healthSub).hasPrefix(OnboardingBrand.name))
        XCTAssertTrue(german.text(.profileSub).contains(OnboardingBrand.name))
        for copy in [english, german] {
            for key in OnboardingText.allCases {
                XCTAssertFalse(copy.text(key).contains("Pulse"), "\(key) still names the old product: \(copy.text(key))")
            }
        }
    }

    func testCallAsFunctionIsTheSameAsText() {
        XCTAssertEqual(english(.welcomeStart), "Get started")
        XCTAssertEqual(german(.welcomeStart), "Los geht’s")
        XCTAssertEqual(english(.coachOff), "No thanks")
        XCTAssertEqual(german(.coachOff), "Nein, danke")
    }

    // MARK: Language

    func testLanguageFollowsThePreferredLanguages() {
        XCTAssertEqual(OnboardingLanguage.resolve(preferredLanguages: ["de-DE", "en-US"]), .german)
        XCTAssertEqual(OnboardingLanguage.resolve(preferredLanguages: ["en-GB", "de"]), .english)
        XCTAssertEqual(OnboardingLanguage.resolve(preferredLanguages: ["fr-FR", "de-DE"]), .german, "the first supported language wins")
        XCTAssertEqual(OnboardingLanguage.resolve(preferredLanguages: ["de_AT"]), .german)
        XCTAssertEqual(OnboardingLanguage.resolve(preferredLanguages: ["DE-de"]), .german)
        XCTAssertEqual(OnboardingLanguage.resolve(preferredLanguages: ["fr", "ja"]), .english)
        XCTAssertEqual(OnboardingLanguage.resolve(preferredLanguages: []), .english)
        XCTAssertEqual(OnboardingCopy(preferredLanguages: ["de"]).language, .german)
    }

    // MARK: Parameters

    func testTextsWithParameters() {
        XCTAssertEqual(english.highlightPosition(2, of: 3), "2 of 3")
        XCTAssertEqual(german.highlightPosition(2, of: 3), "2 von 3")
        XCTAssertEqual(english.showHighlight(1, of: 3), "Show highlight 1 of 3")
        XCTAssertEqual(german.showHighlight(1, of: 3), "Highlight 1 von 3 anzeigen")
        XCTAssertEqual(english.setupProgress(3, of: 4), "Setup progress, step 3 of 4")
        XCTAssertEqual(german.setupProgress(3, of: 4), "Einrichtung, Schritt 3 von 4")
    }

    // MARK: Account messages

    func testEveryAccountErrorHasAMessageInBothLanguagesExceptCancelling() {
        for copy in [english, german] {
            XCTAssertNil(copy.authMessage(for: .cancelled), "the user closed the sheet; nothing to say")
            let messages = [OnboardingAuthError.invalidCredentials, .accountExists, .failed].map { copy.authMessage(for: $0) }
            for message in messages {
                XCTAssertFalse((message ?? "").isEmpty, "\(copy.language)")
            }
            XCTAssertEqual(Set(messages.map { $0 ?? "" }).count, 3, "the three messages differ")
            XCTAssertFalse(copy.authForgotSent.isEmpty)
        }
        XCTAssertNotEqual(english.authMessage(for: .failed), german.authMessage(for: .failed))
        XCTAssertNotEqual(english.authForgotSent, german.authForgotSent)
    }

    func testTheKeyboardHasADoneButtonInBothLanguages() {
        XCTAssertEqual(english.keyboardDone, "Done")
        XCTAssertEqual(german.keyboardDone, "Fertig")
    }

    func testTheResetNoticeDoesNotRevealWhetherTheAccountExists() {
        XCTAssertTrue(english.authForgotSent.hasPrefix("If there is an account"))
        XCTAssertTrue(german.authForgotSent.hasPrefix("Falls es ein Konto"))
    }

    // MARK: Sentences with links and bold parts

    func testLegalSentencesLinkTheTermsAndThePrivacyPolicy() {
        for copy in [english, german] {
            for sentence in [copy.legalWelcome, copy.legalSignup] {
                let documents = sentence.compactMap { run -> LegalDocument? in
                    if case .link(let document) = run.style { return document }
                    return nil
                }
                XCTAssertEqual(documents, [.terms, .privacy], "\(copy.language)")
                XCTAssertTrue(sentence.plainText.hasSuffix("."), sentence.plainText)
            }
        }
        XCTAssertEqual(english.legalWelcome.plainText, "By continuing you agree to our Terms and acknowledge our Privacy Policy.")
        XCTAssertEqual(german.legalSignup.plainText, "Mit der Kontoerstellung akzeptierst du unsere AGB und nimmst die Datenschutzerklärung zur Kenntnis.")
    }

    func testHealthAndConsentSentencesEndWithAPrivacyLink() {
        for copy in [english, german] {
            XCTAssertEqual(copy.healthNote.last?.style, .link(.privacy), "\(copy.language)")
            XCTAssertEqual(copy.coachConsent.last?.style, .link(.privacy), "\(copy.language)")
        }
        XCTAssertTrue(english.healthNote.plainText.contains("stays on your iPhone"))
        XCTAssertTrue(german.healthNote.plainText.contains("bleiben auf deinem iPhone"))
    }

    func testTheConsentSentenceSaysItIsExplicitAndWithdrawable() {
        XCTAssertTrue(english.coachConsent.plainText.contains("explicitly consent"))
        XCTAssertTrue(english.coachConsent.plainText.contains("withdraw"))
        XCTAssertTrue(german.coachConsent.plainText.contains("ausdrücklich"))
        XCTAssertTrue(german.coachConsent.plainText.contains("widerrufen"))
    }

    func testTheNotificationExampleStartsWithABoldLead() {
        XCTAssertEqual(english.notifyBody.first, .bold("Rest over."))
        XCTAssertEqual(german.notifyBody.first, .bold("Pause vorbei."))
        XCTAssertEqual(english.notifyBody.plainText, "Rest over. Bench Press, set 3 of 4. Go!")
    }

    // MARK: Legal pages

    func testLegalLinksPointAtTheMatchingPagesOfTheWebsite() {
        XCTAssertEqual(english.legalURL(.terms).absoluteString, "https://pulse-health.github.io/terms.html")
        XCTAssertEqual(english.legalURL(.privacy).absoluteString, "https://pulse-health.github.io/privacy-policy.html")
        XCTAssertEqual(german.legalURL(.terms).absoluteString, "https://pulse-health.github.io/agb.html")
        XCTAssertEqual(german.legalURL(.privacy).absoluteString, "https://pulse-health.github.io/datenschutz.html")
    }

    // MARK: Summary

    func testSummaryShowsWhatWasChosenAndMutesTheRest() {
        let answers = OnboardingAnswers(
            goal: .strength, level: .intermediate, healthConnected: true, aiCoachingEnabled: false, notificationsEnabled: true
        )
        let items = OnboardingSummary.items(for: answers, copy: english)
        XCTAssertEqual(items.map { $0.text }, ["Build strength", "Intermediate", "Apple Health connected", "AI Coaching off", "Notifications on"])
        XCTAssertEqual(items.map { $0.isOn }, [true, true, true, false, true])

        let germanItems = OnboardingSummary.items(for: answers, copy: german)
        XCTAssertEqual(germanItems.map { $0.text }, ["Kraft aufbauen", "Fortgeschritten", "Apple Health verbunden", "KI-Coaching aus", "Mitteilungen an"])
    }

    func testSummaryTreatsUnansweredQuestionsAsLaterOrOff() {
        let items = OnboardingSummary.items(for: OnboardingAnswers(), copy: english)
        XCTAssertEqual(items.map { $0.text }, ["Apple Health: later", "AI Coaching off", "Notifications: later"])
        XCTAssertEqual(items.map { $0.isOn }, [false, false, false])
    }

    func testEveryGoalAndLevelHasATitleAndASubtitle() {
        for copy in [english, german] {
            for goal in TrainingGoal.allCases {
                XCTAssertFalse(copy.text(OnboardingSummary.goalText(goal)).isEmpty)
                XCTAssertFalse(copy.text(OnboardingSummary.goalSubtitleText(goal)).isEmpty)
            }
            for level in ExperienceLevel.allCases {
                XCTAssertFalse(copy.text(OnboardingSummary.levelText(level)).isEmpty)
            }
        }
    }
}
