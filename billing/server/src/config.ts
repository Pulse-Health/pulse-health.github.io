import { z } from 'zod';
import type { Platform } from './types.js';

// All behaviour that differs per deployment lives here, read from environment variables. Nothing secret has a default.

const csv = (value: string | undefined): string[] =>
  (value ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

const bool = (def: boolean) =>
  z
    .string()
    .optional()
    .transform((v) => (v === undefined || v === '' ? def : ['1', 'true', 'yes', 'on'].includes(v.toLowerCase())));

const int = (def: number, min = 0, max = 10_000) =>
  z
    .string()
    .optional()
    .transform((v) => (v === undefined || v === '' ? def : Number(v)))
    .pipe(z.number().int().min(min).max(max));

const DEFAULT_WITHDRAWAL_COUNTRIES =
  'AT,BE,BG,HR,CY,CZ,DK,EE,FI,FR,DE,GR,HU,IE,IT,LV,LT,LU,MT,NL,PL,PT,RO,SK,SI,ES,SE,IS,LI,NO,GB,CH';

const EnvSchema = z.object({
  STRIPE_SECRET_KEY: z.string().startsWith('sk_').or(z.string().startsWith('rk_')),
  STRIPE_PUBLISHABLE_KEY: z.string().startsWith('pk_'),
  STRIPE_WEBHOOK_SECRET: z.string().startsWith('whsec_'),
  /** API version of the ephemeral key. It must match the version the Stripe mobile SDK in the apps speaks. */
  STRIPE_EPHEMERAL_KEY_API_VERSION: z.string().default('2025-06-30.basil'),

  BILLING_ENABLED: bool(true),
  BILLING_MERCHANT_NAME: z.string().default('Pulse'),
  /** Stripe price lookup keys that are sold. */
  BILLING_PLANS: z.string().default('premium_monthly,premium_yearly'),
  BILLING_TRIAL_DAYS: int(0, 0, 365),
  /**
   * Where the apps may start a purchase (ISO 3166-1 alpha-2, comma separated, or `*` for everywhere).
   * Default: the United States only, the one storefront where both stores allow payment outside their own billing
   * without a separate programme. See billing/docs/store-policy.md before widening it.
   */
  BILLING_PURCHASE_COUNTRIES_IOS: z.string().default('US'),
  BILLING_PURCHASE_COUNTRIES_ANDROID: z.string().default('US'),
  /**
   * Countries whose consumers must expressly consent to immediate performance and acknowledge losing the 14-day withdrawal
   * right before a digital subscription starts (EU Consumer Rights Directive; in Germany § 356 Abs. 5 BGB). Default: EEA, UK and
   * Switzerland. Use `*` for everywhere, or an empty value for nowhere. Not legal advice: have it confirmed.
   */
  BILLING_WITHDRAWAL_CONSENT_COUNTRIES: z.string().default(DEFAULT_WITHDRAWAL_COUNTRIES),
  BILLING_AUTOMATIC_TAX: bool(false),
  /** Mirror subscriptions into the Pulse backend's user_premium_access table (needs migration 002). */
  BILLING_SYNC_PREMIUM_ACCESS: bool(true),
  /** Days Premium continues after a failed renewal while Stripe retries. */
  BILLING_PAST_DUE_GRACE_DAYS: int(3, 0, 30),
  /** Allowed `returnUrl` values for the customer portal: exact URLs or prefixes such as `pulse://`. */
  BILLING_PORTAL_RETURN_URLS: z.string().default(''),

  /**
   * Clerk. `CLERK_ISSUER` (your Frontend API URL, the same variable the Pulse API gateway uses) is enough: the keys are read from
   * `<issuer>/.well-known/jwks.json` and the token's `iss` must equal it. `CLERK_JWKS_URL` overrides the key location.
   */
  CLERK_ISSUER: z.string().url().optional(),
  CLERK_JWKS_URL: z.string().url().optional(),
  /** Optional: allowed `azp` values for tokens that carry one (web origins). Native tokens have none. */
  CLERK_AUTHORIZED_PARTIES: z.string().default(''),

  DATABASE_URL: z.string().min(1),
  PORT: int(3000, 1, 65535),
});

export interface BillingConfig {
  stripeSecretKey: string;
  stripePublishableKey: string;
  stripeWebhookSecret: string;
  ephemeralKeyApiVersion: string;
  enabled: boolean;
  merchantDisplayName: string;
  planIds: string[];
  trialDays: number;
  purchaseCountries: Record<Platform, string[] | '*'>;
  withdrawalConsentCountries: string[] | '*';
  automaticTax: boolean;
  syncPremiumAccess: boolean;
  pastDueGraceDays: number;
  portalReturnUrls: string[];
}

export interface ServerConfig {
  billing: BillingConfig;
  clerkJwksUrl: string;
  clerkIssuer: string | null;
  clerkAuthorizedParties: string[];
  databaseUrl: string;
  port: number;
}

const countries = (value: string): string[] | '*' => {
  const items = csv(value).map((c) => c.toUpperCase());
  if (items.includes('*')) return '*';
  for (const c of items) {
    if (!/^[A-Z]{2}$/.test(c)) throw new Error(`Invalid country code in purchase countries: ${JSON.stringify(c)}`);
  }
  return items;
};

export function loadConfig(env: Record<string, string | undefined> = process.env): ServerConfig {
  const parsed = EnvSchema.safeParse(env);
  if (!parsed.success) {
    const problems = parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ');
    // Never echo values: they may be secrets.
    throw new Error(`Invalid billing configuration: ${problems}`);
  }
  const e = parsed.data;
  // Clerk's `iss` has no trailing slash; accept one in the variable anyway.
  const issuer = e.CLERK_ISSUER ? e.CLERK_ISSUER.replace(/\/+$/, '') : null;
  const jwksUrl = e.CLERK_JWKS_URL ?? (issuer ? `${issuer}/.well-known/jwks.json` : null);
  if (!jwksUrl) throw new Error('Invalid billing configuration: set CLERK_ISSUER (your Clerk Frontend API URL) or CLERK_JWKS_URL');
  return {
    billing: {
      stripeSecretKey: e.STRIPE_SECRET_KEY,
      stripePublishableKey: e.STRIPE_PUBLISHABLE_KEY,
      stripeWebhookSecret: e.STRIPE_WEBHOOK_SECRET,
      ephemeralKeyApiVersion: e.STRIPE_EPHEMERAL_KEY_API_VERSION,
      enabled: e.BILLING_ENABLED,
      merchantDisplayName: e.BILLING_MERCHANT_NAME,
      planIds: csv(e.BILLING_PLANS),
      trialDays: e.BILLING_TRIAL_DAYS,
      purchaseCountries: {
        ios: countries(e.BILLING_PURCHASE_COUNTRIES_IOS),
        android: countries(e.BILLING_PURCHASE_COUNTRIES_ANDROID),
      },
      withdrawalConsentCountries: countries(e.BILLING_WITHDRAWAL_CONSENT_COUNTRIES),
      automaticTax: e.BILLING_AUTOMATIC_TAX,
      syncPremiumAccess: e.BILLING_SYNC_PREMIUM_ACCESS,
      pastDueGraceDays: e.BILLING_PAST_DUE_GRACE_DAYS,
      portalReturnUrls: csv(e.BILLING_PORTAL_RETURN_URLS),
    },
    clerkJwksUrl: jwksUrl,
    clerkIssuer: issuer,
    clerkAuthorizedParties: csv(e.CLERK_AUTHORIZED_PARTIES),
    databaseUrl: e.DATABASE_URL,
    port: e.PORT,
  };
}
