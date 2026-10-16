import pg from 'pg';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { MemoryBillingStore } from '../src/memoryStore.js';
import { migrate } from '../src/migrate.js';
import { PgBillingStore } from '../src/pgStore.js';
import type { BillingStore } from '../src/store.js';
import type { SubscriptionRecord } from '../src/types.js';

// The same behavioural tests run against both stores, so the in-memory fake the other tests rely on cannot drift
// from what PostgreSQL does. The PostgreSQL run needs TEST_DATABASE_URL (CI provides one; locally it is skipped).

const T0 = new Date('2026-10-16T10:00:00Z');
const sub = (overrides: Partial<SubscriptionRecord> = {}): SubscriptionRecord => ({
  stripeSubscriptionId: 'sub_1', userId: 'user_A', stripeCustomerId: 'cus_A', status: 'active', planId: 'premium_monthly',
  priceId: 'price_1', currency: 'eur', unitAmount: 999, currentPeriodEnd: new Date('2026-11-16T10:00:00Z'),
  cancelAtPeriodEnd: false, canceledAt: null, trialEnd: null, paymentMethodAttached: true,
  createdAt: new Date('2026-10-01T00:00:00Z'), fetchedAt: T0, ...overrides,
});

function storeTests(name: string, make: () => Promise<{ store: BillingStore; reset: () => Promise<void>; close: () => Promise<void> }>, enabled = true) {
  describe.skipIf(!enabled)(`BillingStore: ${name}`, () => {
    let store: BillingStore;
    let reset: () => Promise<void>;
    let close: () => Promise<void>;
    beforeAll(async () => ({ store, reset, close } = await make()));
    beforeEach(async () => { await reset(); });
    afterAll(async () => { await close(); });

    it('pairs users and Stripe customers, first pairing wins', async () => {
      expect(await store.getCustomerId('user_A')).toBeNull();
      expect(await store.insertCustomer('user_A', 'cus_A')).toBe('cus_A');
      expect(await store.insertCustomer('user_A', 'cus_OTHER')).toBe('cus_A'); // a lost race returns the stored one
      expect(await store.getCustomerId('user_A')).toBe('cus_A');
      expect(await store.getUserId('cus_A')).toBe('user_A');
      expect(await store.getUserId('cus_unknown')).toBeNull();
    });

    it('never gives one Stripe customer to two users', async () => {
      await store.insertCustomer('user_A', 'cus_A');
      await expect(store.insertCustomer('user_B', 'cus_A')).rejects.toThrow();
    });

    it('stores and lists subscriptions, newest first, with every field round-tripping', async () => {
      await store.insertCustomer('user_A', 'cus_A');
      const older = sub({ stripeSubscriptionId: 'sub_old', status: 'canceled', createdAt: new Date('2026-01-01T00:00:00Z'), canceledAt: new Date('2026-02-01T00:00:00Z'), currentPeriodEnd: null, planId: null, currency: null, unitAmount: null });
      const newer = sub({ trialEnd: new Date('2026-10-08T00:00:00Z'), cancelAtPeriodEnd: true, paymentMethodAttached: false });
      expect(await store.upsertSubscription(older)).toBe(true);
      expect(await store.upsertSubscription(newer)).toBe(true);
      const listed = await store.listSubscriptions('user_A');
      expect(listed.map((s) => s.stripeSubscriptionId)).toEqual(['sub_1', 'sub_old']);
      expect(listed[0]).toEqual(newer);
      expect(listed[1]).toEqual(older);
      expect(await store.listSubscriptions('user_B')).toEqual([]);
    });

    it('updates in place and discards writes that are older than what is stored', async () => {
      await store.insertCustomer('user_A', 'cus_A');
      await store.upsertSubscription(sub({ status: 'incomplete', fetchedAt: new Date(T0.getTime()) }));
      expect(await store.upsertSubscription(sub({ status: 'active', fetchedAt: new Date(T0.getTime() + 2000) }))).toBe(true);
      expect(await store.upsertSubscription(sub({ status: 'incomplete', fetchedAt: new Date(T0.getTime() + 1000) }))).toBe(false); // stale
      expect(await store.upsertSubscription(sub({ status: 'active', fetchedAt: new Date(T0.getTime() + 2000) }))).toBe(true); // same instant is idempotent
      const [only] = await store.listSubscriptions('user_A');
      expect(only?.status).toBe('active');
      expect(await store.listSubscriptions('user_A')).toHaveLength(1);
    });

    it('claims an event once, reports done after completion, and allows a retry after a failure', async () => {
      expect(await store.claimEvent('evt_1', 'invoice.paid', T0, 60_000)).toBe('claimed');
      expect(await store.claimEvent('evt_1', 'invoice.paid', new Date(T0.getTime() + 1000), 60_000)).toBe('busy');
      await store.failEvent('evt_1', 'boom');
      expect(await store.claimEvent('evt_1', 'invoice.paid', new Date(T0.getTime() + 2000), 60_000)).toBe('claimed');
      await store.completeEvent('evt_1', new Date(T0.getTime() + 3000));
      expect(await store.claimEvent('evt_1', 'invoice.paid', new Date(T0.getTime() + 4000), 60_000)).toBe('done');
    });

    it('lets a crashed delivery be taken over once its lock has expired', async () => {
      expect(await store.claimEvent('evt_2', 'x', T0, 60_000)).toBe('claimed');
      expect(await store.claimEvent('evt_2', 'x', new Date(T0.getTime() + 59_000), 60_000)).toBe('busy');
      expect(await store.claimEvent('evt_2', 'x', new Date(T0.getTime() + 61_000), 60_000)).toBe('claimed');
    });

    it('of many concurrent deliveries of one event exactly one claims it', async () => {
      const results = await Promise.all(Array.from({ length: 8 }, () => store.claimEvent('evt_race', 'x', T0, 60_000)));
      expect(results.filter((r) => r === 'claimed')).toHaveLength(1);
      expect(results.filter((r) => r === 'busy')).toHaveLength(7);
    });

    it('serialises work per user but not across users', async () => {
      const order: string[] = [];
      const slow = (label: string, ms: number) => async () => { order.push(`${label}:start`); await new Promise((r) => setTimeout(r, ms)); order.push(`${label}:end`); };
      await Promise.all([
        store.withUserLock('user_A', slow('a1', 40)),
        store.withUserLock('user_A', slow('a2', 1)),
        store.withUserLock('user_B', slow('b', 1)),
      ]);
      const at = (entry: string) => order.indexOf(entry);
      // the same user's two jobs never overlap (which one goes first is up to the database)
      expect(at('a1:end') < at('a2:start') || at('a2:end') < at('a1:start')).toBe(true);
      // another user is not held up by them: it finishes before the 40 ms job does
      expect(at('b:end')).toBeLessThan(at('a1:end'));
    });

    it('releases the lock when the work throws', async () => {
      await expect(store.withUserLock('user_A', async () => { throw new Error('x'); })).rejects.toThrow('x');
      expect(await store.withUserLock('user_A', async () => 'again')).toBe('again');
    });
  });
}

storeTests('memory', async () => {
  const store = new MemoryBillingStore();
  return { store, reset: async () => store.clear(), close: async () => {} };
});

const url = process.env.TEST_DATABASE_URL;
storeTests('postgres', async () => {
  await migrate(url!);
  const pool = new pg.Pool({ connectionString: url, max: 12 });
  return {
    store: new PgBillingStore(pool),
    reset: async () => { await pool.query('truncate billing_webhook_events, billing_subscriptions, billing_customers cascade'); },
    close: async () => { await pool.end(); },
  };
}, Boolean(url));

describe.skipIf(!url)('migrations', () => {
  it('can be applied twice (idempotent) and records what ran', async () => {
    expect(await migrate(url!)).toEqual([]);
    const pool = new pg.Pool({ connectionString: url, max: 1 });
    const { rows } = await pool.query('select name from billing_migrations order by name');
    await pool.end();
    expect(rows.map((r) => r.name)).toEqual(['001_billing.sql', '002_premium_access_link.sql']);
  });
});
