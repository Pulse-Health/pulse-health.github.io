import { Hono, type Context } from 'hono';

type Env = { Variables: { userId: string; email: string | null } };
import { bodyLimit } from 'hono/body-limit';
import { ZodError, z } from 'zod';
import type { Authenticator } from './auth.js';
import { RateLimiter } from './rateLimit.js';
import { silentLogger, type BillingService, type Logger } from './service.js';
import { BillingError } from './types.js';

// The HTTP surface of billing/contract/openapi.yaml, as a Hono app built from web-standard Request/Response. Mount it
// in an existing Hono service with `app.route('/', createBillingApp(...))`, or run it alone (src/server.ts).

export interface BillingAppOptions {
  service: BillingService;
  authenticate: Authenticator;
  logger?: Logger;
  now?: () => Date;
}

const country = z.string().regex(/^[A-Za-z]{2}$/);
const PlatformSchema = z.enum(['ios', 'android']);

const OffersQuery = z.object({ platform: PlatformSchema, country: country.optional() });
const CreateSubscriptionBody = z.object({
  planId: z.string().min(1).max(64),
  platform: PlatformSchema,
  country: country.optional(),
  billingCountry: country.optional(),
  consent: z.object({ withdrawalWaiver: z.boolean(), locale: z.string().min(2).max(16) }).optional(),
});
const PortalBody = z.object({ returnUrl: z.string().min(1).max(2048) });

export function createBillingApp(options: BillingAppOptions): Hono {
  const { service, authenticate } = options;
  const log = options.logger ?? silentLogger;
  const now = options.now ?? (() => new Date());

  const light = new RateLimiter(120, 60_000);
  const heavy = new RateLimiter(10, 60_000); // anything that calls Stripe on the user's behalf

  const app = new Hono();

  app.use('*', async (c, next) => {
    // Echo the caller's request id only if it is a plain token; anything else could not be set as a header value safely.
    const supplied = c.req.header('x-request-id');
    const requestId = supplied && /^[A-Za-z0-9._-]{1,64}$/.test(supplied) ? supplied : crypto.randomUUID();
    c.header('x-request-id', requestId);
    c.header('cache-control', 'no-store');
    await next();
  });

  app.get('/healthz', (c) => c.json({ ok: true }));

  // ---------------------------------------------------------------------------------------------- webhook
  // Registered before the JSON body limit: Stripe signs the exact bytes, so the body is read as text, never parsed first.
  app.post('/v1/billing/webhook', bodyLimit({ maxSize: 1024 * 1024, onError: tooLarge }), async (c) => {
    const rawBody = await c.req.text();
    const result = await service.handleWebhook(rawBody, c.req.header('stripe-signature') ?? null);
    return c.json({ received: true, duplicate: result.duplicate });
  });

  // ---------------------------------------------------------------------------------------------- app endpoints
  const api = new Hono<Env>();
  api.use('*', bodyLimit({ maxSize: 16 * 1024, onError: tooLarge }));
  api.use('*', async (c, next) => {
    const user = await authenticate(c.req.raw).catch((error: unknown) => {
      c.header('www-authenticate', 'Bearer');
      throw error;
    });
    c.set('userId', user.userId);
    c.set('email', user.email ?? null);
    await next();
  });

  const userOf = (c: Context<Env>): string => c.get('userId');
  const limit = (limiter: RateLimiter, c: Context<Env>, bucket: string) => {
    if (!limiter.take(`${bucket}:${userOf(c)}`)) throw new BillingError('rate_limited', 429, 'Too many requests. Try again in a minute.');
  };

  api.get('/offers', async (c) => {
    limit(light, c, 'offers');
    const q = OffersQuery.parse({ platform: c.req.query('platform'), country: c.req.query('country') || undefined });
    return c.json(await service.getOffers(userOf(c), q.platform, q.country));
  });

  api.get('/entitlement', async (c) => {
    limit(light, c, 'entitlement');
    return c.json({ entitlement: await service.getEntitlement(userOf(c)), serverTime: iso(now()) });
  });

  api.post('/subscriptions', async (c) => {
    limit(heavy, c, 'subscriptions');
    const body = CreateSubscriptionBody.parse(await readJson(c));
    const key = c.req.header('idempotency-key');
    return c.json(await service.createSubscription(userOf(c), body, key && key.length <= 255 ? key : null, { email: c.get('email') }));
  });

  api.post('/sync', async (c) => {
    limit(heavy, c, 'sync');
    return c.json({ entitlement: await service.sync(userOf(c)), serverTime: iso(now()) });
  });

  api.post('/subscription/cancel', async (c) => {
    limit(heavy, c, 'cancel');
    return c.json({ entitlement: await service.cancel(userOf(c)), serverTime: iso(now()) });
  });

  api.post('/subscription/resume', async (c) => {
    limit(heavy, c, 'resume');
    return c.json({ entitlement: await service.resume(userOf(c)), serverTime: iso(now()) });
  });

  api.post('/portal', async (c) => {
    limit(heavy, c, 'portal');
    const body = PortalBody.parse(await readJson(c));
    return c.json({ url: await service.createPortal(userOf(c), body.returnUrl) });
  });

  api.delete('/account', async (c) => {
    limit(heavy, c, 'account');
    await service.closeAccount(userOf(c));
    return c.json({ deleted: true });
  });

  app.route('/v1/billing', api);

  // ---------------------------------------------------------------------------------------------- errors
  app.notFound((c) => c.json(errorBody('invalid_request', 'Not found.'), 404));

  app.onError((error, c) => {
    if (error instanceof BillingError) {
      if (error.status >= 500) log.error('billing request failed', { code: error.code, path: c.req.path });
      return c.json(errorBody(error.code, error.message), error.status as 400);
    }
    if (error instanceof ZodError) {
      return c.json(errorBody('invalid_request', 'The request is malformed.'), 400);
    }
    if (isStripeError(error)) {
      log.error('stripe error', { path: c.req.path, type: error.type, code: error.code });
      return c.json(errorBody('stripe_error', 'The payment provider rejected or could not process the request.'), 502);
    }
    log.error('unexpected error', { path: c.req.path, error: error instanceof Error ? error.message : String(error) });
    return c.json(errorBody('internal', 'Something went wrong.'), 500);
  });

  return app;
}

async function readJson(c: Context): Promise<unknown> {
  try {
    return await c.req.json();
  } catch {
    throw new BillingError('invalid_request', 400, 'The request body must be JSON.');
  }
}

const tooLarge = (c: Context) => c.json(errorBody('invalid_request', 'The request body is too large.'), 413);

const errorBody = (code: string, message: string) => ({ error: { code, message } });

const iso = (d: Date) => d.toISOString().replace(/\.\d{3}Z$/, 'Z');

function isStripeError(error: unknown): error is { type: string; code?: string } {
  return typeof error === 'object' && error !== null && typeof (error as { type?: unknown }).type === 'string' && /^Stripe/.test((error as { type: string }).type);
}
