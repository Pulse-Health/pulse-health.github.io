# Legal checklist before taking real money

**This is a checklist for whoever is responsible for the legal side, not legal advice.** I (an AI assistant) am not a lawyer; the
statutes are named so that a lawyer can check each point quickly. Pulse sells to consumers in Germany and the EU, so German and
EU consumer law applies in addition to the store rules in `store-policy.md`.

## What the website and the app say today

The terms (`terms.html`, `agb.html`) and the privacy policies (`privacy-policy.html`, `datenschutz.html`) were written for a free app:

* Terms § 5: "The Service is currently provided free of charge", Premium only through redemption codes, "Any payments would then be
  processed via the Apple App Store, where Apple's terms additionally apply." With Stripe that last sentence becomes **wrong** as soon
  as the first payment is taken.
* Terms § 11 / AGB § 11: only the Apple App Store is mentioned. There is no Google Play wording.
* The withdrawal instruction (AGB § 14) says the service is free, so withdrawal "causes no payment".
* The privacy policies list Premium features but no payment processor.

Nothing in this change edits those pages: they are live, and changing them for a feature that is not on sale yet would publish
contract terms that do not match the app. Change them in the same release that enables purchases.

## How the AGB can be changed (read this first)

Version 1.1 of the AGB is live (`legal-notices/agb-1-1/`). Its § 15 lets the provider change terms by notice with a six-week
objection period, but § 15 Abs. 3 keeps changes to the **core service and to prices** out of that mechanism, and the repository's own
note on it (`legal-notices/agb-1-1/README.md`) points out that the BGH rejected silence-as-consent clauses of this kind (XI ZR 26/20).
Introducing a paid subscription is a price matter. The simplest reading is that Premium is a **new, separate contract** concluded at
checkout, on terms the buyer sees and accepts there, and that the free basic service and code-based Premium do not change. Have a
lawyer confirm that, and decide whether the new terms need an AGB version 1.2 that new users accept actively at onboarding.

## Contract terms (AGB / terms) to add or change

* Price, billing period, automatic renewal, how and until when to cancel, what happens at the end of a trial, what happens when a
  payment fails (access continues for `BILLING_PAST_DUE_GRACE_DAYS`, default 3, while Stripe retries).
* Payment provider: Stripe (Stripe Payments Europe, Ltd. for EEA customers), instead of the Apple-billing sentence.
* Distribution via **Google Play** next to Apple (store terms, third-party-beneficiary clause as applicable).
* Withdrawal: instruction and model form for paid digital content/services (Art. 246a EGBGB, § 355 BGB) and the loss of the right
  once performance has started with the buyer's express consent (§ 356 Abs. 4/5 BGB).
* The contract language and whether the AGB are available in the app language of the buyer.

## At checkout (the app)

The paywall implements the following; **have the wording confirmed**:

| Requirement | Where | What the code does |
| --- | --- | --- |
| Order button states the payment obligation (§ 312j Abs. 3 BGB, "Button-Lösung") | `BillingStrings.buyButton` | German: "Zahlungspflichtig abonnieren" (with a trial: "Kostenlos testen, danach zahlungspflichtig"). |
| Essential information shown directly before the order (§ 312j Abs. 2 BGB, Art. 246a § 1 EGBGB): features, total price, term, how to cancel | paywall | plan and price (from Stripe, VAT-inclusive when the price is), renewal and cancellation note, link to terms and privacy. Confirm that the wording is sufficient, and the price display rules (PAngV: total price including VAT). |
| Express consent to immediate performance and acknowledgement of losing the right of withdrawal (§ 356 Abs. 5 BGB) | consent toggle, `BILLING_WITHDRAWAL_CONSENT_COUNTRIES` | Required (server-enforced) for EEA, UK and Switzerland by default; the time and language of the consent are stored on the Stripe subscription (`consent_withdrawal_waiver_at`, `consent_locale`). The text is a draft. |
| Confirmation of the contract on a durable medium (§ 312f BGB) | Stripe emails | Turn on Stripe's receipt/invoice emails; the customer needs an email (`deploy.md`, "Clerk"). Check that the confirmation contains the required content (including the withdrawal information) or add it. |
| Easy-to-find cancellation (§ 312k BGB "Kündigungsbutton") | "Abo kündigen" in the manage screen, Stripe portal | **Open question for the lawyer:** the statute describes a button on the website/app that is reachable without login and labelled "Verträge hier kündigen", with a confirmation page. The in-app cancel button needs a signed-in user. Decide whether a public page (linked from the website footer and Impressum) is needed. |

## Taxes

* **VAT** on digital services to EU consumers: the destination country's VAT applies; registration (OSS) and the choice between
  Stripe Tax (`BILLING_AUTOMATIC_TAX`) and a self-declared flat gross price must be decided with the tax adviser **before** launch.
  Gross prices are configured as tax-inclusive (`--tax inclusive`).
* Invoices: Stripe issues them; check they carry the data § 14 UStG requires (seller address, VAT id, tax rate/amount).
* Retention: invoice data must be kept for the statutory period (commonly ten years in Germany). `DELETE /v1/billing/account`
  deletes the Stripe customer but Stripe retains invoices; our own tables hold no accounting data.

## Privacy (GDPR)

* Add Stripe as a processor/recipient (Stripe Payments Europe, Ltd.; transfers to Stripe, Inc. in the US under the mechanism Stripe
  documents) and conclude Stripe's data-processing agreement.
* Purpose and legal basis: performance of the contract (Art. 6 Abs. 1 lit. b). Data: Clerk user id, email, billing country,
  subscription state, payment method token (the card number never reaches Pulse's server), consent time/locale.
* Stripe's mobile SDK collects device information for fraud prevention; mention it.
* Retention and deletion: what `DELETE /v1/billing/account` does (above); what Stripe keeps.
* The in-app consent text and the purchase flow must be consistent with the AI-consent and data-export descriptions already in
  the policies (the export in the app covers `user_premium_access`, which now also holds Stripe rows).
* App Store "App Privacy" and Google Play "Data safety" forms need the purchase/payment data types.

## Draft German replacement for terms § 5 (illustration only)

> (1) Der Basisdienst ist kostenlos. (2) „Premium“ ist ein kostenpflichtiges Abonnement mit monatlicher oder jährlicher Laufzeit.
> Preise und Laufzeit werden vor Vertragsschluss in der App angezeigt (Preise inkl. gesetzlicher Umsatzsteuer). Das Abonnement verlängert
> sich automatisch um den gewählten Zeitraum, wenn es nicht vor Ablauf des laufenden Zeitraums gekündigt wird. (3) Die Zahlung erfolgt
> über Stripe (Stripe Payments Europe, Ltd.). (4) Kündigung jederzeit zum Ende des laufenden Zeitraums in der App unter „Dein Abo“.
> (5) Freischaltcodes bleiben unberührt.

A lawyer should replace this; it exists to show which parts of § 5 change.
