// Public surface for embedding billing in another Node service.
export { createBillingApp, type BillingAppOptions } from './http.js';
export { BillingService, type BillingDeps, type Logger } from './service.js';
export { createClerkAuthenticator, clerkJwks, type Authenticator } from './auth.js';
export { createStripeGateway, type StripeGateway } from './gateway.js';
export { PgBillingStore } from './pgStore.js';
export { MemoryBillingStore } from './memoryStore.js';
export { PgPremiumAccess, MemoryPremiumAccess, type PremiumAccessSink } from './premiumAccess.js';
export { loadConfig, type BillingConfig, type ServerConfig } from './config.js';
export { migrate } from './migrate.js';
export { computeEntitlement } from './entitlement.js';
export * from './types.js';
