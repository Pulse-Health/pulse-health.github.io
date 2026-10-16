import type { Pool } from 'pg';

/**
 * Where Stripe subscriptions are mirrored so that the rest of the Pulse backend, which only knows
 * `user_premium_access`, sees them. One row per Stripe subscription (source 'stripe', external_ref = subscription id).
 */
export interface PremiumAccessSink {
  /** Grants or extends access until `endsAt`; with `endsAt` null it revokes the subscription's row (if any). */
  apply(input: { userId: string; subscriptionId: string; endsAt: Date | null; now: Date }): Promise<void>;
  /** The longest-lasting active access of a user that did NOT come from Stripe (redeemed codes), if any. */
  activeOtherAccess(userId: string, now: Date): Promise<{ endsAt: Date; source: string } | null>;
  /** Removes the Stripe-sourced rows of a user (account deletion). */
  removeStripeAccess(userId: string): Promise<void>;
}

export class PgPremiumAccess implements PremiumAccessSink {
  constructor(private readonly pool: Pool) {}

  /** Throws a readable error if the Pulse premium table or the link column is missing. */
  async verify(): Promise<void> {
    const { rows } = await this.pool.query<{ ok: boolean }>(
      `select exists (select 1 from information_schema.columns
                       where table_schema = 'public' and table_name = 'user_premium_access' and column_name = 'external_ref') as ok`,
    );
    if (!rows[0]?.ok) {
      throw new Error(
        'public.user_premium_access.external_ref is missing. Apply migrations/002_premium_access_link.sql to the database that holds ' +
          'user_premium_access, or set BILLING_SYNC_PREMIUM_ACCESS=false if this service is not attached to the Pulse database.',
      );
    }
  }

  async apply({ userId, subscriptionId, endsAt, now }: { userId: string; subscriptionId: string; endsAt: Date | null; now: Date }): Promise<void> {
    if (endsAt) {
      await this.pool.query(
        `insert into public.user_premium_access (user_id, source, external_ref, starts_at, ends_at, revoked_at)
         values ($1, 'stripe', $2, $3, $4, null)
         on conflict (source, external_ref) where external_ref is not null
         do update set ends_at = excluded.ends_at, revoked_at = null`,
        [userId, subscriptionId, now, endsAt],
      );
    } else {
      await this.pool.query(
        `update public.user_premium_access set revoked_at = $3
          where source = 'stripe' and external_ref = $1 and user_id = $2 and revoked_at is null`,
        [subscriptionId, userId, now],
      );
    }
  }

  async activeOtherAccess(userId: string, now: Date): Promise<{ endsAt: Date; source: string } | null> {
    const { rows } = await this.pool.query<{ ends_at: Date; source: string }>(
      `select ends_at, source from public.user_premium_access
        where user_id = $1 and revoked_at is null and ends_at > $2 and source <> 'stripe'
        order by ends_at desc limit 1`,
      [userId, now],
    );
    return rows[0] ? { endsAt: rows[0].ends_at, source: rows[0].source } : null;
  }

  async removeStripeAccess(userId: string): Promise<void> {
    await this.pool.query(`delete from public.user_premium_access where user_id = $1 and source = 'stripe'`, [userId]);
  }
}

/** Test double that records what the service wrote, keyed like the real table. */
export class MemoryPremiumAccess implements PremiumAccessSink {
  rows = new Map<string, { userId: string; subscriptionId: string; startsAt: Date; endsAt: Date; revokedAt: Date | null }>();
  others = new Map<string, { endsAt: Date; source: string }>();

  async apply({ userId, subscriptionId, endsAt, now }: { userId: string; subscriptionId: string; endsAt: Date | null; now: Date }): Promise<void> {
    const row = this.rows.get(subscriptionId);
    if (endsAt) {
      this.rows.set(subscriptionId, { userId, subscriptionId, startsAt: row?.startsAt ?? now, endsAt, revokedAt: null });
    } else if (row && !row.revokedAt) {
      row.revokedAt = now;
    }
  }

  async activeOtherAccess(userId: string, now: Date) {
    const other = this.others.get(userId);
    return other && other.endsAt > now ? other : null;
  }

  async removeStripeAccess(userId: string): Promise<void> {
    for (const [id, row] of this.rows) if (row.userId === userId) this.rows.delete(id);
  }

  /** Whether the Pulse backend's own check (revoked_at is null and ends_at > now) would say premium. */
  isActive(userId: string, now: Date): boolean {
    return [...this.rows.values()].some((r) => r.userId === userId && !r.revokedAt && r.endsAt > now);
  }
}
