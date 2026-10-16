import { createHash } from 'node:crypto';
import type { BillingConfig } from './config.js';
import { computeEntitlement, isLive, isResumable, premiumUntil } from './entitlement.js';
import type { StripeGateway } from './gateway.js';
import { evaluatePurchase, isAllowedReturnUrl, requiresWithdrawalConsent } from './policy.js';
import type { PremiumAccessSink } from './premiumAccess.js';
import type { BillingStore } from './store.js';
import {
  BillingError,
  type EntitlementDto,
  type Platform,
  type PlanDto,
  type PurchaseAvailability,
  type StripePlan,
  type SubscriptionRecord,
  type SubscriptionSnapshot,
} from './types.js';

export interface Logger {
  info(message: string, fields?: Record<string, unknown>): void;
  warn(message: string, fields?: Record<string, unknown>): void;
  error(message: string, fields?: Record<string, unknown>): void;
}

export const silentLogger: Logger = { info() {}, warn() {}, error() {} };

export interface BillingDeps {
  gateway: StripeGateway;
  store: BillingStore;
  config: BillingConfig;
  now?: () => Date;
  logger?: Logger;
  /**
   * The Pulse backend's Premium table. When given, every stored subscription is mirrored into it (so the coaching
   * function, the onboarding gate and the other apps see Stripe subscribers) and redeemed codes are reported in the
   * entitlement. Leave it out for a standalone billing service.
   */
  access?: PremiumAccessSink;
  /**
   * Another place Premium can come from. Return null for "nothing". The result is merged with the Stripe
   * entitlement: the one that lasts longer wins. (`access` already covers redeemed codes.)
   */
  extraEntitlement?: (userId: string, now: Date) => Promise<EntitlementDto | null>;
}

export interface OffersResult {
  purchase: PurchaseAvailability;
  /** The app must show the consent to immediate performance / loss of the right of withdrawal and send `consent` when it is given. */
  requiresWithdrawalConsent: boolean;
  publishableKey: string;
  merchantDisplayName: string;
  plans: PlanDto[];
}

export interface CreateSubscriptionInput {
  planId: string;
  platform: Platform;
  country?: string | undefined;
  billingCountry?: string | undefined;
  consent?: { withdrawalWaiver: boolean; locale: string } | undefined;
}

export interface CreateSubscriptionResult {
  subscriptionId: string;
  status: string;
  customerId: string;
  customerEphemeralKeySecret: string;
  publishableKey: string;
  intent: { kind: 'payment' | 'setup'; clientSecret: string } | null;
}

const PLAN_CACHE_MS = 5 * 60 * 1000;
const EVENT_LOCK_MS = 60 * 1000;

export class BillingService {
  private readonly gateway: StripeGateway;
  private readonly store: BillingStore;
  private readonly cfg: BillingConfig;
  private readonly now: () => Date;
  private readonly log: Logger;
  private readonly extra: BillingDeps['extraEntitlement'];
  private readonly access: PremiumAccessSink | undefined;
  private plansCache: { at: number; plans: StripePlan[] } | null = null;

  constructor(deps: BillingDeps) {
    this.gateway = deps.gateway;
    this.store = deps.store;
    this.cfg = deps.config;
    this.now = deps.now ?? (() => new Date());
    this.log = deps.logger ?? silentLogger;
    this.extra = deps.extraEntitlement;
    this.access = deps.access;
  }

  // ---------------------------------------------------------------------------------------------- reads

  async getOffers(userId: string, platform: Platform, country: string | undefined): Promise<OffersResult> {
    const base = {
      publishableKey: this.cfg.stripePublishableKey,
      merchantDisplayName: this.cfg.merchantDisplayName,
      requiresWithdrawalConsent: requiresWithdrawalConsent(this.cfg, country),
    };
    let purchase = evaluatePurchase(this.cfg, platform, country);
    if (!purchase.available) return { ...base, purchase, plans: [] };

    const subs = await this.store.listSubscriptions(userId);
    if (subs.some(isLive)) return { ...base, purchase: { available: false, reason: 'already_subscribed' }, plans: [] };

    const plans = await this.getPlans();
    if (plans.length === 0) {
      this.log.error('no sellable plans found in Stripe', { planIds: this.cfg.planIds });
      purchase = { available: false, reason: 'billing_disabled' };
      return { ...base, purchase, plans: [] };
    }
    const trialDays = this.trialDaysFor(subs);
    return {
      ...base,
      purchase,
      plans: plans.map((p) => ({
        id: p.id,
        name: p.name,
        interval: p.interval,
        intervalCount: p.intervalCount,
        currency: p.currency,
        unitAmount: p.unitAmount,
        taxBehavior: p.taxBehavior,
        trialDays,
      })),
    };
  }

  async getEntitlement(userId: string): Promise<EntitlementDto> {
    const now = this.now();
    const subs = await this.store.listSubscriptions(userId);
    let entitlement = computeEntitlement(subs, now, this.cfg.pastDueGraceDays);
    if (this.access) {
      const other = await this.access.activeOtherAccess(userId, now).catch((error: unknown) => {
        this.log.warn('could not read other premium access; using Stripe only', { error: messageOf(error) });
        return null;
      });
      if (other) entitlement = longest(entitlement, codeEntitlement(other.endsAt));
    }
    return this.withExtra(userId, now, entitlement);
  }

  /** Re-reads the user's subscriptions from Stripe (after the payment sheet closed, or when the webhook is late). */
  async sync(userId: string): Promise<EntitlementDto> {
    const customerId = await this.store.getCustomerId(userId);
    if (customerId) await this.refreshFromStripe(userId, customerId);
    return this.getEntitlement(userId);
  }

  // ---------------------------------------------------------------------------------------------- purchase

  async createSubscription(
    userId: string,
    input: CreateSubscriptionInput,
    idempotencyKey?: string | null,
    profile?: { email?: string | null },
  ): Promise<CreateSubscriptionResult> {
    const availability = evaluatePurchase(this.cfg, input.platform, input.country);
    if (!availability.available) {
      throw new BillingError('purchase_not_available', 403, `Purchases are not offered here (${availability.reason}).`);
    }
    const plan = await this.findPlan(input.planId);
    const taxCountry = (input.billingCountry ?? input.country)?.toUpperCase() ?? null;
    if (this.cfg.automaticTax && !taxCountry) {
      throw new BillingError('invalid_request', 400, 'billingCountry is required while automatic tax is enabled.');
    }
    const consentGiven = input.consent?.withdrawalWaiver === true;
    if (requiresWithdrawalConsent(this.cfg, taxCountry ?? undefined) && !consentGiven) {
      throw new BillingError('consent_required', 400, 'The consent to immediate performance and loss of the right of withdrawal is required.');
    }

    return this.store.withUserLock(userId, async () => {
      let customerId = await this.store.getCustomerId(userId);
      if (customerId) await this.refreshFromStripe(userId, customerId);
      const subs = customerId ? await this.store.listSubscriptions(userId) : [];

      if (subs.some(isLive)) throw new BillingError('already_subscribed', 409, 'This account already has an active subscription.');

      // A payment sheet that was dismissed leaves an unpaid subscription behind: reopen it instead of piling up new ones.
      const resumable = subs.filter(isResumable);
      for (const old of resumable) {
        if (old.priceId === plan.priceId) {
          const fresh = await this.gateway.retrieveSubscription(old.stripeSubscriptionId);
          const intent = fresh && intentOf(fresh);
          if (fresh && intent && fresh.stripeCustomerId === customerId) {
            await this.recordSnapshot(userId, fresh, this.now());
            return this.respond(fresh, intent, fresh.stripeCustomerId);
          }
        }
      }
      for (const old of resumable) {
        await this.gateway.cancelNow(old.stripeSubscriptionId).catch((error: unknown) => {
          this.log.warn('could not cancel an abandoned subscription', { subscriptionId: old.stripeSubscriptionId, error: messageOf(error) });
        });
      }

      if (!customerId) {
        const created = await this.gateway.createCustomer({ userId, country: taxCountry, email: profile?.email ?? null });
        customerId = await this.store.insertCustomer(userId, created);
      } else if (this.cfg.automaticTax && taxCountry) {
        await this.gateway.setCustomerCountry(customerId, taxCountry);
      }

      const fetchedAt = this.now();
      const snapshot = await this.gateway.createSubscription({
        customerId,
        userId,
        plan,
        trialDays: this.trialDaysFor(subs),
        automaticTax: this.cfg.automaticTax,
        consent: consentGiven && input.consent ? { at: fetchedAt, locale: input.consent.locale.slice(0, 16) } : null,
        idempotencyKey: idempotencyKey ? hash(`${userId}:${idempotencyKey}`) : null,
      });
      await this.recordSnapshot(userId, snapshot, fetchedAt);

      const intent = intentOf(snapshot);
      if (!intent && (snapshot.status === 'incomplete' || (snapshot.status === 'trialing' && !snapshot.paymentMethodAttached))) {
        throw new BillingError('stripe_error', 502, 'Stripe did not return a payment secret for the new subscription.');
      }
      return this.respond(snapshot, intent, customerId);
    });
  }

  async cancel(userId: string): Promise<EntitlementDto> {
    const sub = await this.findLiveSubscription(userId, (s) => !s.cancelAtPeriodEnd);
    const fetchedAt = this.now();
    const updated = await this.gateway.setCancelAtPeriodEnd(sub.stripeSubscriptionId, true);
    await this.recordSnapshot(userId, updated, fetchedAt);
    return this.getEntitlement(userId);
  }

  async resume(userId: string): Promise<EntitlementDto> {
    const sub = await this.findLiveSubscription(userId, (s) => s.cancelAtPeriodEnd);
    const fetchedAt = this.now();
    const updated = await this.gateway.setCancelAtPeriodEnd(sub.stripeSubscriptionId, false);
    await this.recordSnapshot(userId, updated, fetchedAt);
    return this.getEntitlement(userId);
  }

  async createPortal(userId: string, returnUrl: string): Promise<string> {
    if (!isAllowedReturnUrl(returnUrl, this.cfg.portalReturnUrls)) {
      throw new BillingError('invalid_request', 400, 'returnUrl is not allowed.');
    }
    const customerId = await this.store.getCustomerId(userId);
    if (!customerId) throw new BillingError('no_customer', 404, 'There is no billing account for this user yet.');
    return this.gateway.createPortalSession(customerId, returnUrl);
  }

  /**
   * Account deletion: ends the subscription (Stripe deletes the customer, which cancels immediately, so a deleted
   * account is never billed again) and removes our rows. Stripe keeps its invoices, as accounting law requires.
   * Safe to call again after a partial failure.
   */
  async closeAccount(userId: string): Promise<void> {
    await this.store.withUserLock(userId, async () => {
      const customerId = await this.store.getCustomerId(userId);
      if (customerId) {
        try {
          await this.gateway.deleteCustomer(customerId);
        } catch (error) {
          throw stripeFailure(error);
        }
      }
      await this.access?.removeStripeAccess(userId);
      await this.store.deleteUser(userId);
    });
  }

  // ---------------------------------------------------------------------------------------------- webhook

  /** Verifies, de-duplicates and applies one Stripe event. Throws a BillingError with the status Stripe should see. */
  async handleWebhook(rawBody: string, signature: string | null): Promise<{ duplicate: boolean }> {
    if (!signature) throw new BillingError('invalid_request', 400, 'Missing Stripe-Signature header.');
    let event;
    try {
      event = await this.gateway.constructEvent(rawBody, signature);
    } catch {
      throw new BillingError('invalid_request', 400, 'Invalid Stripe signature.');
    }

    const claim = await this.store.claimEvent(event.id, event.type, this.now(), EVENT_LOCK_MS);
    if (claim === 'done') return { duplicate: true };
    if (claim === 'busy') throw new BillingError('internal', 503, 'This event is being processed; retry later.');

    try {
      if (event.subscriptionId) await this.refreshOne(event.subscriptionId, event.type);
      await this.store.completeEvent(event.id, this.now());
      return { duplicate: false };
    } catch (error) {
      await this.store.failEvent(event.id, messageOf(error)).catch(() => undefined);
      this.log.error('webhook processing failed', { eventId: event.id, type: event.type, error: messageOf(error) });
      throw error instanceof BillingError ? error : new BillingError('internal', 500, 'Webhook processing failed.');
    }
  }

  // ---------------------------------------------------------------------------------------------- internals

  /** Reads one subscription from Stripe and stores it. Events are only a trigger: the state always comes from Stripe, so event order is irrelevant. */
  private async refreshOne(subscriptionId: string, eventType: string): Promise<void> {
    const fetchedAt = this.now();
    const snapshot = await this.gateway.retrieveSubscription(subscriptionId);
    if (!snapshot) return;
    const userId = await this.store.getUserId(snapshot.stripeCustomerId);
    if (!userId) {
      // Not a customer of this service (the Stripe account may serve other products): nothing to do.
      this.log.info('ignoring event for a customer that is not a Pulse billing customer', { subscriptionId, eventType });
      return;
    }
    if (snapshot.clerkUserId && snapshot.clerkUserId !== userId) {
      this.log.warn('subscription metadata and customer mapping disagree; trusting the customer mapping', { subscriptionId });
    }
    await this.recordSnapshot(userId, snapshot, fetchedAt);
  }

  private async refreshFromStripe(userId: string, customerId: string): Promise<void> {
    const fetchedAt = this.now();
    let snapshots: SubscriptionSnapshot[];
    try {
      snapshots = await this.gateway.listSubscriptions(customerId);
    } catch (error) {
      throw stripeFailure(error);
    }
    for (const snapshot of snapshots) await this.recordSnapshot(userId, snapshot, fetchedAt);
  }

  private async recordSnapshot(userId: string, snapshot: SubscriptionSnapshot, fetchedAt: Date): Promise<void> {
    const { clerkUserId: _clerk, paymentClientSecret: _p, setupClientSecret: _s, ...rest } = snapshot;
    const record: SubscriptionRecord = { ...rest, userId, fetchedAt };
    const applied = await this.store.upsertSubscription(record);
    // A stale read (applied = false) must not touch the Premium table either.
    if (applied && this.access) {
      const now = this.now();
      await this.access.apply({
        userId,
        subscriptionId: record.stripeSubscriptionId,
        endsAt: premiumUntil(record, now, this.cfg.pastDueGraceDays),
        now,
      });
    }
  }

  private async getPlans(): Promise<StripePlan[]> {
    const nowMs = this.now().getTime();
    if (this.plansCache && nowMs - this.plansCache.at < PLAN_CACHE_MS) return this.plansCache.plans;
    try {
      const plans = await this.gateway.listPlans(this.cfg.planIds);
      this.plansCache = { at: nowMs, plans };
      return plans;
    } catch (error) {
      throw stripeFailure(error);
    }
  }

  private async findPlan(planId: string): Promise<StripePlan> {
    if (!this.cfg.planIds.includes(planId)) throw new BillingError('plan_not_found', 404, 'Unknown plan.');
    const plan = (await this.getPlans()).find((p) => p.id === planId);
    if (!plan) throw new BillingError('plan_not_found', 404, 'This plan is not available right now.');
    return plan;
  }

  /** A trial is offered once per user: only if none of their subscriptions ever got as far as holding a payment method. */
  private trialDaysFor(subs: readonly SubscriptionRecord[]): number {
    if (this.cfg.trialDays <= 0) return 0;
    const hadSubscription = subs.some((s) => s.paymentMethodAttached && s.status !== 'incomplete' && s.status !== 'incomplete_expired');
    return hadSubscription ? 0 : this.cfg.trialDays;
  }

  private async findLiveSubscription(userId: string, predicate: (s: SubscriptionRecord) => boolean): Promise<SubscriptionRecord> {
    const pick = (subs: SubscriptionRecord[]) => subs.find((s) => isLive(s) && predicate(s));
    let found = pick(await this.store.listSubscriptions(userId));
    if (!found) {
      const customerId = await this.store.getCustomerId(userId);
      if (customerId) {
        await this.refreshFromStripe(userId, customerId);
        found = pick(await this.store.listSubscriptions(userId));
      }
    }
    if (!found) throw new BillingError('no_subscription', 404, 'There is no matching subscription.');
    return found;
  }

  private async respond(
    snapshot: SubscriptionSnapshot,
    intent: CreateSubscriptionResult['intent'],
    customerId: string,
  ): Promise<CreateSubscriptionResult> {
    let ephemeral: string;
    try {
      ephemeral = await this.gateway.createEphemeralKey(customerId);
    } catch (error) {
      throw stripeFailure(error);
    }
    return {
      subscriptionId: snapshot.stripeSubscriptionId,
      status: snapshot.status,
      customerId,
      customerEphemeralKeySecret: ephemeral,
      publishableKey: this.cfg.stripePublishableKey,
      intent,
    };
  }

  private async withExtra(userId: string, now: Date, stripe: EntitlementDto): Promise<EntitlementDto> {
    if (!this.extra) return stripe;
    const other = await this.extra(userId, now).catch((error: unknown) => {
      this.log.warn('extra entitlement source failed; using Stripe only', { error: messageOf(error) });
      return null;
    });
    return other?.premium ? longest(stripe, other) : stripe;
  }
}

/** The entitlement for access that does not come from Stripe (a redeemed code). */
function codeEntitlement(endsAt: Date): EntitlementDto {
  const iso = endsAt.toISOString().replace(/\.\d{3}Z$/, 'Z');
  return { premium: true, status: 'active', planId: null, source: 'code', currentPeriodEnd: iso, cancelAtPeriodEnd: false, trialEnd: null, premiumUntil: iso };
}

/** Of two entitlements the one that gives Premium for longer; a premium one always beats a non-premium one. */
function longest(a: EntitlementDto, b: EntitlementDto): EntitlementDto {
  if (!a.premium) return b.premium ? b : a;
  if (!b.premium) return a;
  return Date.parse(b.premiumUntil ?? '') > Date.parse(a.premiumUntil ?? '') ? b : a;
}

function intentOf(snapshot: SubscriptionSnapshot): CreateSubscriptionResult['intent'] {
  if (snapshot.status === 'incomplete' && snapshot.paymentClientSecret) {
    return { kind: 'payment', clientSecret: snapshot.paymentClientSecret };
  }
  if (snapshot.status === 'trialing' && !snapshot.paymentMethodAttached && snapshot.setupClientSecret) {
    return { kind: 'setup', clientSecret: snapshot.setupClientSecret };
  }
  return null;
}

const hash = (value: string): string => createHash('sha256').update(value).digest('hex');

const messageOf = (error: unknown): string => (error instanceof Error ? error.message : String(error));

function stripeFailure(error: unknown): BillingError {
  if (error instanceof BillingError) return error;
  return new BillingError('stripe_error', 502, 'The payment provider is not reachable right now.');
}
