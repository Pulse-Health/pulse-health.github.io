import Stripe from 'stripe';
import { ensurePlans, type SetupSpec } from '../src/setup.js';

// Usage:
//   STRIPE_SECRET_KEY=sk_test_... npx tsx scripts/stripe-setup.ts --monthly 999 --yearly 7999 --currency eur [--tax inclusive] [--tax-code txcd_...] [--name "Pulse Premium"] [--dry-run]
//
// Amounts are in minor units. There are deliberately no default prices: the amounts are a business decision.

function arg(name: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

const key = process.env.STRIPE_SECRET_KEY;
const monthly = Number(arg('monthly'));
const yearly = Number(arg('yearly'));
const currency = (arg('currency') ?? '').toLowerCase();
if (!key || !Number.isInteger(monthly) || monthly <= 0 || !Number.isInteger(yearly) || yearly <= 0 || !/^[a-z]{3}$/.test(currency)) {
  console.error('Usage: STRIPE_SECRET_KEY=sk_... tsx scripts/stripe-setup.ts --monthly <minor units> --yearly <minor units> --currency <eur|usd|...> [--tax inclusive|exclusive] [--tax-code txcd_...] [--name "Pulse Premium"] [--dry-run]');
  process.exit(1);
}
const tax = arg('tax') ?? 'inclusive';
if (tax !== 'inclusive' && tax !== 'exclusive') {
  console.error('--tax must be "inclusive" or "exclusive"');
  process.exit(1);
}

const spec: SetupSpec = {
  productName: arg('name') ?? 'Pulse Premium',
  currency,
  taxBehavior: tax,
  ...(arg('tax-code') ? { taxCode: arg('tax-code')! } : {}),
  plans: [
    { lookupKey: 'premium_monthly', interval: 'month', unitAmount: monthly },
    { lookupKey: 'premium_yearly', interval: 'year', unitAmount: yearly },
  ],
};

const mode = key.startsWith('sk_live') || key.startsWith('rk_live') ? 'LIVE' : 'test';
console.log(`Stripe ${mode} mode${process.argv.includes('--dry-run') ? ' (dry run)' : ''}`);
for (const a of await ensurePlans(new Stripe(key), spec, { dryRun: process.argv.includes('--dry-run') })) {
  console.log(`${a.status.padEnd(12)} ${a.kind.padEnd(8)} ${a.key}${a.id ? `  ${a.id}` : ''}`);
}
