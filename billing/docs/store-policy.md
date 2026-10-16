# Selling Premium with Stripe inside the apps: store rules and risk

**Read this before the first App Store or Play submission.** The billing code works the way you asked (the Stripe
PaymentSheet inside the app, no redirect). Whether Apple and Google *allow* that is decided per storefront, and the rules
changed repeatedly in 2025 and 2026. This page states what is known, what is not, and how the server limits the exposure.

> Status of the facts below: they come from public reporting and the store operators' blogs, found on 2026-10-16, not from
> a lawyer or from App Review. Re-check Apple's current App Review Guidelines (3.1.1, 3.1.1(a), 3.1.3) and Google Play's
> Payments policy and billing-programme pages before relying on any line. Where a source was a third-party summary it is
> marked *(reported)*.

## The default rule

* **Apple** (guideline 3.1.1): features and content that are unlocked inside the app must be sold with In-App Purchase.
  A native card form for a digital subscription is, by default, not allowed.
* **Google Play**: apps that sell digital goods must use Google Play's billing system.

Premium (the AI coach, generated plans) is a digital feature, so both rules apply.

## Where exceptions exist (and what they cost)

| Store | Where | What is allowed | Notes |
| --- | --- | --- | --- |
| Apple | **United States storefront** | Buttons, external links and calls to action that lead to purchase outside the app, with no entitlement needed *(reported; follows the 2025 US court order and the May 2025 guideline update)* | Apple's wording is about *links and buttons to an external purchase*. A card form embedded **in** the app (this implementation) is not the same thing, and I found nothing that says it is covered. **This is the main risk.** Apple's commission on such purchases was in dispute in the courts *(reported)*. |
| Apple | EU, Japan, others | Separate programmes with their own entitlements, terms and fees | Not enabled by this code. Each needs Apple's approval. |
| Google Play | US, UK, EEA *(reported: live since 30 June 2026)* | Alternative billing and/or links to your own checkout, with reporting obligations and a (reduced) service fee *(reported: 10 % / 20 %, third-party summaries disagree)* | Programme enrolment in the Play Console is required; transactions must be reported to Google. |
| Google Play | Australia, Korea, Japan, rest of world | Announced to follow during Q3 2026 to Q3 2027 *(reported)* | Not enabled by default. |

## What the server does about it

`BILLING_PURCHASE_COUNTRIES_IOS` and `BILLING_PURCHASE_COUNTRIES_ANDROID` decide where a purchase can be **started**.
Both default to `US` and **fail closed**: an unknown country means no purchase. Outside the list the apps show a neutral
line ("Subscriptions can't be started here") and **no link or hint to buy elsewhere**, because steering is exactly what the
rules forbid outside the permitted storefronts.

An existing subscription keeps working **everywhere**. Entitlement is read from the database, not from where the user is, so
a subscriber who travels, or who subscribed on another platform, keeps Premium. (This is the "reader app" pattern the stores
tolerate.)

`BILLING_ENABLED=false` switches all purchasing off at once without a release. Use it if a store objects.

The country the app reports is advisory (iOS: App Store storefront, Android: Play country or device region). The
list is a compliance control, not a security boundary: Apple and Google judge by the storefront the user is really in.

## Recommended path to production

1. Ship the **United States only** first (the defaults). Submit to App Review with a note that explains the US-storefront
   external-purchase provision and attach a screen recording. Expect questions about the in-app card form.
2. If Apple rejects the in-app form but accepts external purchase links: switch the iOS button to **Stripe Checkout in the
   browser** (hosted page). It is a small change on this server (one endpoint that creates a Checkout Session; the webhook
   and entitlement code are unchanged) and the apps open the URL instead of the PaymentSheet. It is not built yet because you
   asked for the in-app flow; say so if you want it.
3. Add the Android programmes (UK/EEA) only after enrolling in the Play Console programme and adding transaction reporting
   (see "Not built" below).
4. Add EU storefronts for iOS only through Apple's programme for them.

## Not built (needed before widening beyond the US)

* **Transaction reporting to Google** for the alternative-billing programme, and Apple's equivalent where a programme
  requires it.
* **Fee accounting** (commission owed to Apple/Google on external purchases, where applicable).
* **Hosted Checkout** (see above).
* **Refund handling:** a refund in Stripe does not revoke Premium by itself. Revoke by cancelling the subscription in the
  Stripe dashboard; the `customer.subscription.deleted` event then ends access (see `docs/deploy.md`).

## Also check

* Apple's rule that an app must not be *primarily* about steering users to alternatives, and the requirement to offer
  Sign in with Apple if you offer other third-party sign-in options (Pulse already uses Clerk; verify the Apple option is
  there).
* Google's requirement to show subscription terms (price, period, how to cancel) before purchase. The paywall does.
