import type { EntitlementDto, EntitlementStatus, SubscriptionRecord } from './types.js';

// Pure rules that turn stored subscriptions into the entitlement the apps see.

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * After the end of a paid period a renewing subscription stays `active` until Stripe has tried to collect. Clients
 * that cache the entitlement offline are told to trust it this much longer than the period end so that the moment
 * of renewal never flips a paying user to free.
 */
export const RENEWAL_HORIZON_MS = DAY_MS;

export const NO_ENTITLEMENT: EntitlementDto = {
  premium: false,
  status: 'none',
  planId: null,
  source: 'none',
  currentPeriodEnd: null,
  cancelAtPeriodEnd: false,
  trialEnd: null,
  premiumUntil: null,
};

const iso = (d: Date | null): string | null => (d ? d.toISOString().replace(/\.\d{3}Z$/, 'Z') : null);

/** Maps Stripe's status string to the smaller set the contract exposes. */
export function publicStatus(stripeStatus: string): EntitlementStatus {
  switch (stripeStatus) {
    case 'trialing':
    case 'active':
    case 'past_due':
    case 'incomplete':
    case 'unpaid':
    case 'canceled':
    case 'paused':
      return stripeStatus;
    case 'incomplete_expired':
      return 'canceled';
    default:
      return 'none';
  }
}

/** A trial whose payment sheet was dismissed: it exists in Stripe but cannot ever be charged, so it is not a subscription yet. */
export function isTrialAwaitingPaymentMethod(sub: SubscriptionRecord): boolean {
  return sub.status === 'trialing' && !sub.paymentMethodAttached;
}

/** Instant until which this subscription alone justifies Premium, or null when it does not. */
export function premiumUntil(sub: SubscriptionRecord, now: Date, pastDueGraceDays: number): Date | null {
  if (isTrialAwaitingPaymentMethod(sub)) return null;
  switch (sub.status) {
    case 'trialing':
    case 'active': {
      const end = sub.currentPeriodEnd ?? sub.trialEnd;
      if (!end) return new Date(now.getTime() + RENEWAL_HORIZON_MS);
      // A subscription that will not renew has no renewal horizon: access ends with the paid period.
      return sub.cancelAtPeriodEnd ? end : new Date(end.getTime() + RENEWAL_HORIZON_MS);
    }
    case 'past_due': {
      if (!sub.currentPeriodEnd) return null;
      const until = new Date(sub.currentPeriodEnd.getTime() + pastDueGraceDays * DAY_MS);
      return until.getTime() > now.getTime() ? until : null;
    }
    default:
      return null;
  }
}

/**
 * The entitlement of a user from all of their stored subscriptions: the premium one that lasts longest wins; with
 * none, the most recently created subscription explains why the user is not premium (for example `canceled`).
 */
export function computeEntitlement(
  subs: readonly SubscriptionRecord[],
  now: Date,
  pastDueGraceDays: number,
): EntitlementDto {
  let best: { sub: SubscriptionRecord; until: Date } | null = null;
  for (const sub of subs) {
    const until = premiumUntil(sub, now, pastDueGraceDays);
    if (until && (!best || until.getTime() > best.until.getTime())) best = { sub, until };
  }
  if (best) return toDto(best.sub, true, best.until);

  const newest = [...subs].sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())[0];
  return newest ? toDto(newest, false, null) : NO_ENTITLEMENT;
}

function toDto(sub: SubscriptionRecord, premium: boolean, until: Date | null): EntitlementDto {
  return {
    premium,
    status: isTrialAwaitingPaymentMethod(sub) ? 'incomplete' : publicStatus(sub.status),
    planId: sub.planId,
    source: 'stripe',
    currentPeriodEnd: iso(sub.currentPeriodEnd),
    cancelAtPeriodEnd: sub.cancelAtPeriodEnd,
    trialEnd: iso(sub.trialEnd),
    premiumUntil: iso(until),
  };
}

const LIVE_STATUSES: ReadonlySet<string> = new Set(['active', 'trialing', 'past_due', 'paused', 'unpaid']);

/** The user already has (or is paying for) a subscription and must not buy another one. */
export function isLive(sub: SubscriptionRecord): boolean {
  return LIVE_STATUSES.has(sub.status) && !isTrialAwaitingPaymentMethod(sub);
}

/** A subscription that was started but never paid / never got a payment method: the payment sheet can be reopened for it. */
export function isResumable(sub: SubscriptionRecord): boolean {
  return sub.status === 'incomplete' || isTrialAwaitingPaymentMethod(sub);
}
