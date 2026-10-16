import type Stripe from 'stripe';
import type { StripeEventSummary, StripePlan, SubscriptionSnapshot } from './types.js';

/**
 * The narrow slice of Stripe the service uses. The service never touches the SDK directly, so tests run against a
 * fake and an SDK / API-version change is confined to this file.
 */
export interface StripeGateway {
  listPlans(lookupKeys: string[]): Promise<StripePlan[]>;
  /** Creates the Stripe customer for a user. Calling it twice for the same user returns the same customer (idempotency key). */
  createCustomer(input: { userId: string; country: string | null; email: string | null }): Promise<string>;
  setCustomerCountry(customerId: string, country: string): Promise<void>;
  createEphemeralKey(customerId: string): Promise<string>;
  createSubscription(input: {
    customerId: string;
    userId: string;
    plan: StripePlan;
    trialDays: number;
    automaticTax: boolean;
    /** Evidence of the withdrawal-right consent, stored on the subscription. */
    consent: { at: Date; locale: string } | null;
    idempotencyKey: string | null;
  }): Promise<SubscriptionSnapshot>;
  /** Returns null when the subscription does not exist. Always includes the open payment / setup client secrets. */
  retrieveSubscription(subscriptionId: string): Promise<SubscriptionSnapshot | null>;
  /** All subscriptions of a customer, any status. */
  listSubscriptions(customerId: string): Promise<SubscriptionSnapshot[]>;
  /** Ends an unpaid (incomplete) subscription right away. */
  cancelNow(subscriptionId: string): Promise<void>;
  setCancelAtPeriodEnd(subscriptionId: string, value: boolean): Promise<SubscriptionSnapshot>;
  createPortalSession(customerId: string, returnUrl: string): Promise<string>;
  /** Deletes the customer, which also ends their subscriptions immediately. Idempotent: a customer that is already gone is fine. */
  deleteCustomer(customerId: string): Promise<void>;
  /** Verifies the signature against the RAW body. Throws on any problem. */
  constructEvent(rawBody: string, signature: string): Promise<StripeEventSummary>;
}

const SUBSCRIPTION_EXPAND = ['latest_invoice.confirmation_secret', 'pending_setup_intent'];

const idOf = (value: string | { id: string } | null | undefined): string | null =>
  value == null ? null : typeof value === 'string' ? value : value.id;

const dateOf = (seconds: number | null | undefined): Date | null =>
  typeof seconds === 'number' ? new Date(seconds * 1000) : null;

const taxBehaviorOf = (value: string | null | undefined): 'inclusive' | 'exclusive' | 'unspecified' =>
  value === 'inclusive' || value === 'exclusive' ? value : 'unspecified';

/** Maps an expanded Stripe subscription to our snapshot. Exported for tests. */
export function toSnapshot(sub: Stripe.Subscription): SubscriptionSnapshot {
  const item = sub.items.data[0];
  const price = item?.price;
  const invoice = typeof sub.latest_invoice === 'object' && sub.latest_invoice ? sub.latest_invoice : null;
  const setupIntent = typeof sub.pending_setup_intent === 'object' && sub.pending_setup_intent ? sub.pending_setup_intent : null;
  return {
    stripeSubscriptionId: sub.id,
    stripeCustomerId: idOf(sub.customer) ?? '',
    status: sub.status,
    planId: price?.lookup_key ?? null,
    priceId: price?.id ?? '',
    currency: price?.currency ?? sub.currency ?? null,
    unitAmount: price?.unit_amount ?? null,
    // Since API version 2025-03-31 the billing period lives on the subscription ITEM, not on the subscription.
    currentPeriodEnd: dateOf(item?.current_period_end),
    cancelAtPeriodEnd: sub.cancel_at_period_end,
    canceledAt: dateOf(sub.canceled_at),
    trialEnd: dateOf(sub.trial_end),
    // A trial that still has an unconfirmed setup intent and no default payment method has no way to pay yet.
    paymentMethodAttached: sub.default_payment_method != null || sub.pending_setup_intent == null,
    createdAt: dateOf(sub.created) ?? new Date(0),
    clerkUserId: sub.metadata?.clerk_user_id ?? null,
    paymentClientSecret: invoice?.confirmation_secret?.client_secret ?? null,
    setupClientSecret: setupIntent?.client_secret ?? null,
  };
}

/** Reads the subscription id out of a webhook event, whatever API version the endpoint is pinned to. Exported for tests. */
export function summarizeEvent(event: { id: string; type: string; data: { object: unknown } }): StripeEventSummary {
  const obj = (event.data.object ?? {}) as Record<string, unknown>;
  let subscriptionId: string | null = null;
  if (event.type.startsWith('customer.subscription.')) {
    subscriptionId = typeof obj.id === 'string' ? obj.id : null;
  } else if (event.type.startsWith('invoice.')) {
    const parent = obj.parent as { subscription_details?: { subscription?: string | { id: string } | null } | null } | null | undefined;
    // API >= 2025-03-31 puts it under parent.subscription_details; earlier versions have invoice.subscription.
    subscriptionId = idOf(parent?.subscription_details?.subscription) ?? idOf(obj.subscription as string | { id: string } | null | undefined);
  }
  return { id: event.id, type: event.type, subscriptionId, customerId: idOf(obj.customer as string | { id: string } | null | undefined) };
}

export function createStripeGateway(
  stripe: Stripe,
  options: { webhookSecret: string; ephemeralKeyApiVersion: string },
): StripeGateway {
  return {
    async listPlans(lookupKeys) {
      if (lookupKeys.length === 0) return [];
      const prices = await stripe.prices.list({
        lookup_keys: lookupKeys,
        active: true,
        type: 'recurring',
        expand: ['data.product'],
        limit: 10,
      });
      const plans: StripePlan[] = [];
      for (const price of prices.data) {
        const interval = price.recurring?.interval;
        if (!price.lookup_key || price.unit_amount == null || (interval !== 'month' && interval !== 'year')) continue;
        const product = typeof price.product === 'object' && price.product && !('deleted' in price.product) ? price.product : null;
        plans.push({
          id: price.lookup_key,
          priceId: price.id,
          name: product?.name ?? price.nickname ?? 'Premium',
          interval: interval as 'month' | 'year',
          intervalCount: price.recurring?.interval_count ?? 1,
          currency: price.currency,
          unitAmount: price.unit_amount,
          taxBehavior: taxBehaviorOf(price.tax_behavior),
        });
      }
      // Keep the order of BILLING_PLANS so the paywall shows plans the way the operator listed them.
      return plans.sort((a, b) => lookupKeys.indexOf(a.id) - lookupKeys.indexOf(b.id));
    },

    async createCustomer({ userId, country, email }) {
      const customer = await stripe.customers.create(
        {
          metadata: { clerk_user_id: userId },
          ...(country ? { address: { country } } : {}),
          ...(email ? { email } : {}),
        },
        { idempotencyKey: `pulse-customer-${userId}` },
      );
      return customer.id;
    },

    async setCustomerCountry(customerId, country) {
      await stripe.customers.update(customerId, { address: { country } });
    },

    async createEphemeralKey(customerId) {
      const key = await stripe.ephemeralKeys.create({ customer: customerId }, { apiVersion: options.ephemeralKeyApiVersion });
      if (!key.secret) throw new Error('Stripe returned an ephemeral key without a secret');
      return key.secret;
    },

    async createSubscription({ customerId, userId, plan, trialDays, automaticTax, consent, idempotencyKey }) {
      const sub = await stripe.subscriptions.create(
        {
          customer: customerId,
          items: [{ price: plan.priceId }],
          payment_behavior: 'default_incomplete',
          payment_settings: { save_default_payment_method: 'on_subscription' },
          billing_mode: { type: 'flexible' },
          metadata: {
            clerk_user_id: userId,
            plan_id: plan.id,
            ...(consent ? { consent_withdrawal_waiver_at: consent.at.toISOString(), consent_locale: consent.locale } : {}),
          },
          expand: SUBSCRIPTION_EXPAND,
          ...(trialDays > 0
            ? { trial_period_days: trialDays, trial_settings: { end_behavior: { missing_payment_method: 'cancel' as const } } }
            : {}),
          ...(automaticTax ? { automatic_tax: { enabled: true } } : {}),
        },
        idempotencyKey ? { idempotencyKey } : undefined,
      );
      return toSnapshot(sub);
    },

    async retrieveSubscription(subscriptionId) {
      try {
        return toSnapshot(await stripe.subscriptions.retrieve(subscriptionId, { expand: SUBSCRIPTION_EXPAND }));
      } catch (error) {
        if ((error as { code?: string }).code === 'resource_missing') return null;
        throw error;
      }
    },

    async listSubscriptions(customerId) {
      const out: SubscriptionSnapshot[] = [];
      for await (const sub of stripe.subscriptions.list({ customer: customerId, status: 'all', limit: 100, expand: ['data.pending_setup_intent', 'data.latest_invoice.confirmation_secret'] })) {
        out.push(toSnapshot(sub));
      }
      return out;
    },

    async cancelNow(subscriptionId) {
      await stripe.subscriptions.cancel(subscriptionId);
    },

    async setCancelAtPeriodEnd(subscriptionId, value) {
      return toSnapshot(
        await stripe.subscriptions.update(subscriptionId, { cancel_at_period_end: value, expand: SUBSCRIPTION_EXPAND }),
      );
    },

    async createPortalSession(customerId, returnUrl) {
      const session = await stripe.billingPortal.sessions.create({ customer: customerId, return_url: returnUrl });
      return session.url;
    },

    async deleteCustomer(customerId) {
      try {
        await stripe.customers.del(customerId);
      } catch (error) {
        if ((error as { code?: string }).code !== 'resource_missing') throw error;
      }
    },

    async constructEvent(rawBody, signature) {
      const event = await stripe.webhooks.constructEventAsync(rawBody, signature, options.webhookSecret);
      return summarizeEvent(event);
    },
  };
}
