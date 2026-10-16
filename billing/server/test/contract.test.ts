import { readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import type { ZodType } from 'zod';
import { AccountDeletedResponse, CreateSubscriptionResponse, EntitlementResponse, ErrorResponse, OffersResponse, PortalResponse } from './wire.js';

const dir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'contract', 'fixtures');

// Every fixture must be covered here, so a new fixture cannot be added without a schema.
const schemas: Record<string, ZodType> = {
  'offers_available.json': OffersResponse,
  'offers_unavailable_region.json': OffersResponse,
  'entitlement_none.json': EntitlementResponse,
  'entitlement_active.json': EntitlementResponse,
  'entitlement_canceling.json': EntitlementResponse,
  'entitlement_past_due.json': EntitlementResponse,
  'subscription_payment.json': CreateSubscriptionResponse,
  'subscription_trial_setup.json': CreateSubscriptionResponse,
  'portal.json': PortalResponse,
  'account_deleted.json': AccountDeletedResponse,
  'error_already_subscribed.json': ErrorResponse,
  'error_purchase_not_available.json': ErrorResponse,
  'error_consent_required.json': ErrorResponse,
};

describe('contract fixtures', () => {
  it('has a schema for every fixture file', () => {
    expect(readdirSync(dir).filter((f) => f.endsWith('.json')).sort()).toEqual(Object.keys(schemas).sort());
  });

  it.each(Object.entries(schemas))('%s matches the contract', (file, schema) => {
    const result = schema.safeParse(JSON.parse(readFileSync(path.join(dir, file), 'utf8')));
    expect(result.success, result.success ? '' : JSON.stringify(result.error.issues)).toBe(true);
  });
});
