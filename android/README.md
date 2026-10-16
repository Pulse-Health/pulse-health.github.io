# Pulse Strength for Android

The strength-workout feature of Pulse for **Android phones**: a strength hub with templates, history and recovery, the active-workout
screen (set table, keypad with plate calculator, rest timer, supersets, undo, PR detection, coach tip), the workout summary, an
exercise library with form photos and per-exercise history, and an ongoing **workout notification** (the Android counterpart of the iOS
Live Activity) with buttons that log a set and control the rest timer from the lock screen.

It is a native Kotlin / Jetpack Compose app that follows the iOS app in [`../ios/`](../ios/README.md) screen by screen (same design,
same copy, same workout rules) and is **ready to ship to Google Play**: see [`RELEASING.md`](RELEASING.md) for the steps that need your
accounts, keys and decisions (application id, upload key, Play Console, privacy policy review).

> **Repository note.** This directory lives in the `pulse-health.github.io` website repository. The root `_config.yml` excludes
> `android/` (and `ios/`) from the GitHub Pages build, so these files are not served on the website. If the project later moves to its
> own repository, delete the `exclude` entries.

## Layout

```
android/
  README.md  RELEASING.md       this file; the release guide
  settings.gradle.kts, build.gradle.kts, gradle/libs.versions.toml, gradlew   Gradle 9.8 / AGP 9.4 / Kotlin 2.4 (version catalog)
  core/                         pure Kotlin (JVM) port of PulseStrengthCore: no Android dependency, about 570 unit tests
    src/main/kotlin/health/pulse/strength/core/
      Models, WorkoutState, WorkoutAction, Presentation, Snapshot, Completed   the value types (kotlinx.serialization)
      WorkoutReducer, WorkoutFactory, WorkoutTargets                           every change to a workout (pure function)
      WorkoutPresenter, SummaryBuilder, SnapshotBuilder, TemplateDiff           state -> display-ready values
      ExerciseLibrary, Metrics, SampleData, RecoveryModel                       36 exercises, e1RM / plates / number text, demo data, recovery rule
      StrengthData, StrengthDataModel, Stores (JSON files), StrengthStore       what is remembered between workouts
      WorkoutEngine, WorkoutController                                          the running workout (StateFlow for the UI, side effects for services)
  app/                          the Android application
    src/main/kotlin/health/pulse/strength/
      PulseStrengthApplication, MainActivity, StrengthAppEnvironment            wiring: one environment per process, deep link, edge-to-edge
      ui/theme, ui/components                                                   design tokens (light + dark), buttons, chips, media tile, haptics, clock
      ui/PulseStrengthRoot                                                      hub, active workout, summary layers and the in-progress bar
      ui/hub, ui/active, ui/sheets, ui/detail, ui/summary, ui/settings          the screens (ports of the SwiftUI views)
      services/                                                                 ongoing notification, notification buttons, rest alerts, settings
      health/                                                                   opt-in Health Connect writer and its rationale screen
    src/main/assets/ExerciseMedia/                                              50 form-demo frames (public domain, see below)
    src/test/                                                                   about 630 Robolectric tests: screens render and behave; screenshots go to app/build/screens
  store/                        Google Play listing text (en-US, de-DE), graphics, release notes
../.github/workflows/strength-android.yml                                       CI: tests, lint, release bundle, optional Play upload
../strength-privacy.html, ../strength-datenschutz.html                          the app's privacy policy (served by the website)
```

## Build and test

Requirements: JDK 17+ (CI uses 21) and the Android SDK with platform **37** and build-tools **36** (`ANDROID_HOME` set, licenses accepted).

```sh
cd android
./gradlew :core:test                         # the workout rules (JVM, ~45 s)
./gradlew :app:testDebugUnitTest             # screens, notifications, rest alerts (Robolectric; no emulator needed)
./gradlew :app:lintDebug                     # Android lint (errors fail the build)
./gradlew :app:assembleDebug                 # debug APK (installs next to a Play build: its id ends in .debug)
./gradlew :app:bundleRelease                 # release bundle with R8; unsigned without a keystore (see RELEASING.md)
```

## Verification status

What was run (in a Linux sandbox, no emulator, no device):

| Check | Result |
| --- | --- |
| `:core:test` | 566 tests, all pass (the Swift suite was ported; it found two real divergences from the Swift rules, both fixed) |
| `:app:testDebugUnitTest` | 631 tests, all pass: every screen and sheet, the notification and rest-alert services, and `FirstRunFlowTest` (an empty install through the real picker, a logged set, finish, summary and hub) |
| `:app:lintDebug`, `:app:lintRelease` | no issues (lint errors fail the build) |
| `:app:bundleRelease` + `:app:assembleRelease` | R8 + resource shrinking; a signed 3.2 MB APK and 6.3 MB bundle; `apksigner` and `jarsigner` verify the signature; the merged manifest asks for `POST_NOTIFICATIONS`, `POST_PROMOTED_NOTIFICATIONS` and Health Connect `WRITE_EXERCISE` only (no `INTERNET`) |
| CI (`strength-android`, `verify` job) | green on the pull request |

**Not verified:** anything that needs a real device: the notification buttons on the lock screen, rest alerts with the screen off,
Health Connect, backup and restore, the Play upload. The checklist for those is `RELEASING.md`, section 5.

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
| `pulse-strength://workout` URL scheme | the same deep link on `MainActivity` |
| Apple Watch app, heart rate, Watch sync | **not ported** (see below) |

### Deliberate differences

* **A real install starts empty.** The iOS standalone build seeds demo templates and history on first launch and ships invented
  "previous results" for the library exercises. The Android release does neither (`StrengthData.usesLibraryHistory = false`,
  `seedDemoData = false`): a personal record is only flagged against the user's own history, and "previous" columns fill from it.
  Demo data remains for previews and tests (`StrengthAppEnvironment.preview()`).
* **Muscle recovery is computed** from the finished workouts (`RecoveryModel`, a documented rule of thumb: 48 h after up to 6 sets,
  +4 h per extra set, at most 72 h) instead of the iOS demo constants.
* **No heart rate.** There is no Wear OS companion yet, so the heart-rate stat is hidden; the core keeps the heart-rate fields.
* **No network permission, no foreground service, no exact-alarm permission** (see `RELEASING.md`, "Known limitations").
* The app is English-only and kilograms-only, as the iOS app is.

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

`app/src/main/assets/ExerciseMedia` holds the same 25 exercises x 2 form-demo frames as the iOS app, from the
[Free Exercise DB](https://github.com/yuhonas/free-exercise-db) (Unlicense, public domain). The app shows "Demo photos: Free Exercise
DB (public domain)." in the form sheet and under Settings > About.
