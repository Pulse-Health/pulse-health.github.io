import type { BillingConfig } from './config.js';
import type { Platform, PurchaseAvailability } from './types.js';

// Whether a purchase may be STARTED from this platform and country. This only gates the buy button and the
// create-subscription call. An existing subscription's entitlement is honoured everywhere.
//
// Why this exists: Apple (guideline 3.1.1) and Google Play require their own billing for digital subscriptions sold
// inside an app, except in storefronts / programmes where external payment is permitted. The allow-list is the
// operator's switch for that; it fails closed (unknown country => no purchase). See billing/docs/store-policy.md.

export function evaluatePurchase(
  cfg: Pick<BillingConfig, 'enabled' | 'purchaseCountries'>,
  platform: Platform,
  country: string | undefined,
): PurchaseAvailability {
  if (!cfg.enabled) return { available: false, reason: 'billing_disabled' };
  const allowed = cfg.purchaseCountries[platform];
  if (allowed === undefined) return { available: false, reason: 'platform_not_supported' };
  if (allowed === '*') return { available: true, reason: null };
  if (allowed.length === 0) return { available: false, reason: 'platform_not_supported' };
  const c = country?.trim().toUpperCase();
  if (!c || !allowed.includes(c)) return { available: false, reason: 'region_not_supported' };
  return { available: true, reason: null };
}

/**
 * Whether a customer-portal `returnUrl` is one of the operator's own. Entries ending in `/` or `://` are prefixes
 * (`pulse://`, `https://app.example.com/`), everything else must match exactly.
 */
export function isAllowedReturnUrl(returnUrl: string, allowed: readonly string[]): boolean {
  return allowed.some((entry) => (entry.endsWith('/') || entry.endsWith('://') ? returnUrl.startsWith(entry) : returnUrl === entry));
}

/**
 * Whether the buyer must tick the "start now and lose the right of withdrawal" consent. An unknown country counts as
 * required: the safe side.
 */
export function requiresWithdrawalConsent(cfg: Pick<BillingConfig, 'withdrawalConsentCountries'>, country: string | undefined): boolean {
  const list = cfg.withdrawalConsentCountries;
  if (list === '*') return true;
  const c = country?.trim().toUpperCase();
  if (!c) return list.length > 0;
  return list.includes(c);
}
