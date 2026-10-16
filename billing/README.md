# Pulse billing (Stripe)

Premium subscriptions for the Pulse iOS and Android apps, paid with the Stripe PaymentSheet inside the app. Identity is
Clerk; the Pulse backend's `user_premium_access` table stays the one place that says who is Premium.

```
 iOS / Android app                       billing/server (Node, Railway)                 Stripe
 ┌──────────────────┐  Clerk JWT        ┌────────────────────────────────┐  secret key  ┌────────────┐
 │ PaywallView      │ ───────────────▶  │ /v1/billing/offers             │ ───────────▶ │ prices     │
 │ PaymentSheet ◀───┼── client secret ─ │ /v1/billing/subscriptions      │              │ customers  │
 │ ManageView       │ ◀─ entitlement ── │ /v1/billing/sync, cancel, ...  │ ◀─────────── │ subs       │
 └──────────────────┘                   │                                │   webhook    └────────────┘
         ▲                              │ /v1/billing/webhook  ◀─────────┼─────────────── events
         │ reads premium                └──────────────┬─────────────────┘
         │ (unchanged)                                 │ writes
 ┌───────┴───────────────────────────────────────────────▼────────────────────────────────────┐
 │ Railway Postgres:  billing_customers · billing_subscriptions · billing_webhook_events        │
 │                    user_premium_access  (one row per Stripe subscription, source='stripe')   │
 └─────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Where things are

| Path | What |
| --- | --- |
| `server/` | The billing service (TypeScript). `src/service.ts` is the logic, `src/http.ts` the routes, `src/gateway.ts` the only file that talks to the Stripe SDK. |
| `contract/openapi.yaml`, `contract/fixtures/` | The wire contract and example responses, parsed by the tests of the server, iOS and Android. |
| `docs/client-design.md` | The purchase flow and layering that iOS and Android both implement. |
| `docs/store-policy.md` | **Read first.** Apple/Google rules for in-app Stripe payments and how the server limits exposure. |
| `docs/decisions.md` | Why Stripe and not Clerk Billing, why the Premium table, why a separate service. |
| `docs/deploy.md` | Stripe dashboard, Clerk, Railway, test-mode walkthrough, go-live checklist, operations. |
| `docs/integration.md` | Wiring into the Pulse iOS/Android apps and the Pulse backend. |
| `docs/legal.md` | What the terms, privacy policy and checkout need before taking real money (drafts, not legal advice). |
| `ios/PulseBillingKit` | iOS client (Swift package). |
| `android/` | Android client (Gradle project; not the same as the top-level `android/` of the Strength app). |

## Endpoints (all but the webhook need `Authorization: Bearer <Clerk session token>`)

| | |
| --- | --- |
| `GET /v1/billing/offers?platform=&country=` | plans with real prices, whether a purchase may start here, whether the EU consent is needed |
| `GET /v1/billing/entitlement` | Premium yes/no, plan, period end, cancellation state (database only, cheap) |
| `POST /v1/billing/subscriptions` | create or reopen a subscription; returns what the PaymentSheet needs |
| `POST /v1/billing/sync` | re-read the user's subscriptions from Stripe (after the sheet closes) |
| `POST /v1/billing/subscription/cancel` · `/resume` | cancel at period end / undo |
| `POST /v1/billing/portal` | Stripe customer portal link (payment methods, invoices) |
| `DELETE /v1/billing/account` | account deletion: ends the subscription, removes our rows |
| `POST /v1/billing/webhook` | Stripe events (signature, not Clerk) |
| `GET /healthz` | liveness |

Details and schemas: `contract/openapi.yaml`.

## Run it locally

```sh
cd billing/server
npm ci
npm run typecheck && npm test                 # unit tests; PostgreSQL-backed tests are skipped without TEST_DATABASE_URL
TEST_DATABASE_URL=postgres://user:pw@localhost:5432/billing_test npm test    # all tests (needs an empty database you can truncate)
cp .env.example .env                          # fill in test-mode keys, then:
npm run dev
```

Configuration is environment variables only; `.env.example` lists all of them with comments.

## Data model

* `billing_customers(user_id → stripe_customer_id)`: Clerk user id (JWT `sub`) ↔ Stripe customer.
* `billing_subscriptions`: one row per Stripe subscription, stored from Stripe's answer with a `fetched_at` stamp.
* `billing_webhook_events`: processed event ids (idempotency); no personal data.
* `user_premium_access` (the Pulse table): one row per subscription, `source='stripe'`, `external_ref = subscription id`,
  `ends_at` = paid period end plus one day (a renewing subscription) or exactly the period end (one that will cancel), `revoked_at` set when access ends.

Premium rules (`src/entitlement.ts`): `active` and `trialing` (with a payment method) are Premium; `past_due` stays Premium for
`BILLING_PAST_DUE_GRACE_DAYS` after the period end (Stripe is retrying); `incomplete`, `unpaid`, `canceled`, `paused` are not.

## Things that are easy to get wrong

* **Stripe is read, not trusted.** Events only say "look at subscription X again". Never copy state out of an event payload.
* **The webhook needs the raw body.** `http.ts` reads it as text before anything parses it.
* **Ephemeral key API version** (`STRIPE_EPHEMERAL_KEY_API_VERSION`) must be the version the Stripe mobile SDKs in the apps speak,
  not the server's.
* **Refunds do not revoke Premium.** Cancel the subscription in the Stripe dashboard.
* **`DATABASE_URL` must be a role that can write `user_premium_access`** (the Pulse tables have row-level security; the table
  owner bypasses it).
