import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { migrate } from '../src/migrate.js';
import { PgBillingStore } from '../src/pgStore.js';
import { PgPremiumAccess } from '../src/premiumAccess.js';
import { BillingService } from '../src/service.js';
import { eventBody, FakeGateway, VALID_SIGNATURE, DAY } from './fakes.js';
import { IOS_US, testConfig } from './helpers.js';

// Against a real database that has the Pulse app's user_premium_access table (columns as in the app's supabase/schema.sql;
// RLS omitted: the billing service connects as the table owner). Needs TEST_DATABASE_URL.
const url = process.env.TEST_DATABASE_URL;
const migration002 = readFileSync(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'migrations', '002_premium_access_link.sql'), 'utf8');

describe.skipIf(!url)('PgPremiumAccess on PostgreSQL', () => {
  let pool: pg.Pool;
  const clock = { now: new Date('2026-10-16T10:00:00Z') };

  beforeAll(async () => {
    await migrate(url!);
    pool = new pg.Pool({ connectionString: url, max: 6 });
    await pool.query('drop table if exists public.user_premium_access cascade');
    await pool.query(`create table public.user_premium_access (
      id uuid primary key default gen_random_uuid(), user_id text not null, source text not null,
      starts_at timestamptz not null default now(), ends_at timestamptz not null, revoked_at timestamptz,
      code_id uuid, created_at timestamptz not null default now())`);
    await pool.query(migration002);
  });
  afterAll(async () => { await pool.query('drop table if exists public.user_premium_access cascade'); await pool.end(); });
  beforeEach(async () => {
    await pool.query('truncate billing_webhook_events, billing_subscriptions, billing_customers cascade');
    await pool.query('truncate public.user_premium_access');
  });

  // The Pulse backend's own check (supabase/functions/health-chat/quota.ts hasActivePremium).
  const backendSaysPremium = async (userId: string, at: Date) =>
    ((await pool.query('select 1 from public.user_premium_access where user_id = $1 and revoked_at is null and ends_at > $2 limit 1', [userId, at])).rowCount ?? 0) > 0;

  it('verify() accepts the migrated table and complains about a table without the link column', async () => {
    const access = new PgPremiumAccess(pool);
    await expect(access.verify()).resolves.toBeUndefined();
    await pool.query('alter table public.user_premium_access drop column external_ref');
    await expect(access.verify()).rejects.toThrow(/002_premium_access_link/);
    await pool.query(migration002);
    await expect(access.verify()).resolves.toBeUndefined();
  });

  it('a subscription becomes the row the backend checks, renews in place, and is revoked on cancellation', async () => {
    const gateway = new FakeGateway();
    gateway.now = () => clock.now;
    const service = new BillingService({ gateway, store: new PgBillingStore(pool), config: testConfig(), now: () => clock.now, access: new PgPremiumAccess(pool) });

    const start = await service.createSubscription('user_A', IOS_US);
    expect(await backendSaysPremium('user_A', clock.now)).toBe(false);

    gateway.pay(start.subscriptionId);
    await service.handleWebhook(eventBody({ id: 'evt_1', type: 'invoice.paid', subscriptionId: start.subscriptionId, customerId: start.customerId }), VALID_SIGNATURE);
    expect(await backendSaysPremium('user_A', clock.now)).toBe(true);
    expect(await backendSaysPremium('user_B', clock.now)).toBe(false);
    let rows = (await pool.query('select source, external_ref, revoked_at from public.user_premium_access')).rows;
    expect(rows).toEqual([{ source: 'stripe', external_ref: start.subscriptionId, revoked_at: null }]);

    clock.now = new Date(clock.now.getTime() + 30 * DAY);
    gateway.pay(start.subscriptionId);
    await service.handleWebhook(eventBody({ id: 'evt_2', type: 'invoice.paid', subscriptionId: start.subscriptionId, customerId: start.customerId }), VALID_SIGNATURE);
    expect((await pool.query('select count(*)::int as n from public.user_premium_access')).rows[0].n).toBe(1);
    expect(await backendSaysPremium('user_A', clock.now)).toBe(true);

    gateway.patch(start.subscriptionId, { status: 'canceled' });
    await service.handleWebhook(eventBody({ id: 'evt_3', type: 'customer.subscription.deleted', subscriptionId: start.subscriptionId, customerId: start.customerId }), VALID_SIGNATURE);
    expect(await backendSaysPremium('user_A', clock.now)).toBe(false);
    rows = (await pool.query('select revoked_at from public.user_premium_access')).rows;
    expect(rows[0].revoked_at).not.toBeNull();
  });

  it('reports redeemed codes, leaves them alone, and deletion removes only Stripe rows', async () => {
    const gateway = new FakeGateway();
    gateway.now = () => clock.now;
    const access = new PgPremiumAccess(pool);
    const service = new BillingService({ gateway, store: new PgBillingStore(pool), config: testConfig(), now: () => clock.now, access });
    await pool.query(`insert into public.user_premium_access (user_id, source, ends_at) values ('user_A', 'code:Private Alpha', $1)`, [new Date(clock.now.getTime() + 10 * DAY)]);

    expect(await service.getEntitlement('user_A')).toMatchObject({ premium: true, source: 'code' });
    expect(await access.activeOtherAccess('user_B', clock.now)).toBeNull();

    const start = await service.createSubscription('user_A', IOS_US);
    gateway.pay(start.subscriptionId);
    await service.sync('user_A');
    expect((await pool.query('select count(*)::int as n from public.user_premium_access')).rows[0].n).toBe(2);

    await service.closeAccount('user_A');
    const left = (await pool.query('select source from public.user_premium_access')).rows;
    expect(left).toEqual([{ source: 'code:Private Alpha' }]);
  });

  it('two different subscriptions of one user keep separate rows (unique per source + subscription)', async () => {
    const access = new PgPremiumAccess(pool);
    const until = new Date(clock.now.getTime() + 5 * DAY);
    await access.apply({ userId: 'user_A', subscriptionId: 'sub_1', endsAt: until, now: clock.now });
    await access.apply({ userId: 'user_A', subscriptionId: 'sub_2', endsAt: until, now: clock.now });
    await access.apply({ userId: 'user_A', subscriptionId: 'sub_1', endsAt: until, now: clock.now });
    expect((await pool.query('select count(*)::int as n from public.user_premium_access')).rows[0].n).toBe(2);
    await access.apply({ userId: 'user_A', subscriptionId: 'sub_3', endsAt: null, now: clock.now }); // nothing to revoke: no row appears
    expect((await pool.query('select count(*)::int as n from public.user_premium_access')).rows[0].n).toBe(2);
  });
});
