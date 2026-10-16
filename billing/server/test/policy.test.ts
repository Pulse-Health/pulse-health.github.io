import { describe, expect, it } from 'vitest';
import { evaluatePurchase, isAllowedReturnUrl, requiresWithdrawalConsent } from '../src/policy.js';

const base = { enabled: true, purchaseCountries: { ios: ['US'], android: ['US', 'GB'] } as const };

describe('evaluatePurchase', () => {
  it('allows listed countries per platform, case-insensitively', () => {
    expect(evaluatePurchase(base as never, 'ios', 'us')).toEqual({ available: true, reason: null });
    expect(evaluatePurchase(base as never, 'android', 'GB')).toEqual({ available: true, reason: null });
  });

  it('fails closed for other and unknown countries', () => {
    expect(evaluatePurchase(base as never, 'ios', 'DE')).toEqual({ available: false, reason: 'region_not_supported' });
    expect(evaluatePurchase(base as never, 'ios', undefined)).toEqual({ available: false, reason: 'region_not_supported' });
    expect(evaluatePurchase(base as never, 'ios', '')).toEqual({ available: false, reason: 'region_not_supported' });
  });

  it('honours the global kill switch before anything else', () => {
    expect(evaluatePurchase({ ...base, enabled: false } as never, 'ios', 'US')).toEqual({ available: false, reason: 'billing_disabled' });
  });

  it('"*" opens every country, including unknown, and an empty list closes the platform', () => {
    expect(evaluatePurchase({ enabled: true, purchaseCountries: { ios: '*', android: [] } }, 'ios', undefined).available).toBe(true);
    expect(evaluatePurchase({ enabled: true, purchaseCountries: { ios: '*', android: [] } }, 'android', 'US')).toEqual({
      available: false, reason: 'platform_not_supported',
    });
  });
});

describe('isAllowedReturnUrl', () => {
  const allowed = ['pulse://', 'https://app.example.com/', 'https://app.example.com/exact'];
  it.each([
    ['pulse://billing/return', true],
    ['https://app.example.com/billing', true],
    ['https://app.example.com/exact', true],
    ['https://app.example.com.evil.com/', false],
    ['https://evil.com/https://app.example.com/', false],
    ['http://app.example.com/billing', false],
    ['pulse:/billing', false],
    ['', false],
  ])('%s -> %s', (url, expected) => {
    expect(isAllowedReturnUrl(url, allowed)).toBe(expected);
  });
  it('exact entries do not act as prefixes, and an empty list allows nothing', () => {
    expect(isAllowedReturnUrl('https://x.test/exact/more', ['https://x.test/exact'])).toBe(false);
    expect(isAllowedReturnUrl('pulse://x', [])).toBe(false);
  });
});

describe('requiresWithdrawalConsent', () => {
  const cfg = { withdrawalConsentCountries: ['DE', 'FR'] };
  it('applies to the listed consumer countries, case-insensitively', () => {
    expect(requiresWithdrawalConsent(cfg, 'de')).toBe(true);
    expect(requiresWithdrawalConsent(cfg, 'US')).toBe(false);
  });
  it('treats an unknown country as required, unless nowhere requires it', () => {
    expect(requiresWithdrawalConsent(cfg, undefined)).toBe(true);
    expect(requiresWithdrawalConsent({ withdrawalConsentCountries: [] }, undefined)).toBe(false);
    expect(requiresWithdrawalConsent({ withdrawalConsentCountries: [] }, 'DE')).toBe(false);
  });
  it('"*" means everywhere', () => {
    expect(requiresWithdrawalConsent({ withdrawalConsentCountries: '*' }, 'US')).toBe(true);
  });
});
