// Models.kt
// The wire models of billing/contract/openapi.yaml. Field names are the contract's; enums decode unknown values to
// UNKNOWN (see WireSerializers.kt), unknown fields are ignored (see BillingJson).

@file:UseSerializers(InstantIso8601Serializer::class)

package com.robinjungerich.pulse.billing

import kotlinx.serialization.Serializable
import kotlinx.serialization.UseSerializers
import java.time.Instant

@Serializable(with = PlatformSerializer::class)
enum class Platform(override val wire: String) : WireEnum {
    IOS("ios"),
    ANDROID("android"),
    UNKNOWN("unknown"),
}

internal object PlatformSerializer : WireEnumSerializer<Platform>("Platform", Platform.entries, Platform.UNKNOWN)

// MARK: - Offers

@Serializable(with = UnavailableReasonSerializer::class)
enum class UnavailableReason(override val wire: String) : WireEnum {
    BILLING_DISABLED("billing_disabled"),
    PLATFORM_NOT_SUPPORTED("platform_not_supported"),
    REGION_NOT_SUPPORTED("region_not_supported"),
    ALREADY_SUBSCRIBED("already_subscribed"),
    UNKNOWN("unknown"),
}

internal object UnavailableReasonSerializer :
    WireEnumSerializer<UnavailableReason>("UnavailableReason", UnavailableReason.entries, UnavailableReason.UNKNOWN)

@Serializable
data class PurchaseAvailability(
    val available: Boolean,
    /** Present when [available] is false. */
    val reason: UnavailableReason? = null,
)

@Serializable(with = PlanIntervalSerializer::class)
enum class PlanInterval(override val wire: String) : WireEnum {
    MONTH("month"),
    YEAR("year"),
    UNKNOWN("unknown"),
}

internal object PlanIntervalSerializer :
    WireEnumSerializer<PlanInterval>("PlanInterval", PlanInterval.entries, PlanInterval.UNKNOWN)

@Serializable(with = TaxBehaviorSerializer::class)
enum class TaxBehavior(override val wire: String) : WireEnum {
    INCLUSIVE("inclusive"),
    EXCLUSIVE("exclusive"),
    UNSPECIFIED("unspecified"),
    UNKNOWN("unknown"),
}

internal object TaxBehaviorSerializer :
    WireEnumSerializer<TaxBehavior>("TaxBehavior", TaxBehavior.entries, TaxBehavior.UNKNOWN)

@Serializable
data class Plan(
    /** Stable plan id = the Stripe price lookup_key, e.g. `premium_monthly`. */
    val id: String,
    val name: String,
    val interval: PlanInterval,
    val intervalCount: Int,
    /** Lower-case ISO 4217, as Stripe reports it. */
    val currency: String,
    /** Minor units of [currency]. */
    val unitAmount: Long,
    val taxBehavior: TaxBehavior,
    /** 0 when no trial is offered to this user. */
    val trialDays: Int,
) {
    val hasTrial: Boolean get() = trialDays > 0
}

@Serializable
data class Offers(
    val purchase: PurchaseAvailability,
    /** The buyer must expressly consent to immediate performance and the loss of the right of withdrawal. */
    val requiresWithdrawalConsent: Boolean,
    val publishableKey: String,
    val merchantDisplayName: String,
    val plans: List<Plan>,
)

// MARK: - Entitlement

@Serializable(with = EntitlementStatusSerializer::class)
enum class EntitlementStatus(override val wire: String) : WireEnum {
    NONE("none"),
    TRIALING("trialing"),
    ACTIVE("active"),
    PAST_DUE("past_due"),
    INCOMPLETE("incomplete"),
    UNPAID("unpaid"),
    CANCELED("canceled"),
    PAUSED("paused"),
    UNKNOWN("unknown"),
}

internal object EntitlementStatusSerializer :
    WireEnumSerializer<EntitlementStatus>("EntitlementStatus", EntitlementStatus.entries, EntitlementStatus.UNKNOWN)

@Serializable(with = EntitlementSourceSerializer::class)
enum class EntitlementSource(override val wire: String) : WireEnum {
    NONE("none"),
    STRIPE("stripe"),
    CODE("code"),

    /** A source added after this client was built; [Entitlement.premium] still says what the user gets. */
    UNKNOWN("unknown"),
}

internal object EntitlementSourceSerializer :
    WireEnumSerializer<EntitlementSource>("EntitlementSource", EntitlementSource.entries, EntitlementSource.UNKNOWN)

@Serializable
data class Entitlement(
    val premium: Boolean,
    val status: EntitlementStatus,
    val planId: String? = null,
    val source: EntitlementSource,
    val currentPeriodEnd: Instant? = null,
    val cancelAtPeriodEnd: Boolean,
    val trialEnd: Instant? = null,
    /** Until when a client may treat the user as Premium without asking the server. Null when not premium. */
    val premiumUntil: Instant? = null,
) {
    companion object {
        val NONE = Entitlement(
            premium = false,
            status = EntitlementStatus.NONE,
            source = EntitlementSource.NONE,
            cancelAtPeriodEnd = false,
        )
    }
}

@Serializable
data class EntitlementResponse(
    val entitlement: Entitlement,
    val serverTime: Instant,
)

// MARK: - Subscriptions

/** The consent the buyer gave next to the buy button; required when [Offers.requiresWithdrawalConsent]. */
@Serializable
data class WithdrawalConsent(
    val withdrawalWaiver: Boolean,
    /** BCP 47 language of the text the buyer saw, e.g. `de-DE`. */
    val locale: String,
)

@Serializable
internal data class CreateSubscriptionRequest(
    val planId: String,
    val platform: Platform,
    val country: String? = null,
    val billingCountry: String? = null,
    val consent: WithdrawalConsent? = null,
)

@Serializable(with = IntentKindSerializer::class)
enum class IntentKind(override val wire: String) : WireEnum {
    /** Charge now. */
    PAYMENT("payment"),

    /** Collect a payment method, charge nothing now (free trial). */
    SETUP("setup"),
    UNKNOWN("unknown"),
}

internal object IntentKindSerializer : WireEnumSerializer<IntentKind>("IntentKind", IntentKind.entries, IntentKind.UNKNOWN)

@Serializable
data class StripeIntent(
    val kind: IntentKind,
    val clientSecret: String,
) {
    override fun toString() = "StripeIntent(kind=$kind, clientSecret=<redacted>)"
}

@Serializable
data class CreateSubscriptionResponse(
    val subscriptionId: String,
    /** Stripe's status string; informational only, the entitlement is the source of truth. */
    val status: String,
    val customerId: String,
    val customerEphemeralKeySecret: String,
    val publishableKey: String,
    /** Null when there is nothing to collect (for example a resumed subscription that is already paid). */
    val intent: StripeIntent? = null,
) {
    override fun toString() =
        "CreateSubscriptionResponse(subscriptionId=$subscriptionId, status=$status, customerId=$customerId, " +
            "customerEphemeralKeySecret=<redacted>, publishableKey=$publishableKey, intent=$intent)"
}

// MARK: - Portal, account

@Serializable
internal data class PortalRequest(val returnUrl: String)

@Serializable
internal data class PortalResponse(val url: String)

@Serializable
internal data class AccountDeletedResponse(val deleted: Boolean)

// MARK: - Errors

@Serializable(with = ErrorCodeSerializer::class)
enum class ErrorCode(override val wire: String) : WireEnum {
    UNAUTHORIZED("unauthorized"),
    INVALID_REQUEST("invalid_request"),
    CONSENT_REQUIRED("consent_required"),
    PURCHASE_NOT_AVAILABLE("purchase_not_available"),
    PLAN_NOT_FOUND("plan_not_found"),
    ALREADY_SUBSCRIBED("already_subscribed"),
    NO_SUBSCRIPTION("no_subscription"),
    NO_CUSTOMER("no_customer"),
    RATE_LIMITED("rate_limited"),
    STRIPE_ERROR("stripe_error"),
    INTERNAL("internal"),

    /** A code added after this client was built, or a response that was not the contract's error body. */
    UNKNOWN("unknown"),
}

internal object ErrorCodeSerializer : WireEnumSerializer<ErrorCode>("ErrorCode", ErrorCode.entries, ErrorCode.UNKNOWN)

@Serializable
internal data class ErrorResponse(val error: ErrorBody) {
    @Serializable
    data class ErrorBody(val code: ErrorCode, val message: String = "")
}
