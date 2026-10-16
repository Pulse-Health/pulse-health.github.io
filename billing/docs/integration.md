# Wiring billing into the Pulse apps and backend

The Pulse app code lives in `RobinJue/pulse` (`ios/`, `android/`, `supabase/`, `web/`; the Railway backend is being built on a
branch of it). This repository holds the billing pieces; nothing here edits that repository. These are the exact places to
connect, found by reading it on 2026-10-16.

## Backend

1. Add `billing/server/migrations/001_billing.sql` and `002_premium_access_link.sql` to the Pulse migrations
   (`supabase/migrations/YYYYMMDDHHMMSS_*.sql`) or let the billing service apply them itself (`BILLING_RUN_MIGRATIONS=true`).
   `002` adds `external_ref` and a partial unique index to `user_premium_access`; it changes nothing else of that table.
2. New tables in the Pulse database get row-level security automatically; the billing tables are only ever touched by the billing
   service (owner role), which is what you want: the apps' PostgREST roles cannot read Stripe ids.
3. **Premium cache in the coaching function.** `supabase/functions/health-chat/quota.ts` (`hasActivePremium`) caches a successful
   answer for five minutes, *including "no"*. A user who has just paid can therefore be treated as free by the coach for up to five
   minutes. Cheapest fix in that repo: cache only positive answers (or use a short TTL for negatives). The same applies to the
   Railway copy of the gateway.
4. Account deletion has one more step, see "iOS" below. The SQL function `delete_all_user_data()` already removes the Stripe-sourced
   `user_premium_access` rows (same table); the Stripe customer and the billing tables are removed by `DELETE /v1/billing/account`.

## Clerk

* Add the `email` claim to the session token (`deploy.md`, "Clerk").
* No other Clerk setting. The server verifies the same session token the apps already send to the Pulse API.

## iOS (`ios/HealthCoach`)

1. **Add the package.** Copy `ios/Packages/PulseBillingKit` from this repository to `ios/Packages/PulseBillingKit` in the Pulse repo,
   and add it to the HealthCoach target (*Package Dependencies → Add Local…*; products `PulseBillingCore` and `PulseBillingUI`).
   It pulls in the Stripe iOS SDK (`stripe-ios-spm`, product `StripePaymentSheet`).
2. **URL scheme.** Register a scheme for Stripe's redirects (for example `pulse://stripe-redirect`) and for the portal return
   (for example `pulse://billing/return`). The latter must also be in `BILLING_PORTAL_RETURN_URLS`. In `.onOpenURL`, call
   `PulseBilling.handle(url:)` first.
3. **Create the view model** once per signed-in user:
   ```swift
   let model = PulseBilling.makeViewModel(
       configuration: BillingConfiguration(baseURL: URL(string: "https://<billing-host>")!),
       userID: clerk.user?.id ?? "",
       tokens: ClosureSessionTokenProvider {
           // the same call SupabaseManager and HealthChatTransport make
           guard let token = try await Clerk.shared.session?.getToken() else { throw BillingError.unauthorized }
           return token
       },
       links: BillingLinks(termsURL: URL(string: "https://pulse-health.github.io/terms.html"),
                           privacyURL: URL(string: "https://pulse-health.github.io/privacy-policy.html"),
                           portalReturnURL: "pulse://billing/return"),
       stripeReturnURL: "pulse://stripe-redirect")
   ```
   (`Clerk.shared.session?.getToken()` returns the token string in the Clerk SDK version the app uses today; adapt the two
   lines if that changes.)
4. **Premium gate.** `OnboardingFlowView` shows the code-redemption screen for `OnboardingStore.GateState.needsPremium`. Add
   `PaywallView(viewModel: model) { Task { await store.refreshPremiumAccess() } }` next to it. The refresh matters: the gate
   reads `user_premium_access`, and the server has already written the row by the time the paywall reports "active".
5. **Manage.** In `ProfileView`, link `ManageSubscriptionView(viewModel: model)` for users with a subscription.
6. **Account deletion.** `ProfileView.deleteAccount()` calls `SupabaseManager.shared.deleteAllUserData(userID:)`. Call
   `BillingAPI.deleteAccount()` (or the view model's coordinator) **before** it and before the Clerk user is deleted (the call needs a
   valid session), and abort the deletion with an error if it fails, otherwise a deleted account could keep being billed.
7. **Capabilities.** None required. Apple Pay is optional (Merchant ID + the capability + `applePayMerchantID`).
8. **App Store Connect.** Update the App Privacy answers (purchases, payment info handled by Stripe) and see `store-policy.md`.
9. The Stripe SDK ships its own privacy manifest. Keep `PrivacyInfo.xcprivacy` of the app consistent with the data you now collect.

## Android (`billing/android/`)

The Pulse Android app has no sign-in and no Premium logic yet (`feature/dashboard`, `feature/detail` only), and the repository's
rule is feature parity. Billing needs both, so on Android the order is: sign-in with Clerk, the Premium gate / `user_premium_access`
read, then this module. The module itself is complete and takes the Clerk token as a `SessionTokenProvider`. Integration steps are in
`billing/android/README.md`.

## Web console

Nothing is required. If the console lists Premium users, it can read `user_premium_access` (`source = 'stripe'`).

## Parity

Both platforms use the same contract, flow and strings by design (`client-design.md`); change them together.
