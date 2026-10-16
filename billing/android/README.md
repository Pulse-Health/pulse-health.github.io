# Pulse billing for Android

The Android client of the Stripe subscription billing in `billing/`: paywall, subscription management and the Stripe
PaymentSheet, on Kotlin + Jetpack Compose. It implements `billing/docs/client-design.md` against the contract in
`billing/contract/openapi.yaml`, with the same names as the iOS package (`BillingApi`, `PurchaseCoordinator`,
`PurchaseState`, `EntitlementCache`, `BillingStrings`, ...).

| Module | What | Depends on |
| --- | --- | --- |
| `billing-core` | Plain Kotlin/JVM: models, `BillingApi` on OkHttp, entitlement cache rule, `PurchaseCoordinator`, `BillingStrings` (de/en), `BillingFormat` (prices). No Android, no Stripe. | OkHttp, kotlinx.serialization, coroutines |
| `billing-android` | Android library: `StripePaymentSheetPresenter`, `BillingViewModel`, `PaywallScreen`, `ManageSubscriptionScreen`, SharedPreferences cache. | `billing-core`, Stripe Android SDK, Compose Material3 |

## What the host app provides

1. **`baseUrl`** of the billing API (the Railway service that mounts `billing/server`).
2. **A `SessionTokenProvider`**: returns the user's current Clerk session token. It is called for every request and once more
   after a 401, so it must return a token that is valid now. The module has no Clerk dependency.
3. **Links**: the URL of the terms and the privacy policy, and the **portal return URL** (a URL scheme or App Link of the app;
   it must be in the server's `BILLING_PORTAL_RETURN_URLS`).

Also needed: the Clerk **user id** (the offline cache is kept per user). Optional: the country (`BillingConfig.country`, default
the device region; use the Play country if you know it), `googlePay` (off unless passed), `stripeReturnUrl`, a different
`BillingStrings`, your own `OkHttpClient` (do not add a logging interceptor that prints headers or bodies: bearer tokens,
client secrets and ephemeral keys pass through it).

## Integrating into the Pulse app

The Pulse app has no sign-in and no Premium gate yet; do those first (see `billing/docs/integration.md`).

1. **Add the modules.** Copy `billing-core/` and `billing-android/` into the app's `android/` directory, or include them in place:
   ```kotlin
   // android/settings.gradle.kts
   include(":billing-core", ":billing-android")
   project(":billing-core").projectDir = file("<path to>/billing/android/billing-core")
   project(":billing-android").projectDir = file("<path to>/billing/android/billing-android")
   ```
   and `implementation(project(":billing-android"))` in `app/build.gradle.kts`.
2. **Version catalog.** Add what `gradle/libs.versions.toml` here has and the app lacks: `coroutines-core`, `okhttp-mockwebserver` (tests),
   `lifecycle-runtime-compose` (`collectAsStateWithLifecycle`), `browser`, `stripe-android`, and the plugin aliases
   `android-library` and `kotlin-jvm`. All other versions are the app's own (see below). Run `./gradlew :app:dependencies` once:
   the Stripe SDK brings its own Compose dependencies, check that they did not move the app's Compose version.
3. **Register the return link** in `AndroidManifest.xml` on the activity that should receive it, for example
   `pulse://billing/return` (`<data android:scheme="pulse" android:host="billing" />`), and put the same URL in the server's
   `BILLING_PORTAL_RETURN_URLS`.
4. **Create the view model once per signed-in user** (the key keeps users apart) and show the screens:
   ```kotlin
   val config = BillingConfig(
       baseUrl = "https://<billing-host>",
       sessionTokens = SessionTokenProvider { clerkSessionToken() },
       userId = clerkUserId,
       links = BillingLinks(
           termsUrl = "https://pulse-health.github.io/terms.html",
           privacyUrl = "https://pulse-health.github.io/privacy-policy.html",
           portalReturnUrl = "pulse://billing/return",
       ),
   )
   val billing = viewModel<BillingViewModel>(key = config.userId, factory = BillingViewModelFactory(context, config))
   PaywallScreen(billing, onClose = { /* e.g. refresh the Premium gate */ })
   ManageSubscriptionScreen(billing)
   ```
   `PaywallScreen` creates the Stripe `PaymentSheet` while composing, which is before the Activity starts, as the SDK requires.
   Wrap both screens in the app's `MaterialTheme`; the module uses no colors of its own.
5. **Premium gate.** Keep gating on the existing Premium source (`user_premium_access`; the billing server fills it). After a
   purchase, `onClose` is the moment to refresh it. The module's cache is for the billing screens and offline display.
6. **Account deletion.** Before the Pulse account (and the Clerk user) is deleted, call
   `BillingApi(baseUrl, sessionTokens).deleteAccount()` and abort the deletion if it throws; otherwise a deleted account could keep
   being billed.

## Behavior worth knowing

* The Stripe SDK is configured per purchase from the server's `publishableKey`; nothing happens at app start.
* If the process dies while the payment sheet is open, the result is dropped. The next `loadOffers()` then reports
  `already_subscribed` (or the paywall again) and the entitlement refresh picks up the paid subscription via the webhook.
* Where purchase is unavailable (region, platform, billing off) the paywall shows one neutral line and no link or hint to buy elsewhere.
* The consent text and the buy-button label ("Zahlungspflichtig abonnieren") are in `BillingStrings`. The legal wording is a
  draft: have it reviewed (`billing/docs/legal.md`).
* Prices are formatted by `BillingFormat` from `unitAmount` and `currency` with **Stripe's minor-unit table** (zero-decimal: BIF CLP DJF GNF JPY
  KMF KRW MGA PYG RWF UGX VND VUV XAF XOF XPF; three-decimal: BHD JOD KWD OMR TND; everything else 2), not `java.util.Currency`'s,
  because the server's `unitAmount` follows Stripe's table. The iOS package has the same table.

## Build and test

Needs JDK 17 or newer and an Android SDK with `platforms;android-36` and `build-tools;36.0.0` (`sdk.dir` in
`billing/android/local.properties`, which is git-ignored, or `ANDROID_HOME`).

```sh
cd billing/android
./gradlew :billing-core:test :billing-android:testDebugUnitTest :billing-android:assembleDebug
```

The contract tests read `billing/contract/fixtures/` (Gradle passes the path as the system property `billing.contract.fixtures`)
and **fail**, not skip, when the directory is missing or when a fixture has no parser. No device or emulator is needed;
the Compose screens are covered through their plain-data models (`PaywallModel`, `ManageModel`) and have no instrumented tests.

## Versions

Match the Pulse app (`android/gradle/libs.versions.toml` there): AGP 8.9.1, Kotlin 2.1.0 (`kotlin.plugin.compose` and
`kotlin.plugin.serialization`), Gradle 8.11.1, Compose BOM 2024.12.01, activity-compose 1.9.3, lifecycle 2.8.7,
kotlinx-serialization-json 1.7.3, OkHttp 4.12.0 (and MockWebServer), kotlinx-coroutines 1.9.0, JUnit 4.13.2, Java 17,
minSdk 28, compileSdk 36, targetSdk 35 (tests). Added by this project: `androidx.browser` 1.8.0 (Custom Tabs),
Stripe Android SDK `com.stripe:stripe-android` 23.23.0.
