# Design decisions

Each entry: what was decided, why, and what would change it.

## 1. Stripe directly, not Clerk Billing

You asked to check whether payments should go through Clerk directly. They should not, today.

Clerk Billing is Clerk's own subscription product that uses Stripe only to move money. From Clerk's documentation
(<https://clerk.com/docs/billing/overview>, read 2026-10-16):

* "Clerk Billing currently supports only USD as the billing currency." Pulse sells to euro customers.
* "Clerk Billing does not currently support tax or VAT, but these are planned for future releases." A German seller of
  digital services to EU consumers has to charge and report VAT (destination-country VAT through OSS).
* "Clerk Billing does not currently support payment methods that require additional authentication, such as 3D Secure
  (3DS)." Strong Customer Authentication is mandatory for many EU card payments; without it a large share of European
  cards would be declined.
* "Clerk Billing checkout is only available in web applications, including Expo web." and "Clerk doesn't provide a native
  checkout surface or integrate with Apple In-App Purchase or Google Play Billing." Native apps could only read plans
  and check access (`has()`), which does not help here.
* "No, Clerk Billing does not support refunds at this time."

Each of the first four alone rules it out for in-app sales to European consumers. Clerk stays what it is in this
design: the identity provider. The Clerk user id (`sub`) is the key of every billing row and is stored as
`metadata.clerk_user_id` on the Stripe customer and subscription.

**Revisit when** Clerk Billing supports EUR, VAT and SCA *and* a native checkout.

## 2. Native Stripe PaymentSheet inside the app

Your instruction ("do it in app"). Trade-off and risk: see `store-policy.md`. The PaymentSheet is also the integration
Stripe documents for mobile subscriptions: the server creates the subscription with `payment_behavior=default_incomplete`,
returns the client secret of the first invoice (`latest_invoice.confirmation_secret`) plus a customer ephemeral key, and
the sheet collects and confirms the payment, including 3-D Secure.

## 3. Stripe state is mirrored into `user_premium_access`

The Pulse backend already decides "is this user premium" from one table: the coaching function's `hasActivePremium` reads
`user_premium_access` (`revoked_at is null and ends_at > now()`), the iOS onboarding gate and `PremiumAccessCache` read
the same rows, and account deletion clears them. A second authority (for example "ask the billing service") would mean
changing every one of those readers and would leave a paying user locked out of the coach wherever one was missed.

So the billing server writes one row per Stripe subscription (`source = 'stripe'`, `external_ref = subscription id`) and
every existing consumer works unchanged. `ends_at` is absolute, so access also lapses by itself if the server is down.
The row is revoked, not deleted, when the subscription ends.

**Cost:** the Pulse table gets one additive column (`external_ref`) and a partial unique index
(`migrations/002_premium_access_link.sql`).

## 4. Events are triggers; Stripe is the source of truth

On every relevant webhook event the server re-reads the subscription from Stripe and stores that, instead of trusting the
event payload. Consequences: event order does not matter, duplicate and late deliveries are harmless, and the code does not
depend on the API version the webhook endpoint is pinned to. Concurrent writers (webhook, `/sync`) are made safe by a
`fetched_at` guard: a read that started earlier can never overwrite a later one.

## 5. A trial without a payment method is not a trial

With a free trial, opening the payment sheet and closing it would otherwise create a subscription that is `trialing`
without any way to charge it. Such a subscription does not grant Premium (`paymentMethodAttached = false`), is reported as
`incomplete`, and is reused when the user comes back. Trials are offered once per user.

## 6. Where the code runs

A separate Node service (`billing/server`) in the Railway project, on the same Postgres as the Pulse API. The Pulse API
gateway (Deno) is not touched, so the two can be changed and deployed independently. Because the HTTP layer is a plain
web-standard `fetch` handler, it can later be mounted into the gateway (`app.fetch(request)`) if you prefer one service.
The Clerk token check is the standard JWKS check the gateway does; no new auth scheme.

## 7. Prices live in Stripe

The apps never hard-code a price. Plans are Stripe prices addressed by `lookup_key` (`premium_monthly`,
`premium_yearly`); the server lists them (cached five minutes) and the apps format `unitAmount` with the currency's own
decimals. Change a price in the dashboard by creating a new price with "transfer lookup key"; no release needed.
`scripts/stripe-setup.ts` creates the product and prices idempotently and has **no default amounts**: the price is a
business decision.

## 8. Fail-closed defaults

Unknown country: no purchase. Unknown portal return URL: refused. Missing consent where the law may require it: refused.
Unknown enum values from a newer server: tolerated by the clients (never a crash). Billing disabled: one switch.
