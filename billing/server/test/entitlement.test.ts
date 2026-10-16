import { describe, expect, it } from 'vitest';
import { computeEntitlement, publicStatus, RENEWAL_HORIZON_MS } from '../src/entitlement.js';
import type { SubscriptionRecord } from '../src/types.js';

const NOW = new Date('2026-10-16T10:00:00Z');
const DAY = 24 * 60 * 60 * 1000;
const at = (offsetMs: number) => new Date(NOW.getTime() + offsetMs);

function sub(overrides: Partial<SubscriptionRecord> = {}): SubscriptionRecord {
  return {
    stripeSubscriptionId: 'sub_1',
    userId: 'user_1',
    stripeCustomerId: 'cus_1',
    status: 'active',
    planId: 'premium_monthly',
    priceId: 'price_1',
    currency: 'eur',
    unitAmount: 999,
    currentPeriodEnd: at(30 * DAY),
    cancelAtPeriodEnd: false,
    canceledAt: null,
    trialEnd: null,
    paymentMethodAttached: true,
    createdAt: at(-10 * DAY),
    fetchedAt: NOW,
    ...overrides,
  };
}

describe('computeEntitlement', () => {
  it('is not premium without subscriptions', () => {
    expect(computeEntitlement([], NOW, 3)).toEqual({
      premium: false, status: 'none', planId: null, source: 'none', currentPeriodEnd: null,
      cancelAtPeriodEnd: false, trialEnd: null, premiumUntil: null,
    });
  });

  it('active renewing subscription is premium with a renewal horizon after the period end', () => {
    const e = computeEntitlement([sub()], NOW, 3);
    expect(e.premium).toBe(true);
    expect(e.status).toBe('active');
    expect(e.source).toBe('stripe');
    expect(e.currentPeriodEnd).toBe('2026-11-15T10:00:00Z');
    expect(e.premiumUntil).toBe(new Date(at(30 * DAY).getTime() + RENEWAL_HORIZON_MS).toISOString().replace('.000Z', 'Z'));
  });

  it('a subscription that is set to cancel keeps Premium exactly until the period end', () => {
    const e = computeEntitlement([sub({ cancelAtPeriodEnd: true })], NOW, 3);
    expect(e.premium).toBe(true);
    expect(e.cancelAtPeriodEnd).toBe(true);
    expect(e.premiumUntil).toBe(e.currentPeriodEnd);
  });

  it('trialing is premium', () => {
    const e = computeEntitlement([sub({ status: 'trialing', trialEnd: at(7 * DAY), currentPeriodEnd: at(7 * DAY) })], NOW, 3);
    expect(e.premium).toBe(true);
    expect(e.status).toBe('trialing');
    expect(e.trialEnd).toBe('2026-10-23T10:00:00Z');
  });

  it('a trial without a collected payment method is not premium and reads as incomplete', () => {
    const e = computeEntitlement([sub({ status: 'trialing', trialEnd: at(7 * DAY), currentPeriodEnd: at(7 * DAY), paymentMethodAttached: false })], NOW, 3);
    expect(e.premium).toBe(false);
    expect(e.status).toBe('incomplete');
    expect(e.premiumUntil).toBeNull();
  });

  it('past_due is premium only inside the grace window after the period end', () => {
    const within = computeEntitlement([sub({ status: 'past_due', currentPeriodEnd: at(-1 * DAY) })], NOW, 3);
    expect(within.premium).toBe(true);
    expect(within.status).toBe('past_due');
    expect(within.premiumUntil).toBe('2026-10-18T10:00:00Z');

    const expired = computeEntitlement([sub({ status: 'past_due', currentPeriodEnd: at(-4 * DAY) })], NOW, 3);
    expect(expired.premium).toBe(false);
    expect(expired.status).toBe('past_due');
    expect(expired.premiumUntil).toBeNull();
  });

  it('zero grace days means no access once a payment is overdue', () => {
    expect(computeEntitlement([sub({ status: 'past_due', currentPeriodEnd: at(-1000) })], NOW, 0).premium).toBe(false);
  });

  it.each(['incomplete', 'incomplete_expired', 'unpaid', 'canceled', 'paused'])('%s is not premium', (status) => {
    expect(computeEntitlement([sub({ status })], NOW, 3).premium).toBe(false);
  });

  it('prefers the premium subscription that lasts longest', () => {
    const monthly = sub({ stripeSubscriptionId: 'sub_m', planId: 'premium_monthly', currentPeriodEnd: at(10 * DAY) });
    const yearly = sub({ stripeSubscriptionId: 'sub_y', planId: 'premium_yearly', currentPeriodEnd: at(200 * DAY) });
    expect(computeEntitlement([monthly, yearly], NOW, 3).planId).toBe('premium_yearly');
  });

  it('explains a non-premium user with the newest subscription', () => {
    const old = sub({ stripeSubscriptionId: 'sub_old', status: 'canceled', createdAt: at(-90 * DAY) });
    const recent = sub({ stripeSubscriptionId: 'sub_new', status: 'incomplete', createdAt: at(-1 * DAY), planId: 'premium_yearly' });
    const e = computeEntitlement([old, recent], NOW, 3);
    expect(e.premium).toBe(false);
    expect(e.status).toBe('incomplete');
    expect(e.planId).toBe('premium_yearly');
  });

  it('maps unknown statuses to none and incomplete_expired to canceled', () => {
    expect(publicStatus('incomplete_expired')).toBe('canceled');
    expect(publicStatus('something_new')).toBe('none');
  });
});
