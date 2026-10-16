import type { StripeGateway } from '../src/gateway.js';
import type { StripeEventSummary, StripePlan, SubscriptionSnapshot } from '../src/types.js';

export const PLAN_MONTHLY: StripePlan = {
  id: 'premium_monthly', priceId: 'price_monthly', name: 'Pulse Premium', interval: 'month', intervalCount: 1,
  currency: 'eur', unitAmount: 999, taxBehavior: 'inclusive',
};
export const PLAN_YEARLY: StripePlan = { ...PLAN_MONTHLY, id: 'premium_yearly', priceId: 'price_yearly', interval: 'year', unitAmount: 7999 };

export const VALID_SIGNATURE = 'valid-signature';
export const DAY = 24 * 60 * 60 * 1000;

/**
 * A small in-memory Stripe: enough behaviour for the service (customers, subscriptions that start incomplete or
 * trialing, payments that complete them) plus switches to make it fail.
 */
export class FakeGateway implements StripeGateway {
  plans: StripePlan[] = [PLAN_MONTHLY, PLAN_YEARLY];
  customers = new Map<string, { userId: string; country: string | null; email: string | null }>();
  subs = new Map<string, SubscriptionSnapshot>();
  calls: string[] = [];
  createSubscriptionInputs: Array<Parameters<StripeGateway['createSubscription']>[0]> = [];
  failOn = new Set<string>();
  now: () => Date = () => new Date('2026-10-16T10:00:00Z');
  private seq = 0;

  private enter(name: string): void {
    this.calls.push(name);
    if (this.failOn.has(name)) throw Object.assign(new Error(`${name} failed`), { type: 'StripeAPIError' });
  }

  count(name: string): number {
    return this.calls.filter((c) => c === name).length;
  }

  async listPlans(lookupKeys: string[]): Promise<StripePlan[]> {
    this.enter('listPlans');
    return this.plans.filter((p) => lookupKeys.includes(p.id));
  }

  async createCustomer(input: { userId: string; country: string | null; email: string | null }): Promise<string> {
    this.enter('createCustomer');
    for (const [id, c] of this.customers) if (c.userId === input.userId) return id; // idempotent like Stripe's key
    const id = `cus_${++this.seq}`;
    this.customers.set(id, { userId: input.userId, country: input.country, email: input.email });
    return id;
  }

  async setCustomerCountry(customerId: string, country: string): Promise<void> {
    this.enter('setCustomerCountry');
    const c = this.customers.get(customerId);
    if (c) c.country = country;
  }

  async createEphemeralKey(customerId: string): Promise<string> {
    this.enter('createEphemeralKey');
    return `ek_${customerId}`;
  }

  async createSubscription(input: Parameters<StripeGateway['createSubscription']>[0]): Promise<SubscriptionSnapshot> {
    this.enter('createSubscription');
    this.createSubscriptionInputs.push(input);
    const id = `sub_${++this.seq}`;
    const trial = input.trialDays > 0;
    const snap: SubscriptionSnapshot = {
      stripeSubscriptionId: id,
      stripeCustomerId: input.customerId,
      status: trial ? 'trialing' : 'incomplete',
      planId: input.plan.id,
      priceId: input.plan.priceId,
      currency: input.plan.currency,
      unitAmount: input.plan.unitAmount,
      currentPeriodEnd: trial ? new Date(this.now().getTime() + input.trialDays * DAY) : null,
      cancelAtPeriodEnd: false,
      canceledAt: null,
      trialEnd: trial ? new Date(this.now().getTime() + input.trialDays * DAY) : null,
      paymentMethodAttached: !trial ? true : false,
      createdAt: this.now(),
      clerkUserId: input.userId,
      paymentClientSecret: trial ? null : `pi_${id}_secret_x`,
      setupClientSecret: trial ? `seti_${id}_secret_x` : null,
    };
    this.subs.set(id, snap);
    return { ...snap };
  }

  async retrieveSubscription(id: string): Promise<SubscriptionSnapshot | null> {
    this.enter('retrieveSubscription');
    const s = this.subs.get(id);
    return s ? { ...s } : null;
  }

  async listSubscriptions(customerId: string): Promise<SubscriptionSnapshot[]> {
    this.enter('listSubscriptions');
    return [...this.subs.values()].filter((s) => s.stripeCustomerId === customerId).map((s) => ({ ...s }));
  }

  async cancelNow(id: string): Promise<void> {
    this.enter('cancelNow');
    const s = this.subs.get(id);
    if (s) this.subs.set(id, { ...s, status: 'canceled', canceledAt: this.now(), paymentClientSecret: null, setupClientSecret: null });
  }

  async setCancelAtPeriodEnd(id: string, value: boolean): Promise<SubscriptionSnapshot> {
    this.enter('setCancelAtPeriodEnd');
    const s = this.subs.get(id);
    if (!s) throw new Error('no such subscription');
    const updated = { ...s, cancelAtPeriodEnd: value };
    this.subs.set(id, updated);
    return { ...updated };
  }

  async createPortalSession(customerId: string, returnUrl: string): Promise<string> {
    this.enter('createPortalSession');
    return `https://billing.stripe.test/portal/${customerId}?return=${encodeURIComponent(returnUrl)}`;
  }

  async deleteCustomer(customerId: string): Promise<void> {
    this.enter('deleteCustomer');
    this.customers.delete(customerId);
    for (const [id, s] of this.subs) if (s.stripeCustomerId === customerId) this.subs.set(id, { ...s, status: 'canceled', canceledAt: this.now() });
  }

  async constructEvent(rawBody: string, signature: string): Promise<StripeEventSummary> {
    this.enter('constructEvent');
    if (signature !== VALID_SIGNATURE) throw new Error('bad signature');
    return JSON.parse(rawBody) as StripeEventSummary;
  }

  // ---- test controls ----------------------------------------------------------------------------

  /** The user finished the payment sheet and the card was charged. */
  pay(id: string, periodDays = 30): void {
    const s = this.must(id);
    this.subs.set(id, {
      ...s, status: 'active', paymentMethodAttached: true, paymentClientSecret: null, setupClientSecret: null,
      currentPeriodEnd: new Date(this.now().getTime() + periodDays * DAY),
    });
  }

  /** The user finished the setup sheet of a trial. */
  completeSetup(id: string): void {
    const s = this.must(id);
    this.subs.set(id, { ...s, paymentMethodAttached: true, setupClientSecret: null });
  }

  patch(id: string, changes: Partial<SubscriptionSnapshot>): void {
    this.subs.set(id, { ...this.must(id), ...changes });
  }

  private must(id: string): SubscriptionSnapshot {
    const s = this.subs.get(id);
    if (!s) throw new Error(`unknown subscription ${id}`);
    return s;
  }
}

export function eventBody(event: Partial<StripeEventSummary> & { id: string }): string {
  return JSON.stringify({ type: 'customer.subscription.updated', subscriptionId: null, customerId: null, ...event });
}
