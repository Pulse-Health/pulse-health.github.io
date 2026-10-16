import type { BillingStore, ClaimResult } from './store.js';
import type { SubscriptionRecord } from './types.js';

interface EventRow {
  type: string;
  lockedUntil: Date | null;
  attempts: number;
  processedAt: Date | null;
  lastError: string | null;
}

/** In-memory `BillingStore` for tests and local development. */
export class MemoryBillingStore implements BillingStore {
  private customersByUser = new Map<string, string>();
  private usersByCustomer = new Map<string, string>();
  private subs = new Map<string, SubscriptionRecord>();
  private events = new Map<string, EventRow>();
  private locks = new Map<string, Promise<unknown>>();

  async getCustomerId(userId: string): Promise<string | null> {
    return this.customersByUser.get(userId) ?? null;
  }

  async getUserId(stripeCustomerId: string): Promise<string | null> {
    return this.usersByCustomer.get(stripeCustomerId) ?? null;
  }

  async insertCustomer(userId: string, stripeCustomerId: string): Promise<string> {
    const existing = this.customersByUser.get(userId);
    if (existing) return existing;
    const owner = this.usersByCustomer.get(stripeCustomerId);
    if (owner && owner !== userId) throw new Error('Stripe customer already belongs to another user');
    this.customersByUser.set(userId, stripeCustomerId);
    this.usersByCustomer.set(stripeCustomerId, userId);
    return stripeCustomerId;
  }

  async upsertSubscription(record: SubscriptionRecord): Promise<boolean> {
    if (!this.customersByUser.has(record.userId)) throw new Error('foreign key: unknown billing customer');
    const current = this.subs.get(record.stripeSubscriptionId);
    if (current && current.fetchedAt.getTime() > record.fetchedAt.getTime()) return false;
    this.subs.set(record.stripeSubscriptionId, { ...record });
    return true;
  }

  async listSubscriptions(userId: string): Promise<SubscriptionRecord[]> {
    return [...this.subs.values()]
      .filter((s) => s.userId === userId)
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
      .map((s) => ({ ...s }));
  }

  async claimEvent(eventId: string, eventType: string, now: Date, lockMs: number): Promise<ClaimResult> {
    const row = this.events.get(eventId);
    if (row?.processedAt) return 'done';
    if (row && row.lockedUntil && row.lockedUntil.getTime() >= now.getTime()) return 'busy';
    this.events.set(eventId, {
      type: eventType,
      lockedUntil: new Date(now.getTime() + lockMs),
      attempts: (row?.attempts ?? 0) + 1,
      processedAt: null,
      lastError: row?.lastError ?? null,
    });
    return 'claimed';
  }

  async completeEvent(eventId: string, now: Date): Promise<void> {
    const row = this.events.get(eventId);
    if (row) this.events.set(eventId, { ...row, processedAt: now, lockedUntil: null, lastError: null });
  }

  async failEvent(eventId: string, error: string): Promise<void> {
    const row = this.events.get(eventId);
    if (row) this.events.set(eventId, { ...row, lockedUntil: null, lastError: error.slice(0, 500) });
  }

  async deleteUser(userId: string): Promise<void> {
    const customer = this.customersByUser.get(userId);
    if (customer) this.usersByCustomer.delete(customer);
    this.customersByUser.delete(userId);
    for (const [id, sub] of this.subs) if (sub.userId === userId) this.subs.delete(id);
  }

  async withUserLock<T>(userId: string, work: () => Promise<T>): Promise<T> {
    const previous = this.locks.get(userId) ?? Promise.resolve();
    const run = previous.catch(() => undefined).then(work);
    const tail = run.catch(() => undefined);
    this.locks.set(userId, tail);
    try {
      return await run;
    } finally {
      if (this.locks.get(userId) === tail) this.locks.delete(userId);
    }
  }

  /** Test helper: forget everything. */
  clear(): void {
    this.customersByUser.clear();
    this.usersByCustomer.clear();
    this.subs.clear();
    this.events.clear();
    this.locks.clear();
  }

  /** Test helper. */
  eventRow(eventId: string): EventRow | undefined {
    return this.events.get(eventId);
  }
}
