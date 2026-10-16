# Billing clients: shared design (iOS and Android)

The iOS package (`billing/ios/PulseBillingKit`) and the Android modules (`billing/android`) implement the same design with the
same names, so a change to the flow is made twice in the same shape. The wire format is `billing/contract/openapi.yaml`;
the example responses in `billing/contract/fixtures/` are parsed by the tests of the server and of both clients.

## Layers

| Layer | iOS target | Android module | Depends on |
| --- | --- | --- | --- |
| **Core**: models, API client, entitlement cache, purchase state machine, strings. No UI, no Stripe SDK. | `PulseBillingCore` | `billing-core` (plain Kotlin/JVM) | nothing platform specific |
| **UI**: Stripe PaymentSheet presenter, paywall and manage screens, view model. | `PulseBillingUI` | `billing-android` | Core + Stripe SDK |

The host app supplies three things; the kit has no dependency on Clerk or on the app's theme:

1. `baseURL` of the billing API.
2. A **session token provider**: returns the user's current Clerk session token (iOS: `Clerk.shared.session?.getToken()`).
3. The **portal return URL** (a URL scheme of the app, which must be in the server's `BILLING_PORTAL_RETURN_URLS`) and the URLs of the terms and the privacy policy.

## API client (`BillingAPI`)

One method per contract operation, all `async` / `suspend`, all authenticated with `Authorization: Bearer <token>`:

| Method | HTTP |
| --- | --- |
| `offers(country)` | `GET /v1/billing/offers?platform=<ios|android>&country=<cc>` |
| `entitlement()` | `GET /v1/billing/entitlement` |
| `startSubscription(planId, country, billingCountry?, consent?, idempotencyKey)` | `POST /v1/billing/subscriptions`, header `Idempotency-Key` |
| `sync()` | `POST /v1/billing/sync` |
| `cancel()` / `resume()` | `POST /v1/billing/subscription/cancel` / `.../resume` |
| `portalURL(returnURL)` | `POST /v1/billing/portal` |
| `deleteAccount()` | `DELETE /v1/billing/account` |

Rules:

* The platform is a constant of the client (`ios` / `android`). The country is whatever the host passes (iOS: the App
  Store storefront; Android: the Play country if known, else the device region). It is advisory.
* A 401 is retried **once** with a fresh token from the provider, then surfaces as `unauthorized`.
* Non-2xx responses with the contract's error body become `BillingError.api(code, status, message)`. The error `code` is
  an enum with an `unknown` fallback; unknown response fields are ignored; unknown enum values never crash decoding
  (`status`, `reason`, `source`, `kind` all have an `unknown` case).
* Dates are ISO-8601 UTC strings like `2026-11-16T10:00:00Z`; accept fractional seconds too.
* The transport is an injected seam (iOS `BillingTransport`, Android OkHttp with a `MockWebServer` in tests).
* Never log tokens, client secrets or ephemeral keys.

## Entitlement cache

`EntitlementCache` stores the last server answer per user together with `confirmedAt` (when the server last vouched for
it). `isPremium(now)` is true iff the cached entitlement is premium, `now < premiumUntil`, and
`now - confirmedAt <= 7 days` (the same offline trust window as the Pulse app's `PremiumAccessCache`). A *successful*
fetch that says "not premium" overwrites the cache; a *failed* fetch never does. Gating in the host app should keep using
its existing Premium source (`user_premium_access`, which the billing server fills for Stripe subscribers); this cache
exists for the billing screens and for offline display.

## Purchase flow (`PurchaseCoordinator`)

```
idle
 └─ loadOffers() ─▶ loadingOffers ─▶ ready(offers)            purchase.available and plans not empty
                                   └▶ unavailable(reason)      hide the buy button; manage UI may still show
 └─ purchase(planId, consentGiven) ─▶ preparing
        POST /subscriptions (fresh Idempotency-Key per call)
        ├─ intent == null ........................▶ confirming        (nothing to collect: just sync)
        └─ intent {payment|setup} ─▶ awaitingPayment                   present the Stripe sheet
              ├─ completed ─▶ confirming
              ├─ canceled  ─▶ canceled                                 (the user closed the sheet; no error)
              └─ failed(m) ─▶ failed(m)
   confirming: POST /sync, up to 6 attempts spaced 0, 1, 2, 3, 5, 8 seconds, until entitlement.premium
        ├─ premium ─▶ activated(entitlement)
        └─ still not ─▶ pendingActivation        (paid; the webhook is late — show "this can take a moment")
```

* `consent_required` from the server maps to `failed` with a typed reason so the UI can show the consent checkbox.
* `already_subscribed` maps to `activated` after a `sync()` (the user simply already has Premium).
* The `delay`/sleep function is injectable so tests run instantly.
* The sheet is presented through the `PaymentSheetPresenting` seam (`present(session) -> completed | canceled | failed`)
  so the coordinator is testable without Stripe. A `session` carries: customer id, ephemeral key secret, publishable key,
  merchant display name, intent kind and client secret.

## UI

* **Paywall**: plan picker (price formatted from `unitAmount`/`currency` with the platform's currency formatter; the apps
  never hard-code prices), trial note when `trialDays > 0`, price-incl.-tax note when `taxBehavior == inclusive`,
  auto-renewal and cancellation text, links to terms and privacy, the **withdrawal consent** checkbox when
  `requiresWithdrawalConsent`, and a buy button whose label states the payment obligation (German: "Zahlungspflichtig
  abonnieren"). The button is disabled until the consent is ticked when it is required.
* **Manage**: status, renewal or end date, "cancel at period end" / "undo cancellation", "payment methods and invoices"
  (opens the portal URL in the system browser / Custom Tab).
* When purchase is unavailable in this region the paywall shows a neutral line and **no link or hint to buy elsewhere**
  (store rules: no steering outside the permitted storefronts).
* Strings: German and English, selected from the device language, overridable by the host.
* The Stripe SDK is configured per purchase from the session (`publishableKey`), not at app start.
