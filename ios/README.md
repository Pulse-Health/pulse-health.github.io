# Pulse Strength for Apple platforms

The strength-workout feature of Pulse for **iPhone**, **Apple Watch**, the **Lock Screen** (Live Activity) and the
**Dynamic Island**. It implements the design "Pulse Gym & Strength" as real Swift: a strength hub with templates and
history, the active-workout screen (set table, keypad, rest timer, supersets, undo, PR detection, coach tip), the
workout summary, a Watch app that mirrors the workout and records heart rate, and a Live Activity that logs sets and
controls the rest timer from the Lock Screen.

The Pulse app repository is not part of this build, so the feature is a self-contained Swift package
(`PulseStrengthKit`) plus a small host Xcode project that runs it standalone. The integration points with the Pulse app
are listed under [Integrating with the Pulse app](#integrating-with-the-pulse-app).

> **Status in one paragraph.** The platform-neutral core is unit-tested on Linux and macOS (700 tests, 716 with the Combine
> stand-in). The Apple-only code was written without access to the Apple SDKs, and since then the GitHub Actions workflow
> `strength-ios` has compiled it with Xcode 16 for the iOS and watchOS simulators, run a 30-step UI flow through the real
> iPhone app, rendered the Lock Screen, Dynamic Island and Watch screens, and re-run the app in dark mode, at large text
> sizes and on an iPhone SE. Several rounds of adversarial review fixed what they found. What has **not** been tried is
> anything that needs real hardware (Live Activity buttons, Watch heart rate and WatchConnectivity, notifications):
> see [Verification status](#verification-status).

> **Repository note.** This directory lives in the `pulse-health.github.io` website repository, which GitHub Pages publishes from
> the repository root. The root `_config.yml` excludes `ios/` from that build, so these files are not served on the website.
> If the project later moves to its own repository, delete the `exclude` entry.

## Layout

```
ios/
  README.md                  this file
  ARCHITECTURE.md            build contract: models, reducer, presenter, services, Apple targets (read this next)
  project.yml                XcodeGen spec: iOS app, widget extension, Watch app, three visual-test targets, schemes
  Packages/PulseStrengthKit/ Swift package (swift-tools-version 5.9, iOS 17 / watchOS 10 / macOS 14)
    Sources/
      PulseStrengthCore/       Foundation only: models, reducer, presenter, controller, store, sync, exercise library
      PulseStrengthActivity/   iOS: ActivityAttributes + WorkoutCommandBus (linked by the app AND the widget extension)
      PulseStrengthIOS/        iOS: SwiftUI screens and sheets, Live Activity manager, notifications, HealthKit, Watch bridge
        Resources/ExerciseMedia/  25 exercises x 2 form-demo frames (JPEG)
      PulseStrengthWatchUI/    watchOS: SwiftUI screens, workout session, WatchConnectivity client
    Tests/PulseStrengthCoreTests/
  Apps/
    PulseStrength/           iOS host app: @main entry point, Info.plist, entitlements, assets
    PulseStrengthWidgets/    widget extension: @main WidgetBundle, Info.plist, entitlements
    PulseStrengthWatch/      watchOS app: @main entry point, Info.plist, entitlements, assets
    Shared/Intents/          App Intents behind the Live Activity buttons (compiled into the app AND the extension)
    Shared/LiveActivity/     Lock Screen and Dynamic Island views (compiled into the extension)
    PulseStrengthUITests/              UI test: walks the iPhone app in the simulator, one screenshot per step
    PulseStrengthLiveSnapshotTests/    test that draws the Lock Screen and Dynamic Island views into PNG files
    PulseStrengthWatchSnapshotTests/   test that draws the Watch pages into PNG files
.github/workflows/strength-ios.yml   (at the repository root) CI: Linux core tests + macOS Xcode builds + screenshots
```

Why the intents and the Live Activity views are not in the package: a `LiveActivityIntent` is referenced by the
extension but executed in the app's process, and Apple's documented pattern is to compile its source into both targets.
Intents inside a package would need `AppIntentsPackage` plumbing that only exists from iOS 17.4.

## Requirements

* **Xcode 16** (macOS 14.5 or later). The code is written to also build with Xcode 15.4, Swift 5 language mode.
* **A paid Apple Developer Program team to run on a real iPhone / Apple Watch.** The app uses HealthKit and time-sensitive
  notifications; Apple's free personal teams may not be able to provision those (not tried). The simulators need no account.
* iOS 17 / watchOS 10 or later on the simulator or the device. The Dynamic Island needs an iPhone 14 Pro or newer
  (or such a simulator); the Lock Screen presentation works on every iPhone with iOS 17.
* **XcodeGen is not needed to open or run the project**: `PulseStrength.xcodeproj` is generated from `project.yml` and
  committed. You only need XcodeGen 2.46.0 (`brew install xcodegen`) after changing `project.yml`.
* To run only the Core tests: any Swift 5.9+ toolchain on Linux or macOS (CI uses `swift:6.1` on Linux).

## Quick start in Xcode

1. Open **`ios/PulseStrength.xcodeproj`** (`open ios/PulseStrength.xcodeproj`). Xcode resolves the local package
   `Packages/PulseStrengthKit` by itself.
2. **Simulator**: pick the **PulseStrength** scheme and any iPhone simulator, press Run. No signing needed.
3. **Real iPhone**: open `Config/Signing.xcconfig` (it is in the Xcode navigator) and set `DEVELOPMENT_TEAM` to your 10-character
   Team ID (developer.apple.com > Account > Membership details). Change `PULSE_APP_BUNDLE_ID` to an id you own if
   `health.pulse.strength` is not yours (the widget gets `.widgets`, the Watch app `.watchkitapp`). To keep your values out of
   git, create `Config/Signing.local.xcconfig` with the same two lines instead; it is git-ignored. Alternatively pick the team in
   *Signing & Capabilities* for the three targets; Xcode then writes it into the project file.
4. On the iPhone enable *Settings > Privacy & Security > Developer Mode*, connect it, choose it as the run destination and press
   Run (first install: trust your developer profile in *Settings > General > VPN & Device Management*). Allow Health and
   Notifications when the app asks.
5. **Apple Watch**: with a paired Watch the Watch app installs together with the iPhone app (or from the iPhone's Watch app >
   Available Apps). To run it directly, choose the **PulseStrengthWatch** scheme and the Watch as destination. Enable Developer
   Mode on the Watch as well.

### Simulator notes

* The first launch seeds demo templates and history (see [Placeholders](#placeholders-to-replace)).
* Start a workout from the hub. To see the Live Activity, lock the simulator (Device > Lock, Cmd-L) while a workout runs;
  use an iPhone 14 Pro or newer simulator to see the Dynamic Island as well.
* For the Watch app, use a simulator pair (iPhone + Apple Watch, created in Xcode > Window > Devices and Simulators),
  run the **PulseStrengthWatch** scheme on the Watch simulator, then start a workout on the paired iPhone simulator.
  The simulator has no real heart-rate sensor; Watch heart rate needs a real Watch.

### Capabilities and signing

The iOS app and the Watch app declare **HealthKit**; the iOS app also declares **Time Sensitive Notifications**; Live Activities need
only the `NSSupportsLiveActivities` Info.plist key. With automatic signing Xcode registers these capabilities for your team. The app
uses **no App Group** (its data lives in Application Support; the Live Activity buttons run inside the app process).

### Regenerating the project (only after editing `project.yml`)

```sh
brew install xcodegen          # CI uses 2.46.0; the same version gives identical output
cd ios && xcodegen generate    # rewrites PulseStrength.xcodeproj; commit the result
```

The `apple` CI job regenerates the project and fails when the committed `PulseStrength.xcodeproj` differs.

### Command-line build without code signing (what CI does)

```sh
cd ios
xcodebuild -project PulseStrength.xcodeproj -scheme PulseStrength \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project PulseStrength.xcodeproj -scheme PulseStrengthWatch \
  -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Running the Core tests

```sh
cd ios/Packages/PulseStrengthKit
swift build && swift test                                   # Linux or macOS
swift test --scratch-path .build-shim -Xswiftc -DPULSE_COMBINE_SHIM   # Linux: also compiles StrengthStore and WorkoutController
```

`PulseStrengthCore` imports Foundation only, plus Combine under `#if canImport(Combine)`. On Linux there is no Combine,
so the second command defines `PULSE_COMBINE_SHIM`, which enables small stand-ins for `ObservableObject` / `@Published`
so the store and the controller are type-checked and tested there too. On Apple platforms the real Combine is used and
the flag has no effect. Every file of the iOS and watchOS targets is wrapped in `#if os(iOS)` / `#if os(watchOS)`, so on
Linux (and on macOS) those targets build as empty modules.

## Screenshots in CI

Nobody can run an iOS simulator on the machines this code was written on, so the `visual` job of the `strength-ios`
workflow runs the app and the views in the simulators on a macOS runner and uploads what it drew. It starts together with
the `apple` job (on every pull request and push that touches `ios/`, and on demand through **Run workflow**), needs nothing
from it, and does not replace it.

What it does, in this order: `xcodegen generate`; boots an iPhone simulator with a Dynamic Island (iPhone 16 Pro, else
15 Pro, else any iPhone) and runs two schemes on it; boots a watchOS simulator and runs the third. All three use the Debug
configuration, `CODE_SIGNING_ALLOWED=NO` and `-parallel-testing-enabled NO`.

| Scheme (target) | What it produces | Files in the artifact |
| --- | --- | --- |
| `PulseStrengthLiveSnapshots` (`PulseStrengthLiveSnapshotTests`, no host app) | Lock Screen card, Dynamic Island compact / minimal / expanded in 12 workout states, plus contact sheets | `live-NN-*.png` (about 57), `live-measurements.txt` (sizes and limit violations) |
| `PulseStrengthUITests` (`PulseStrengthUITests`) | One long walk through the iPhone app in demo mode (`-PulseUITest`): hub, active workout, keypad, sheets, rest timer, undo, finish, summary, exercise library | `ui-NN-*.png` (about 70), `ui-flow-log.txt` (OK / FAILED / SKIPPED per step) |
| `PulseStrengthWatchSnapshots` (`PulseStrengthWatchSnapshotTests`, no host app) | The Watch pages at 45 mm and at 40 / 41 / 44 / 49 mm, plus experimental root-view shots | `watch-NN-*.png` (44), `watch-manifest.txt` (a `BLANK` line marks an image that came out empty) |

The tests write their files to the directory in `SCREENSHOT_DIR`; the workflow passes it as `TEST_RUNNER_SCREENSHOT_DIR`
(xcodebuild forwards `TEST_RUNNER_*` variables to the test process without the prefix).

**Artifacts** (Actions run page, section "Artifacts"):

* **`strength-screens`** (kept 14 days): all PNGs and text files above, `digest.txt`, `logs/` (the xcodebuild logs) and
  `results/` (summaries of the `.xcresult` bundles, where Xcode 16's `xcresulttool` can read them).
* **`strength-xcresults`** (kept 3 days): the zipped `.xcresult` bundles (`ui`, `live`, `watch`). They hold every test
  attachment and are only needed when the PNGs and logs do not explain a failure.

**Reading the result.** Every test step is `continue-on-error`, so the PNGs are collected and uploaded whatever happened, and
the job fails only when no PNG exists at all (a failed assertion or one missing element does not fail it). Look at the end of
the `Gate` step in the job log: it prints a digest with the verdict and the unique `error:` / `XCTAssert` / `failed` lines of
each test log, the number of PNGs per suite and their file names (also saved as `digest.txt`). A suite with no PNG gets a
warning annotation; the log of its step then usually shows a compile error of the test code. The UI flow keeps going after a
failed step, so open `ui-flow-log.txt` first: it names the steps that failed, with the screenshot taken at that point.

* **`matrix` job:** a short second tour (`StrengthTourTests`, 14 screenshots, about 3 minutes) on four simulators in parallel: `dark` (dark mode), `xxl` (accessibility-extra-large text), `se` (iPhone SE 3rd generation, 375 x 667 pt) and `ios17` (oldest installed iOS 17+ runtime). A simulator the runner lacks prints `SKIPPED: <reason>`; the entry still succeeds.
* **Artifact `strength-matrix-<name>`** (14 days): `tour-<name>-NN-*.png`, `tour-<name>-layout.txt` (frames of header, navigator, card and rest dock, `pageScrolls`, `LAYOUT VIOLATION` lines), `tour-<name>-flow-log.txt`, `simulator-settings.txt`, `digest.txt` (also printed at the end of the job log).
* The tour belongs to the `PulseStrengthUITests` scheme, so `visual` runs it once more with the defaults (`tour-default-*` in `strength-screens`).

**Run it locally** (macOS, Xcode 16; the UI flow needs the software keyboard, so disconnect the hardware keyboard in the
Simulator, I/O > Keyboard):

```sh
cd ios
mkdir -p /tmp/pulse-screens
TEST_RUNNER_SCREENSHOT_DIR=/tmp/pulse-screens xcodebuild test -project PulseStrength.xcodeproj \
  -scheme PulseStrengthLiveSnapshots -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO
# -scheme PulseStrengthUITests: same destination; -scheme PulseStrengthWatchSnapshots: -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)'
```

**Limits.** The snapshot tests draw the views with `ImageRenderer`: the Lock Screen material, the island animation, scrolling
containers and the live timers are not reproduced exactly (the Live Activity suite also draws the production timer views once,
as `live-49` to `live-53`, to show what the renderer makes of them). The Watch images are plain rectangles of the screen size
without status bar or rounded corners. None of this code had been compiled or run when the job was added; expect a fix or two
after the first run.

## Architecture in ten lines

1. All workout logic is a pure reducer in Core: `WorkoutState` + `WorkoutAction` -> `WorkoutReducer.reduce(_:_:now:)`.
2. `WorkoutController` owns the state, persists it and notifies side effects. The phone is the `authority`, the Watch a `mirror`.
3. `WorkoutPresenter` turns state into a display-ready `ActiveWorkoutPresentation`; views only render it and dispatch actions.
4. `SnapshotBuilder` produces the compact `WorkoutSnapshot` that drives the Live Activity and the Watch.
5. Platform services are `WorkoutSideEffect`s: Live Activity manager, rest notification, HealthKit writer, Watch bridge (iOS);
   WatchConnectivity client and `HKWorkoutSession` (watchOS). `PulseServices` registers the iOS set.
6. Data lives as JSON files in the app's Application Support folder (`FileStrengthPersistence`; an App Group container is used when the entitlement is added); `StrengthStore` holds templates, history,
   custom exercises and personal bests.
7. Live Activity buttons are App Intents compiled into app and extension; they call `WorkoutCommandBus`, whose handler the
   app installs when `StrengthAppEnvironment` starts (the app waits up to 3 s for a background launch).
8. Phone and Watch exchange `SyncEnvelope`s / `RemoteCommand`s over WatchConnectivity. The Watch applies its taps at once and the
   phone acknowledges every command in its next envelope (duplicates are dropped by command id, also across a phone relaunch);
   the Watch shows the phone's state with its unacknowledged taps on top, orders late envelopes and expires a lost tap on its
   own timer ("Sync protocol" in `ARCHITECTURE.md` 3.4).
9. Clock-driven UI uses `TimelineView`; the Live Activity uses `Text(timerInterval:)` and a stale date, because a widget cannot tick.
10. Contracts, file by file: [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Placeholders to replace

Everything below is a stand-in until the feature lives inside the Pulse app.

| Placeholder | Value | Where to change it |
| --- | --- | --- |
| Bundle ids | `health.pulse.strength`, `.widgets`, `.watchkitapp` | `PULSE_APP_BUNDLE_ID` in `Config/Signing.xcconfig` (the Watch `Info.plist` reads it for `WKCompanionAppBundleIdentifier`) |
| Notification id | `health.pulse.strength.rest` | `StrengthConfig.restNotificationID` (Core); only a label, it does not have to match the bundle id |
| App Group | `group.health.pulse.strength` (not used by this standalone build: no entitlement) | `StrengthConfig.appGroupID` (Core); when sharing data with the Pulse app add the App Groups capability to the app (and the widget) and use the same id |
| URL scheme | `pulse-strength://workout` | `StrengthConfig.urlScheme` / `workoutURL` and `CFBundleURLTypes` in `Apps/PulseStrength/Info.plist` |
| Team | empty | `DEVELOPMENT_TEAM` in `Config/Signing.xcconfig` (or `Config/Signing.local.xcconfig`) |
| Names, version | "Pulse Strength", 1.0.0 (1) | `CFBundleDisplayName` in the three `Info.plist` files, `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` |
| Permission texts | Health usage descriptions | `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` in the iOS and Watch `Info.plist` files |
| App icon | generated green dumbbell | `Apps/PulseStrength/Assets.xcassets/AppIcon.appiconset/AppIcon.png` and the same in `Apps/PulseStrengthWatch` (1024 x 1024, opaque) |
| Accent colour | green `#1B8448` | `AccentColor.colorset` in both asset catalogs |
| Demo data | templates and history seeded on first launch | `StrengthAppEnvironment.live(seedDemoData:)`; the host app uses the default `true` through `StrengthAppEnvironment.shared` |
| Muscle recovery | fixed demo percentages | `DemoRecovery.provider`, see below |

## Integrating with the Pulse app

The seams are plain protocols and closures:

* **Recovery data.** `RecoveryProvider` is `@Sendable (MuscleGroup) -> Int` (percent recovered, 0 to 100). Pass the Pulse
  app's own muscle-recovery model to `WorkoutController(store:persistence:role:recovery:clock:)`, or assign
  `controller.recovery` later. The default, `DemoRecovery.provider`, returns fixed demo numbers.
* **Storage.** `FileStrengthPersistence` is a small final class with one load/save pair per file (active workout,
  templates, history, custom exercises, personal bests). Point it at a directory of the Pulse app
  (`FileStrengthPersistence(directory:)`), or replace it, and `StrengthStore`, with a type backed by the Pulse database:
  the controller and the screens only use the store's published properties and `record`, `saveTemplate`,
  `addCustomExercise`, `history(for:now:)`. There is no persistence protocol yet; introducing one is the first change to
  make if the storage engine changes.
* **Side effects.** Implement `WorkoutSideEffect` (three `@MainActor` callbacks: `workoutStarted`, `workoutChanged`,
  `workoutEnded`) and register it with `controller.addEffect(_:)`: Pulse analytics, syncing finished workouts to the
  Pulse backend, an existing HealthKit pipeline. `PulseServices(controller:)` is a convenience that registers the four
  built-in effects; construct your own set instead if the Pulse app already owns notifications or HealthKit.
* **Media.** `ExerciseMediaView(mediaKey:)` shows the two frames `<mediaKey>-a.jpg` / `-b.jpg` from the package bundle and a
  placeholder when they are missing. Replace its internals (one file) to stream licensed GIFs or video; `Exercise.mediaKey`
  and the 25 built-in keys stay the contract.
* **UI entry point.** `PulseStrengthRootView(environment:)` is one view with its own `NavigationStack`; embed it, or use
  `StrengthHubView`, `ActiveWorkoutView` and the sheets individually. It handles `pulse-strength://workout` through `onOpenURL`.
* **Live Activity.** Add `Apps/Shared/LiveActivity` and `Apps/Shared/Intents` as sources of the Pulse widget extension,
  list `WorkoutLiveActivity()` in its `WidgetBundle`, compile `Apps/Shared/Intents` into the Pulse app target as well, and touch
  `StrengthAppEnvironment.shared` during app launch (see `PulseStrengthApp.init()`), so a button press that launches the app in the
  background finds the command-bus handler installed.
* **Watch.** Link `PulseStrengthWatchUI` into the Pulse Watch app, use `WatchRootView(environment: WatchEnvironment.shared)` and
  `WatchAppDelegate` (`@WKApplicationDelegateAdaptor`), as `Apps/PulseStrengthWatch` does.

Note that this repository also serves the pulse-health.github.io site. If GitHub Pages publishes from the branch root,
the files under `ios/` are served too; move the folder to its own repository before using it for a product.

## Capabilities needed

| Target | Capability / setting |
| --- | --- |
| iOS app | HealthKit (reads heart rate and active energy, writes workouts); Live Activities (`NSSupportsLiveActivities`, `NSSupportsLiveActivitiesFrequentUpdates`, no push token: the app updates the activity locally); Time Sensitive Notifications (the rest alert); the notification permission is requested at runtime by `PulseServices.requestPermissions()`; URL type `pulse-strength`. No background mode is declared because none is needed. |
| Widget extension | No capability; `NSExtension` point `com.apple.widgetkit-extension`. `NSSupportsLiveActivities` is read from the host app. |
| Watch app | HealthKit; Background Modes: Workout processing (`WKBackgroundModes` = `workout-processing`); `WKApplication`, `WKCompanionAppBundleIdentifier`, `WKRunsIndependentlyOfCompanionApp` = false (the Watch needs the phone). |

## Exercise photos

The form-demo frames in `Packages/PulseStrengthKit/Sources/PulseStrengthIOS/Resources/ExerciseMedia` come from the
[Free Exercise DB](https://github.com/yuhonas/free-exercise-db), released under the Unlicense (public domain): 25
exercises, two frames each. The app shows the line "Demo photos: Free Exercise DB (public domain)." in the form sheets.
They are demo material: the real Pulse app may prefer licensed GIFs or video with a consistent look, which the media seam
above allows without touching the rest of the feature.

## Verification status

State at the last commit of this branch; the numbers come from the `strength-ios` workflow
(<https://github.com/Pulse-Health/pulse-health.github.io/actions/workflows/strength-ios.yml>), whose jobs were all green on it.

**Verified**

* **Core (`PulseStrengthCore`)**: 700 unit tests (716 with the Combine stand-in) pass on Linux (job `core-linux`) and on macOS (job `apple`):
  reducer, presenter, snapshot and summary builders, persistence, the phone <-> Watch sync protocol (acknowledgements, optimistic
  replay, delivery fuzzing with dropped, duplicated and reordered messages), exercise library and sample data.
* **Compiles**: `xcodegen generate`, then `xcodebuild` of the iOS app (with the widget extension and the embedded Watch app) and of the
  Watch scheme for the simulators, without code signing (job `apple`). Xcode 16, deployment targets iOS 17.0 / watchOS 10.0, Swift 5 mode.
* **Runs in a simulator** (job `visual`, artifact `strength-screens`): a 30-step XCUITest flow through the real app (start a workout, log
  sets, keypad, set detail, rest settings, options, form info, exercise list, picker with search and multi-select, create exercise,
  navigator, superset, undo, rest dock, pause/resume, finish, update-template alert, summary, history, exercise library and detail, empty
  workout, discard) with 55 screenshots; snapshot tests that render the Lock Screen and Dynamic Island (compact, minimal, expanded) for
  every phase and the Watch screens on five case sizes. The screenshots were compared with the design boards.
* **Dark mode, large text, small phone** (job `matrix`): the same tour on an iPhone 16 Pro in dark mode, at accessibility-extra-large text,
  and on an iPhone SE (3rd generation, 375 x 667 pt). On the SE the workout screen fits without page scrolling (only the set list scrolls
  inside the card) and nothing leaves the screen. Text follows Dynamic Type on every screen; the dense workout screen and the keypad are
  capped at `xxxLarge` so they keep fitting.
* **Reviews**: adversarial multi-lens reviews (API cross-checks, SwiftUI / ActivityKit / HealthKit / WatchConnectivity correctness,
  concurrency, end-to-end sync traces, design parity, project and CI) each followed by an independent skeptic that tried to refute
  every finding; the confirmed ones were fixed with regression tests where the logic is in Core. The Watch Health session code was
  also run against a fake HealthKit in a scratch harness.

**Not verified** (be careful before shipping)

* Anything on real hardware, see below. The simulator cannot show Live Activity buttons, Dynamic Island on a device, WatchConnectivity,
  Watch heart rate, HealthKit writes, or the rest notification. The Lock Screen and Dynamic Island screens are the SwiftUI views rendered
  directly (the same code the widget uses), not the system's presentation.
* The oldest runtime is not covered: the CI runner only offers iOS 18.5 and iOS 26.2 simulators, so the iOS 17.0 deployment target is
  compile-checked (the build enforces API availability) but has never been run on an iOS 17 runtime.
* The Watch app was rendered (snapshot tests) but not driven in a watchOS simulator; its Health session logic is covered by unit tests of
  the Core rules and a stub harness, not by a real session.
* VoiceOver, Reduce Motion and the landscape / iPad layouts were not exercised. Bundle ids, team, App Group and the exercise photos are
  placeholders / public-domain stand-ins, see [Placeholders to replace](#placeholders-to-replace).

### Must be tested on real hardware

CI and the simulators cannot show any of these, and none of them has been tried:

* **Live Activity buttons**: "Log set", the -/+ steppers, -15 s / +15 s / Skip from the Lock Screen and the Dynamic Island, including
  the case where the app was suspended or terminated and the intent launches it in the background (command-bus hand-over within 3 s,
  state restored from disk), the "Go" state after the stale date, and the paused presentation.
* **Watch heart rate**: the `HKWorkoutSession` / `HKLiveWorkoutBuilder` on a real Watch, the first samples after the phone launches the
  Watch app with `startWatchApp(with:)`, the throttled stream to the phone (the header and the Live Activity), the Health permission flow,
  and the workout saved by the Watch when `usedWatch` is true.
* **Rest notification**: the time-sensitive local notification at the end of the rest with the app in the background and the phone
  locked, its cancellation on skip, pause, finish and discard, the haptic when the rest ends in the foreground, and the Watch haptic.
* Also worth a pass on a device: WatchConnectivity reachability and the "Watch not connected" / "Health access denied" banners,
  a workout written to Health by the phone when no Watch is used, Dynamic Island layouts on a 14 Pro or newer,
  VoiceOver in the active-workout screen, and Reduce Motion (form demos, heart beat).
