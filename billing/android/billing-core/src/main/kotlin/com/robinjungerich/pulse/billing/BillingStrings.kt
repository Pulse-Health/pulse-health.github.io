// BillingStrings.kt
// Every user-visible sentence of the billing UI, in German and English, so the strings live in one place for both
// platforms and the UI needs no Android string resources.
//
// Override single strings by delegation:
//
//     val strings = object : BillingStrings by BillingStrings.forLocale(Locale.getDefault()) {
//         override val buyButton = "Jetzt kaufen"
//     }
//
// Sentences built from several strings (failure messages, unavailable messages) are extension functions below, not
// members, so an override of a member is also seen by them.

package com.robinjungerich.pulse.billing

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

interface BillingStrings {
    /** The language of the strings. It is also what the server stores as the consent locale. */
    val locale: Locale

    // MARK: Paywall

    val paywallTitle: String
    val choosePlan: String

    /** "Monthly", "Yearly", "Every 3 months". */
    fun planTitle(plan: Plan): String

    /** "€9.99 / month". [formattedPrice] is the plan's price already formatted for the locale. */
    fun priceLine(formattedPrice: String, plan: Plan): String

    /** "7 days free". */
    fun trialBadge(trialDays: Int): String

    /** What happens after the trial; [priceLine] is the plan's [priceLine]. */
    fun trialNote(trialDays: Int, priceLine: String): String
    val taxInclusiveNote: String
    val taxExclusiveNote: String
    fun renewalNote(priceLine: String): String
    val termsLink: String
    val privacyLink: String

    /** The consent to immediate performance and the loss of the right of withdrawal, shown next to the buy button. */
    val withdrawalConsent: String
    val consentRequiredHint: String

    /** Must state that the order creates an obligation to pay. */
    val buyButton: String
    val retry: String
    val done: String

    /** Spoken by screen readers on links that leave the app. */
    val opensInBrowser: String
    val loadingOffers: String
    val preparing: String
    val awaitingPayment: String
    val confirming: String
    val activated: String
    val pendingActivation: String
    val canceled: String

    /** Neutral by design: no link or hint to buy elsewhere. */
    val unavailable: String
    val alreadySubscribed: String

    // MARK: Manage

    val manageTitle: String
    val loadingStatus: String
    fun status(status: EntitlementStatus): String
    fun renewsOn(date: String): String
    fun endsOn(date: String): String
    fun trialEndsOn(date: String): String
    val pastDueNote: String
    val noSubscription: String

    /** Premium that does not come from a Stripe subscription (an access code), so there is nothing to cancel. */
    val premiumWithoutSubscription: String
    val cancelSubscription: String
    val undoCancellation: String
    val cancelConfirmTitle: String
    fun cancelConfirmBody(endDate: String?): String
    val cancelConfirmKeep: String
    val managePayments: String
    fun lastKnownStatus(date: String): String

    // MARK: Errors

    val errorNetwork: String
    val errorUnauthorized: String
    val errorRateLimited: String
    val errorPaymentFailed: String
    val errorGeneric: String

    companion object {
        /** German for German locales, English for everything else. */
        fun forLocale(locale: Locale = Locale.getDefault()): BillingStrings =
            if (locale.language == "de") GermanBillingStrings(locale) else EnglishBillingStrings(
                if (locale.language == "en") locale else Locale.ENGLISH,
            )
    }
}

// MARK: - Derived sentences

fun BillingStrings.formatDate(instant: Instant, zone: ZoneId = ZoneId.systemDefault()): String =
    DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG).withLocale(locale).format(instant.atZone(zone))

fun BillingStrings.unavailableMessage(reason: UnavailableReason?): String =
    if (reason == UnavailableReason.ALREADY_SUBSCRIBED) alreadySubscribed else unavailable

fun BillingStrings.failureMessage(failure: PurchaseFailure): String = when (failure) {
    PurchaseFailure.ConsentRequired -> consentRequiredHint
    PurchaseFailure.Network -> errorNetwork
    is PurchaseFailure.Payment -> failure.message?.takeIf { it.isNotBlank() } ?: errorPaymentFailed
    is PurchaseFailure.Server -> errorFor(failure.code)
    PurchaseFailure.Unexpected -> errorGeneric
}

fun BillingStrings.errorMessage(error: BillingError): String = when (error) {
    is BillingError.Api -> errorFor(error.code)
    is BillingError.Network -> errorNetwork
    is BillingError.Decoding -> errorGeneric
}

private fun BillingStrings.errorFor(code: ErrorCode): String = when (code) {
    ErrorCode.UNAUTHORIZED -> errorUnauthorized
    ErrorCode.RATE_LIMITED -> errorRateLimited
    ErrorCode.ALREADY_SUBSCRIBED -> alreadySubscribed
    ErrorCode.PURCHASE_NOT_AVAILABLE -> unavailable
    ErrorCode.CONSENT_REQUIRED -> consentRequiredHint
    else -> errorGeneric
}

// MARK: - English

open class EnglishBillingStrings(override val locale: Locale = Locale.ENGLISH) : BillingStrings {
    override val paywallTitle = "Pulse Premium"
    override val choosePlan = "Choose your plan"

    override fun planTitle(plan: Plan) = when {
        plan.intervalCount == 1 && plan.interval == PlanInterval.MONTH -> "Monthly"
        plan.intervalCount == 1 && plan.interval == PlanInterval.YEAR -> "Yearly"
        else -> "Every ${period(plan)}"
    }

    override fun priceLine(formattedPrice: String, plan: Plan) =
        if (plan.intervalCount == 1) "$formattedPrice / ${period(plan)}" else "$formattedPrice every ${period(plan)}"

    override fun trialBadge(trialDays: Int) = "${days(trialDays)} free"

    override fun trialNote(trialDays: Int, priceLine: String) =
        "Free for the first ${days(trialDays)}, then $priceLine. Cancel before the trial ends and you will not be charged."

    override val taxInclusiveNote = "Price includes applicable taxes."
    override val taxExclusiveNote = "Applicable taxes are added."

    override fun renewalNote(priceLine: String) =
        "Renews automatically at $priceLine until you cancel. You can cancel at any time in the app; " +
            "Premium then stays active until the end of the period you have paid for."

    override val termsLink = "Terms of Service"
    override val privacyLink = "Privacy Policy"
    override val withdrawalConsent =
        "I expressly agree that Pulse starts providing the service immediately, and I acknowledge that I lose my right of withdrawal."
    override val consentRequiredHint = "Please confirm the checkbox to continue."
    override val buyButton = "Subscribe with obligation to pay"
    override val retry = "Try again"
    override val done = "Done"
    override val opensInBrowser = "Opens in the browser"
    override val loadingOffers = "Loading plans…"
    override val preparing = "Preparing your subscription…"
    override val awaitingPayment = "Waiting for the payment…"
    override val confirming = "Confirming your payment…"
    override val activated = "You are all set. Pulse Premium is active."
    override val pendingActivation =
        "Thank you, your payment went through. Activating Premium can take a moment; it will show up here shortly."
    override val canceled = "Payment canceled. Nothing was charged."
    override val unavailable = "Pulse Premium is currently not available."
    override val alreadySubscribed = "You already have a Pulse Premium subscription."

    override val manageTitle = "Subscription"
    override val loadingStatus = "Loading your subscription…"

    override fun status(status: EntitlementStatus) = when (status) {
        EntitlementStatus.NONE -> "No subscription"
        EntitlementStatus.TRIALING -> "Free trial"
        EntitlementStatus.ACTIVE -> "Active"
        EntitlementStatus.PAST_DUE -> "Payment overdue"
        EntitlementStatus.INCOMPLETE -> "Not completed"
        EntitlementStatus.UNPAID -> "Unpaid"
        EntitlementStatus.CANCELED -> "Canceled"
        EntitlementStatus.PAUSED -> "Paused"
        EntitlementStatus.UNKNOWN -> "Unknown"
    }

    override fun renewsOn(date: String) = "Renews on $date"
    override fun endsOn(date: String) = "Premium ends on $date"
    override fun trialEndsOn(date: String) = "Free trial ends on $date"
    override val pastDueNote = "Your last payment did not go through. Update your payment method to keep Premium."
    override val noSubscription = "You do not have an active subscription."
    override val premiumWithoutSubscription = "Premium is active on your account."
    override val cancelSubscription = "Cancel subscription"
    override val undoCancellation = "Undo cancellation"
    override val cancelConfirmTitle = "Cancel subscription?"

    override fun cancelConfirmBody(endDate: String?) =
        if (endDate != null) "Premium stays active until $endDate. After that you will not be charged again."
        else "Premium stays active until the end of the period you have paid for. After that you will not be charged again."

    override val cancelConfirmKeep = "Keep subscription"
    override val managePayments = "Payment methods and invoices"
    override fun lastKnownStatus(date: String) = "You are offline. Showing the status from $date."

    override val errorNetwork = "No connection. Check your internet connection and try again."
    override val errorUnauthorized = "Please sign in again."
    override val errorRateLimited = "Too many attempts. Please wait a minute and try again."
    override val errorPaymentFailed = "The payment could not be completed. Please try again or use a different payment method."
    override val errorGeneric = "Something went wrong. Please try again later."

    private fun period(plan: Plan): String {
        val unit = when (plan.interval) {
            PlanInterval.MONTH -> "month"
            PlanInterval.YEAR -> "year"
            PlanInterval.UNKNOWN -> "period"
        }
        return if (plan.intervalCount == 1) unit else "${plan.intervalCount} ${unit}s"
    }

    private fun days(count: Int) = if (count == 1) "1 day" else "$count days"
}

// MARK: - German

open class GermanBillingStrings(override val locale: Locale = Locale.GERMAN) : BillingStrings {
    override val paywallTitle = "Pulse Premium"
    override val choosePlan = "Wähle dein Abo"

    override fun planTitle(plan: Plan) = when {
        plan.intervalCount == 1 && plan.interval == PlanInterval.MONTH -> "Monatlich"
        plan.intervalCount == 1 && plan.interval == PlanInterval.YEAR -> "Jährlich"
        else -> "Alle ${period(plan)}"
    }

    override fun priceLine(formattedPrice: String, plan: Plan) =
        if (plan.intervalCount == 1) "$formattedPrice / ${period(plan)}" else "$formattedPrice alle ${period(plan)}"

    override fun trialBadge(trialDays: Int) = "${days(trialDays)} kostenlos"

    override fun trialNote(trialDays: Int, priceLine: String) =
        "Die ersten ${days(trialDays)} kostenlos, danach $priceLine. Wenn du vor Ende der Testphase kündigst, entstehen keine Kosten."

    override val taxInclusiveNote = "Preis inkl. gesetzlicher Umsatzsteuer."
    override val taxExclusiveNote = "Zzgl. gesetzlicher Umsatzsteuer."

    override fun renewalNote(priceLine: String) =
        "Das Abo verlängert sich automatisch zu $priceLine, bis du kündigst. Du kannst jederzeit in der App kündigen; " +
            "Premium bleibt dann bis zum Ende des bezahlten Zeitraums aktiv."

    override val termsLink = "AGB"
    override val privacyLink = "Datenschutzerklärung"
    override val withdrawalConsent =
        "Ich stimme ausdrücklich zu, dass Pulse sofort mit der Ausführung des Vertrags beginnt, und nehme zur Kenntnis, dass ich mein Widerrufsrecht verliere."
    override val consentRequiredHint = "Bitte bestätige das Kästchen, um fortzufahren."
    override val buyButton = "Zahlungspflichtig abonnieren"
    override val retry = "Erneut versuchen"
    override val done = "Fertig"
    override val opensInBrowser = "Öffnet im Browser"
    override val loadingOffers = "Angebote werden geladen…"
    override val preparing = "Abo wird vorbereitet…"
    override val awaitingPayment = "Warten auf die Zahlung…"
    override val confirming = "Zahlung wird bestätigt…"
    override val activated = "Geschafft. Pulse Premium ist aktiv."
    override val pendingActivation =
        "Danke, deine Zahlung ist eingegangen. Die Freischaltung von Premium kann einen Moment dauern; sie erscheint gleich hier."
    override val canceled = "Zahlung abgebrochen. Es wurde nichts berechnet."
    override val unavailable = "Pulse Premium ist derzeit nicht verfügbar."
    override val alreadySubscribed = "Du hast bereits ein Pulse-Premium-Abo."

    override val manageTitle = "Abo"
    override val loadingStatus = "Dein Abo wird geladen…"

    override fun status(status: EntitlementStatus) = when (status) {
        EntitlementStatus.NONE -> "Kein Abo"
        EntitlementStatus.TRIALING -> "Testphase"
        EntitlementStatus.ACTIVE -> "Aktiv"
        EntitlementStatus.PAST_DUE -> "Zahlung überfällig"
        EntitlementStatus.INCOMPLETE -> "Nicht abgeschlossen"
        EntitlementStatus.UNPAID -> "Unbezahlt"
        EntitlementStatus.CANCELED -> "Gekündigt"
        EntitlementStatus.PAUSED -> "Pausiert"
        EntitlementStatus.UNKNOWN -> "Unbekannt"
    }

    override fun renewsOn(date: String) = "Verlängert sich am $date"
    override fun endsOn(date: String) = "Premium endet am $date"
    override fun trialEndsOn(date: String) = "Testphase endet am $date"
    override val pastDueNote = "Deine letzte Zahlung ist fehlgeschlagen. Aktualisiere deine Zahlungsmethode, um Premium zu behalten."
    override val noSubscription = "Du hast kein aktives Abo."
    override val premiumWithoutSubscription = "Premium ist für dein Konto aktiv."
    override val cancelSubscription = "Abo kündigen"
    override val undoCancellation = "Kündigung zurücknehmen"
    override val cancelConfirmTitle = "Abo kündigen?"

    override fun cancelConfirmBody(endDate: String?) =
        if (endDate != null) "Premium bleibt bis zum $endDate aktiv. Danach wird nichts mehr berechnet."
        else "Premium bleibt bis zum Ende des bezahlten Zeitraums aktiv. Danach wird nichts mehr berechnet."

    override val cancelConfirmKeep = "Abo behalten"
    override val managePayments = "Zahlungsmethoden und Rechnungen"
    override fun lastKnownStatus(date: String) = "Du bist offline. Angezeigt wird der Stand vom $date."

    override val errorNetwork = "Keine Verbindung. Prüfe deine Internetverbindung und versuche es erneut."
    override val errorUnauthorized = "Bitte melde dich erneut an."
    override val errorRateLimited = "Zu viele Versuche. Bitte warte eine Minute und versuche es erneut."
    override val errorPaymentFailed = "Die Zahlung konnte nicht abgeschlossen werden. Bitte versuche es erneut oder nutze eine andere Zahlungsmethode."
    override val errorGeneric = "Etwas ist schiefgelaufen. Bitte versuche es später erneut."

    private fun period(plan: Plan): String {
        val count = plan.intervalCount
        return when (plan.interval) {
            PlanInterval.MONTH -> if (count == 1) "Monat" else "$count Monate"
            PlanInterval.YEAR -> if (count == 1) "Jahr" else "$count Jahre"
            PlanInterval.UNKNOWN -> "Zeitraum"
        }
    }

    private fun days(count: Int) = if (count == 1) "1 Tag" else "$count Tage"
}
