import type Stripe from 'stripe';

// Creates the Stripe objects the billing service sells: one product and recurring prices addressed by lookup_key. The
// service finds prices by lookup key, so no price ids are ever configured. Safe to run repeatedly: it never edits or
// duplicates an existing price (Stripe prices are immutable; to change an amount create a new price and move the lookup key).

export interface PlanSpec {
  lookupKey: string;
  interval: 'month' | 'year';
  /** Minor units, e.g. 999 = 9.99. */
  unitAmount: number;
}

export interface SetupSpec {
  productName: string;
  currency: string;
  taxBehavior: 'inclusive' | 'exclusive';
  /** Stripe product tax code for Stripe Tax (for example `txcd_10000000`, electronically supplied services). Optional. */
  taxCode?: string;
  plans: PlanSpec[];
}

export interface SetupAction {
  kind: 'product' | 'price';
  key: string;
  status: 'exists' | 'created' | 'would-create';
  id?: string;
}

const PRODUCT_METADATA_KEY = 'pulse_billing_product';

export async function ensurePlans(stripe: Stripe, spec: SetupSpec, options: { dryRun?: boolean } = {}): Promise<SetupAction[]> {
  const actions: SetupAction[] = [];
  const dryRun = options.dryRun ?? false;

  const found = await stripe.products.search({ query: `active:'true' AND metadata['${PRODUCT_METADATA_KEY}']:'premium'`, limit: 1 });
  let productId = found.data[0]?.id;
  if (productId) {
    actions.push({ kind: 'product', key: spec.productName, status: 'exists', id: productId });
  } else if (dryRun) {
    actions.push({ kind: 'product', key: spec.productName, status: 'would-create' });
  } else {
    const product = await stripe.products.create({
      name: spec.productName,
      metadata: { [PRODUCT_METADATA_KEY]: 'premium' },
      ...(spec.taxCode ? { tax_code: spec.taxCode } : {}),
    });
    productId = product.id;
    actions.push({ kind: 'product', key: spec.productName, status: 'created', id: productId });
  }

  const existing = await stripe.prices.list({ lookup_keys: spec.plans.map((p) => p.lookupKey), active: true, limit: 10 });
  const byKey = new Map(existing.data.map((p) => [p.lookup_key, p]));
  for (const plan of spec.plans) {
    const price = byKey.get(plan.lookupKey);
    if (price) {
      const same = price.unit_amount === plan.unitAmount && price.currency === spec.currency && price.recurring?.interval === plan.interval;
      if (!same) {
        throw new Error(
          `Price "${plan.lookupKey}" already exists as ${price.unit_amount} ${price.currency}/${price.recurring?.interval}, ` +
            `which differs from the requested ${plan.unitAmount} ${spec.currency}/${plan.interval}. Prices are immutable: create a new price ` +
            `in the Stripe dashboard with "transfer lookup key" enabled instead.`,
        );
      }
      actions.push({ kind: 'price', key: plan.lookupKey, status: 'exists', id: price.id });
      continue;
    }
    if (dryRun || !productId) {
      actions.push({ kind: 'price', key: plan.lookupKey, status: 'would-create' });
      continue;
    }
    const created = await stripe.prices.create({
      product: productId,
      currency: spec.currency,
      unit_amount: plan.unitAmount,
      recurring: { interval: plan.interval },
      lookup_key: plan.lookupKey,
      tax_behavior: spec.taxBehavior,
    });
    actions.push({ kind: 'price', key: plan.lookupKey, status: 'created', id: created.id });
  }
  return actions;
}
