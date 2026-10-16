# Pulse Strength for Android

The strength-workout feature of Pulse for **Android phones**: a strength hub with templates, history and recovery, the active-workout
screen (set table, keypad with plate calculator, rest timer, supersets, undo, PR detection, coach tip), the workout summary, an
exercise library with how-to cues and per-exercise history, and an ongoing **workout notification** (the Android counterpart of the iOS
Live Activity) with buttons that log a set and control the rest timer from the lock screen. It also feeds the glanceable surfaces of the
design "Pulse Strength Widget Ideas": home screen and lock screen widgets, Quick Settings tiles, richer Live Update states, planned
sessions, bench mode and a **Wear OS** companion (see [Widgets, tiles and live surfaces](#widgets-tiles-and-live-surfaces)).

It is a native Kotlin / Jetpack Compose app that follows the iOS app in [`../ios/`](../ios/README.md) screen by screen (same design,
same copy, same workout rules, as the iOS app was when the Android work started; see "Parity with iOS" below) and is **ready to ship to Google Play**: see [`RELEASING.md`](RELEASING.md) for the steps that need your
accounts, keys and decisions (application id, upload key, Play Console, privacy policy review).

> **Repository note.** This directory lives in the `pulse-health.github.io` website repository. The root `_config.yml` excludes
> `android/` (and `ios/`) from the GitHub Pages build, so these files are not served on the website. If the project later moves to its
> own repository, delete the `exclude` entries.

## Layout

```
android/
  README.md  RELEASING.md       this file; the release guide
  settings.gradle.kts, build.gradle.kts, gradle/libs.versions.toml, gradlew   Gradle 9.8 / AGP 9.4 / Kotlin 2.4 (version catalog)
  core/                         pure Kotlin (JVM) port of PulseStrengthCore: no Android dependency, about 880 unit tests
    src/main/kotlin/health/pulse/strength/core/
      Models, WorkoutState, WorkoutAction, Presentation, Snapshot, Completed   the value types (kotlinx.serialization)
      WorkoutReducer, WorkoutFactory, WorkoutTargets                           every change to a workout (pure function)
      WorkoutPresenter, SummaryBuilder, SnapshotBuilder, TemplateDiff           state -> display-ready values
      ExerciseLibrary, Metrics, SampleData, RecoveryModel                       36 exercises, e1RM / plates / number text, demo data, recovery rule
      StrengthData, StrengthDataModel, Stores (JSON files), StrengthStore       what is remembered between workouts
      WorkoutEngine, WorkoutController                                          the running workout (StateFlow for the UI, side effects for services)
      widgets/                                                                  the widget data contract (WidgetSnapshot, generated), its builder, deep links, commands
  app/                          the Android application
    src/main/kotlin/health/pulse/strength/
      PulseStrengthApplication, MainActivity, StrengthAppEnvironment            wiring: one environment per process, deep link, edge-to-edge
      ui/theme, ui/components                                                   design tokens (light + dark), buttons, chips, media tile, haptics, clock
      ui/PulseStrengthRoot                                                      hub, active workout, summary layers and the in-progress bar
      ui/hub, ui/active, ui/sheets, ui/detail, ui/summary, ui/settings          the screens (ports of the SwiftUI views)
      services/                                                                 ongoing notification, notification buttons, rest alerts, settings
      health/                                                                   opt-in Health Connect writer and its rationale screen
      runtime/, surfaces/                                                       the snapshot seam (LiveRuntime), refresh of every surface, midnight refresh
      widgets/common, home, tablet, lock, extras                                Glance app widgets (HS, SB, LS, WI ids of widgets/SPEC.md)
      live/, controls/                                                          Live Update decoration, planned session, bench mode; Quick Settings tiles, shortcuts
      wear/                                                                     phone side of the Wear OS sync (Data Layer)
    src/exerciseMedia/assets/ExerciseMedia/                                     50 demo photos: debug builds only, NOT in the release (see below)
    src/test/                                                                   about 1,200 Robolectric tests: screens, widgets, tiles, services; screenshots go to app/build/screens
  wear/                         the Wear OS companion: tiles, complications, Ongoing Activity, watch screens (:wear, watch-only APK)
  store/                        Google Play listing text (en-US, de-DE), graphics, release notes
../.github/workflows/strength-android.yml                                       CI: tests, lint, release bundle, optional Play upload
../strength-privacy.html, ../strength-datenschutz.html                          the app's privacy policy (served by the website)
```

## Build and test

Requirements: JDK 17+ (CI uses 21) and the Android SDK with platform **37** and build-tools **36** (`ANDROID_HOME` set, licenses accepted).

```sh
cd android
./gradlew :core:test                         # the workout rules (JVM, ~45 s)
./gradlew :app:testDebugUnitTest             # screens, notifications, rest alerts, widgets, tiles (Robolectric; no emulator needed)
./gradlew :wear:testDebugUnitTest            # the watch app: tiles, complications, Ongoing Activity, screens
./gradlew :app:lintDebug :wear:lintDebug     # Android lint (errors fail the build)
./gradlew :app:assembleDebug :wear:assembleDebug   # debug APKs (install next to a Play build: the id ends in .debug)
./gradlew :app:bundleRelease                 # release bundle with R8; unsigned without a keystore (see RELEASING.md)
```

## Verification status

What was run (in a Linux sandbox, no emulator, no device):

| Check | Result |
| --- | --- |
| `:core:test` | 887 tests, all pass (the Swift suite was ported; it found two real divergences from the Swift rules, both fixed; the widget builder and the live moments are tested too, and the Kotlin snapshot of the demo data equals the Swift one, `widgets/fixtures/golden-sample.json`) |
| `:app:testDebugUnitTest` | 1213 tests, all pass: every screen and sheet, the notification and rest-alert services, `FirstRunFlowTest` (an empty install through the real picker, a logged set, finish, summary and hub), and the widgets, tiles, live surfaces, runtime and watch sync described below (the widgets are drawn into PNGs) |
| `:wear:testDebugUnitTest` | 236 tests, all pass: tiles, complications, Ongoing Activity, the watch screens, the Data Layer codec |
| `:app:lintDebug`, `:wear:lintDebug` | no errors (lint errors fail the build) |
| `:app:assembleRelease`, `:wear:assembleRelease` | R8 + resource shrinking, unsigned APKs; the merged manifests contain no `INTERNET` or `ACCESS_NETWORK_STATE`; the phone asks for `POST_NOTIFICATIONS`, `POST_PROMOTED_NOTIFICATIONS`, Health Connect `WRITE_EXERCISE`, `RECEIVE_BOOT_COMPLETED` and, through WorkManager (a dependency of Glance), `WAKE_LOCK` and `FOREGROUND_SERVICE` |
| CI (`strength-android`, `verify` job) | runs the same tests, lint and debug builds on every pull request |

**Not verified:** anything that needs a real device: the notification buttons on the lock screen, rest alerts with the screen off,
Health Connect, backup and restore, the Play upload, and everything listed under "Widgets, tiles and live surfaces" below. The checklist for
those is `RELEASING.md`, section 5.

The UI tests render the real Compose screens on the JVM with Robolectric's native graphics and write PNGs to
`app/build/screens/` (CI uploads them as the `android-screens` artifact), so a screen can be looked at without an emulator.

## How it maps to the iOS app

| iOS | Android |
| --- | --- |
| `PulseStrengthCore` (Swift package) | `:core` (Kotlin, same rules, same names; the iOS test suite was ported and passes) |
| SwiftUI screens and sheets | Compose screens; sheets are Material 3 `ModalBottomSheet`, `confirmationDialog` is an `AlertDialog` |
| `PulseTheme` | `ui/theme/PulseTheme.kt` (same tokens, light and dark) |
| Live Activity, Lock Screen buttons (App Intents) | ongoing notification with buttons (`NotificationActionReceiver`); on Android 16 it asks to be a *Live Update* chip |
| time-sensitive rest notification | `RestAlerts`: in-process exact alarm + `PendingIntent` backup; sound/vibration channel "Rest over" |
| HealthKit workout writer | Health Connect `ExerciseSessionRecord` writer, opt-in, write-only |
| `UIApplication.isIdleTimerDisabled` | `KeepScreenOn` while the workout screen is open |
| App Group / Application Support | `files/PulseStrength/*.json`, included in Android backup (the unfinished workout is not) |
| `pulse-strength://` URL scheme (workout, start-next, start, start-empty, exercise, hub, plates, weight) | the same links on `MainActivity` (`DeepLinkRouter`) |
| WidgetKit widgets, controls, Live Activity states | Glance widgets, Quick Settings tiles, Live Update decoration (see below) |
| Apple Watch app and widgets | the Wear OS companion in `wear/` (tiles, complications, Ongoing Activity); **no heart-rate recording** yet |

### Deliberate differences

* **A real install starts empty.** The iOS standalone build seeds demo templates and history on first launch and ships invented
  "previous results" for the library exercises. The Android release does neither (`StrengthData.usesLibraryHistory = false`,
  `seedDemoData = false`): a personal record is only flagged against the user's own history, and "previous" columns fill from it.
  Demo data remains for previews and tests (`StrengthAppEnvironment.preview()`).
* **Muscle recovery is computed** from the finished workouts (`RecoveryModel`, a documented rule of thumb: 48 h after up to 6 sets,
  +4 h per extra set, at most 72 h) instead of the iOS demo constants.
* **No heart rate.** The Wear OS companion shows data and sends commands but does not record heart rate, so the heart-rate stat is hidden; the core keeps the heart-rate fields.
* **No network permission, no foreground service, no exact-alarm permission** (see `RELEASING.md`, "Known limitations").
* The app is English-only and kilograms-only, as the iOS app is.

### Parity with iOS

The Kotlin core is a port of the iOS strength core **as it was when the Android work started** (`main` at `b6c14ac`; the ported Swift test
suite is the proof). `ios/` has moved on since, and none of these later iOS features exist on Android yet:

* body weight with weigh-in reminders and the Apple Health sync, and the body-weight based records (iOS PR #7);
* training plans with a flexible rotation, rep ranges (`repsMax`), template notes and plan import;
* the YouTube workout import tool (`ios/tools/youtube-workouts`).

Nothing detects drift between the two cores automatically; when one of these is ported, port its Swift tests with it and update this
list. The Android app is complete and shippable without them (v1 of the iOS app did not have them either).

## Widgets, tiles and live surfaces

The 68 designs of the canvas "Pulse Strength Widget Ideas" (ids `HS-01` ... `WI-11`) are implemented here and on iOS. The catalogue, the
exact rule behind every figure and the platform mapping are in [`../widgets/SPEC.md`](../widgets/SPEC.md); [`../widgets/README.md`](../widgets/README.md)
maps every area to its files on both platforms.

* **One data contract.** `WidgetSnapshot` is generated from `../widgets/tools/schema.py` (Kotlin here, Swift on iOS) and is the only thing a
  surface reads. `WidgetSnapshotBuilder.make(data, context, now)` in `:core` builds it with the rules of SPEC section 2; for the demo data its
  output equals the Swift builder's (`widgets/fixtures/golden-sample.json`, compared by `WidgetSnapshotGoldenTest`).
* **Runtime (`runtime/`, `surfaces/`).** `StrengthRuntime` is the seam. `LiveRuntime` keeps the snapshot in memory (the widgets run in the app's
  own process, so there is no file) in step with the store, the workout, the weekly goal, the end of a rest and the clock, publishes only
  what changed and calls `Surfaces.refreshAll` (one failing surface never stops the next). `LiveCommands` runs what a surface asks (log set,
  skip rest, pause, start, finish, ...). `DayChange` rebuilds the snapshot at local midnight, on a change of the clock or the time zone, after
  a restart and after an update (an inexact alarm: no permission).
* **Widgets (`widgets/`, Glance).** 12 Home Screen widgets and the tablet training block (`home`, `tablet`), 11 Lock Screen / glanceable hub widgets
  (`lock`) and 11 extras (`extras`), registered in the manifest regions of their owners. Cards, light / dark / Material You, 48 dp targets,
  spoken descriptions, text fitted by measurement, an empty state for every one.
* **Live surfaces (`live/`, `controls/`).** The ongoing workout notification of `services/` is decorated (record flash, superset round with
  "Log A2", plate math, coach tip answers, the finish summary, status-bar chip text, segmented progress on Android 16); a planned session counts
  down 30 minutes before its start and says "Time to train" (`PlannedSessions`, alarms re-armed after a restart; exact on Android 11 and older and where the
  user allows "Alarms & reminders" for the app, inexact otherwise: the app declares no exact-alarm permission); bench mode is a full-screen
  rest timer (`BenchModeActivity`, red night theme); eight Quick Settings tiles, the "Primary action" activity and the static shortcuts
  (`res/xml/shortcuts.xml`) are the controls and the Action button.
* **Wear OS (`wear/`, `app/.../wear/`).** The watch app (Compose), five tiles, seven complications and an Ongoing Activity chip read the snapshot
  the phone writes into the Data Layer (`PhoneWearSync`); Log set, rest and start commands travel back (`PhoneWearListenerService`). Phone and
  watch must share the application id and the signing key. Each tile has a preview image for the watch's tile gallery
  (`wear/src/main/res/drawable-nodpi/tile_preview_*.png`, drawn by `wear/tools/tile-previews/render.mjs`). The privacy pages describe the watch app (section 5a).
* **In the app.** The hub shows a weekly-goal stepper under "This Week" (`PulseSettings.weeklyGoal`, 1 to 7), a template's calendar button opens
  "Plan a session", and `pulse-strength://` links reach `MainActivity` (cold start included).
* **Offline by design.** The merged manifests of the phone and the watch app contain neither `INTERNET` nor `ACCESS_NETWORK_STATE` (the one that
  WorkManager, a dependency of Glance, adds is removed; a unit test guards it). The one permission the widget work adds on the phone is
  `RECEIVE_BOOT_COMPLETED` (to arm a planned session again after a restart); the watch asks for `POST_NOTIFICATIONS` (Ongoing Activity chip).

**Verified** (`./gradlew :core:test :app:testDebugUnitTest :wear:testDebugUnitTest :app:lintDebug :wear:lintDebug :app:assembleDebug :wear:assembleDebug
:app:assembleRelease :wear:assembleRelease`): 887 + 1213 + 236 tests, lint without errors, R8 release builds of both apps. The widgets are composed through
Glance, inflated and drawn into PNGs by Robolectric (`app/build/screens/widgets*`, in the `android-screens` artifact); tile layouts and complications
are checked as data (protolayout trees, complication data per type).

**Not verified**: nothing ran on a phone, a watch or an emulator, so launcher sizes, rounded corners (API 31+), the Android 16 Live Update chip, the
Quick Settings and shortcut behaviour, widget updates on placed widgets, the Data Layer round trip, the real tile renderer and TalkBack are untested;
see [`RELEASING.md`](RELEASING.md) section 5 for the device checklist.

**Not in the Android data model**, so these degrade: training plans (the plan fields of `nextUp` are empty), rep ranges and entry notes, stored body
weight (the strength ratio shows the estimated 1RM only), readiness and training partners (the "connect" states of `WI-09` / `WI-03`).

## Placeholders to replace

| Placeholder | Value | Where |
| --- | --- | --- |
| Application id | `health.pulse.strength` (same string as the iOS bundle id) | `applicationId` in `app/build.gradle.kts`; `packageName` in the workflow. **Final once uploaded to Play.** |
| Version | `1.0.0` / code from `-Ppulse.versionCode` | `app/build.gradle.kts`, `-Ppulse.versionName` |
| Privacy policy / contact | `https://pulse-health.github.io/strength-privacy.html`, `robin.juengerich@icloud.com` | `ui/PrivacyLinks.kt` |
| App icon | green dumbbell (adaptive + monochrome) | `app/src/main/res/drawable/ic_launcher_foreground.xml`, `values/colors.xml`; Play icon `store/graphics/icon-512.png` |
| Accent colour | green `#1B8448` | `ui/theme/PulseTheme.kt` |
| Signing | none in the repository | `keystore.properties` or `PULSE_KEYSTORE_*` (see `RELEASING.md`) |

## Exercise photos

`app/src/exerciseMedia/assets/ExerciseMedia` holds the same 25 exercises x 2 form-demo frames as the iOS app, from the
[Free Exercise DB](https://github.com/yuhonas/free-exercise-db). **They are placeholders, not cleared media.** The database is released
under the Unlicense, but its README does not say where its images come from or under which licence they may be used, so "public domain"
cannot be claimed for them; the photos show identifiable people in a commercial gym and some show brand marks (the iOS README says the same).

So the **release build does not contain them**: they are an extra asset folder of the *debug* build type (used by the debug APK, the tests
and the store-screenshot test) and a release only ships them with `-Ppulse.includeExerciseMedia=true` (or `PULSE_INCLUDE_EXERCISE_MEDIA=true`;
in CI the repository variable `ANDROID_INCLUDE_EXERCISE_MEDIA=true`). The CI `release-build` job fails when the release APK holds any of them
without that variable. Without photos the app shows its placeholder tile, no "Form demo" badge and no photo attribution; where photos are
present it says "Demo photos from the Free Exercise DB." in the form sheet, the exercise detail and under Settings.

To ship photos: replace the 50 files with your own or properly licensed ones (same file names, `<key>-a.jpg` / `<key>-b.jpg`), update the
attribution line and the privacy/listing text, then set the variable. The current files also remain in the git history of this public repository.
