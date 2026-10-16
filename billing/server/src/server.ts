import { serve } from '@hono/node-server';
import pg from 'pg';
import Stripe from 'stripe';
import { clerkJwks, createClerkAuthenticator } from './auth.js';
import { loadConfig } from './config.js';
import { createStripeGateway } from './gateway.js';
import { createBillingApp } from './http.js';
import { migrate } from './migrate.js';
import { PgBillingStore } from './pgStore.js';
import { PgPremiumAccess } from './premiumAccess.js';
import { BillingService, type Logger } from './service.js';

// Standalone entry point (for example a Railway service whose root directory is billing/server). To run the billing
// routes inside an existing service instead, import createBillingApp / BillingService from ./index.js.

const logger: Logger = {
  info: (message, fields) => console.log(JSON.stringify({ level: 'info', message, ...fields })),
  warn: (message, fields) => console.warn(JSON.stringify({ level: 'warn', message, ...fields })),
  error: (message, fields) => console.error(JSON.stringify({ level: 'error', message, ...fields })),
};

async function main(): Promise<void> {
  const config = loadConfig();
  if (process.env.BILLING_RUN_MIGRATIONS !== 'false') {
    const applied = await migrate(config.databaseUrl);
    if (applied.length) logger.info('migrations applied', { applied });
  }

  const pool = new pg.Pool({ connectionString: config.databaseUrl, max: 10 });
  const stripe = new Stripe(config.billing.stripeSecretKey, { maxNetworkRetries: 2, timeout: 20_000 });
  const gateway = createStripeGateway(stripe, {
    webhookSecret: config.billing.stripeWebhookSecret,
    ephemeralKeyApiVersion: config.billing.ephemeralKeyApiVersion,
  });
  const access = config.billing.syncPremiumAccess ? new PgPremiumAccess(pool) : undefined;
  await access?.verify();
  const service = new BillingService({ gateway, store: new PgBillingStore(pool), config: config.billing, logger, ...(access ? { access } : {}) });
  const app = createBillingApp({
    service,
    logger,
    authenticate: createClerkAuthenticator({
      keys: clerkJwks(config.clerkJwksUrl),
      issuer: config.clerkIssuer,
      authorizedParties: config.clerkAuthorizedParties,
    }),
  });

  const server = serve({ fetch: app.fetch, port: config.port }, (info) => logger.info('billing server listening', { port: info.port }));
  const shutdown = () => {
    server.close(() => void pool.end().finally(() => process.exit(0)));
    setTimeout(() => process.exit(1), 10_000).unref();
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
