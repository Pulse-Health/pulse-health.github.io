import type Stripe from 'stripe';
import { describe, expect, it, vi } from 'vitest';
import { createStripeGateway, summarizeEvent, toSnapshot } from '../src/gateway.js';
import { PLAN_MONTHLY } from './fakes.js';

// These tests pin the exact requests we send to Stripe and how its responses are read. They use hand-written objects in
// the shape of the current API (billing period on the subscription item, invoice.confirmation_secret).

const SECS = (iso: string) => Math.floor(Date.parse(iso) / 1000);

function stripeSub(overrides: Record<string, unknown> = {}): Stripe.Subscription {
  return {
    id: 'sub_1', object: 'subscription', customer: 'cus_1', status: 'incomplete', created: SECS('2026-10-16T10:00:00Z'),
    currency: 'eur', cancel_at_period_end: false, canceled_at: null, trial_end: null, default_payment_method: null,
    pending_setup_intent: null, metadata: { clerk_user_id: 'user_A', plan_id: 'premium_monthly' },
    items: { data: [{ current_period_end: SECS('2026-11-16T10:00:00Z'), price: { id: 'price_monthly', lookup_key: 'premium_monthly', currency: 'eur', unit_amount: 999 } }] },
    latest_invoice: { id: 'in_1', confirmation_secret: { client_secret: 'pi_1_secret_abc', type: 'payment_intent' } },
    ...overrides,
  } as unknown as Stripe.Subscription;
}

function fakeStripe() {
  const sub = stripeSub();
  const stripe = {
    subscriptions: {
      create: vi.fn(async () => sub),
      retrieve: vi.fn(async () => sub),
      update: vi.fn(async () => sub),
      cancel: vi.fn(async () => sub),
      list: vi.fn(() => (async function* () { yield sub; })()),
    },
    customers: { create: vi.fn(async () => ({ id: 'cus_new' })), update: vi.fn(async () => ({})) },
    ephemeralKeys: { create: vi.fn(async () => ({ secret: 'ek_test_123' })) },
    billingPortal: { sessions: { create: vi.fn(async () => ({ url: 'https://billing.stripe.com/p/session/x' })) } },
    prices: { list: vi.fn() },
    webhooks: { constructEventAsync: vi.fn() },
  };
  return { stripe, gateway: createStripeGateway(stripe as unknown as Stripe, { webhookSecret: 'whsec_x', ephemeralKeyApiVersion: '2025-06-30.basil' }) };
}

describe('toSnapshot', () => {
  it('reads the billing period from the subscription item and the payment secret from the latest invoice', () => {
    expect(toSnapshot(stripeSub())).toEqual({
      stripeSubscriptionId: 'sub_1', stripeCustomerId: 'cus_1', status: 'incomplete', planId: 'premium_monthly', priceId: 'price_monthly',
      currency: 'eur', unitAmount: 999, currentPeriodEnd: new Date('2026-11-16T10:00:00Z'), cancelAtPeriodEnd: false, canceledAt: null,
      trialEnd: null, paymentMethodAttached: true, createdAt: new Date('2026-10-16T10:00:00Z'), clerkUserId: 'user_A',
      paymentClientSecret: 'pi_1_secret_abc', setupClientSecret: null,
    });
  });

  it('accepts an expanded customer and an unexpanded invoice', () => {
    const s = toSnapshot(stripeSub({ customer: { id: 'cus_9' }, latest_invoice: 'in_1' }));
    expect(s.stripeCustomerId).toBe('cus_9');
    expect(s.paymentClientSecret).toBeNull();
  });

  it('a trial that still waits for its setup intent has no payment method attached', () => {
    const s = toSnapshot(stripeSub({ status: 'trialing', trial_end: SECS('2026-10-23T10:00:00Z'), latest_invoice: null, pending_setup_intent: { id: 'seti_1', client_secret: 'seti_1_secret_x' } }));
    expect(s).toMatchObject({ paymentMethodAttached: false, setupClientSecret: 'seti_1_secret_x', trialEnd: new Date('2026-10-23T10:00:00Z') });
  });

  it('a trial with a default payment method, or whose setup intent is done, is attached', () => {
    expect(toSnapshot(stripeSub({ status: 'trialing', pending_setup_intent: 'seti_1', default_payment_method: 'pm_1' })).paymentMethodAttached).toBe(true);
    expect(toSnapshot(stripeSub({ status: 'trialing', pending_setup_intent: null })).paymentMethodAttached).toBe(true);
  });

  it('survives a subscription without items or metadata', () => {
    const s = toSnapshot(stripeSub({ items: { data: [] }, metadata: undefined }));
    expect(s).toMatchObject({ planId: null, priceId: '', currentPeriodEnd: null, clerkUserId: null });
  });
});

describe('summarizeEvent', () => {
  it('reads subscription events', () => {
    expect(summarizeEvent({ id: 'evt_1', type: 'customer.subscription.updated', data: { object: { id: 'sub_1', customer: 'cus_1' } } }))
      .toEqual({ id: 'evt_1', type: 'customer.subscription.updated', subscriptionId: 'sub_1', customerId: 'cus_1' });
  });

  it('reads invoice events of the current API version (parent.subscription_details)', () => {
    expect(summarizeEvent({ id: 'evt_2', type: 'invoice.paid', data: { object: { id: 'in_1', customer: 'cus_1', parent: { subscription_details: { subscription: 'sub_1' } } } } }))
      .toMatchObject({ subscriptionId: 'sub_1', customerId: 'cus_1' });
  });

  it('reads invoice events of older API versions (invoice.subscription), also when expanded', () => {
    expect(summarizeEvent({ id: 'evt_3', type: 'invoice.payment_failed', data: { object: { customer: 'cus_1', subscription: 'sub_1' } } })).toMatchObject({ subscriptionId: 'sub_1' });
    expect(summarizeEvent({ id: 'evt_4', type: 'invoice.paid', data: { object: { customer: { id: 'cus_1' }, subscription: { id: 'sub_2' } } } })).toMatchObject({ subscriptionId: 'sub_2', customerId: 'cus_1' });
  });

  it('has no subscription for other events or one-off invoices', () => {
    expect(summarizeEvent({ id: 'evt_5', type: 'customer.updated', data: { object: { id: 'cus_1' } } }).subscriptionId).toBeNull();
    expect(summarizeEvent({ id: 'evt_6', type: 'invoice.paid', data: { object: { customer: 'cus_1', parent: null, subscription: null } } }).subscriptionId).toBeNull();
  });
});

describe('requests sent to Stripe', () => {
  it('creates a subscription the way the mobile payment sheet needs it', async () => {
    const { stripe, gateway } = fakeStripe();
    await gateway.createSubscription({ customerId: 'cus_1', userId: 'user_A', plan: PLAN_MONTHLY, trialDays: 0, automaticTax: false, consent: null, idempotencyKey: 'abc' });
    expect(stripe.subscriptions.create).toHaveBeenCalledWith(
      {
        customer: 'cus_1', items: [{ price: 'price_monthly' }], payment_behavior: 'default_incomplete',
        payment_settings: { save_default_payment_method: 'on_subscription' }, billing_mode: { type: 'flexible' },
        metadata: { clerk_user_id: 'user_A', plan_id: 'premium_monthly' },
        expand: ['latest_invoice.confirmation_secret', 'pending_setup_intent'],
      },
      { idempotencyKey: 'abc' },
    );
  });

  it('adds the trial (cancelling if no payment method arrives) and automatic tax only when asked', async () => {
    const { stripe, gateway } = fakeStripe();
    await gateway.createSubscription({ customerId: 'cus_1', userId: 'user_A', plan: PLAN_MONTHLY, trialDays: 7, automaticTax: true, consent: null, idempotencyKey: null });
    const [params, options] = stripe.subscriptions.create.mock.calls[0] as unknown as [Record<string, unknown>, unknown];
    expect(params).toMatchObject({ trial_period_days: 7, trial_settings: { end_behavior: { missing_payment_method: 'cancel' } }, automatic_tax: { enabled: true } });
    expect(options).toBeUndefined();
  });

  it('records the withdrawal-right consent as evidence on the subscription', async () => {
    const { stripe, gateway } = fakeStripe();
    await gateway.createSubscription({ customerId: 'cus_1', userId: 'user_A', plan: PLAN_MONTHLY, trialDays: 0, automaticTax: false, consent: { at: new Date('2026-10-16T10:00:00Z'), locale: 'de-DE' }, idempotencyKey: null });
    const [params] = stripe.subscriptions.create.mock.calls[0] as unknown as [{ metadata: Record<string, string> }];
    expect(params.metadata).toEqual({
      clerk_user_id: 'user_A', plan_id: 'premium_monthly', consent_withdrawal_waiver_at: '2026-10-16T10:00:00.000Z', consent_locale: 'de-DE',
    });
  });

  it('creates the customer with an idempotency key per user and the Clerk id as metadata', async () => {
    const { stripe, gateway } = fakeStripe();
    expect(await gateway.createCustomer({ userId: 'user_A', country: 'DE', email: 'a@example.com' })).toBe('cus_new');
    expect(stripe.customers.create).toHaveBeenCalledWith({ metadata: { clerk_user_id: 'user_A' }, address: { country: 'DE' }, email: 'a@example.com' }, { idempotencyKey: 'pulse-customer-user_A' });
    await gateway.createCustomer({ userId: 'user_B', country: null, email: null });
    expect(stripe.customers.create).toHaveBeenLastCalledWith({ metadata: { clerk_user_id: 'user_B' } }, { idempotencyKey: 'pulse-customer-user_B' });
  });

  it('creates the ephemeral key with the API version of the mobile SDK', async () => {
    const { stripe, gateway } = fakeStripe();
    expect(await gateway.createEphemeralKey('cus_1')).toBe('ek_test_123');
    expect(stripe.ephemeralKeys.create).toHaveBeenCalledWith({ customer: 'cus_1' }, { apiVersion: '2025-06-30.basil' });
  });

  it('lists all subscriptions of a customer in every status', async () => {
    const { stripe, gateway } = fakeStripe();
    expect(await gateway.listSubscriptions('cus_1')).toHaveLength(1);
    expect(stripe.subscriptions.list).toHaveBeenCalledWith(expect.objectContaining({ customer: 'cus_1', status: 'all' }));
  });

  it('treats a missing subscription as null but rethrows other errors', async () => {
    const { stripe, gateway } = fakeStripe();
    stripe.subscriptions.retrieve.mockRejectedValueOnce(Object.assign(new Error('nope'), { code: 'resource_missing' }));
    expect(await gateway.retrieveSubscription('sub_x')).toBeNull();
    stripe.subscriptions.retrieve.mockRejectedValueOnce(Object.assign(new Error('down'), { code: 'api_error' }));
    await expect(gateway.retrieveSubscription('sub_x')).rejects.toThrow('down');
  });

  it('sets and clears cancellation at period end', async () => {
    const { stripe, gateway } = fakeStripe();
    await gateway.setCancelAtPeriodEnd('sub_1', true);
    expect(stripe.subscriptions.update).toHaveBeenCalledWith('sub_1', expect.objectContaining({ cancel_at_period_end: true }));
  });

  it('opens the portal with a return URL', async () => {
    const { stripe, gateway } = fakeStripe();
    expect(await gateway.createPortalSession('cus_1', 'pulse://billing')).toMatch(/^https:/);
    expect(stripe.billingPortal.sessions.create).toHaveBeenCalledWith({ customer: 'cus_1', return_url: 'pulse://billing' });
  });

  it('verifies webhooks against the raw body with the endpoint secret', async () => {
    const { stripe, gateway } = fakeStripe();
    stripe.webhooks.constructEventAsync.mockResolvedValue({ id: 'evt_1', type: 'invoice.paid', data: { object: { customer: 'cus_1', parent: { subscription_details: { subscription: 'sub_1' } } } } });
    expect(await gateway.constructEvent('RAW', 'sig')).toMatchObject({ id: 'evt_1', subscriptionId: 'sub_1' });
    expect(stripe.webhooks.constructEventAsync).toHaveBeenCalledWith('RAW', 'sig', 'whsec_x');
    stripe.webhooks.constructEventAsync.mockRejectedValue(new Error('bad sig'));
    await expect(gateway.constructEvent('RAW', 'bad')).rejects.toThrow();
  });

  it('lists only recurring monthly / yearly prices that have a lookup key, in the configured order', async () => {
    const { stripe, gateway } = fakeStripe();
    const price = (over: Record<string, unknown>) => ({ id: 'p', lookup_key: 'k', unit_amount: 100, currency: 'eur', tax_behavior: 'inclusive', product: { id: 'prod', name: 'Pulse Premium' }, recurring: { interval: 'month', interval_count: 1 }, ...over });
    stripe.prices.list.mockResolvedValue({ data: [
      price({ id: 'p_y', lookup_key: 'premium_yearly', unit_amount: 7999, recurring: { interval: 'year', interval_count: 1 } }),
      price({ id: 'p_m', lookup_key: 'premium_monthly', unit_amount: 999 }),
      price({ id: 'p_w', lookup_key: 'weekly', recurring: { interval: 'week', interval_count: 1 } }),
      price({ id: 'p_free', lookup_key: 'free', unit_amount: null }),
      price({ id: 'p_nokey', lookup_key: null }),
    ] });
    const plans = await gateway.listPlans(['premium_monthly', 'premium_yearly']);
    expect(plans.map((p) => [p.id, p.priceId, p.interval, p.unitAmount, p.name])).toEqual([
      ['premium_monthly', 'p_m', 'month', 999, 'Pulse Premium'],
      ['premium_yearly', 'p_y', 'year', 7999, 'Pulse Premium'],
    ]);
    expect(await gateway.listPlans([])).toEqual([]);
  });
});
