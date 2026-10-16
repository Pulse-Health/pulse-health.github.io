import { generateKeyPair, SignJWT } from 'jose';
import { beforeAll, describe, expect, it } from 'vitest';
import type { ZodType } from 'zod';
import { createClerkAuthenticator } from '../src/auth.js';
import { createBillingApp } from '../src/http.js';
import { eventBody, VALID_SIGNATURE } from './fakes.js';
import { setup } from './helpers.js';
import { AccountDeletedResponse, CreateSubscriptionResponse, EntitlementResponse, ErrorResponse, OffersResponse, PortalResponse } from './wire.js';

let privateKey: CryptoKey;
let publicKey: CryptoKey;
beforeAll(async () => ({ publicKey, privateKey } = await generateKeyPair('RS256')));

const token = (sub: string, claims: Record<string, unknown> = {}) => new SignJWT(claims).setProtectedHeader({ alg: 'RS256' }).setSubject(sub).setIssuer('https://clerk.example.com').setExpirationTime('5m').sign(privateKey);

async function harness(overrides = {}) {
  const ctx = setup(overrides);
  const app = createBillingApp({
    service: ctx.service,
    authenticate: createClerkAuthenticator({ keys: async () => publicKey, issuer: 'https://clerk.example.com' }),
    now: () => ctx.clock.now,
  });
  const call = async (method: string, path: string, opts: { user?: string; body?: unknown; headers?: Record<string, string>; claims?: Record<string, unknown> } = {}) => {
    const headers: Record<string, string> = { ...opts.headers };
    if (opts.user) headers.authorization = `Bearer ${await token(opts.user, opts.claims)}`;
    if (opts.body !== undefined) headers['content-type'] = 'application/json';
    const res = await app.request(path, { method, headers, ...(opts.body !== undefined ? { body: JSON.stringify(opts.body) } : {}) });
    return { res, json: (await res.json()) as unknown };
  };
  return { ...ctx, app, call };
}

const matches = (schema: ZodType, value: unknown) => {
  const r = schema.safeParse(value);
  expect(r.success, r.success ? '' : JSON.stringify(r.error.issues)).toBe(true);
};

describe('authentication', () => {
  it.each([
    ['GET', '/v1/billing/offers?platform=ios&country=US'],
    ['GET', '/v1/billing/entitlement'],
    ['POST', '/v1/billing/subscriptions'],
    ['POST', '/v1/billing/sync'],
    ['POST', '/v1/billing/subscription/cancel'],
    ['POST', '/v1/billing/subscription/resume'],
    ['POST', '/v1/billing/portal'],
    ['DELETE', '/v1/billing/account'],
    ['GET', '/v1/billing/does-not-exist'],
  ])('%s %s needs a Clerk session', async (method, path) => {
    const { res, json } = await (await harness()).call(method, path);
    expect(res.status).toBe(401);
    expect(res.headers.get('www-authenticate')).toBe('Bearer');
    matches(ErrorResponse, json);
  });

  it('health check and unknown routes need no session', async () => {
    const h = await harness();
    expect((await h.call('GET', '/healthz')).res.status).toBe(200);
    expect((await h.call('GET', '/nope')).res.status).toBe(404);
  });

  it('echoes a sane request id and replaces a hostile one', async () => {
    const h = await harness();
    const good = await h.app.request('/healthz', { headers: { 'x-request-id': 'req-123.abc_DEF' } });
    expect(good.headers.get('x-request-id')).toBe('req-123.abc_DEF');
    for (const hostile of ['has spaces', 'semi;colon', 'x'.repeat(200), 'ünï']) {
      const res = await h.app.request('/healthz', { headers: { 'x-request-id': hostile } });
      expect(res.status).toBe(200);
      expect(res.headers.get('x-request-id')).toMatch(/^[0-9a-f-]{36}$/);
    }
  });

  it('never caches', async () => {
    const { res } = await (await harness()).call('GET', '/v1/billing/entitlement', { user: 'user_A' });
    expect(res.headers.get('cache-control')).toBe('no-store');
    expect(res.headers.get('x-request-id')).toBeTruthy();
  });
});

describe('the purchase journey, as the app sees it', () => {
  it('offers -> subscribe -> pay -> sync -> cancel -> resume, with every response matching the contract', async () => {
    const h = await harness();

    const offers = await h.call('GET', '/v1/billing/offers?platform=ios&country=US', { user: 'user_A' });
    expect(offers.res.status).toBe(200);
    matches(OffersResponse, offers.json);

    const none = await h.call('GET', '/v1/billing/entitlement', { user: 'user_A' });
    matches(EntitlementResponse, none.json);
    expect(none.json).toMatchObject({ entitlement: { premium: false, status: 'none' }, serverTime: '2026-10-16T10:00:00Z' });

    const created = await h.call('POST', '/v1/billing/subscriptions', {
      user: 'user_A', body: { planId: 'premium_monthly', platform: 'ios', country: 'US' }, headers: { 'idempotency-key': 'tap-1' },
    });
    expect(created.res.status).toBe(200);
    matches(CreateSubscriptionResponse, created.json);
    const subscriptionId = (created.json as { subscriptionId: string }).subscriptionId;

    h.gateway.pay(subscriptionId);
    const synced = await h.call('POST', '/v1/billing/sync', { user: 'user_A' });
    matches(EntitlementResponse, synced.json);
    expect(synced.json).toMatchObject({ entitlement: { premium: true, status: 'active' } });

    const canceled = await h.call('POST', '/v1/billing/subscription/cancel', { user: 'user_A' });
    expect(canceled.json).toMatchObject({ entitlement: { premium: true, cancelAtPeriodEnd: true } });
    const resumed = await h.call('POST', '/v1/billing/subscription/resume', { user: 'user_A' });
    expect(resumed.json).toMatchObject({ entitlement: { cancelAtPeriodEnd: false } });

    const portal = await h.call('POST', '/v1/billing/portal', { user: 'user_A', body: { returnUrl: 'pulse://billing/return' } });
    matches(PortalResponse, portal.json);

    const deleted = await h.call('DELETE', '/v1/billing/account', { user: 'user_A' });
    expect(deleted.res.status).toBe(200);
    matches(AccountDeletedResponse, deleted.json);
    expect(((await h.call('GET', '/v1/billing/entitlement', { user: 'user_A' })).json as { entitlement: { premium: boolean } }).entitlement.premium).toBe(false);
  });

  it('the email claim of the session token reaches the Stripe customer', async () => {
    const h = await harness();
    await h.call('POST', '/v1/billing/subscriptions', { user: 'user_A', claims: { email: 'a@example.com' }, body: { planId: 'premium_monthly', platform: 'ios', country: 'US' } });
    expect(h.gateway.customers.get('cus_1')?.email).toBe('a@example.com');
  });

  it('another user sees nothing of it', async () => {
    const h = await harness();
    await h.call('POST', '/v1/billing/subscriptions', { user: 'user_A', body: { planId: 'premium_monthly', platform: 'ios', country: 'US' } });
    const { json } = await h.call('GET', '/v1/billing/entitlement', { user: 'user_B' });
    expect(json).toMatchObject({ entitlement: { status: 'none' } });
  });
});

describe('errors', () => {
  it('maps service errors to their status and code', async () => {
    const h = await harness();
    let r = await h.call('POST', '/v1/billing/subscriptions', { user: 'u', body: { planId: 'premium_monthly', platform: 'ios', country: 'DE' } });
    expect(r.res.status).toBe(403);
    expect(r.json).toMatchObject({ error: { code: 'purchase_not_available' } });
    matches(ErrorResponse, r.json);

    r = await h.call('POST', '/v1/billing/subscriptions', { user: 'u', body: { planId: 'nope', platform: 'ios', country: 'US' } });
    expect(r.res.status).toBe(404);

    const eu = await harness({ purchaseCountries: { ios: ['DE'], android: [] } });
    r = await eu.call('POST', '/v1/billing/subscriptions', { user: 'u', body: { planId: 'premium_monthly', platform: 'ios', country: 'DE' } });
    expect(r.res.status).toBe(400);
    expect(r.json).toMatchObject({ error: { code: 'consent_required' } });
    matches(ErrorResponse, r.json);
    r = await eu.call('POST', '/v1/billing/subscriptions', { user: 'u', body: { planId: 'premium_monthly', platform: 'ios', country: 'DE', consent: { withdrawalWaiver: true, locale: 'de-DE' } } });
    expect(r.res.status).toBe(200);

    r = await h.call('POST', '/v1/billing/portal', { user: 'u', body: { returnUrl: 'pulse://x' } });
    expect(r.res.status).toBe(404);
    expect(r.json).toMatchObject({ error: { code: 'no_customer' } });

    r = await h.call('POST', '/v1/billing/subscription/cancel', { user: 'u' });
    expect(r.res.status).toBe(404);
  });

  it('rejects malformed requests with 400', async () => {
    const h = await harness();
    for (const [path, body] of [
      ['/v1/billing/subscriptions', { platform: 'ios' }],
      ['/v1/billing/subscriptions', { planId: 'premium_monthly', platform: 'windows' }],
      ['/v1/billing/subscriptions', { planId: 'premium_monthly', platform: 'ios', country: 'USA' }],
      ['/v1/billing/portal', {}],
    ] as const) {
      const r = await h.call('POST', path, { user: 'u', body });
      expect(r.res.status, path).toBe(400);
      matches(ErrorResponse, r.json);
    }
    const bad = await h.app.request('/v1/billing/subscriptions', { method: 'POST', headers: { authorization: `Bearer ${await token('u')}`, 'content-type': 'application/json' }, body: '{not json' });
    expect(bad.status).toBe(400);
    const offers = await h.call('GET', '/v1/billing/offers', { user: 'u' });
    expect(offers.res.status).toBe(400);
  });

  it('rejects oversized bodies', async () => {
    const h = await harness();
    const res = await h.app.request('/v1/billing/subscriptions', { method: 'POST', headers: { authorization: `Bearer ${await token('u')}`, 'content-type': 'application/json', 'content-length': String(100_000) }, body: JSON.stringify({ planId: 'x'.repeat(100_000) }) });
    expect(res.status).toBe(413);
  });

  it('reports Stripe failures as 502 without leaking details', async () => {
    const h = await harness();
    h.gateway.failOn.add('listPlans');
    const r = await h.call('GET', '/v1/billing/offers?platform=ios&country=US', { user: 'u' });
    expect(r.res.status).toBe(502);
    expect(JSON.stringify(r.json)).not.toContain('listPlans');
    expect(r.json).toMatchObject({ error: { code: 'stripe_error' } });
  });

  it('rate limits the calls that reach Stripe', async () => {
    const h = await harness();
    const statuses: number[] = [];
    for (let i = 0; i < 12; i++) statuses.push((await h.call('POST', '/v1/billing/sync', { user: 'spammer' })).res.status);
    expect(statuses.slice(0, 10).every((s) => s === 200)).toBe(true);
    expect(statuses.slice(10)).toEqual([429, 429]);
    expect((await h.call('POST', '/v1/billing/sync', { user: 'someone-else' })).res.status).toBe(200);
  });
});

describe('POST /v1/billing/webhook', () => {
  it('does not use the Clerk session; the signature is the credential', async () => {
    const h = await harness();
    const start = await h.call('POST', '/v1/billing/subscriptions', { user: 'user_A', body: { planId: 'premium_monthly', platform: 'ios', country: 'US' } });
    const { subscriptionId, customerId } = start.json as { subscriptionId: string; customerId: string };
    h.gateway.pay(subscriptionId);

    const res = await h.app.request('/v1/billing/webhook', {
      method: 'POST', headers: { 'stripe-signature': VALID_SIGNATURE }, body: eventBody({ id: 'evt_http', type: 'invoice.paid', subscriptionId, customerId }),
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ received: true, duplicate: false });
    expect(((await h.call('GET', '/v1/billing/entitlement', { user: 'user_A' })).json as { entitlement: { premium: boolean } }).entitlement.premium).toBe(true);
  });

  it('passes the raw body through untouched (the signature covers the exact bytes)', async () => {
    const h = await harness();
    const seen: string[] = [];
    const original = h.gateway.constructEvent.bind(h.gateway);
    h.gateway.constructEvent = async (raw, sig) => { seen.push(raw); return original(raw, sig); };
    const raw = ` { "id" :"evt_raw",\n "type":"x" }  `; // odd whitespace on purpose
    await h.app.request('/v1/billing/webhook', { method: 'POST', headers: { 'stripe-signature': VALID_SIGNATURE }, body: raw });
    expect(seen).toEqual([raw]);
  });

  it.each([[undefined], ['bad']])('answers 400 for signature %s', async (signature) => {
    const h = await harness();
    const res = await h.app.request('/v1/billing/webhook', { method: 'POST', headers: signature ? { 'stripe-signature': signature } : {}, body: eventBody({ id: 'evt_x' }) });
    expect(res.status).toBe(400);
  });

  it('answers 5xx when processing fails so that Stripe retries', async () => {
    const h = await harness();
    const start = await h.call('POST', '/v1/billing/subscriptions', { user: 'user_A', body: { planId: 'premium_monthly', platform: 'ios', country: 'US' } });
    const { subscriptionId, customerId } = start.json as { subscriptionId: string; customerId: string };
    h.gateway.failOn.add('retrieveSubscription');
    const res = await h.app.request('/v1/billing/webhook', { method: 'POST', headers: { 'stripe-signature': VALID_SIGNATURE }, body: eventBody({ id: 'evt_5xx', subscriptionId, customerId }) });
    expect(res.status).toBe(500);
  });
});
