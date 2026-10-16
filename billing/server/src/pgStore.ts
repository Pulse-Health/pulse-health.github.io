import type { Pool } from 'pg';
import type { BillingStore, ClaimResult } from './store.js';
import type { SubscriptionRecord } from './types.js';

interface SubscriptionRow {
  stripe_subscription_id: string;
  user_id: string;
  stripe_customer_id: string;
  status: string;
  plan_id: string | null;
  price_id: string;
  currency: string | null;
  unit_amount: string | null; // bigint comes back as string
  current_period_end: Date | null;
  cancel_at_period_end: boolean;
  canceled_at: Date | null;
  trial_end: Date | null;
  payment_method_attached: boolean;
  stripe_created_at: Date;
  fetched_at: Date;
}

const toRecord = (r: SubscriptionRow): SubscriptionRecord => ({
  stripeSubscriptionId: r.stripe_subscription_id,
  userId: r.user_id,
  stripeCustomerId: r.stripe_customer_id,
  status: r.status,
  planId: r.plan_id,
  priceId: r.price_id,
  currency: r.currency,
  unitAmount: r.unit_amount === null ? null : Number(r.unit_amount),
  currentPeriodEnd: r.current_period_end,
  cancelAtPeriodEnd: r.cancel_at_period_end,
  canceledAt: r.canceled_at,
  trialEnd: r.trial_end,
  paymentMethodAttached: r.payment_method_attached,
  createdAt: r.stripe_created_at,
  fetchedAt: r.fetched_at,
});

/** PostgreSQL `BillingStore`. The schema is migrations/001_billing.sql. */
export class PgBillingStore implements BillingStore {
  constructor(private readonly pool: Pool) {}

  async getCustomerId(userId: string): Promise<string | null> {
    const { rows } = await this.pool.query<{ stripe_customer_id: string }>(
      'select stripe_customer_id from billing_customers where user_id = $1',
      [userId],
    );
    return rows[0]?.stripe_customer_id ?? null;
  }

  async getUserId(stripeCustomerId: string): Promise<string | null> {
    const { rows } = await this.pool.query<{ user_id: string }>(
      'select user_id from billing_customers where stripe_customer_id = $1',
      [stripeCustomerId],
    );
    return rows[0]?.user_id ?? null;
  }

  async insertCustomer(userId: string, stripeCustomerId: string): Promise<string> {
    const inserted = await this.pool.query<{ stripe_customer_id: string }>(
      `insert into billing_customers (user_id, stripe_customer_id) values ($1, $2)
       on conflict (user_id) do nothing returning stripe_customer_id`,
      [userId, stripeCustomerId],
    );
    if (inserted.rows[0]) return inserted.rows[0].stripe_customer_id;
    const existing = await this.getCustomerId(userId);
    if (!existing) throw new Error('billing_customers insert lost a race and the row vanished');
    return existing;
  }

  async upsertSubscription(r: SubscriptionRecord): Promise<boolean> {
    const result = await this.pool.query(
      `insert into billing_subscriptions (
         stripe_subscription_id, user_id, stripe_customer_id, status, plan_id, price_id, currency, unit_amount,
         current_period_end, cancel_at_period_end, canceled_at, trial_end, payment_method_attached, stripe_created_at, fetched_at)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
       on conflict (stripe_subscription_id) do update set
         status = excluded.status, plan_id = excluded.plan_id, price_id = excluded.price_id,
         currency = excluded.currency, unit_amount = excluded.unit_amount,
         current_period_end = excluded.current_period_end, cancel_at_period_end = excluded.cancel_at_period_end,
         canceled_at = excluded.canceled_at, trial_end = excluded.trial_end,
         payment_method_attached = excluded.payment_method_attached,
         fetched_at = excluded.fetched_at, updated_at = now()
       where billing_subscriptions.fetched_at <= excluded.fetched_at
       returning stripe_subscription_id`,
      [
        r.stripeSubscriptionId, r.userId, r.stripeCustomerId, r.status, r.planId, r.priceId, r.currency,
        r.unitAmount, r.currentPeriodEnd, r.cancelAtPeriodEnd, r.canceledAt, r.trialEnd, r.paymentMethodAttached,
        r.createdAt, r.fetchedAt,
      ],
    );
    return (result.rowCount ?? 0) > 0;
  }

  async listSubscriptions(userId: string): Promise<SubscriptionRecord[]> {
    const { rows } = await this.pool.query<SubscriptionRow>(
      'select * from billing_subscriptions where user_id = $1 order by stripe_created_at desc',
      [userId],
    );
    return rows.map(toRecord);
  }

  async claimEvent(eventId: string, eventType: string, now: Date, lockMs: number): Promise<ClaimResult> {
    const lockedUntil = new Date(now.getTime() + lockMs);
    const claimed = await this.pool.query(
      `insert into billing_webhook_events (stripe_event_id, event_type, locked_until, attempts)
       values ($1, $2, $3, 1)
       on conflict (stripe_event_id) do update
         set locked_until = excluded.locked_until, attempts = billing_webhook_events.attempts + 1
         where billing_webhook_events.processed_at is null
           and (billing_webhook_events.locked_until is null or billing_webhook_events.locked_until < $4)
       returning 1`,
      [eventId, eventType, lockedUntil, now],
    );
    if ((claimed.rowCount ?? 0) > 0) return 'claimed';
    const { rows } = await this.pool.query<{ processed_at: Date | null }>(
      'select processed_at from billing_webhook_events where stripe_event_id = $1',
      [eventId],
    );
    return rows[0]?.processed_at ? 'done' : 'busy';
  }

  async completeEvent(eventId: string, now: Date): Promise<void> {
    await this.pool.query(
      'update billing_webhook_events set processed_at = $2, locked_until = null, last_error = null where stripe_event_id = $1',
      [eventId, now],
    );
  }

  async failEvent(eventId: string, error: string): Promise<void> {
    await this.pool.query(
      'update billing_webhook_events set locked_until = null, last_error = $2 where stripe_event_id = $1',
      [eventId, error.slice(0, 500)],
    );
  }

  async deleteUser(userId: string): Promise<void> {
    await this.pool.query('delete from billing_customers where user_id = $1', [userId]); // subscriptions cascade
  }

  async withUserLock<T>(userId: string, work: () => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('begin');
      await client.query('select pg_advisory_xact_lock(hashtextextended($1, 0))', [`billing:${userId}`]);
      try {
        return await work();
      } finally {
        await client.query('rollback'); // nothing was written on this connection; this just releases the lock
      }
    } finally {
      client.release();
    }
  }
}
