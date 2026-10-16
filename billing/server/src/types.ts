// Domain types shared by the service, the stores and the HTTP layer. The wire format (what the apps see) is
// `EntitlementDto` and friends; it mirrors billing/contract/openapi.yaml.

export type Platform = 'ios' | 'android';

/** What the apps see. Keep in sync with the `Entitlement` schema in contract/openapi.yaml. */
export type EntitlementStatus =
  | 'none'
  | 'trialing'
  | 'active'
  | 'past_due'
  | 'incomplete'
  | 'unpaid'
  | 'canceled'
  | 'paused';

export interface EntitlementDto {
  premium: boolean;
  status: EntitlementStatus;
  planId: string | null;
  /** `code` is for entitlements that come from another source (for example Premium codes) via `extraEntitlements`. */
  source: 'none' | 'stripe' | 'code';
  currentPeriodEnd: string | null;
  cancelAtPeriodEnd: boolean;
  trialEnd: string | null;
  premiumUntil: string | null;
}

export interface PlanDto {
  id: string;
  name: string;
  interval: 'month' | 'year';
  intervalCount: number;
  currency: string;
  unitAmount: number;
  taxBehavior: 'inclusive' | 'exclusive' | 'unspecified';
  trialDays: number;
}

export type PurchaseUnavailableReason =
  | 'billing_disabled'
  | 'platform_not_supported'
  | 'region_not_supported'
  | 'already_subscribed';

export interface PurchaseAvailability {
  available: boolean;
  reason: PurchaseUnavailableReason | null;
}

/** A recurring Stripe price that is one of our plans (found by lookup_key). */
export interface StripePlan {
  id: string; // lookup_key
  priceId: string;
  name: string;
  interval: 'month' | 'year';
  intervalCount: number;
  currency: string;
  unitAmount: number;
  taxBehavior: 'inclusive' | 'exclusive' | 'unspecified';
}

/** A subscription as we store it (one row per Stripe subscription). */
export interface SubscriptionRecord {
  stripeSubscriptionId: string;
  userId: string;
  stripeCustomerId: string;
  status: string; // Stripe's status string
  planId: string | null;
  priceId: string;
  currency: string | null;
  unitAmount: number | null;
  currentPeriodEnd: Date | null;
  cancelAtPeriodEnd: boolean;
  canceledAt: Date | null;
  trialEnd: Date | null;
  /**
   * False while a trial has been created but no payment method has been collected yet (the user dismissed the
   * payment sheet). Such a trial must not unlock Premium, otherwise opening and closing the sheet would be a free trial.
   */
  paymentMethodAttached: boolean;
  /** Stripe's `created`. */
  createdAt: Date;
  /**
   * When we read this state from Stripe. A write with an older value than the stored one is discarded, which
   * makes webhook deliveries and /sync calls safe to run concurrently and out of order.
   */
  fetchedAt: Date;
}

/** What the gateway returns for a subscription read from Stripe (no user attached yet). */
export interface SubscriptionSnapshot extends Omit<SubscriptionRecord, 'userId' | 'fetchedAt'> {
  /** `metadata.clerk_user_id` as we wrote it at creation time. */
  clerkUserId: string | null;
  /** From `latest_invoice.confirmation_secret`, when the first payment is still open. */
  paymentClientSecret: string | null;
  /** From `pending_setup_intent`, when a trial needs a payment method. */
  setupClientSecret: string | null;
}

export class BillingError extends Error {
  constructor(
    readonly code:
      | 'unauthorized'
      | 'invalid_request'
      | 'consent_required'
      | 'purchase_not_available'
      | 'plan_not_found'
      | 'already_subscribed'
      | 'no_subscription'
      | 'no_customer'
      | 'rate_limited'
      | 'stripe_error'
      | 'internal',
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = 'BillingError';
  }
}

/** A Stripe webhook event reduced to what the service needs. */
export interface StripeEventSummary {
  id: string;
  type: string;
  /** The subscription the event is about, if any (subscription events and invoice events). */
  subscriptionId: string | null;
  customerId: string | null;
}
