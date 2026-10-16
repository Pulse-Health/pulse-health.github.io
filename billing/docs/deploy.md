# Deploying and operating billing

Do everything in **Stripe test mode** first. Nothing here needs a code change; it is dashboard and variable work.

## 1. Stripe (test mode)

1. **Product and prices.** From `billing/server`:
   ```sh
   STRIPE_SECRET_KEY=sk_test_... npx tsx scripts/stripe-setup.ts --monthly <minor units> --yearly <minor units> --currency eur --tax inclusive --dry-run
   ```
   Drop `--dry-run` to create. There are deliberately no default prices. It creates the product "Pulse Premium" and the prices
   `premium_monthly` and `premium_yearly` (addressed by *lookup key*, so no price ids are ever configured). Running it again
   changes nothing; it refuses to disagree with an existing price (prices are immutable: to change one, create a new price in
   the dashboard with *Transfer lookup key* ticked). Add `--tax-code txcd_...` if you use Stripe Tax.
2. **Customer portal** (Settings → Billing → Customer portal): allow *update payment methods*, *cancel subscriptions*
   (**at end of billing period**), *view invoice history*; add the links to your terms and privacy policy. Save it (test and
   live mode are configured separately).
3. **Customer emails** (Settings → Customer emails): turn on *successful payments*, *refunds*, *upcoming renewals* and
   *trial ending* reminders. Receipts and invoices are also the confirmation of the contract on a durable medium
   (§ 312f BGB). They only go out if the customer has an email address, see "Clerk" below.
4. **Webhook endpoint:** `https://<billing-host>/v1/billing/webhook`, events:
   `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`,
   `customer.subscription.paused`, `customer.subscription.resumed`, `invoice.paid`, `invoice.payment_failed`,
   `invoice.payment_action_required`. Copy its signing secret into `STRIPE_WEBHOOK_SECRET`. The endpoint's API version does not
   matter: the server re-reads the subscription instead of using the payload.
5. **Payment methods** (Settings → Payment methods): the PaymentSheet shows what is enabled (cards with 3-D Secure, SEPA debit,
   Apple Pay, Google Pay, …). Apple Pay also needs an Apple Merchant ID and Stripe's certificate; the app passes the id
   (`applePayMerchantID`). Google Pay on Android is enabled by the host passing a `GooglePayConfig`.
6. **Tax (optional):** Stripe Tax needs your tax registrations and origin address in the dashboard; then set
   `BILLING_AUTOMATIC_TAX=true`. The app then sends the buyer's country as the tax location. Without it prices are treated as
   tax-inclusive gross prices and you declare VAT yourself.

## 2. Clerk

* `CLERK_JWKS_URL` = `https://<your Frontend API>/.well-known/jwks.json`, `CLERK_ISSUER` = `https://<your Frontend API>`.
* **Email in the session token** (so Stripe can send receipts and invoices): Dashboard → Sessions → Customize session token →
  `{ "email": "{{user.primary_email_address}}" }`. The server uses it only when the Stripe customer is created. Without the
  claim everything works except that Stripe has no address to send to.
* Native tokens carry no `azp`; leave `CLERK_AUTHORIZED_PARTIES` empty unless you also call the API from a browser.

## 3. Railway

1. In the Railway project (EU West), **New service → GitHub repo**, root directory `billing/server`. `railway.json` sets the build
   and start commands and the `/healthz` check. Give it a public domain.
2. Variables (see `billing/server/.env.example`): `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`,
   `CLERK_JWKS_URL`, `CLERK_ISSUER`, `DATABASE_URL` (reference the Postgres service; **the owner role**, so it can write the
   Pulse tables despite row-level security), `BILLING_PORTAL_RETURN_URLS` (e.g. `pulse://` for the app's URL scheme), and
   `BILLING_PURCHASE_COUNTRIES_IOS` / `_ANDROID` (leave at `US` until you have read `store-policy.md`).
3. On start the service applies `migrations/001` (billing tables) and `002` (the `external_ref` column on `user_premium_access`);
   with `BILLING_SYNC_PREMIUM_ACCESS=true` (default) it refuses to start if that table or column is missing, with a message that says
   what to do. If the Pulse repo's own migration flow owns the schema, copy both files there with timestamped names
   (`YYYYMMDDHHMMSS_billing.sql`) and set `BILLING_RUN_MIGRATIONS=false`. They are idempotent.
4. Secrets are Railway variables only. Nothing in this repo contains a key, and no code path logs one.

## 4. Test-mode walkthrough

1. Point an app build at the billing host, sign in, open the paywall (set `BILLING_PURCHASE_COUNTRIES_IOS=*` in test only, or use
   the debug `countryProvider`).
2. Pay with Stripe's test cards: `4242 4242 4242 4242` (succeeds), `4000 0027 6000 3184` (3-D Secure), `4000 0000 0000 9995`
   (declined). Any future expiry and CVC.
3. Check: the sheet closes, the paywall shows "Premium is active", `select * from user_premium_access where source='stripe'` has a
   row with `revoked_at is null`, and the coach answers as Premium.
4. Renewal, failed payment, cancellation: use Stripe **test clocks** (Billing → Test clocks) to advance time, or cancel in the
   dashboard. Watch `billing_webhook_events` (every event has `processed_at`).
5. Locally: `stripe listen --forward-to localhost:3000/v1/billing/webhook` gives a `whsec_...` for `.env`.

## 5. Go-live checklist

* [ ] `store-policy.md` read; the country lists are what you intend; an App Review plan exists.
* [ ] `legal.md` items done by a person with legal authority (terms, privacy, withdrawal text, cancellation access, VAT).
* [ ] Live-mode product, prices, portal configuration, webhook endpoint and its secret (test and live are separate).
* [ ] Live keys only in Railway variables. `STRIPE_PUBLISHABLE_KEY` is the live `pk_live_...`.
* [ ] One real payment with a real card, refunded afterwards; the account-deletion path tried once with a test user.
* [ ] An alert on `billing_webhook_events where processed_at is null and received_at < now() - interval '15 minutes'`.

## 6. Operating it

* **Kill switch:** `BILLING_ENABLED=false` (redeploy). Existing subscribers keep Premium; nobody can start a purchase.
* **Refund / chargeback:** a refund does not end the subscription. Cancel it in the dashboard (immediately, not at period end);
  `customer.subscription.deleted` then revokes the Premium row.
* **A user says "I paid and have no Premium":** they can tap "Check again" (`/sync`); or look at
  `billing_subscriptions` for their Clerk id and at `billing_webhook_events` for unprocessed events. Stripe retries failed
  webhooks for days; the Dashboard can resend an event.
* **A user deletes their account:** the apps call `DELETE /v1/billing/account` (see `integration.md`); it deletes the Stripe
  customer (which ends the subscription at once) and our rows. Stripe keeps invoices as accounting law requires.
* **Rotating the webhook secret:** add it in Railway, redeploy, then roll it in the dashboard.
* **Logs** are JSON lines on stdout. They contain event ids, subscription ids and error messages; never tokens or client secrets.
