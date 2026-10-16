import pg from 'pg';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { migrate } from '../src/migrate.js';
import { PgBillingStore } from '../src/pgStore.js';
import { BillingService } from '../src/service.js';
import { eventBody, FakeGateway, VALID_SIGNATURE } from './fakes.js';
import { IOS_US, testConfig, USER } from './helpers.js';

// The service on real PostgreSQL (foreign keys, advisory locks, ordering). Needs TEST_DATABASE_URL.
const url = process.env.TEST_DATABASE_URL;

describe.skipIf(!url)('BillingService on PostgreSQL', () => {
  let pool: pg.Pool;
  let gateway: FakeGateway;
  let service: BillingService;
  const clock = { now: new Date('2026-10-16T10:00:00Z') };

  beforeAll(async () => {
    await migrate(url!);
    pool = new pg.Pool({ connectionString: url, max: 12 });
  });
  afterAll(async () => { await pool.end(); });
  beforeEach(async () => {
    await pool.query('truncate billing_webhook_events, billing_subscriptions, billing_customers cascade');
    gateway = new FakeGateway();
    gateway.now = () => clock.now;
    service = new BillingService({ gateway, store: new PgBillingStore(pool), config: testConfig(), now: () => clock.now });
  });

  it('runs the whole journey', async () => {
    const start = await service.createSubscription(USER, IOS_US);
    expect((await service.getEntitlement(USER)).status).toBe('incomplete');
    gateway.pay(start.subscriptionId);
    await service.handleWebhook(eventBody({ id: 'evt_1', type: 'invoice.paid', subscriptionId: start.subscriptionId, customerId: start.customerId }), VALID_SIGNATURE);
    expect(await service.getEntitlement(USER)).toMatchObject({ premium: true, status: 'active', planId: 'premium_monthly' });
    expect(await service.cancel(USER)).toMatchObject({ premium: true, cancelAtPeriodEnd: true });
    const again = await service.handleWebhook(eventBody({ id: 'evt_1', type: 'invoice.paid', subscriptionId: start.subscriptionId, customerId: start.customerId }), VALID_SIGNATURE);
    expect(again.duplicate).toBe(true);
  });

  it('three simultaneous taps create one customer and one subscription', async () => {
    const results = await Promise.all([1, 2, 3].map((i) => service.createSubscription(USER, IOS_US, `tap-${i}`)));
    expect(new Set(results.map((r) => r.subscriptionId)).size).toBe(1);
    expect(gateway.count('createSubscription')).toBe(1);
    const { rows } = await pool.query('select count(*)::int as n from billing_customers');
    expect(rows[0].n).toBe(1);
  });

  it('keeps users apart', async () => {
    const a = await service.createSubscription('user_A', IOS_US);
    gateway.pay(a.subscriptionId);
    await service.sync('user_A');
    expect((await service.getEntitlement('user_A')).premium).toBe(true);
    expect((await service.getEntitlement('user_B')).premium).toBe(false);
  });
});
