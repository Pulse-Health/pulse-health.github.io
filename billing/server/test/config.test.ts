import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/config.js';

const base = {
  STRIPE_SECRET_KEY: 'sk_test_abc',
  STRIPE_PUBLISHABLE_KEY: 'pk_test_abc',
  STRIPE_WEBHOOK_SECRET: 'whsec_abc',
  CLERK_ISSUER: 'https://eager-fly-1.clerk.accounts.dev',
  DATABASE_URL: 'postgres://u:p@h:5432/d',
};

describe('loadConfig', () => {
  it('needs only the Stripe keys, the Clerk issuer and the database, and defaults everything else safely', () => {
    const c = loadConfig(base);
    expect(c.clerkJwksUrl).toBe('https://eager-fly-1.clerk.accounts.dev/.well-known/jwks.json');
    expect(c.clerkIssuer).toBe('https://eager-fly-1.clerk.accounts.dev');
    expect(c.billing).toMatchObject({
      enabled: true,
      planIds: ['premium_monthly', 'premium_yearly'],
      trialDays: 0,
      purchaseCountries: { ios: ['US'], android: ['US'] },
      automaticTax: false,
      syncPremiumAccess: true,
      pastDueGraceDays: 3,
      portalReturnUrls: [],
    });
    expect(c.port).toBe(3000);
  });

  it('withdrawal consent defaults to the EU, EEA, UK and Switzerland', () => {
    const list = loadConfig(base).billing.withdrawalConsentCountries;
    expect(list).toEqual(expect.arrayContaining(['DE', 'FR', 'AT', 'IT', 'ES', 'NL', 'NO', 'IS', 'GB', 'CH']));
    expect(list).not.toContain('US');
    expect(list).toHaveLength(32);
  });

  it('accepts a trailing slash on the issuer and an explicit JWKS location', () => {
    expect(loadConfig({ ...base, CLERK_ISSUER: 'https://x.clerk.accounts.dev/' }).clerkIssuer).toBe('https://x.clerk.accounts.dev');
    expect(loadConfig({ ...base, CLERK_ISSUER: 'https://x.clerk.accounts.dev/' }).clerkJwksUrl).toBe('https://x.clerk.accounts.dev/.well-known/jwks.json');
    const explicit = loadConfig({ ...base, CLERK_JWKS_URL: 'https://keys.example.com/jwks' });
    expect(explicit.clerkJwksUrl).toBe('https://keys.example.com/jwks');
    expect(explicit.clerkIssuer).toBe('https://eager-fly-1.clerk.accounts.dev');
  });

  it('works with only a JWKS URL (no issuer check) and fails with neither', () => {
    const { CLERK_ISSUER: _drop, ...noIssuer } = base;
    expect(loadConfig({ ...noIssuer, CLERK_JWKS_URL: 'https://keys.example.com/jwks' }).clerkIssuer).toBeNull();
    expect(() => loadConfig(noIssuer)).toThrow(/CLERK_ISSUER/);
  });

  it('parses country lists, "*" and rejects malformed codes', () => {
    const c = loadConfig({ ...base, BILLING_PURCHASE_COUNTRIES_IOS: 'us, de ,GB', BILLING_PURCHASE_COUNTRIES_ANDROID: '*' });
    expect(c.billing.purchaseCountries).toEqual({ ios: ['US', 'DE', 'GB'], android: '*' });
    expect(() => loadConfig({ ...base, BILLING_PURCHASE_COUNTRIES_IOS: 'USA' })).toThrow(/Invalid country code/);
    expect(loadConfig({ ...base, BILLING_WITHDRAWAL_CONSENT_COUNTRIES: '' }).billing.withdrawalConsentCountries).toEqual([]);
  });

  it('parses booleans and numbers', () => {
    const c = loadConfig({ ...base, BILLING_ENABLED: 'false', BILLING_AUTOMATIC_TAX: 'TRUE', BILLING_SYNC_PREMIUM_ACCESS: '0', BILLING_TRIAL_DAYS: '14', BILLING_PAST_DUE_GRACE_DAYS: '5', PORT: '8080' });
    expect(c.billing).toMatchObject({ enabled: false, automaticTax: true, syncPremiumAccess: false, trialDays: 14, pastDueGraceDays: 5 });
    expect(c.port).toBe(8080);
    expect(() => loadConfig({ ...base, BILLING_TRIAL_DAYS: '-1' })).toThrow();
    expect(() => loadConfig({ ...base, PORT: 'abc' })).toThrow();
  });

  it('rejects keys of the wrong kind without echoing any value', () => {
    for (const bad of [{ STRIPE_SECRET_KEY: 'pk_test_wrong' }, { STRIPE_PUBLISHABLE_KEY: 'sk_test_wrong' }, { STRIPE_WEBHOOK_SECRET: 'nope' }]) {
      let message = '';
      try { loadConfig({ ...base, ...bad }); } catch (error) { message = (error as Error).message; }
      expect(message).toMatch(/Invalid billing configuration/);
      for (const value of Object.values(bad)) expect(message).not.toContain(value);
    }
  });

  it('accepts restricted Stripe keys', () => {
    expect(loadConfig({ ...base, STRIPE_SECRET_KEY: 'rk_live_abc' }).billing.stripeSecretKey).toBe('rk_live_abc');
  });

  it('portal return URLs are a list', () => {
    expect(loadConfig({ ...base, BILLING_PORTAL_RETURN_URLS: 'pulse://, https://app.example.com/billing' }).billing.portalReturnUrls).toEqual(['pulse://', 'https://app.example.com/billing']);
  });
});
