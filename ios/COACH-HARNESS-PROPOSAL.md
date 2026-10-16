# Proposal: a harness for the Pulse Strength coach (v2)

Status: **Phase 0 is implemented in the same pull request as this document; no model layer exists.** v1 was written on 2026-10-16. v2 is the same day, revised after
an independent review: 12 verifier agents re-checked the code references and the sourced claims in clusters (each doubtful claim got a
second, independent opinion), three reviewers attacked the design (safety/legal, evaluation, product/engineering), and a critic
looked for gaps. What changed is listed in section 14.

> **Decision (2026-10-16, product owner): no on-device ("edge") models.** This supersedes section 6.3 (the on-device model layer, the
> Apple adapter, the prompt spec and the availability matrix), the on-device parts of section 7 (suite S2, Apple's Evaluations
> framework), Phase 0.5 and Phase 1 in section 9 as originally written, and section 11 (kept as background only). Still valid: the
> engine and its rules (6.1), the guards that do not depend on where a model runs (G0, G1, G2, and G3, G4, G5, G7, G8 if model text
> is ever shown), the evaluation approach, and sections 8 and 10. The privacy argument "on-device, nothing leaves the phone" is gone,
> so any future model is a **cloud model** that reuses the existing consented EU pipeline (section 8, "Phase 2 default"), and starts
> with measurement, not an adapter.

Confidence markers: *unmarked* = I read it in the repo or a primary source. **†** = established by a review agent reading the
source; re-check before relying on it. **‡** = secondary source, press, or recalled from memory; needs counsel or a primary source.

## 1. Recommendation

> **Numbers come from tested code. A language model, if we use one at all, only writes words, behind code guards, with a
> template fallback. Build the evaluated deterministic core first. Make the model layer conditional on a named user problem
> and a two-day spike.**

* **Phase 0 (ships to every device, no model) is implemented:** a `ProgressionEngine` over performed sets, a "Next time" card with
  an "Apply" button, the duplicated target maths removed, and tests that gate every PR on Linux. See section 9 for what was built and
  what was not.
* **Phase 0.5 (measurement, about two days):** log-RIR coverage on real exports, how often the current tip is acted on, a coach
  review of the thresholds, a competitor teardown. This is what decides whether any model is wanted at all.
* **A model, if ever, is a cloud model** (section 9, Phase 1), conditional on a named user problem.

The thresholds in `CoachConfig` are **starting values that no qualified coach has signed off**; that sign-off is the gate before
this ships to users.

## 2. Which "workout AI"? (decision 1)

There are two candidates, and I have only seen one.

* **A. The Strength coach in this repo** (`ios/`): rule-based, on device, no model. This is what the rest of the document designs.
* **B. The production cloud coach in the Pulse app.** The site's own legal pages describe it: coaching chat, AI-generated training
  and meal plans (Premium) and health-analysis summaries, sent through Eden AI to EU-hosted Mistral models, with explicit consent
  (Art. 9(2)(a) GDPR) and an off switch (`privacy-policy.html` §7, `terms.html` §8). The Eden AI processing agreement and the
  Mistral due-diligence are listed as pending. This repo has an unwired "Ask AI" hook that a host app can install
  (`ExerciseDetailView.swift:15-16`), and the README says the Pulse app is a separate repository that is not part of this build.
  That this hook leads to B is my inference.

The harness ideas apply even more directly to B (chat memory, plan generation, grounding). Section 10 says what carries over and
what I would need to see. If "our workout AI" means B, this document is the wrong target and should be reframed.

## 3. Where the Strength coach is today

Three deterministic recommendation surfaces, no model:

| Surface | Code | What it says |
|---|---|---|
| In-workout tip | `PresenterSupport.coachTip` (`PulseStrengthCore/WorkoutPresenter.swift:339`) | "85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg." |
| Hub note | `HubCoach` (`PulseStrengthIOS/Screens/StrengthHubView.swift:1341`) | A readiness sentence plus "Aim for 85 kg × 6 on your last bench press set." |
| Hub "next template" | `HubRotation.next` (`StrengthHubView.swift:1215`) | The template after the last performed one, ignoring readiness and effort. |

Findings (each re-verified):

1. **One progression rule.** Both weight texts give the lightest weight, in whole equipment steps, whose Epley e1RM at the planned
   reps beats the best e1RM by more than 0.05 kg. Nothing in the Swift sources says hold, back off, deload or stalling. The hub note
   prepends a readiness sentence that is independent of the target, so a real recovery provider could produce "Legs are still
   recovering. Aim for 120 kg × 5": a stance conflict that exists today.
2. **RIR is logged but unused.** Reps in reserve (0 to 4, optional) is stored per set (`Models.swift:209`, `Completed.swift:9`),
   entered from the rest dock or the set-detail sheet, shown per set and as an average (`Completed.swift:99`). No coach logic reads it.
3. **The target maths exists twice and differs.** `lowestBeatingWeight` (`WorkoutPresenter.swift:352`) is internal to Core and
   returns `nil` on invalid input; `HubCoach.beatingWeight` (`StrengthHubView.swift:1379`) is file-private to the iOS target, hard-codes
   `+ 0.05` instead of `recordMargin`, floors the step at 0.5, never returns `nil` and walks at most 400 steps. The tip uses a running
   baseline that includes today's sets; the hub uses the stored previous best. The hub skips an exercise whose last working set has
   0 reps and talks about the next one; the tip returns `nil`. For real steps (1, 2, 2.5 kg) two ports gave identical weights.
   Only `coachTip` is tested (indirectly, in `PresenterTests` and `IntegrationTests`); `HubCoach` has no test and cannot have one
   in `swift test` as it stands.
4. **Readiness is canned in this build.** `RecoveryProvider` is a typealias for `@Sendable (MuscleGroup) -> Int`
   (`Presentation.swift:328`), defaulting to `DemoRecovery` (88, 100, 82, 79, 64, 100) at `WorkoutController.swift:36` and
   `WorkoutEngine.swift:177`. The code comment says the Pulse app injects its real model (`Presentation.swift:327`) and the README
   tells the host to pass one (lines 245-247). The same constants drive the readiness score, the chips, the Muscle Recovery tab and
   the in-workout recovery line. With the default, "still recovering" (needs a value under 60) can never appear.
5. **The summary screen has no coach text** (`WorkoutSummaryView.swift:14`).
6. **User-typed text can reach a prompt.** Custom exercise names (`Models.swift:168`), workout and template names, and exercise
   notes are unrestricted free text.
7. **History keeps only what was performed.** `CompletedSet` has type, kg, reps, RIR. The planned target is not stored, and
   "update template" overwrites `PlannedSet` with the performed values (`WorkoutFactory.swift`), so "missed the target" cannot be
   computed from history. `WorkoutExercise.note` is not copied into `CompletedExercise`.
8. **No audience inputs.** Nothing here knows age, declared limitations or body areas to avoid. The production app collects them
   (`privacy-policy.html` §7), and the Terms set a minimum age of 16 (§4).

What to preserve: a Foundation-only core with about 700 unit tests (README; 718 test functions counted), fuzz tests
(`WorkoutFuzzTests`, `SyncChannelFuzzTests`), a hardened reducer and sync protocol. CI renders the UI in simulators and uploads
screenshots, but every step is non-gating and no check asserts text, so **copy changes are not protected by CI**. That is why the
model must stay out of the write path (G2).

## 4. What the user will see (Phase 0)

The v1 proposal never said. The headline change is a **per-exercise "Next time" line** on the hub card and at workout start, with
an **"Apply to this workout" button** that dispatches the existing `setWeight` actions (the reducer is untouched):

| Verdict | Copy (illustrative, needs design and coach review) |
|---|---|
| progress | "Next time: 82.5 kg × 6. Two clean sessions at RIR 2 or more." |
| hold | "Next time: stay at 80 kg × 6. Last session ended at RIR 0." |
| reduce | "Next time: 75 kg × 6. Reps fell at the same weight twice." |
| addRep | "Next time: 8 kg × 16. A 2 kg step would be a 25% jump." |
| noEffortData | "Log RIR on your sets to get a suggestion for this lift." |
| insufficientData | nothing |

The hub drops the readiness sentence unless the host injected a real provider (a Bool on the environment; no change to the
`RecoveryProvider` signature). The in-workout PR-chase tip stays, under the same caps as the engine (G0).

## 5. Alternatives considered

| Option | Verdict |
|---|---|
| Engine plus templates only | **Recommended (Phase 0).** Often enough; fully testable. |
| Coach-written phrase variants chosen deterministically | Cheap way to add variety without a model. Try before Phase 1. |
| User-set aggressiveness (conservative, standard, push) shifting the RIR threshold and step | Strong candidate for Phase 0; replaces "AI personalisation" with a control the user understands. |
| Licensed coach content for the "why" lines | Worth pricing against the model path. |
| On-device model as writer | Conditional (Phase 1). |
| Bundled local model (MLX or Core AI**†**) | Rejected for now: app size and ops burden, no gain over templates until a user problem is named. |
| Core ML personalisation | Rejected: not enough per-user data. |
| Server-side coach | Out of scope for A (EU-only promise, privacy). Relevant only if B is the target. |
| Free-text notes as input | Rejected: `CompletedExercise` does not keep notes, and free text conflicts with G1. |

## 6. Design

```
StrengthStore (performed sets, PBs, templates) ─┐
AudienceProfile (host-supplied)                 ├─► ProgressionEngine   pure, Core, Linux-tested
RecoveryProvider (real or unknown)              ─┘        │  [Recommendation]  verdict, target, reasons, versions
                                                          ▼
                                             CoachComposer ──► TemplateWriter v2   always available, compositional
                                                  │
                                                  └─ conditional: model available, consent on ─► CoachModel ─► phrases
                                                                                    Guards G1…G8 ─ pass ─► UI (labelled)
                                                                                                 └ fail / timeout / refusal ─► template
```

### 6.1 Engine rules (starting policy; every threshold needs coach sign-off)

All rules use **performed working sets only** (warm-ups and drop sets excluded) and are encoded as coach-labelled golden cases.

| Rule | Why |
|---|---|
| Fewer than two sessions → `insufficientData` | Say nothing rather than guess. |
| **progress** needs two consecutive sessions at the same load, no rep drop, and RIR of 2 or more on at least two thirds of the working sets in each | Self-reported RIR is about one rep off on average**‡**, so one session must not flip hold to progress. |
| No RIR recorded → `noEffortData`, never an automatic progress | Reps at constant load cannot tell "easy" from "stalled". Also nudges RIR logging. |
| **hold** if the last session ended at RIR 0 or 1 | |
| **reduce** if reps fell at the same load in two consecutive sessions and the last session ended at RIR 1 or less; bounded to a few percent, rounded to one equipment step | Bounded by definition, never open-ended. |
| After N consecutive progress sessions (N from the coach) → lighter-week suggestion | A coach that only ever says progress, hold or reduce never says rest. |
| Gap longer than D days → hold at the old load, reason `returningAfterBreak` | The all-time best e1RM is a poor baseline after a layoff. |
| Step = a per-exercise **increment table**, capped at a relative jump (about 5 to 7.5%); if the smallest step exceeds the cap → `addRep` | `weightStepKg` is the keypad stepper, not a training increment: today's demo tip for an 8 kg lateral raise (best e1RM 12.6 kg) is 10 kg × 15, a 25% jump. |
| e1RM for baselines only from sets of about 10 reps or fewer, from a recent window | Epley is unreliable at high reps and is uncapped today. |
| `suspectData`: a single set far above the exercise's own recent best is excluded and flagged | A series-wide 2× jump rule misses a 6→16 rep typo (1.28×). |
| Bodyweight, reps-only and duration → `insufficientData` in v1 | e1RM is 0 for them; a separate path is a coach decision. |
| `AudienceProfile` minor or unknown → no PR-chase tip, smaller cap, no model text; declared avoid-area → silent for that muscle | The Terms allow users from 16; the production app already collects limitations. |

Evidence caveat: none of the cited sources tested an RIR-triggered progression rule. In Graham and Cleather, RIR was a prescribed
intensity schedule, and a later meta-analysis found autoregulation gave similar strength gains**†**. The engine's value is
consistency, explainability and testability, not a proven training advantage.

### 6.2 Guards

Each is code with a test, a reason, and a retire condition.

| ID | Guard | Mechanism |
|---|---|---|
| **G0** | Engine bounds | Caps, gap rule, high-rep exclusion, bounded reduce, version stamps on each `Recommendation`. Fuzzed in S0. Applies to the PR-chase tip too. |
| **G1** | No user-typed text in prompts or instructions | `CoachBrief` has no `String` fields, enforced by a reflection test. Exercise names never enter a prompt; code adds them. |
| **G2** | Model outside the write path | Nothing handed to the model can mutate state. "Apply" is a user tap through the existing reducer. |
| **G3** | No figures from the model | Fail closed: NFKC-normalise, strip format characters, reject any scalar with a numeric Unicode type, then accept only a per-locale letter allow-list, whole-word. Add a short quantity-word list ("double", "half", "twice", "record"). Figures appear only as slot tokens that must exist in the brief and are filled by code. |
| **G4** | Stance by construction | The model returns one short phrase per item; code fixes the order and the verdict. A lexicon cannot check stance on mixed verdicts (swapped stances use the same words), so contradiction must be impossible, not detected. |
| **G5** | Vocabulary allow-list | Permit muscle and verdict vocabulary derived from `MuscleGroup` titles and a reviewed phrase list; reject other health or body-state terms (whole-word, stemmed, per locale). The list ships in the app bundle and changes with app releases, never fetched at run time. Tested against a benign corpus ("fatigue", "Muskelkater") and a harmful one. |
| **G6** | Budget | Length enforced by prompt phrasing plus the validator, **not** `maximumResponseTokens` (Apple warns it truncates mid-sentence). Generated once at workout finish, cached by brief hash, template shown immediately if not ready, no swap on screen. |
| **G7** | Fallback | `CoachComposer` never throws. Covers errors, guardrail violations, unavailability, timeouts and guard failures. **String-mode refusals are returned as ordinary text, not thrown**, so use a structured output type or an explicit refusal check. A result that arrives after the timeout is discarded and not logged as shown. |
| **G8** | Grounding | Output may mention only categories and verdict phrases from the brief. Relative-time words ("since yesterday") are banned or rendered by code. Press reports of a shipped LLM coach describe invented workouts and stale remembered context, not wrong digits**‡**, so digit guards alone are not enough. The decision log is never read into prompts. |

### 6.3 Model layer (superseded: no on-device models)

> Kept for the record. The decision at the top rules out the on-device layer below. The parts that are not specific to Apple's on-device
> model (typed brief with no free text, fixed fallback, availability and consent gating, UX requirements) carry over to a cloud model.

* **Seam.** v1 sketched a custom `CoachModel` protocol. Apple's framework now has a `LanguageModel` protocol that
  `SystemLanguageModel` and `PrivateCloudComputeLanguageModel` conform to**†**, and says it is being open-sourced**†** (WWDC26
  session 241). Decide after reading that session whether `CoachModel` wraps `LanguageModelSession` or is replaced by it. The Linux
  S1 suite may be able to use the real framework types with a scripted model.
* **No tools in v1.** The brief is pre-computed and typed (4096-token on-device window; Apple: skip tool calling when the model
  always needs the same information, and use at most three to five tools).
* **Prompt spec** (Apple WWDC25 session 248**†**: about 3B parameters, good at summarising and composing, weak at maths and facts,
  "avoid asking this small model to act as a calculator"): a single specific task, fewer than five few-shot examples **with no
  digits** (digits in examples teach the model to emit them), length by phrasing, safety rules in instructions only, a locale line and
  an explicit output-language instruction. Prompts live as versioned files; see the version cut points in section 11.
* **Availability.** Gate on `SystemLanguageModel.availability`, on `supportsLocale()`, and on the device and Siri language matching
  the UI language**†**. An app in German on an English device gets English by default. Guardrails apply only to supported locales.

| Device | Behaviour |
|---|---|
| iOS 17 to 25, watchOS | Template |
| iOS 26+, Apple Intelligence off, not ready, or locale unsupported | Template |
| iOS 26+, available, supported locale, consent on | On-device model, guards on |
| iOS 27+ | Larger models only in Phase 2 |

* **UX requirements** (Apple HIG, generative AI**†**): label model text and only model text, one-time limitations copy, a way to
  dismiss, voluntary feedback, a non-AI fallback. Classify each surface as proactive (silent fallback is fine) or user-initiated
  (show feedback). A "report this note" control and a named review owner are Phase 1 exit criteria.
* **Audience.** Needs iOS 26, an Apple Intelligence iPhone, the feature on, the model downloaded and a supported language. Apple
  reports iOS 26 on 79% of iPhones**‡**; no figure was found for the AI-capable share, which is lower.

### 6.4 Decision log (Phase 1, not Phase 0)

Purpose: explain "why this target" in the UI, nothing else. Fields: verdict, reason codes, engine and prompt versions, session ids;
no copied inputs. Retention cap in days, backup exclusion and file protection, cascade deletion on workout delete, sign-out and
account deletion, included in data export. Never uploaded, never sent to crash or analytics tools; evals use synthetic data only.
v1 planned it for Phase 0 with no consumer; it moved.

## 7. Evaluation plan

> S0 and S1 are as described and S0 exists in this PR (`CoachEngineTests`, `CoachPropertyTests`, `CoachPlannerTests`, `HubNoteTests`). S2 and the
> Apple Evaluations framework assumed an on-device model and are superseded; a cloud model would be evaluated with the same
> structure (escaped violations 0, rejection and fallback rates with confidence bounds, blind preference over `TemplateWriter`).

| Suite | What it tests | Runs on | Gate |
|---|---|---|---|
| **S0 Engine** | Table cases, **coach-labelled golden cases**, simulated lifter trajectories, invariants (cap, no progress after a gap or without effort data, bounded reduce), seeded fuzz reusing `RedLCG` (`WorkoutFuzzTests.swift:5`) | Linux `swift test`, existing `core-linux` job | Every PR, 100% |
| **S1 Harness** | Guards and fallback with a `ScriptedCoachModel`: exhaustive Unicode sweep for G3, swapped stances and negation for G4, "fatigue" and "Muskelkater" for G5, refusal text, empty, over-length, German, **late result after timeout, cancellation, no double log**; replay of every raw model output captured so far | Linux `swift test` | Every PR, 100% |
| **S2 Model** | The real on-device model | A Mac with Apple Intelligence | Gates only; see below |

**S2, re-specified.** v1 said "hard graders 100% over k = 5", which is undefined and statistically empty (on raw output, 150
clean trials only bound the failure rate below about 2%; a true 1% defect still passes 22% of the time; after the guards the gate is
vacuous because the template passes). Replace it with:

1. **Escaped violations after the guards must be 0**, argued by S1 and re-checked on S2 output.
2. **Per-guard first-attempt rejection rate and overall fallback rate**, with a Wilson 95% upper bound over at least 300 generated
   briefs at one trial each, and an explicit ceiling (for example fallback at most 20% on the oldest supported device).
3. **One preregistered run per gate.** A failure is investigated, not re-run. Gate results expire on each OS or model update.
4. **A fixed dev set and a frozen holdout** (at least 300 briefs from a seeded generator). Few-shot examples come only from the dev set.
5. **Fixed `GenerationOptions`** (greedy or low temperature); S2 records seed, OS build, device, raw text and each guard's verdict.
   Retries only when sampling is random, with a new seed; first-attempt and post-retry rates are reported separately.
6. pass^k only for a small variance sub-suite (k = 10).

**Model versus template.** Build `TemplateWriter v2` first: compositional (one clause per item, priority order, merged subjects),
with the same effort as the model path. v1's "one sentence per verdict" baseline was a strawman. Exit rule: blind pairwise
preference by two coaches, position-swapped, figures normalised; the model must be preferred in at least 65% of pairs with the
Wilson lower bound above 50% (about 85 pairs for 80% power). Any model judge is named, labelled on at least 100 stratified
outputs including seeded-bad items, and recalibrated when it changes. The "did the user hit the next target" outcome measures the
engine, not the writer, and is not an exit criterion.

**Tooling.** Apple's Evaluations framework (metrics, model-judge evaluators, aggregation, Swift Testing integration) is first-party
and works with any Foundation Models model**†**, but is **27.0 only**, so it needs an Xcode 27 Mac and cannot run on Linux or the
Xcode 16.4 jobs. Decide between it and a custom CLI before fixing S2 thresholds. I could not confirm that hosted macOS runners can run
the on-device model, so S2 may live on a developer Mac with results uploaded as an artifact.

## 8. Privacy, legal and App Store

Counsel should review this section; I am not a lawyer and several points are secondary sources.

| Topic | Position |
|---|---|
| Existing consent regime | The production app has explicit consent for AI coaching and an off switch (`terms.html` §8). **Model text must appear only while that consent is on, or behind its own explicit on-device opt-in with its own wording.** A feature flag alone is not enough. |
| v1 data flow | On device only. No workout data leaves the phone. Excluding average heart rate from the brief is a precaution, not an Apple requirement. |
| Apple 5.1.2(i) | "You must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so." Apple's text does not say whether its own on-device model counts. Our reading, not Apple's statement: no data is transmitted, so v1 has no third-party recipient. Anything sent to a non-Apple model is in scope; Private Cloud Compute is Apple-operated but off device and the text is silent. |
| Apple 5.1.2(vi), 5.1.3(i), 5.1.3(ii) | HealthKit and fitness data may not be used for advertising or use-based data mining, including by third parties, and health information may not be stored in iCloud. No guideline forbids a HealthKit-derived value in a prompt as such. These bind Phase 2. |
| Apple acceptable-use requirements for the framework**†** | Prohibit inaccurate or dangerous output in high-risk domains including medical, and circumventing guardrails. State the intended purpose as general fitness, not medical. |
| Apple 1.4.1 | Health apps should remind users to check with a doctor. Consider matching the wording for the static "not medical advice" text. |
| EU AI Act Art. 50**‡** | Transparency duties for AI-generated content and chatbots reportedly apply from 2 Aug 2026, with a short transition for machine-readable marking that new features may not get. A visible label may not satisfy it. Record the provider or deployer role; if the note is in scope, carry a machine-readable `source = model` marker through storage and any export. Make a legal check a Phase 1 exit criterion. |
| GDPR**‡** | Health-derived inferences (the decision log) are plausibly Art. 9 data; run a DPIA threshold assessment before Phase 1. |
| Minors and conditions | Terms minimum age 16. The engine takes an `AudienceProfile` from the host (adult, minor or unknown, avoid areas); minors and unknown get the conservative path. |
| Policy files | A data-table row, a new "on-device coach" subsection and a "no transmission" statement are needed in `privacy-policy.html` and `datenschutz.html`; `agb.html` and `terms.html` §8 describe AI as third-party models on EU servers, which an on-device model does not match; `datenschutz-einfach.html` should be reconciled with the main policy (server location and provider list differ), and the "private iCloud" wording for HealthKit data in §4 checked against 5.1.3(ii). Bump version stamps and respect the six-week change notice (Terms §15). |
| Phase 2 default | Reuse the existing EU pipeline. Any non-EU provider needs new consent and a Terms change, and should not ship while the Eden AI and Mistral agreements are pending. |

## 9. Phased plan and decisions

**Phase 0: evaluated deterministic core. Implemented.** No model; gate before release: policy-owner sign-off.
* 0a. Make the Core target-weight function public, extract the hub note builder into Core, write tests that **pin today's hub output and list the two divergences**, then remove the duplicate. (The existing `coachTip` tests are the seeds for S0.)
* 0b. `ProgressionEngine`, `Recommendation`, G0, `AudienceProfile`, S0. Measure RIR coverage on `SampleData` and a few real exports first, because most sets may have no RIR.
* 0c. "Next time" card with Apply, readiness hidden without a real provider, text through a String Catalog with German as an acceptance item (the code is English-only and `NumberText` is locale-free).
* 0d. `TemplateWriter v2`. Update `ARCHITECTURE.md` (it specifies the exact `coachTip` rule and text, and the test count).

*What was built:* `TargetWeight` (the one copy of the arithmetic, public), `HubNoteBuilder` (extracted, checked against a verbatim copy
of the old code over 4,000 random templates), `ProgressionEngine` with `CoachConfig`, `AudienceProfile` and `Recommendation`,
`TemplateWriter`, `CoachPlanner`, the hub "Next time" block, the exercise-card suggestion with Apply, the readiness sentence hidden while
the recovery numbers are demo data (`WorkoutController.isUsingDemoRecovery`), and `ARCHITECTURE.md` section 3.7.

*Review of the first implementation.* Four independent reviews (a fuzz run of about 300,000 cases, a strength-coach reading with 62
scenarios and 11 trajectories, a read against this document, an iOS behaviour review) found about 55 issues. Fixed in the same pull request,
each with a regression test (`CoachReviewFixTests`): Apply flattened back-off sets and ramps; a lift trained on two different days was judged
as one series; "two clean sessions" could be months apart; future-dated sessions and non-finite dates defeated the break rule; the progress
gate used the mean RIR where this document says two thirds of the sets; a re-marked failure set kept a stale RIR; the typo guard dropped a
real climb and was blind with two sessions; holds at a cap had no explanation; the sentences hard-coded the RIR threshold; a bad
`CoachConfig` silently removed a cap; the hub "Aim for" sentence ignored the audience and contradicted the "Next time" line; and several iOS
points (room on a small screen, VoiceOver, contrast, tap target, date pinned to the workout start, Apply recomputed at the tap).

A second review of those fixes found more, fixed the same way (`CoachSecondReviewTests`): Apply still reached back-off sets behind a
heavier to-failure set; the record tip came back right after "Apply"; the typo guard missed rep typos when the older session was
stronger, erased a genuinely heavier session whose sets agreed, ignored recency and had no tolerance at exactly 1.25; a stale workout name
hid recent training and the other day's weight reached Apply in a split's first sessions (now a plan check); "Stay at" was the wrong word
after a layoff; the 28-day boundary flipped on the time of day; and the lighter week still fired for a typical beginner.

*Found, not fixed, because each is a policy decision for a qualified coach:*
* **Light lifts only ever gain reps.** With a 7.5 % cap (5 % when the age is unknown) the 2 to 2.5 kg steps are "too big a jump" for
  barbells under 33 kg (50 kg), dumbbells under 27 kg (40 kg) and most isolation work; the target climbs to 30 reps and then holds, now with
  an explanation. A coach would move to the next weight at 15 to 20 reps and drop the reps.
* **No template rep ranges.** The engine works from performed sets only, so it cannot recognise the top of a range (8 to 12) and holds
  lifters who train close to failure indefinitely. Using `PlannedSet.repsMax` (optional input) is the natural next step.
* **Beginner pace.** Two sessions per step is about half of linear progression; a one-session lane for sessions at RIR 3 or more is a
  candidate. **Deloads are forgotten:** after a lighter week the engine climbs back 2.5 kg per two sessions. **No RIR, no suggestion:** a
  fallback such as "all planned reps in two sessions" needs the planned reps. **Break handling:** a long layoff holds at the old weight; coaches
  restart at 60 to 90 %. **Targets from the mean:** one bad set lowers the next target by a rep.
* **Wording.** "RIR" and "clean session" are not explained; a decrease and an increase read alike on the card.
* **Same-day sessions and rep typos on high-rep lifts.** Two workouts logged on one day count as two sessions; a typo in the reps of a
  lift done above ten reps cannot be seen by the typo guard (a weight typo is stopped by the plan check).
* **The PR-chase "Aim for" arithmetic** still starts from the all-time best estimated 1RM, so one typo set can inflate it (the engine's typo
  guard does not apply); it is now hidden whenever the engine names a weight, for minors and for avoided muscles.

*What was deliberately not done, and why:*
* **German / String Catalog.** The whole app is English with locale-free number formatting; localising only the new strings would
  mix languages. `CoachLine` keeps the words separate from the figures so localisation can be added app-wide later.
* **The cap on the in-workout PR-chase tip.** The existing tests pin that tip as independent of the set's current weight, so the
  tip is unchanged. Only people known to be minors lose it; `.unknown` keeps it. (The engine's caps apply to the new "Next time".)
* **`TemplateWriter v2` (compositional) and the decision log.** Both only matter once a model writes text.
* **Per-exercise increment table from a coach.** `CoachConfig.incrementsKg` is by equipment and equals the keypad steps.
* **RIR coverage measurement on real data.** In the demo data only bench has RIR, so five of the six upper-body lifts show the
  "Log RIR" hint. Real coverage is unknown.
**Phase 0.5: measurement (about two days).** *The on-device model spike is dropped.* Instead: RIR coverage on a few real exports, any available usage data for the current tip and the new "Next time" lines, a coach review of the thresholds (the sign-off), an accessibility pass (VoiceOver and Dynamic Type for the new views), and one evening of competitor teardown (Strong, Hevy, Fitbod, Alpha Progression). Output: a named user problem, or no model.

**Phase 1 (conditional, cloud only): a model as writer.** *The on-device version is ruled out.* If Phase 0.5 names a user problem templates cannot solve: a seam and composer in Core, G1 to G8, a scripted model for S1, the decision log, and a cloud model reached through the existing EU pipeline only while the existing AI-coaching consent is on (section 8). **Exit:** escaped violations 0, a fallback rate under its ceiling, blind preference over `TemplateWriter v2`, a "report this note" control with a named review owner, and the legal check in section 8. Otherwise stop and keep templates.

**Phase 2 (conditional): free-form Q&A.** Read-only tools (`exercise_status`, `session_plan`, `readiness` returning `unavailable`, never demo numbers). Required tool calling and dynamic profiles are **iOS 27 only**. Every larger-model path (Private Cloud Compute, Anthropic's package) is iOS 27 and Xcode 27 only. Anthropic's Swift package has three auth modes**†**: App Attest (recommended; no key in the app and no backend), a proxy you run, and a bundled key (extractable; never ship it). Requests go straight from the app to Anthropic, so workout data would leave the EU pipeline: see section 8. Replace "skip the model on flagged input" with a fixed safe-messaging reply.

**Decisions.** *Blocking Phase 0:*
1. Which workout AI (section 2)? Default: A, and look at B separately.
2. Who signs off the engine thresholds (a qualified coach), and do we ship an aggressiveness setting? Default: yes to both.
3. Languages: English only or English and German in Phase 0? Default: both, via String Catalog.
4. Will the Pulse app supply `AudienceProfile` and a real or "unknown" recovery value? Default: yes.

*Blocking only Phase 1 and later:*
5. ~~Minimum OS, Apple Intelligence audience, Xcode 27 for evaluation, prompt variants~~ Not applicable after the no-on-device decision.
6. Judge model, human calibrators, spike length and who calls it dead.
7. Silent or visible fallback on user-initiated surfaces; dismiss and feedback UX.
8. Appetite for cloud models (Phase 2) and the legal work in section 8.

## 10. If the target is the production cloud coach (B)

I have not seen its code. What carries over, and what I would need:

* **Model swap behind a stable interface.** The Terms already reserve the right to switch model or provider (§8(4)). Keep prompts, tool definitions and guards independent of the provider, as in Anthropic's brain/hands/session split and Apple's HIG ("separate your model from your user experience").
* **Plan generation as structured output with executable checks.** Apple's own evaluation guidance uses a "zero tolerance" criterion for dietary restrictions; the analogue here is "body areas to avoid and declared limitations are respected in 100% of generated plans", graded by code, with a model judge only for tone.
* **Chat grounding and memory.** Treat memory as scarce context: notes outside the window, just-in-time lookups of workout logs through a few consolidated tools, compaction, and expiry for stale remembered claims (press reports of a shipped LLM coach describe exactly that failure**‡**).
* **Consent and EU-only handling** are already designed in; any harness change must keep them.
* **To go further I would need:** read access to the Pulse app repository and the prompt and edge-function code, the eval data policy (synthetic only), and your answer to decision 1. I have not opened any repository other than this one.

## 11. API availability (background only: no on-device model will be used)

From Apple's DocC metadata**†**. Relevant again only if a cloud model is reached through Apple's Foundation Models API (Private Cloud Compute or a provider package), which is iOS 27 only.

| OS | What exists |
|---|---|
| 26.0 | Framework, `SystemLanguageModel`, `LanguageModelSession`, `Tool`, `Instructions`, `GenerationOptions`, `@Generable`. Errors are `LanguageModelSession.GenerationError` (introduced 26.0, deprecated 27.0). macOS 26.0 also has the framework, so the adapter guard must include `os(iOS)`. |
| 26.4 | `tokenCount(for:)` (all overloads); `contextSize` back-deployed (needs an SDK from Xcode 26.4). The on-device model also changed with 26.4 and again with 27. |
| 27.0 | `DynamicProfile`, `Profile`, `DynamicInstructions`, `GenerationOptions.ToolCallingMode`, the `LanguageModel` protocol, `PrivateCloudComputeLanguageModel`, `LanguageModelError`, `transcriptErrorHandlingPolicy`, the Evaluations framework. The framework itself reaches watchOS at 27. |

Consequences: the adapter must be whole-file `#if os(iOS) && canImport(FoundationModels)` with `@available(iOS 26, *)` types
(`ARCHITECTURE.md` §2). `canImport` alone would break the `xcode26` job, which runs `swift test` for macOS 14 on a macOS 26 SDK.
Put the adapter in the existing iOS-only `PulseStrengthIOS` target (already linked by the app, no `project.yml` change), or in a new
product that needs `xcodegen generate` and a regenerated project. Construct it through an SDK-independent factory returning `nil`
when unavailable. An adapter the app does not link is compiled by no CI job, and the iOS 17 floor is compile-checked but never run (per the README's
verification notes the runners offer only iOS 18.5 and 26.x simulators). Token-budget tests need 26.4 or later and belong in S2, not S1.

## 12. Research digest (appendix)

*Harness* here means everything around the model: instructions, tools, context handling, control loop, guards, memory and evals
(my wording). Marmelab defines *harness engineering* as "building the tools, context, memory, and control loops to make an agent
reliable" and credits "Agent = Model + Harness" to Birgitta Böckeler.

| # | Lesson | Source | Consequence here |
|---|---|---|---|
| 1 | Start with the simplest thing that works: a single LLM call, then a workflow, an agent only when flexibility is needed. | Anthropic, *Building effective agents* | A workflow with at most one model call. |
| 2 | Context is scarce. Preload small facts, retrieve large ones just in time. | Anthropic, *Effective context engineering* | Facts are tiny and always needed: precompute them. |
| 3 | The on-device window is 4096 tokens; three to five tools at most; skip tool calling when the model always needs the same data. | Apple, *Managing the context window* | No tools in v1. |
| 4 | Few, consolidated tools with readable output and actionable errors, tuned against evals. | Anthropic, *Writing tools for agents* | Phase 2 tool design. |
| 5 | Executable guards beat prose rules (Marmelab: rules in prose are "almost never actually enforced"). Permission and security layers belong outside the harness self-improvement loop (Weng). | Marmelab; Weng | Guards are code; the model has no write access (the second half is my design inference). |
| 6 | Evals first: 20 to 50 cases from real failures, grade outcomes not paths, test both directions. | Anthropic, *Demystifying evals*; Apple, *Evaluating prompts* | Section 7. |
| 7 | A separate skeptical evaluator is easier to tune than a self-critical generator, and the evaluator "is not a fixed yes-or-no decision". In one SWE-bench comparison a four-role team scored 72.2% against 71.8% for the best single agent; one ablation found a reviewer lowered success (the base rate was 41%). | Anthropic, *Harness design*; Marmelab | The evaluator is deterministic code; a model judge only for tone. |
| 8 | Harness parts encode assumptions that go stale: "give every control an expiry condition, and write down the incident it exists for". | Anthropic, *Managed Agents*; Marmelab | A retire condition per guard (to add to section 6.2 as the guards are built). |
| 9 | Keep durable state outside the model. The session is an append-only log (Managed Agents); *Effective harnesses* uses a progress file, git history and a JSON feature list edited in place. | Anthropic | The decision log, kept out of prompts. |
| 10 | Bound inputs and outputs, keep unverified text out of instructions, write a risk assessment, keep safety tests. | Apple, *Improving the safety of generative model output* | G1, G3, G5, G8. |
| 11 | Model updates ship with the OS; version prompts and re-run evals. | Apple, *Updating prompts for new model versions* | Prompt files and cut points. |
| 12 | Coach panels rate LLM-written multi-week programs as moderate overall and say they need expert refinement; the JMIR preprint names individualisation, load progression and risk management as gaps without rating them separately. None tested next-session load progression from a user's history. | Havers et al. 2025; Washif et al. 2024; Silva et al. 2026 (preprint) | Consistent with keeping progression maths in code. That is a design choice, not a finding of these studies. |

**What does not transfer.** The long-running coding-agent pattern (initializer agent, feature list, `init.sh`, browser testing) solves
"an agent across many context windows". A one-shot note has no such problem. Anthropic's full planner/generator/evaluator harness
cost about $200 over 6 hours against $9 in 20 minutes for a solo run in one example, with a visibly better result there; the point
is that it is far too heavy for a note, not that extra roles never pay.

**Evidence quality.** Many 2026 sources are engineering blogs. Marmelab discloses that it writes AI harnesses and authors Atomic CRM
(one of its 11 ranked finalists) and that it used AI to aggregate its sources; only some of its figures are flagged second-hand.
A solo founder's DEV post claims a deterministic engine feeds the LLM only verdicts; that wording appears in a reply comment, the post
itself says methodology documents are cached into the model's context, and it offers no code, tests or demo. Directional only.
OpenAI's *Harness engineering* post (read via an archive copy**†**) describes a roughly 100-line `AGENTS.md` as a table of contents,
with architecture enforced by custom linters and structural tests.

## 13. Sources

Opened and read (by me, or by a review agent**†** where marked):
* Anthropic: [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents), [Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents), [Writing tools for agents](https://www.anthropic.com/engineering/writing-tools-for-agents), [Demystifying evals](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents), [Harness design for long-running apps](https://www.anthropic.com/engineering/harness-design-long-running-apps), [Scaling Managed Agents](https://www.anthropic.com/engineering/managed-agents), [Building intelligent apps for Apple platforms with Claude in the Foundation Models framework](https://claude.com/blog/claude-for-foundation-models); package docs**†**: [ClaudeForFoundationModels](https://github.com/anthropics/ClaudeForFoundationModels), [library docs](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/apple-foundation-models)
* Apple Foundation Models: [overview](https://developer.apple.com/documentation/foundationmodels), [tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling), [safety](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output), [evaluating prompts](https://developer.apple.com/documentation/foundationmodels/evaluating-prompts-to-measure-performance-and-improve-model-responses), [dynamic profiles](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles), [context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window), [Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), [prompt versioning](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions); by review agents**†**: [supporting languages](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models), [Evaluations](https://developer.apple.com/documentation/evaluations), [HIG: generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai), WWDC25 session 248, WWDC26 session 241
* Apple, [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (primary text, updated 8 June 2026**†**)
* Surveys: [Marmelab, State of AI harness engineering 2026](https://marmelab.com/blog/2026/09/24/the-state-of-ai-harness-engineering-2026.html), [Lilian Weng, Harness engineering for self-improvement](https://lilianweng.github.io/posts/2026-07-04-harness/), [OpenAI, Harness engineering](https://openai.com/index/harness-engineering/) (403 directly; read via an [archive copy](https://web.archive.org/web/20261012001826/https://openai.com/index/harness-engineering/)**†**)
* Fitness evidence (abstracts**†**): [Havers et al. 2025](https://pmc.ncbi.nlm.nih.gov/articles/PMC12492345/), [Washif et al. 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC10955742/), [Silva et al. 2026, JMIR preprint](https://preprints.jmir.org/preprint/93865), [Graham and Cleather 2021](https://research.stmarys.ac.uk/3067/3/Graham-Cleather-Autoregulation-Repetitions-in-Reserve.pdf); a 2022 meta-analysis by Hickmott et al. that pooled the Graham and Cleather trial (citation to confirm)
* Practitioner claim: [DEV Community post](https://dev.to/arqamwd/logging-workouts-is-solved-im-building-what-comes-after-36cc)

Secondary only**‡**: EU AI Act Art. 50 timing and scope (law-firm summaries); a press report on a shipped LLM health coach ([WebProNews](https://www.webpronews.com/googles-ai-health-coach-already-hallucinates-workouts-that-never-happened/), citing Android Authority and Wired); RIR self-report accuracy (search snippets of Halperin et al. and two 2025 papers, not opened).

## 14. Review log (v1 to v2)

Corrected after verification:
* "The README says the Pulse app injects the real model": it is a code comment (`Presentation.swift:327`); the README only tells the host to pass one.
* "Private to the iOS target" is file-private; "move the target maths into Core": it is already in Core but internal, so it must be made public. The two copies are not identical (finding 3).
* RIR is also shown per set, not only as an average; the "one idea only" claim ignored the hub's readiness sentence.
* Marmelab "sells a harness": it writes harnesses and authors an open-source finalist. Weng's "this loop" is the self-improvement loop, not the agent loop. The append-only log is Managed Agents, not *Effective harnesses*.
* "Plans improved with more detailed prompts" was attributed to the wrong study and is removed. Row 12 reworded ("weak" was stronger than the sources).
* Anthropic's announcement is silent on keys, but the package docs are not (three auth modes); "plan a backend proxy" was wrong as the only path.
* Apple availability was unresolved in v1 and is now in section 11. `tokenCount(for:)` is 26.4, not 26.0. Dynamic profiles, tool-calling mode and the `LanguageModel` protocol are 27.0 only.
* The OpenAI post was read via an archive copy; the DEV post's "verdicts only" wording is from a reply comment.
* "Screenshot CI will show copy changes" overstated: nothing asserts text.

Redesigned after the red team: the progression policy (it assumed data that history does not keep), G3 to G5 (leaky, hosted, lexicon-based), the S2 gate and the template baseline, Phase 0 ordering, the missing first user-visible change, the missing audience and legal sections, and the decision log moved out of Phase 0. Added: section 2 (which AI), section 5, G0 and G8, section 10.

Not done: the real on-device model was never run, no one has measured RIR coverage or usage of the current tip, there was no coach review, and the Evaluations and open-source Foundation Models material was read only second-hand. Phase 0.5 exists to close those.
