import { describe, expect, it } from 'vitest';
import { BillingError } from '../src/types.js';
import { DAY, eventBody, VALID_SIGNATURE } from './fakes.js';
import { IOS_US, OTHER_USER, setup, USER } from './helpers.js';

const rejects = async (promise: Promise<unknown>, code: string, status: number) => {
  const error = await promise.then(() => null, (e: unknown) => e);
  expect(error).toBeInstanceOf(BillingError);
  expect(error).toMatchObject({ code, status });
};

describe('offers', () => {
  it('lists the plans with real prices where purchases are allowed', async () => {
    const { service } = setup();
    const offers = await service.getOffers(USER, 'ios', 'US');
    expect(offers.purchase).toEqual({ available: true, reason: null });
    expect(offers.publishableKey).toBe('pk_test_x');
    expect(offers.plans.map((p) => [p.id, p.unitAmount, p.currency, p.trialDays])).toEqual([
      ['premium_monthly', 999, 'eur', 0],
      ['premium_yearly', 7999, 'eur', 0],
    ]);
  });

  it('shows no plans and no Stripe call outside the allowed regions', async () => {
    const { service, gateway } = setup();
    const offers = await service.getOffers(USER, 'ios', 'DE');
    expect(offers).toMatchObject({ purchase: { available: false, reason: 'region_not_supported' }, plans: [] });
    expect(gateway.calls).toEqual([]);
  });

  it('reports a misconfigured account (no prices in Stripe) as billing_disabled', async () => {
    const { service, gateway } = setup();
    gateway.plans = [];
    expect((await service.getOffers(USER, 'ios', 'US')).purchase).toEqual({ available: false, reason: 'billing_disabled' });
  });

  it('caches prices for a few minutes', async () => {
    const { service, gateway, clock } = setup();
    await service.getOffers(USER, 'ios', 'US');
    await service.getOffers(USER, 'ios', 'US');
    expect(gateway.count('listPlans')).toBe(1);
    clock.now = new Date(clock.now.getTime() + 6 * 60 * 1000);
    await service.getOffers(USER, 'ios', 'US');
    expect(gateway.count('listPlans')).toBe(2);
  });

  it('offers the trial only to users who never had a subscription', async () => {
    const { service, gateway } = setup({ trialDays: 7 });
    expect((await service.getOffers(USER, 'ios', 'US')).plans[0]?.trialDays).toBe(7);
    const start = await service.createSubscription(USER, IOS_US);
    gateway.completeSetup(start.subscriptionId);
    await service.sync(USER);
    gateway.patch(start.subscriptionId, { status: 'canceled' });
    await service.sync(USER);
    expect((await service.getOffers(USER, 'ios', 'US')).plans[0]?.trialDays).toBe(0);
  });

  it('says already_subscribed once the user pays', async () => {
    const { service, gateway } = setup();
    const start = await service.createSubscription(USER, IOS_US);
    gateway.pay(start.subscriptionId);
    await service.sync(USER);
    expect(await service.getOffers(USER, 'ios', 'US')).toMatchObject({ purchase: { available: false, reason: 'already_subscribed' }, plans: [] });
  });
});

describe('createSubscription', () => {
  it('creates a customer and an incomplete subscription and returns the payment sheet inputs', async () => {
    const { service, gateway, store } = setup();
    const result = await service.createSubscription(USER, IOS_US, 'tap-1');
    expect(result).toMatchObject({
      status: 'incomplete',
      customerId: 'cus_1',
      customerEphemeralKeySecret: 'ek_cus_1',
      publishableKey: 'pk_test_x',
      intent: { kind: 'payment' },
    });
    expect(result.intent?.clientSecret).toMatch(/^pi_/);
    expect(await store.getCustomerId(USER)).toBe('cus_1');
    expect(gateway.createSubscriptionInputs[0]).toMatchObject({ userId: USER, trialDays: 0, automaticTax: false });
    // the key sent to Stripe is derived from user + tap, never the raw client value
    expect(gateway.createSubscriptionInputs[0]?.idempotencyKey).toMatch(/^[0-9a-f]{64}$/);
    expect((await service.getEntitlement(USER)).status).toBe('incomplete');
    expect((await service.getEntitlement(USER)).premium).toBe(false);
  });

  it('gives the Stripe customer the email from the session token (receipts and invoices need it)', async () => {
    const { service, gateway } = setup();
    await service.createSubscription(USER, IOS_US, null, { email: 'robin@example.com' });
    expect(gateway.customers.get('cus_1')?.email).toBe('robin@example.com');
    const noEmail = setup();
    await noEmail.service.createSubscription(USER, IOS_US);
    expect(noEmail.gateway.customers.get('cus_1')?.email).toBeNull();
  });

  it('refuses regions that are not allowed, before touching Stripe', async () => {
    const { service, gateway } = setup();
    await rejects(service.createSubscription(USER, { ...IOS_US, country: 'DE' }), 'purchase_not_available', 403);
    await rejects(service.createSubscription(USER, { planId: 'premium_monthly', platform: 'ios' }), 'purchase_not_available', 403);
    expect(gateway.calls).toEqual([]);
  });

  it('refuses unknown plans', async () => {
    const { service } = setup();
    await rejects(service.createSubscription(USER, { ...IOS_US, planId: 'premium_lifetime' }), 'plan_not_found', 404);
  });

  it('refuses a second subscription while one is active', async () => {
    const { service, gateway } = setup();
    const first = await service.createSubscription(USER, IOS_US);
    gateway.pay(first.subscriptionId);
    await rejects(service.createSubscription(USER, IOS_US), 'already_subscribed', 409);
  });

  it('reopens an abandoned subscription for the same plan instead of creating another', async () => {
    const { service, gateway } = setup();
    const first = await service.createSubscription(USER, IOS_US);
    const again = await service.createSubscription(USER, IOS_US);
    expect(again.subscriptionId).toBe(first.subscriptionId);
    expect(again.intent?.clientSecret).toBe(first.intent?.clientSecret);
    expect(gateway.count('createSubscription')).toBe(1);
  });

  it('cancels an abandoned subscription of another plan and starts the new one', async () => {
    const { service, gateway } = setup();
    const monthly = await service.createSubscription(USER, IOS_US);
    const yearly = await service.createSubscription(USER, { ...IOS_US, planId: 'premium_yearly' });
    expect(yearly.subscriptionId).not.toBe(monthly.subscriptionId);
    expect(gateway.subs.get(monthly.subscriptionId)?.status).toBe('canceled');
  });

  it('two taps at once create exactly one subscription', async () => {
    const { service, gateway } = setup();
    const [a, b] = await Promise.all([service.createSubscription(USER, IOS_US, 'k1'), service.createSubscription(USER, IOS_US, 'k2')]);
    expect(a.subscriptionId).toBe(b.subscriptionId);
    expect(gateway.count('createSubscription')).toBe(1);
    expect(gateway.customers.size).toBe(1);
  });

  it('isolates users from each other', async () => {
    const { service, gateway } = setup();
    const a = await service.createSubscription(USER, IOS_US);
    gateway.pay(a.subscriptionId);
    await service.sync(USER);
    expect((await service.getEntitlement(OTHER_USER)).premium).toBe(false);
    const b = await service.createSubscription(OTHER_USER, IOS_US);
    expect(b.customerId).not.toBe(a.customerId);
  });

  it('a trial returns a setup intent and grants nothing until a payment method is saved', async () => {
    const { service, gateway } = setup({ trialDays: 7 });
    const result = await service.createSubscription(USER, IOS_US);
    expect(result.status).toBe('trialing');
    expect(result.intent?.kind).toBe('setup');
    expect(gateway.createSubscriptionInputs[0]?.trialDays).toBe(7);

    // the user closed the sheet: opening and closing it must not be a free trial
    let e = await service.getEntitlement(USER);
    expect(e).toMatchObject({ premium: false, status: 'incomplete' });
    e = await service.sync(USER);
    expect(e.premium).toBe(false);

    // and can reopen the same sheet
    const again = await service.createSubscription(USER, IOS_US);
    expect(again.subscriptionId).toBe(result.subscriptionId);
    expect(again.intent?.kind).toBe('setup');

    gateway.completeSetup(result.subscriptionId);
    e = await service.sync(USER);
    expect(e).toMatchObject({ premium: true, status: 'trialing' });
  });

  it('requires a country for tax when automatic tax is on, and sends it to Stripe', async () => {
    const { service, gateway } = setup({ automaticTax: true });
    await rejects(service.createSubscription(USER, { planId: 'premium_monthly', platform: 'ios', country: undefined }), 'purchase_not_available', 403);
    const noCountryAllowed = setup({ automaticTax: true, purchaseCountries: { ios: '*', android: '*' } });
    await rejects(noCountryAllowed.service.createSubscription(USER, { planId: 'premium_monthly', platform: 'ios' }), 'invalid_request', 400);
    await service.createSubscription(USER, { ...IOS_US, billingCountry: 'de', consent: { withdrawalWaiver: true, locale: 'de-DE' } });
    expect(gateway.customers.get('cus_1')?.country).toBe('DE');
    expect(gateway.createSubscriptionInputs[0]?.automaticTax).toBe(true);
  });

  it('does not create a second customer when Stripe fails after the customer exists', async () => {
    const { service, gateway } = setup();
    gateway.failOn.add('createSubscription');
    await expect(service.createSubscription(USER, IOS_US)).rejects.toThrow();
    gateway.failOn.clear();
    await service.createSubscription(USER, IOS_US);
    expect(gateway.customers.size).toBe(1);
  });
});

describe('withdrawal-right consent (EU consumers)', () => {
  const eu = { purchaseCountries: { ios: ['US', 'DE'] as string[], android: [] as string[] } };
  const DE = { planId: 'premium_monthly', platform: 'ios', country: 'DE' } as const;

  it('offers tell the app whether to show the consent', async () => {
    const { service } = setup(eu);
    expect((await service.getOffers(USER, 'ios', 'DE')).requiresWithdrawalConsent).toBe(true);
    expect((await service.getOffers(USER, 'ios', 'US')).requiresWithdrawalConsent).toBe(false);
  });

  it('refuses a purchase in a consent country without the consent, before touching Stripe', async () => {
    const { service, gateway } = setup(eu);
    await rejects(service.createSubscription(USER, DE), 'consent_required', 400);
    await rejects(service.createSubscription(USER, { ...DE, consent: { withdrawalWaiver: false, locale: 'de-DE' } }), 'consent_required', 400);
    expect(gateway.count('createCustomer')).toBe(0);
  });

  it('stores when and in which language the consent was given', async () => {
    const { service, gateway } = setup(eu);
    await service.createSubscription(USER, { ...DE, consent: { withdrawalWaiver: true, locale: 'de-DE' } });
    expect(gateway.createSubscriptionInputs[0]?.consent).toEqual({ at: new Date('2026-10-16T10:00:00Z'), locale: 'de-DE' });
  });

  it('is not asked of buyers elsewhere, and is not recorded when not given', async () => {
    const { service, gateway } = setup(eu);
    await service.createSubscription(USER, IOS_US);
    expect(gateway.createSubscriptionInputs[0]?.consent).toBeNull();
  });

  it('judges by the billing country when it differs from the storefront', async () => {
    const { service } = setup(eu);
    await rejects(service.createSubscription(USER, { ...IOS_US, billingCountry: 'DE' }), 'consent_required', 400);
  });
});

describe('after the payment sheet', () => {
  it('sync turns a paid subscription into Premium without waiting for the webhook', async () => {
    const { service, gateway } = setup();
    const start = await service.createSubscription(USER, IOS_US);
    gateway.pay(start.subscriptionId);
    expect((await service.getEntitlement(USER)).premium).toBe(false); // DB not updated yet
    const e = await service.sync(USER);
    expect(e).toMatchObject({ premium: true, status: 'active', planId: 'premium_monthly', source: 'stripe' });
  });

  it('sync of a user without a billing account is simply "none"', async () => {
    const { service, gateway } = setup();
    expect(await service.sync(USER)).toMatchObject({ premium: false, status: 'none' });
    expect(gateway.calls).toEqual([]);
  });
});

describe('cancel and resume', () => {
  async function subscribed() {
    const ctx = setup();
    const start = await ctx.service.createSubscription(USER, IOS_US);
    ctx.gateway.pay(start.subscriptionId);
    await ctx.service.sync(USER);
    return { ...ctx, subscriptionId: start.subscriptionId };
  }

  it('cancels at the end of the period and keeps Premium until then', async () => {
    const { service } = await subscribed();
    const e = await service.cancel(USER);
    expect(e).toMatchObject({ premium: true, cancelAtPeriodEnd: true });
    expect(e.premiumUntil).toBe(e.currentPeriodEnd);
  });

  it('resume undoes it', async () => {
    const { service } = await subscribed();
    await service.cancel(USER);
    expect(await service.resume(USER)).toMatchObject({ premium: true, cancelAtPeriodEnd: false });
  });

  it('has nothing to cancel or resume without a matching subscription', async () => {
    const { service } = setup();
    await rejects(service.cancel(USER), 'no_subscription', 404);
    await rejects(service.resume(USER), 'no_subscription', 404);
    const sub = await subscribed();
    await rejects(sub.service.resume(USER), 'no_subscription', 404); // not set to cancel
  });
});

describe('portal', () => {
  it('opens the portal for a customer and only for allowed return URLs', async () => {
    const { service } = setup();
    await service.createSubscription(USER, IOS_US);
    expect(await service.createPortal(USER, 'pulse://billing/return')).toContain('portal/cus_1');
    expect(await service.createPortal(USER, 'https://app.example.com/billing/return')).toContain('portal/cus_1');
    await rejects(service.createPortal(USER, 'https://evil.example.com/'), 'invalid_request', 400);
    await rejects(service.createPortal(USER, 'https://app.example.com/billing/return/../../x'), 'invalid_request', 400);
    await rejects(service.createPortal(USER, 'javascript:alert(1)'), 'invalid_request', 400);
  });

  it('needs a billing account', async () => {
    await rejects(setup().service.createPortal(USER, 'pulse://billing'), 'no_customer', 404);
  });
});

describe('webhook', () => {
  async function paidUser() {
    const ctx = setup();
    const start = await ctx.service.createSubscription(USER, IOS_US);
    return { ...ctx, subscriptionId: start.subscriptionId, customerId: start.customerId };
  }

  it('rejects missing and invalid signatures', async () => {
    const { service } = setup();
    await rejects(service.handleWebhook('{}', null), 'invalid_request', 400);
    await rejects(service.handleWebhook(eventBody({ id: 'evt_1' }), 'nope'), 'invalid_request', 400);
  });

  it('applies an event by re-reading the subscription from Stripe', async () => {
    const { service, gateway, subscriptionId, customerId } = await paidUser();
    gateway.pay(subscriptionId);
    const r = await service.handleWebhook(eventBody({ id: 'evt_1', type: 'invoice.paid', subscriptionId, customerId }), VALID_SIGNATURE);
    expect(r.duplicate).toBe(false);
    expect((await service.getEntitlement(USER)).premium).toBe(true);
  });

  it('processes every event id at most once', async () => {
    const { service, gateway, subscriptionId, customerId } = await paidUser();
    const body = eventBody({ id: 'evt_dup', subscriptionId, customerId });
    await service.handleWebhook(body, VALID_SIGNATURE);
    const retrievals = gateway.count('retrieveSubscription');
    const again = await service.handleWebhook(body, VALID_SIGNATURE);
    expect(again.duplicate).toBe(true);
    expect(gateway.count('retrieveSubscription')).toBe(retrievals);
  });

  it('answers with an error when processing fails, and succeeds when Stripe retries', async () => {
    const { service, gateway, subscriptionId, customerId } = await paidUser();
    gateway.pay(subscriptionId);
    const body = eventBody({ id: 'evt_flaky', subscriptionId, customerId });
    gateway.failOn.add('retrieveSubscription');
    await expect(service.handleWebhook(body, VALID_SIGNATURE)).rejects.toMatchObject({ status: 500 });
    expect((await service.getEntitlement(USER)).premium).toBe(false);
    gateway.failOn.clear();
    expect((await service.handleWebhook(body, VALID_SIGNATURE)).duplicate).toBe(false);
    expect((await service.getEntitlement(USER)).premium).toBe(true);
  });

  it('asks Stripe to retry while another delivery of the same event is in flight', async () => {
    const { service, store, subscriptionId, customerId } = await paidUser();
    await store.claimEvent('evt_busy', 'invoice.paid', new Date('2026-10-16T10:00:00Z'), 60_000);
    await rejects(service.handleWebhook(eventBody({ id: 'evt_busy', subscriptionId, customerId }), VALID_SIGNATURE), 'internal', 503);
  });

  it('a stale read can never overwrite a newer one (events arriving out of order)', async () => {
    const { service, gateway, clock, subscriptionId, customerId } = await paidUser();
    // t0: event A is triggered while the subscription is still incomplete, but its Stripe read is slow
    const slowRead = gateway.retrieveSubscription.bind(gateway);
    let release!: () => void;
    let started!: () => void;
    const gate = new Promise<void>((resolve) => (release = resolve));
    const readHappened = new Promise<void>((resolve) => (started = resolve));
    gateway.retrieveSubscription = async (id) => {
      const snapshot = await slowRead(id); // state as of t0: incomplete
      started();
      await gate; // ...delivered late
      return snapshot;
    };
    const eventA = service.handleWebhook(eventBody({ id: 'evt_A', subscriptionId, customerId }), VALID_SIGNATURE);
    await readHappened; // the old state has really been read before anything below happens

    // t1: the subscription is paid and a /sync (newer read) stores that
    clock.now = new Date(clock.now.getTime() + 5000);
    gateway.pay(subscriptionId);
    await service.sync(USER);
    expect((await service.getEntitlement(USER)).premium).toBe(true);

    // t2: the slow, older read finally lands; it must be discarded
    release();
    await eventA;
    expect((await service.getEntitlement(USER)).premium).toBe(true);
  });

  it('ignores events of customers that are not Pulse billing customers', async () => {
    const { service, gateway } = setup();
    gateway.subs.set('sub_foreign', {
      stripeSubscriptionId: 'sub_foreign', stripeCustomerId: 'cus_foreign', status: 'active', planId: 'other', priceId: 'price_other',
      currency: 'eur', unitAmount: 100, currentPeriodEnd: new Date(Date.now() + DAY), cancelAtPeriodEnd: false, canceledAt: null,
      trialEnd: null, paymentMethodAttached: true, createdAt: new Date(), clerkUserId: null, paymentClientSecret: null, setupClientSecret: null,
    });
    const r = await service.handleWebhook(eventBody({ id: 'evt_foreign', subscriptionId: 'sub_foreign', customerId: 'cus_foreign' }), VALID_SIGNATURE);
    expect(r.duplicate).toBe(false);
  });

  it('events without a subscription are acknowledged', async () => {
    const { service } = setup();
    expect((await service.handleWebhook(eventBody({ id: 'evt_misc', type: 'customer.updated' }), VALID_SIGNATURE)).duplicate).toBe(false);
  });

  it('revokes Premium when Stripe reports the subscription deleted', async () => {
    const { service, gateway, subscriptionId, customerId } = await paidUser();
    gateway.pay(subscriptionId);
    await service.sync(USER);
    gateway.patch(subscriptionId, { status: 'canceled', canceledAt: new Date() });
    await service.handleWebhook(eventBody({ id: 'evt_del', type: 'customer.subscription.deleted', subscriptionId, customerId }), VALID_SIGNATURE);
    expect(await service.getEntitlement(USER)).toMatchObject({ premium: false, status: 'canceled' });
  });
});

describe('extra entitlement sources', () => {
  it('merges another source (for example Premium codes): the longer one wins', async () => {
    const { gateway, store, clock } = setup();
    const { BillingService } = await import('../src/service.js');
    const { testConfig } = await import('./helpers.js');
    const codeUntil = '2027-01-01T00:00:00Z';
    const service = new BillingService({
      gateway, store, config: testConfig(), now: () => clock.now,
      extraEntitlement: async (userId) => userId === USER
        ? { premium: true, status: 'active', planId: null, source: 'code', currentPeriodEnd: codeUntil, cancelAtPeriodEnd: false, trialEnd: null, premiumUntil: codeUntil }
        : null,
    });
    expect(await service.getEntitlement(USER)).toMatchObject({ premium: true, source: 'code' });
    expect((await service.getEntitlement(OTHER_USER)).premium).toBe(false);
    const start = await service.createSubscription(USER, IOS_US).catch(() => null);
    expect(start).not.toBeNull();
  });
});

describe('mirroring into the Pulse Premium table', () => {
  async function paid() {
    const ctx = setup();
    const start = await ctx.service.createSubscription(USER, IOS_US);
    ctx.gateway.pay(start.subscriptionId);
    await ctx.service.sync(USER);
    return { ...ctx, subscriptionId: start.subscriptionId, customerId: start.customerId };
  }

  it('an unpaid subscription grants nothing there', async () => {
    const { service, access } = setup();
    await service.createSubscription(USER, IOS_US);
    expect(access.rows.size).toBe(0);
  });

  it('paying creates the row the rest of the backend checks (revoked_at null, ends_at in the future)', async () => {
    const { access, clock, subscriptionId } = await paid();
    expect(access.isActive(USER, clock.now)).toBe(true);
    const row = access.rows.get(subscriptionId)!;
    expect(row.userId).toBe(USER);
    expect(row.endsAt.getTime()).toBeGreaterThan(clock.now.getTime() + 29 * DAY);
  });

  it('renewal extends the same row; the start of access is kept', async () => {
    const { service, gateway, access, clock, subscriptionId, customerId } = await paid();
    const startsAt = access.rows.get(subscriptionId)!.startsAt;
    const before = access.rows.get(subscriptionId)!.endsAt;
    clock.now = new Date(clock.now.getTime() + 30 * DAY);
    gateway.pay(subscriptionId);
    await service.handleWebhook(eventBody({ id: 'evt_renew', type: 'invoice.paid', subscriptionId, customerId }), VALID_SIGNATURE);
    expect(access.rows.size).toBe(1);
    expect(access.rows.get(subscriptionId)!.startsAt).toEqual(startsAt);
    expect(access.rows.get(subscriptionId)!.endsAt.getTime()).toBeGreaterThan(before.getTime());
  });

  it('cancelling at period end keeps access until the period end, then Stripe\'s deletion revokes it', async () => {
    const { service, gateway, access, clock, subscriptionId, customerId } = await paid();
    await service.cancel(USER);
    const periodEnd = gateway.subs.get(subscriptionId)!.currentPeriodEnd!;
    expect(access.rows.get(subscriptionId)!.endsAt).toEqual(periodEnd); // exactly the paid period, no renewal horizon
    expect(access.isActive(USER, clock.now)).toBe(true);

    clock.now = new Date(periodEnd.getTime() + 1000);
    gateway.patch(subscriptionId, { status: 'canceled' });
    await service.handleWebhook(eventBody({ id: 'evt_del', type: 'customer.subscription.deleted', subscriptionId, customerId }), VALID_SIGNATURE);
    expect(access.isActive(USER, clock.now)).toBe(false);
    expect(access.rows.get(subscriptionId)!.revokedAt).not.toBeNull();
  });

  it('a failed renewal keeps access through the grace period and a recovered payment restores a revoked row', async () => {
    const { service, gateway, access, clock, subscriptionId, customerId } = await paid();
    const periodEnd = gateway.subs.get(subscriptionId)!.currentPeriodEnd!;
    gateway.patch(subscriptionId, { status: 'past_due' });
    clock.now = new Date(periodEnd.getTime() + 1 * DAY);
    await service.handleWebhook(eventBody({ id: 'evt_pd', type: 'invoice.payment_failed', subscriptionId, customerId }), VALID_SIGNATURE);
    expect(access.isActive(USER, clock.now)).toBe(true);

    clock.now = new Date(periodEnd.getTime() + 4 * DAY); // grace (3 days) is over
    await service.handleWebhook(eventBody({ id: 'evt_pd2', type: 'invoice.payment_failed', subscriptionId, customerId }), VALID_SIGNATURE);
    expect(access.isActive(USER, clock.now)).toBe(false);

    gateway.pay(subscriptionId);
    await service.handleWebhook(eventBody({ id: 'evt_paid', type: 'invoice.paid', subscriptionId, customerId }), VALID_SIGNATURE);
    expect(access.isActive(USER, clock.now)).toBe(true);
    expect(access.rows.get(subscriptionId)!.revokedAt).toBeNull();
  });

  it('a stale read does not touch the Premium table', async () => {
    const { service, gateway, access, clock, subscriptionId, customerId } = await paid();
    const slowRead = gateway.retrieveSubscription.bind(gateway);
    let release!: () => void;
    let started!: () => void;
    const gate = new Promise<void>((resolve) => (release = resolve));
    const readHappened = new Promise<void>((resolve) => (started = resolve));
    gateway.retrieveSubscription = async (id) => { const snapshot = await slowRead(id); started(); await gate; return snapshot; };
    gateway.patch(subscriptionId, { status: 'canceled' }); // the slow reader sees "canceled"
    const stale = service.handleWebhook(eventBody({ id: 'evt_stale', subscriptionId, customerId }), VALID_SIGNATURE);
    await readHappened;
    clock.now = new Date(clock.now.getTime() + 5000);
    gateway.pay(subscriptionId); // ...but a newer read finds it active again
    await service.sync(USER);
    release();
    await stale;
    expect(access.isActive(USER, clock.now)).toBe(true);
  });

  it('reports redeemed codes in the entitlement and lets the longer source win', async () => {
    const { service, access, clock } = setup();
    expect((await service.getEntitlement(USER)).premium).toBe(false);
    access.others.set(USER, { endsAt: new Date(clock.now.getTime() + 20 * DAY), source: 'code:Private Alpha' });
    expect(await service.getEntitlement(USER)).toMatchObject({ premium: true, source: 'code', planId: null });
    // a subscription that lasts longer than the code takes over
    const start = await service.createSubscription(USER, IOS_US);
    (await import('./fakes.js')).FakeGateway.prototype.pay.call((service as unknown as { gateway: InstanceType<typeof import('./fakes.js').FakeGateway> }).gateway, start.subscriptionId, 60);
    expect(await service.sync(USER)).toMatchObject({ premium: true, source: 'stripe' });
  });
});

describe('account deletion', () => {
  it('ends the subscription at Stripe, removes Premium access and every stored row, and can be repeated', async () => {
    const { service, gateway, store, access, clock } = setup();
    const start = await service.createSubscription(USER, IOS_US);
    gateway.pay(start.subscriptionId);
    await service.sync(USER);
    expect(access.isActive(USER, clock.now)).toBe(true);

    await service.closeAccount(USER);
    expect(gateway.count('deleteCustomer')).toBe(1);
    expect(gateway.subs.get(start.subscriptionId)?.status).toBe('canceled');
    expect(access.rows.size).toBe(0);
    expect(await store.getCustomerId(USER)).toBeNull();
    expect(await store.listSubscriptions(USER)).toEqual([]);
    expect(await service.getEntitlement(USER)).toMatchObject({ premium: false, status: 'none' });

    await service.closeAccount(USER); // second time: nothing left, still fine
    expect(gateway.count('deleteCustomer')).toBe(1);
  });

  it('works for users who never subscribed', async () => {
    const { service, gateway } = setup();
    await service.closeAccount('user_never');
    expect(gateway.count('deleteCustomer')).toBe(0);
  });

  it('keeps our rows when Stripe fails, so the deletion can be retried', async () => {
    const { service, gateway, store } = setup();
    await service.createSubscription(USER, IOS_US);
    gateway.failOn.add('deleteCustomer');
    await expect(service.closeAccount(USER)).rejects.toMatchObject({ code: 'stripe_error', status: 502 });
    expect(await store.getCustomerId(USER)).not.toBeNull();
    gateway.failOn.clear();
    await service.closeAccount(USER);
    expect(await store.getCustomerId(USER)).toBeNull();
  });

  it('later Stripe events for the deleted customer are ignored', async () => {
    const { service, gateway, access, clock } = setup();
    const start = await service.createSubscription(USER, IOS_US);
    gateway.pay(start.subscriptionId);
    await service.closeAccount(USER);
    gateway.pay(start.subscriptionId); // a late event would otherwise resurrect the access
    await service.handleWebhook(eventBody({ id: 'evt_late', type: 'invoice.paid', subscriptionId: start.subscriptionId, customerId: start.customerId }), VALID_SIGNATURE);
    expect(access.isActive(USER, clock.now)).toBe(false);
  });
});
