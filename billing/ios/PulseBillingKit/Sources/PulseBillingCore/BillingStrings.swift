import Foundation

/// All user-visible text of the paywall and the manage screen, in German and English. The host app can replace any of it
/// (`var strings = BillingStrings.forLocale(); strings.buyButton = "…"`).
///
/// The German purchase texts follow the Button-Lösung (§ 312j BGB: the order button states the payment obligation) and the
/// consent to immediate performance (§ 356 Abs. 5 BGB). They are a draft for legal review, not legal advice.
public struct BillingStrings: Sendable {
    public var paywallTitle: String
    public var paywallSubtitle: String
    public var buyButton: String
    public var buyButtonWithTrial: String
    public var consentText: String
    public var renewalNote: String
    public var taxIncludedNote: String
    public var termsLink: String
    public var privacyLink: String
    public var unavailable: String
    public var working: String
    public var confirming: String
    public var activatedTitle: String
    public var activatedBody: String
    public var pendingTitle: String
    public var pendingBody: String
    public var refresh: String
    public var tryAgain: String
    public var done: String
    public var consentMissing: String
    public var errorNetwork: String
    public var errorGeneric: String
    public var errorSignIn: String
    public var errorRateLimited: String
    public var errorNotAvailable: String

    public var manageTitle: String
    public var manageStatusLabel: String
    public var manageRenews: String
    public var manageEnds: String
    public var manageTrialEnds: String
    public var manageCancel: String
    public var manageResume: String
    public var manageCancelNote: String
    public var managePortal: String
    public var manageNone: String
    public var manageViaCode: String

    public var monthlyPlan: String
    public var yearlyPlan: String
    public var manageCancelConfirm: String
    public var perMonth: String
    public var perYear: String
    public var trialLine: @Sendable (_ days: Int, _ price: String, _ period: String) -> String
    public var statusText: @Sendable (EntitlementStatus) -> String

    public static func forLocale(_ locale: Locale = .current) -> BillingStrings {
        let language = locale.language.languageCode?.identifier ?? "en"
        return language == "de" ? .german : .english
    }

    public static let english = BillingStrings(
        paywallTitle: "Pulse Premium",
        paywallSubtitle: "Unlock the AI coach and personalised training and nutrition plans.",
        buyButton: "Subscribe and pay",
        buyButtonWithTrial: "Start free trial, then pay",
        consentText: "I expressly agree that Pulse starts providing the service before the withdrawal period ends, and I acknowledge that I lose my right of withdrawal once the service has started.",
        renewalNote: "Renews automatically until you cancel. You can cancel at any time under Manage subscription; it then ends after the period you have paid for.",
        taxIncludedNote: "Prices include VAT where it applies.",
        termsLink: "Terms of use",
        privacyLink: "Privacy policy",
        unavailable: "Subscriptions can't be started here.",
        working: "One moment…",
        confirming: "Confirming your payment…",
        activatedTitle: "Premium is active",
        activatedBody: "Thank you. Everything in Premium is unlocked.",
        pendingTitle: "Payment received",
        pendingBody: "Premium is being activated. This can take a moment; you can close this screen.",
        refresh: "Check again",
        tryAgain: "Try again",
        done: "Done",
        consentMissing: "Please confirm the checkbox above to continue.",
        errorNetwork: "No connection. Check your internet and try again.",
        errorGeneric: "Something went wrong. Please try again.",
        errorSignIn: "Please sign in again.",
        errorRateLimited: "Too many attempts. Please wait a minute.",
        errorNotAvailable: "Subscriptions can't be started here.",
        manageTitle: "Your subscription",
        manageStatusLabel: "Status",
        manageRenews: "Renews on",
        manageEnds: "Ends on",
        manageTrialEnds: "Trial ends on",
        manageCancel: "Cancel subscription",
        manageResume: "Keep subscription",
        manageCancelNote: "Your subscription ends after the current period. You keep Premium until then.",
        managePortal: "Payment methods and invoices",
        manageNone: "You don't have a subscription.",
        manageViaCode: "Premium is active through a redeemed code.",
        monthlyPlan: "Monthly",
        yearlyPlan: "Yearly",
        manageCancelConfirm: "Cancel subscription?",
        perMonth: "per month",
        perYear: "per year",
        trialLine: { days, price, period in "Free for \(days) days, then \(price) \(period)." },
        statusText: { status in
            switch status {
            case .active: return "Active"
            case .trialing: return "Free trial"
            case .pastDue: return "Payment overdue"
            case .incomplete: return "Not completed"
            case .unpaid: return "Unpaid"
            case .canceled: return "Canceled"
            case .paused: return "Paused"
            case .none: return "No subscription"
            case .unknown: return "Unknown"
            }
        }
    )

    public static let german = BillingStrings(
        paywallTitle: "Pulse Premium",
        paywallSubtitle: "Schalte den KI-Coach sowie persönliche Trainings- und Ernährungspläne frei.",
        buyButton: "Zahlungspflichtig abonnieren",
        buyButtonWithTrial: "Kostenlos testen, danach zahlungspflichtig",
        consentText: "Ich stimme ausdrücklich zu, dass Pulse vor Ablauf der Widerrufsfrist mit der Ausführung des Vertrags beginnt, und nehme zur Kenntnis, dass ich mit Beginn der Ausführung mein Widerrufsrecht verliere.",
        renewalNote: "Verlängert sich automatisch, bis du kündigst. Du kannst jederzeit unter „Abo verwalten“ kündigen; das Abo endet dann nach dem bezahlten Zeitraum.",
        taxIncludedNote: "Preise inkl. Umsatzsteuer, soweit anfallend.",
        termsLink: "Nutzungsbedingungen",
        privacyLink: "Datenschutz",
        unavailable: "Hier kann kein Abo abgeschlossen werden.",
        working: "Einen Moment…",
        confirming: "Zahlung wird bestätigt…",
        activatedTitle: "Premium ist aktiv",
        activatedBody: "Danke! Alles in Premium ist freigeschaltet.",
        pendingTitle: "Zahlung eingegangen",
        pendingBody: "Premium wird gerade aktiviert. Das kann einen Moment dauern; du kannst diesen Bildschirm schließen.",
        refresh: "Erneut prüfen",
        tryAgain: "Erneut versuchen",
        done: "Fertig",
        consentMissing: "Bitte bestätige das Kästchen oben, um fortzufahren.",
        errorNetwork: "Keine Verbindung. Prüfe dein Internet und versuche es erneut.",
        errorGeneric: "Etwas ist schiefgelaufen. Bitte versuche es erneut.",
        errorSignIn: "Bitte melde dich erneut an.",
        errorRateLimited: "Zu viele Versuche. Bitte warte eine Minute.",
        errorNotAvailable: "Hier kann kein Abo abgeschlossen werden.",
        manageTitle: "Dein Abo",
        manageStatusLabel: "Status",
        manageRenews: "Verlängert sich am",
        manageEnds: "Endet am",
        manageTrialEnds: "Testphase endet am",
        manageCancel: "Abo kündigen",
        manageResume: "Abo behalten",
        manageCancelNote: "Dein Abo endet nach dem laufenden Zeitraum. Bis dahin behältst du Premium.",
        managePortal: "Zahlungsmittel und Rechnungen",
        manageNone: "Du hast kein Abo.",
        manageViaCode: "Premium ist über einen eingelösten Code aktiv.",
        monthlyPlan: "Monatlich",
        yearlyPlan: "Jährlich",
        manageCancelConfirm: "Abo kündigen?",
        perMonth: "pro Monat",
        perYear: "pro Jahr",
        trialLine: { days, price, period in "\(days) Tage kostenlos, danach \(price) \(period)." },
        statusText: { status in
            switch status {
            case .active: return "Aktiv"
            case .trialing: return "Testphase"
            case .pastDue: return "Zahlung überfällig"
            case .incomplete: return "Nicht abgeschlossen"
            case .unpaid: return "Unbezahlt"
            case .canceled: return "Gekündigt"
            case .paused: return "Pausiert"
            case .none: return "Kein Abo"
            case .unknown: return "Unbekannt"
            }
        }
    )

    /// "per month" / "per year" (or "every 3 months" is not offered: only month and year plans exist).
    public func period(of plan: Plan) -> String {
        switch plan.interval {
        case .year: return perYear
        default: return perMonth
        }
    }

    public func title(of plan: Plan) -> String {
        plan.interval == .year ? yearlyPlan : monthlyPlan
    }

    public func message(for failure: PurchaseFailure) -> String {
        switch failure {
        case .consentRequired: return consentMissing
        case .notAvailable: return errorNotAvailable
        case .rateLimited: return errorRateLimited
        case .unauthorized: return errorSignIn
        case .network: return errorNetwork
        case .message(let text): return text.isEmpty ? errorGeneric : text
        }
    }
}
