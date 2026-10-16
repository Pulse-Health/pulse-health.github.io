import { z } from 'zod';

// The response schemas of billing/contract/openapi.yaml as zod. Used to check that the contract fixtures (which the
// iOS and Android clients also parse) and the server's real responses agree on every field.

const date = z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);

export const Plan = z.strictObject({
  id: z.string(), name: z.string(), interval: z.enum(['month', 'year']), intervalCount: z.number().int().min(1),
  currency: z.string(), unitAmount: z.number().int(), taxBehavior: z.enum(['inclusive', 'exclusive', 'unspecified']),
  trialDays: z.number().int().min(0),
});

export const OffersResponse = z.strictObject({
  purchase: z.strictObject({
    available: z.boolean(),
    reason: z.enum(['billing_disabled', 'platform_not_supported', 'region_not_supported', 'already_subscribed']).nullable(),
  }),
  requiresWithdrawalConsent: z.boolean(),
  publishableKey: z.string(), merchantDisplayName: z.string(), plans: z.array(Plan),
});

export const Entitlement = z.strictObject({
  premium: z.boolean(),
  status: z.enum(['none', 'trialing', 'active', 'past_due', 'incomplete', 'unpaid', 'canceled', 'paused']),
  planId: z.string().nullable(),
  source: z.enum(['none', 'stripe', 'code']),
  currentPeriodEnd: date.nullable(),
  cancelAtPeriodEnd: z.boolean(),
  trialEnd: date.nullable(),
  premiumUntil: date.nullable(),
});

export const EntitlementResponse = z.strictObject({ entitlement: Entitlement, serverTime: date });

export const CreateSubscriptionResponse = z.strictObject({
  subscriptionId: z.string(), status: z.string(), customerId: z.string(), customerEphemeralKeySecret: z.string(),
  publishableKey: z.string(),
  intent: z.strictObject({ kind: z.enum(['payment', 'setup']), clientSecret: z.string() }).nullable(),
});

export const PortalResponse = z.strictObject({ url: z.string().url() });

export const ErrorResponse = z.strictObject({
  error: z.strictObject({
    code: z.enum(['unauthorized', 'invalid_request', 'consent_required', 'purchase_not_available', 'plan_not_found', 'already_subscribed', 'no_subscription', 'no_customer', 'rate_limited', 'stripe_error', 'internal']),
    message: z.string(),
  }),
});

export const AccountDeletedResponse = z.strictObject({ deleted: z.literal(true) });
