import type Stripe from 'stripe';
import { describe, expect, it, vi } from 'vitest';
import { ensurePlans, type SetupSpec } from '../src/setup.js';

const spec: SetupSpec = {
  productName: 'Pulse Premium', currency: 'eur', taxBehavior: 'inclusive',
  plans: [{ lookupKey: 'premium_monthly', interval: 'month', unitAmount: 999 }, { lookupKey: 'premium_yearly', interval: 'year', unitAmount: 7999 }],
};

function fake(existing: { products?: unknown[]; prices?: unknown[] } = {}) {
  const stripe = {
    products: { search: vi.fn(async () => ({ data: existing.products ?? [] })), create: vi.fn(async () => ({ id: 'prod_new' })) },
    prices: { list: vi.fn(async () => ({ data: existing.prices ?? [] })), create: vi.fn(async () => ({ id: 'price_new' })) },
  };
  return { stripe, client: stripe as unknown as Stripe };
}
const price = (key: string, amount: number, interval: string, currency = 'eur') => ({ id: `price_${key}`, lookup_key: key, unit_amount: amount, currency, recurring: { interval } });

describe('ensurePlans', () => {
  it('creates the product and both prices on an empty account', async () => {
    const { stripe, client } = fake();
    const actions = await ensurePlans(client, spec);
    expect(actions.map((a) => `${a.kind}:${a.key}:${a.status}`)).toEqual(['product:Pulse Premium:created', 'price:premium_monthly:created', 'price:premium_yearly:created']);
    expect(stripe.prices.create).toHaveBeenCalledWith({ product: 'prod_new', currency: 'eur', unit_amount: 999, recurring: { interval: 'month' }, lookup_key: 'premium_monthly', tax_behavior: 'inclusive' });
  });

  it('is a no-op the second time', async () => {
    const { stripe, client } = fake({ products: [{ id: 'prod_1' }], prices: [price('premium_monthly', 999, 'month'), price('premium_yearly', 7999, 'year')] });
    const actions = await ensurePlans(client, spec);
    expect(actions.every((a) => a.status === 'exists')).toBe(true);
    expect(stripe.products.create).not.toHaveBeenCalled();
    expect(stripe.prices.create).not.toHaveBeenCalled();
  });

  it('only creates what is missing', async () => {
    const { stripe, client } = fake({ products: [{ id: 'prod_1' }], prices: [price('premium_monthly', 999, 'month')] });
    await ensurePlans(client, spec);
    expect(stripe.prices.create).toHaveBeenCalledTimes(1);
    expect(stripe.prices.create).toHaveBeenCalledWith(expect.objectContaining({ product: 'prod_1', lookup_key: 'premium_yearly' }));
  });

  it('refuses to silently disagree with an existing price', async () => {
    const { client } = fake({ products: [{ id: 'prod_1' }], prices: [price('premium_monthly', 1299, 'month'), price('premium_yearly', 7999, 'year')] });
    await expect(ensurePlans(client, spec)).rejects.toThrow(/immutable/);
  });

  it('changes nothing in a dry run', async () => {
    const { stripe, client } = fake();
    const actions = await ensurePlans(client, spec, { dryRun: true });
    expect(actions.every((a) => a.status === 'would-create')).toBe(true);
    expect(stripe.products.create).not.toHaveBeenCalled();
    expect(stripe.prices.create).not.toHaveBeenCalled();
  });
});
