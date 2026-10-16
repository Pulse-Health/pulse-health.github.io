import type { SubscriptionRecord } from './types.js';

/** Outcome of trying to start processing a webhook event. */
export type ClaimResult =
  /** First delivery, or a retry after a failure: process it. */
  | 'claimed'
  /** Already processed successfully: acknowledge and do nothing. */
  | 'done'
  /** Another delivery of the same event is being processed right now: ask Stripe to retry later. */
  | 'busy';

/**
 * Persistence used by the billing service. Two implementations: `PgBillingStore` (production) and
 * `MemoryBillingStore` (tests). The contract tests in test/store.contract.ts run against both.
 */
export interface BillingStore {
  /** Stripe customer id of the user, if one was created. */
  getCustomerId(userId: string): Promise<string | null>;
  /** The user a Stripe customer belongs to. */
  getUserId(stripeCustomerId: string): Promise<string | null>;
  /** Stores the pairing unless the user already has one; returns the customer id that is stored afterwards. */
  insertCustomer(userId: string, stripeCustomerId: string): Promise<string>;

  /**
   * Inserts or updates a subscription. Returns false (and changes nothing) when a row with a NEWER `fetchedAt`
   * is already stored, so that a slow, older read of Stripe can never overwrite a newer one.
   */
  upsertSubscription(record: SubscriptionRecord): Promise<boolean>;
  listSubscriptions(userId: string): Promise<SubscriptionRecord[]>;

  claimEvent(eventId: string, eventType: string, now: Date, lockMs: number): Promise<ClaimResult>;
  completeEvent(eventId: string, now: Date): Promise<void>;
  /** Releases the claim immediately so that Stripe's retry can process the event. */
  failEvent(eventId: string, error: string): Promise<void>;

  /** Forgets a user's billing data (customer pairing and subscriptions). Webhook event ids are kept: they hold no personal data. */
  deleteUser(userId: string): Promise<void>;

  /** Serialises work per user (double taps, concurrent webhook + sync). */
  withUserLock<T>(userId: string, work: () => Promise<T>): Promise<T>;
}
