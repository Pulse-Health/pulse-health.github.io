import type { BillingConfig } from '../src/config.js';
import { MemoryBillingStore } from '../src/memoryStore.js';
import { MemoryPremiumAccess } from '../src/premiumAccess.js';
import { BillingService } from '../src/service.js';
import { FakeGateway } from './fakes.js';

export function testConfig(overrides: Partial<BillingConfig> = {}): BillingConfig {
  return {
    stripeSecretKey: 'sk_test_x',
    stripePublishableKey: 'pk_test_x',
    stripeWebhookSecret: 'whsec_x',
    ephemeralKeyApiVersion: '2025-06-30.basil',
    enabled: true,
    merchantDisplayName: 'Pulse',
    planIds: ['premium_monthly', 'premium_yearly'],
    trialDays: 0,
    purchaseCountries: { ios: ['US'], android: ['US', 'GB'] },
    withdrawalConsentCountries: ['DE', 'FR', 'GB'],
    automaticTax: false,
    syncPremiumAccess: true,
    pastDueGraceDays: 3,
    portalReturnUrls: ['pulse://', 'https://app.example.com/billing/return'],
    ...overrides,
  };
}

export function setup(overrides: Partial<BillingConfig> = {}) {
  const gateway = new FakeGateway();
  const store = new MemoryBillingStore();
  const clock = { now: new Date('2026-10-16T10:00:00Z') };
  gateway.now = () => clock.now;
  const access = new MemoryPremiumAccess();
  const service = new BillingService({ gateway, store, config: testConfig(overrides), now: () => clock.now, access });
  return { gateway, store, service, clock, access };
}

export const USER = 'user_A';
export const OTHER_USER = 'user_B';
export const IOS_US = { planId: 'premium_monthly', platform: 'ios', country: 'US' } as const;
