# Pulse Strength for Apple platforms

The strength-workout feature of Pulse for **iPhone**, **Apple Watch**, the **Lock Screen** (Live Activity) and the
**Dynamic Island**. It implements the design "Pulse Gym & Strength" as real Swift: a strength hub with templates and
history, the active-workout screen (set table, keypad, rest timer, supersets, undo, PR detection, coach tip), the
workout summary, a Watch app that mirrors the workout and records heart rate, and a Live Activity that logs sets and
controls the rest timer from the Lock Screen.

The Pulse app repository is not part of this build, so the feature is a self-contained Swift package
(`PulseStrengthKit`) plus a small host Xcode project that runs it standalone. The integration points with the Pulse app
are listed under [Integrating with the Pulse app](#integrating-with-the-pulse-app).

> **Status in one paragraph.** The platform-neutral core is unit-tested on Linux and macOS (1172 tests on Linux, 1174 on macOS).
> The Apple-only code was written without access to the Apple SDKs, and since then the GitHub Actions workflow `strength-ios`
> has compiled it with Xcode 16 and Xcode 26 (the iPhone app with its widget extension, the Watch app with its widget
> extension), run a 30-step UI flow through the real iPhone app, rendered the Lock Screen, Dynamic Island, Watch screens and
> every widget (363 images), and re-run the app in dark mode, at large text sizes and on an iPhone SE. Several rounds of
> adversarial review fixed what they found. What has **not** been tried is anything that needs real hardware or the system's
> own widget surfaces (Live Activity buttons, widget gallery and configuration, Control Center, StandBy, Watch heart rate and
> WatchConnectivity, notifications): see [Verification status](#verification-status).

> **Repository note.** This directory lives in the `pulse-health.github.io` website repository, which GitHub Pages publishes from
> the repository root. The root `_config.yml` excludes `ios/` from that build, so these files are not served on the website.
> If the project later moves to its own repository, delete the `exclude` entry.

## Layout

```
ios/
  README.md                  this file
  ARCHITECTURE.md            build contract: models, reducer, presenter, services, Apple targets (read this next)
  project.yml                XcodeGen spec: iOS app, widget extension, Watch app, three visual-test targets, schemes
  PulseStrength.xcodeproj/   generated from project.yml and COMMITTED: open this in Xcode (run xcodegen only after editing project.yml)
  Config/Signing.xcconfig    DEVELOPMENT_TEAM and PULSE_APP_BUNDLE_ID (optional git-ignored Signing.local.xcconfig overrides them)
  Packages/PulseStrengthKit/ Swift package (swift-tools-version 5.9, iOS 17 / watchOS 10 / macOS 14)
    Sources/
      PulseStrengthCore/       Foundation only: models, reducer, presenter, controller, store, sync, exercise library
        Widgets/               the widget data contract (WidgetSnapshot, generated), its builder, the App Group snapshot store and command inbox, deep links
      PulseStrengthActivity/   iOS: ActivityAttributes + WorkoutCommandBus (linked by the app AND the widget extension)
      PulseStrengthIOS/        iOS: SwiftUI screens and sheets, Live Activity manager, notifications, HealthKit, Watch bridge
        Resources/ExerciseMedia/  25 exercises x 2 form-demo frames (JPEG)
      PulseStrengthWatchUI/    watchOS: SwiftUI screens, workout session, WatchConnectivity client
    Tests/PulseStrengthCoreTests/
  Apps/
    PulseStrength/           iOS host app: @main entry point, Info.plist, entitlements, assets
    PulseStrengthWidgets/    widget extension: @main WidgetBundle (Live Activity, Home Screen / StandBy, Lock Screen, extras, controls), Info.plist
    PulseStrengthWatchWidgets/  watchOS widget extension: @main WidgetBundle of the Apple Watch complications and Smart Stack cards
    PulseStrengthWatch/      watchOS app: @main entry point, Info.plist, entitlements, assets
    Shared/Intents/          App Intents behind the Live Activity buttons (compiled into the app AND the extension)
    Shared/LiveActivity/     Lock Screen and Dynamic Island views, the extra Live Activity states, planned-session countdown, bench mode (compiled into the extension)
    Shared/Widgets/          Common (theme, text rules), Home (Home Screen, StandBy, iPad), Lock (Lock Screen accessories), Extras, Watch (compiled into the extensions)
    Shared/Controls/         Control Center and Lock Screen controls (compiled into the widget extension)
    PulseStrengthUITests/              UI test: walks the iPhone app in the simulator, one screenshot per step
    PulseStrengthLiveSnapshotTests/    test that draws the Lock Screen and Dynamic Island views into PNG files
    PulseStrengthWatchSnapshotTests/   test that draws the Watch pages into PNG files
    PulseStrengthWidgetSnapshotTests/  test that draws the Home Screen, StandBy, Lock Screen and extra widgets into PNG files
    PulseStrengthWatchWidgetSnapshotTests/  test that draws the Apple Watch widgets into PNG files
.github/workflows/strength-ios.yml   (at the repository root) CI: Linux core tests + macOS Xcode builds + screenshots
```

Why the intents and the Live Activity views are not in the package: a `LiveActivityIntent` is referenced by the
extension but executed in the app's process, and Apple's documented pattern is to compile its source into both targets.
Intents inside a package would need `AppIntentsPackage` plumbing that only exists from iOS 17.4.

## Requirements

* **Xcode 16 or newer**, on a macOS version that Xcode supports. Use an Xcode that knows your devices' OS: an iPhone / Apple Watch on
  iOS 26 / watchOS 26 needs Xcode 26. CI builds the committed project with Xcode 16.4 and with Xcode 26.6 (simulators; Xcode 26 also for
  the device SDKs without signing); newer Xcode versions have not been tried. Swift 5 language mode; the code is written to also build
  with Xcode 15.4.
* **A paid Apple Developer Program team to run on a real iPhone / Apple Watch.** The app uses HealthKit and time-sensitive
  notifications; Apple's free personal teams may not be able to provision those (not tried). The simulators need no account.
* iOS 17 / watchOS 10 or later on the simulator or the device. The Dynamic Island needs an iPhone 14 Pro or newer
  (or such a simulator); the Lock Screen presentation works on every iPhone with iOS 17.
* **XcodeGen is not needed to open or run the project**: `PulseStrength.xcodeproj` is generated from `project.yml` and
  committed. You only need XcodeGen after changing `project.yml` (see "Regenerating the project").
* To run only the Core tests: any Swift 5.9+ toolchain on Linux or macOS (CI uses `swift:6.1` on Linux).

## Quick start in Xcode

1. Open **`ios/PulseStrength.xcodeproj`** (`open ios/PulseStrength.xcodeproj`). Xcode resolves the local package
   `Packages/PulseStrengthKit` by itself.
2. **Simulator**: pick the **PulseStrength** scheme and any iPhone simulator, press Run. No signing needed.
3. **Real iPhone**: set your team and, if `health.pulse.strength` is not yours, your own bundle id. The safe way that keeps your values
   out of git: create the git-ignored file `ios/Config/Signing.local.xcconfig` (in Terminal, not through Xcode; it is not shown in the
   navigator) with
   ```sh
   printf 'DEVELOPMENT_TEAM = ABCDE12345\nPULSE_APP_BUNDLE_ID = com.yourcompany.pulsestrength\n' > ios/Config/Signing.local.xcconfig
   ```
   (`DEVELOPMENT_TEAM` is your 10-character Team ID: developer.apple.com > Account > Membership details; the widget gets the id with
   `.widgets`, the Watch app with `.watchkitapp`). You can also edit the tracked `Config/Signing.xcconfig` (it is in the Xcode
   navigator), but then the change shows up in `git status`. Do not type a bundle id into Xcode's *Bundle Identifier* field (it would
   override the derived ids of one target only), and prefer not to pick the team in *Signing & Capabilities*: Xcode would write it into
   `PulseStrength.xcodeproj/project.pbxproj` for that target only, and a committed project that differs from `project.yml` fails the CI
   check (`git checkout -- ios/PulseStrength.xcodeproj` undoes it).
4. Connect the iPhone by cable, unlock it, tap *Trust*, and choose it as the run destination (the first connection can take a minute
   while Xcode prepares the device). Then enable *Settings > Privacy & Security > Developer Mode* on the iPhone (the entry only
   appears after the iPhone has been connected to Xcode once; the iPhone restarts and asks you to confirm). Press Run. First install:
   trust your developer profile in *Settings > General > VPN & Device Management*. Allow Health and Notifications when the app asks.
5. **Apple Watch**: with a paired Watch the Watch app installs together with the iPhone app (or from the iPhone's Watch app >
   Available Apps). Enable Developer Mode on the Watch too (Watch: *Settings > Privacy & Security > Developer Mode*, or the iPhone's Watch
   app > *Privacy & Security > Developer Mode*); it only appears after the paired iPhone is connected to Xcode with Developer Mode on. To
   run the Watch app directly, choose the **PulseStrengthWatch** scheme and the Watch as destination.

### Simulator notes

* A fresh install starts empty (no demo workouts, no invented records). Create a template or start an empty workout from the hub; the UI-test mode `-PulseUITest` and the SwiftUI previews use demo data (see [Placeholders](#placeholders-to-replace)).
* Start a workout from the hub. To see the Live Activity, lock the simulator (Device > Lock, Cmd-L) while a workout runs;
  use an iPhone 14 Pro or newer simulator to see the Dynamic Island as well.
* For the Watch app, use a simulator pair (iPhone + Apple Watch, created in Xcode > Window > Devices and Simulators, Shift-Cmd-2),
  run the **PulseStrengthWatch** scheme on the Watch simulator, then start a workout on the paired iPhone simulator.
  The simulator has no real heart-rate sensor; Watch heart rate needs a real Watch.

### Capabilities and signing

The iOS app and the Watch app declare **HealthKit**; the iOS app also declares **Time Sensitive Notifications**; Live Activities need
only the `NSSupportsLiveActivities` Info.plist key. With automatic signing Xcode registers these capabilities for your team. The app
uses **no App Group** (its data lives in Application Support; the Live Activity buttons run inside the app process).

### Regenerating the project (only after editing `project.yml`)

```sh
brew install xcodegen          # then check `xcodegen --version`: CI pins 2.46.0; another version may write a different project file
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
| `PulseStrengthUITests` (`PulseStrengthUITests`) | One long walk through the iPhone app in demo mode (`-PulseUITest`): hub, active workout, keypad, sheets, rest timer, undo, finish, summary, exercise library | `ui-NN-*.png` (55), `ui-flow-log.txt` (OK / FAILED / SKIPPED per step) |
| `PulseStrengthWatchSnapshots` (`PulseStrengthWatchSnapshotTests`, no host app) | The Watch pages at 45 mm and at 40 / 41 / 44 / 49 mm, plus experimental root-view shots | `watch-NN-*.png` (44), `watch-manifest.txt` (a `BLANK` line marks an image that came out empty) |

The tests write their files to the directory in `SCREENSHOT_DIR`; the workflow passes it as `TEST_RUNNER_SCREENSHOT_DIR`
(xcodebuild forwards `TEST_RUNNER_*` variables to the test process without the prefix).

**Artifacts** (Actions run page, section "Artifacts"):

* **`strength-screens`** (kept 14 days): all PNGs and text files above, `digest.txt`, `logs/` (the xcodebuild logs) and
  `results/` (summaries of the `.xcresult` bundles, where Xcode 16's `xcresulttool` can read them).
* **`generated-xcodeproj`** (kept 7 days, job `apple`): the freshly generated `PulseStrength.xcodeproj` and `project.yml`, to update the committed
  project without installing XcodeGen. The `apple` job also uploads `strength-ios-logs` (14 days, the xcodebuild / swift test logs).
* **`strength-xcresults`** (kept 3 days): the zipped `.xcresult` bundles (`ui`, `live`, `watch`). They hold every test
  attachment and are only needed when the PNGs and logs do not explain a failure.

**Reading the result.** Every test step is `continue-on-error`, so the PNGs are collected and uploaded whatever happened, and
the job fails only when no PNG exists at all (a failed assertion or one missing element does not fail it). Look at the end of
the `Gate` step in the job log: it prints a digest with the verdict and the unique `error:` / `XCTAssert` / `failed` lines of
each test log, the number of PNGs per suite and their file names (also saved as `digest.txt`). A suite with no PNG gets a
warning annotation; the log of its step then usually shows a compile error of the test code. The UI flow keeps going after a
failed step, so open `ui-flow-log.txt` first: it names the steps that failed, with the screenshot taken at that point.

* **`matrix` job:** a short second tour (`StrengthTourTests`, 21 screenshots, about 4 minutes; 15 to 21 are the pages of the walkthrough) on four simulators in parallel: `dark` (dark mode), `xxl` (accessibility-extra-large text), `se` (iPhone SE 3rd generation, 375 x 667 pt) and `ios17` (oldest installed iOS 17+ runtime). A simulator the runner lacks prints `SKIPPED: <reason>`; the entry still succeeds.
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

## Widgets, controls and live surfaces

Besides the Live Activity, the package feeds the rest of the glanceable surfaces of the design "Pulse Strength Widget Ideas": Home Screen,
StandBy and iPad widgets, Lock Screen accessories, extra "wilder idea" widgets, Control Center and Lock Screen controls, the Action button, the
further Live Activity states (record flash, superset round, plate math, coach tip, finish card, planned-session countdown, bench mode) and the
Apple Watch complications and Smart Stack cards. Every design has a stable catalogue id (`HS-01` ... `WI-11`). The catalogue, the exact rule behind
every number and the platform mapping are in [`../widgets/SPEC.md`](../widgets/SPEC.md); [`../widgets/README.md`](../widgets/README.md) is the map
of where each one lives on iOS and Android, and [`ARCHITECTURE.md` 5.7](ARCHITECTURE.md) has the contracts.

* **One data contract.** `PulseStrengthCore/Widgets/WidgetSnapshot.generated.swift` (generated from `../widgets/tools/schema.py`, which also writes the Kotlin
  twin for Android) is the only thing a surface reads. `WidgetSnapshotBuilder` turns the strength data into it; `WidgetPublisher` (iOS app) rebuilds it after
  every change, writes it into the App Group (`WidgetSnapshotStore`), reloads every widget timeline and control, and `WatchWidgetSnapshotSender` hands the Watch
  variant to the Watch over WatchConnectivity.
* **Commands go the other way.** Buttons in widgets, controls and Live Activities are App Intents. The ones that change the workout (log set, skip rest, pause,
  nudge, finish a rest, apply the coach tip) are `LiveActivityIntent`s: the system runs them in the app's process, which applies them through
  `WidgetIntentDispatch` and `WorkoutCommandBus`. Should the system run one inside the extension, the command waits in the App Group inbox
  (`WidgetCommandInbox`) and a Darwin notification wakes the app (`WidgetCommandDrain`). The ones that need the app on screen set `openAppWhenRun` and
  leave a `pulse-strength://` link, which `PulseStrengthRootView` handles through `StrengthDeepLink` (`workout`, `start-next`, `start?template=`,
  `start-empty?name=`, `exercise/<id>`, `hub`, `plates`, `weight`).
* **Targets.** `PulseStrengthWidgets` composes `LiveActivityBundle`, `HomeWidgetBundle`, `LockWidgetBundle`, `ExtrasWidgetBundle` and `ControlsBundle`;
  `PulseStrengthWatchWidgets`, embedded in the Watch app, composes the Watch bundles. The Action-button intent and the App Shortcuts are in the app target only
  (`ForegroundContinuableIntent` does not exist in app extensions).
* **App Group.** `group.<PULSE_APP_BUNDLE_ID>` is now declared by all four targets (app, widget extension, Watch app, Watch widget extension) and carries the
  snapshot, the command inbox and the shared data. Enable the App Groups capability for that id in your developer account before running on a device; the CI
  builds do not sign and need nothing. Without the container the app falls back to its own folder, and the widgets, which cannot read it, show their empty states.
* **In the app.** The hub shows a weekly-goal stepper (1 to 7: the goal of the goal widgets and of the "Sessions" figure), a template's toolbar has
  "Plan a session" (a countdown on the Lock Screen and in the Dynamic Island before the start, a notification at the start); `LiveActivityManager` flashes a
  new record on the Live Activity for four seconds and turns the finished workout into the finish card.

What the widgets assume: weights are in kilograms (the unit setting of the Pulse app is not handled), and the Watch widgets' "Start" opens the Watch app
(a start request from the Watch to the phone does not exist yet). The training-block widget for iPad (`SB-03`) is only offered once the app supports iPad.

## Placeholders to replace

Everything below is a stand-in until the feature lives inside the Pulse app.

| Placeholder | Value | Where to change it |
| --- | --- | --- |
| Bundle ids | `health.pulse.strength`, `.widgets`, `.watchkitapp` | `PULSE_APP_BUNDLE_ID` in `Config/Signing.xcconfig` (the Watch `Info.plist` reads it for `WKCompanionAppBundleIdentifier`) |
| Notification id | `health.pulse.strength.rest` | `StrengthConfig.restNotificationID` (Core); only a label, it does not have to match the bundle id |
| App Group | `group.health.pulse.strength` (`group.$(PULSE_APP_BUNDLE_ID)` in the four entitlements files) | `StrengthConfig.appGroupID` (Core) and the `*.entitlements` of the app, the widget extension, the Watch app and the Watch widget extension; enable the App Groups capability for it in your developer account |
| Weigh-in notification ids | `health.pulse.strength.weight.0` ... `.2` (category `health.pulse.strength.weight.category`) | `StrengthConfig.weightReminderIDPrefix` / `weightReminderCategoryID` (Core); only labels |
| URL scheme | `pulse-strength://workout`, `pulse-strength://weight` | `StrengthConfig.urlScheme` / `workoutURL` / `weightURL` and `CFBundleURLTypes` in `Apps/PulseStrength/Info.plist` |
| Team | empty | `DEVELOPMENT_TEAM` in `Config/Signing.xcconfig` (or `Config/Signing.local.xcconfig`) |
| Names, version | "Pulse Strength", 1.0.0 (1) | `CFBundleDisplayName` in the three `Info.plist` files, `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` |
| Permission texts | Health usage descriptions | `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` in the iOS and Watch `Info.plist` files |
| App icon | generated green dumbbell | `Apps/PulseStrength/Assets.xcassets/AppIcon.appiconset/AppIcon.png` and the same in `Apps/PulseStrengthWatch` (1024 x 1024, opaque) |
| Accent colour | green: `PulseTheme.green` (`#187A42` light, `#30D158` dark) tints the app's own controls; the system fallback tint `#1B8448` is `AccentColor.colorset` in both asset catalogs | `PulseTheme.swift`, `AccentColor.colorset` |
| Demo data | demo templates, five invented workouts and personal bests, used by previews and the UI tests only | `StrengthAppEnvironment.preview(withActiveWorkout:)` seeds it; `StrengthAppEnvironment.live(seedDemoData:)` defaults to `false`, so the running app starts empty |
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
* **Walkthrough after onboarding.** Call `environment.showWalkthroughAfterOnboarding()` where the Pulse app's onboarding ends: it opens the
  tour (`StrengthWalkthroughView`, presented by `PulseStrengthRootView`) the first time and never again by itself, so calling it on every
  launch is fine. It needs no extra wiring; the seen-flag is one integer in `UserDefaults` (`WalkthroughMemory`). See [Walkthrough](#walkthrough-after-onboarding).
* **Live Activity.** Add `Apps/Shared/LiveActivity` and `Apps/Shared/Intents` as sources of the Pulse widget extension,
  list `WorkoutLiveActivity()` in its `WidgetBundle`, compile `Apps/Shared/Intents` into the Pulse app target as well, and touch
  `StrengthAppEnvironment.shared` during app launch (see `PulseStrengthApp.init()`), so a button press that launches the app in the
  background finds the command-bus handler installed.
* **Watch.** Link `PulseStrengthWatchUI` into the Pulse Watch app, use `WatchRootView(environment: WatchEnvironment.shared)` and
  `WatchAppDelegate` (`@WKApplicationDelegateAdaptor`), as `Apps/PulseStrengthWatch` does.

Note that this repository also serves the pulse-health.github.io site. The root `_config.yml` excludes `ios/` from the GitHub Pages
build, so these files are not published on the website, but everyone who can read the repository can read them; move the folder to its
own repository before using it for a product (then delete the `exclude` entry).

## Capabilities needed

| Target | Capability / setting |
| --- | --- |
| iOS app | HealthKit (writes workouts and reads nothing during a workout: the heart rate arrives from the Watch over WatchConnectivity; reads and writes body weight (`bodyMass`) once the user turns on Sync with Apple Health in Settings); Live Activities (`NSSupportsLiveActivities`, `NSSupportsLiveActivitiesFrequentUpdates`, no push token: the app updates the activity locally); Time Sensitive Notifications (the rest alert); App Groups (`group.<bundle id>`: the widget snapshot and command inbox); the notification permission is requested at runtime by `PulseServices.requestPermissions()` and again, if still undecided, when the user turns the weigh-in reminder on (the weigh-in reminder is an ordinary, not time-sensitive, notification); URL type `pulse-strength`. No background mode is declared because none is needed. |
| Widget extension | App Groups (the same id as the app: it reads the snapshot and leaves commands); `NSExtension` point `com.apple.widgetkit-extension`. `NSSupportsLiveActivities` is read from the host app. |
| Watch widget extension | App Groups (the same id); `NSExtension` point `com.apple.widgetkit-extension` (watchOS). It reads the snapshot the Watch app stores from the phone. |
| Watch app | HealthKit; App Groups; Background Modes: Workout processing (`WKBackgroundModes` = `workout-processing`); `WKApplication`, `WKCompanionAppBundleIdentifier`, `WKRunsIndependentlyOfCompanionApp` = false (the Watch needs the phone). |

### Privacy manifests

`Apps/PulseStrength/PrivacyInfo.xcprivacy` and `Apps/PulseStrengthWatch/PrivacyInfo.xcprivacy` are bundled into the iPhone and Watch apps (App Store Connect
rejects an upload that uses a required-reason API without one). Both declare `UserDefaults` (reason `CA92.1`: the app reads and writes only its own
values, such as the ids of the workouts already saved to Health), no tracking and no collected data types, because nothing leaves the device. Update
them when the app gains network code, an SDK, or another required-reason API (file timestamps, disk space, system boot time, active keyboards). The
widget extension uses none of these APIs. XcodeGen 2.46.0 adds the files to the project; run `xcodegen generate` after changing them and commit the
regenerated project (on Linux set `USER`, otherwise XcodeGen stops before it writes anything).

## Exercise photos

The form-demo frames in `Packages/PulseStrengthKit/Sources/PulseStrengthIOS/Resources/ExerciseMedia` come from the
[Free Exercise DB](https://github.com/yuhonas/free-exercise-db): 25 exercises, two frames each. The app shows the line
"Demo photos from the Free Exercise DB." in the form sheets.

**These photos are placeholders, not cleared media.** The database is released under the Unlicense, but its README does not say where
its images come from or under which licence they may be used, so "public domain" cannot be claimed for them. The photos show
identifiable people in a commercial gym, and some show brand marks. Replace them with your own or properly licensed photos, GIFs or
video before any TestFlight or App Store build (the media seam above allows that without touching the rest of the feature), and
remember that the current files also remain in the git history of this public repository.

## Walkthrough after onboarding

A short tour of the Strength feature that follows onboarding: seven swipeable pages (welcome, today's workout on the hub, logging sets,
the rest timer, shaping a workout, finishing, and where everything else lives), each with a small picture drawn in the theme colours, a
sentence and up to three tips. "Skip", "Get Started" and a swipe down all close it; "Back" and the page dots are on every page.

* **When it opens.** `StrengthAppEnvironment.showWalkthroughAfterOnboarding()` opens it once (it remembers the version it showed, see
  `Walkthrough.version`: raise it to show a revised tour again), and not while a workout runs. The standalone app calls it at launch because it has
  no onboarding of its own, so its first launch stands in for "after onboarding". The permission prompts (notifications, Health) wait until the
  tour has closed, so they do not cover it. Previews and the UI-test mode (`-PulseUITest`) never open it by themselves.
* **Replay.** Hub > More > **App Walkthrough** (`environment.startWalkthrough()`).
* **Where the text lives.** `Walkthrough.steps` in `PulseStrengthCore/Walkthrough.swift`, next to `WalkthroughProgress` (the page logic) and
  `Walkthrough.shouldShow(seenVersion:)`; `WalkthroughTests` covers them on Linux. The pictures are in `Screens/StrengthWalkthroughView.swift`,
  chosen by the step's `id`. When a screen the tour describes changes, change its step.
* **Verification.** The Core logic is unit-tested (`WalkthroughTests`, on Linux in CI). The screen compiles with Xcode 16 and 26, and CI renders it:
  `StrengthTourTests` opens it from the More menu, pages through all seven pages and takes screenshots 15 to 21 in every `matrix` configuration
  (dark mode, accessibility-extra-large text, iPhone SE, oldest available runtime). The screenshots were looked at in the simulator: nothing overflows,
  `Next` / `Get Started` stay visible, and on the SE and at large text the pages scroll inside (a short fade at the bottom shows there is more). Not tried:
  a real device, VoiceOver, Reduce Motion, landscape and iPad layouts.

## Training plans and importing them

A **plan** is a rotation of workouts (Upper, Lower, Push, Pull, Legs, then Upper again), not a calendar: it has no weekdays, so a
missed day never leaves it behind. The Strength hub shows the active plan with its next workout tagged "next up", how many of its workouts
were done in the last 7 days, and a "Skip" button; doing a workout moves the rotation to the one after it, and the "Start Workout" card
recommends the plan's next workout. Workouts can carry rep ranges (8–10) and a note per exercise (technique cues).

Plans come from a file: `tools/youtube-workouts/yt_workout.py` turns YouTube workout videos into `pulse-import.json`; put that file on
the phone (AirDrop, Files) and choose **More › Import Plan…** in the Strength hub. Importing the same file again replaces the earlier copy
and keeps your place in the rotation. Details: [ARCHITECTURE.md §3.6](ARCHITECTURE.md) and
[tools/youtube-workouts/README.md](tools/youtube-workouts/README.md). The plan screens are compiled by CI's Xcode jobs; they have not
been run on a device (the UI flow tests do not exercise them).

## Verification status

State at the last commit of this branch; the numbers come from the `strength-ios` workflow
(<https://github.com/Pulse-Health/pulse-health.github.io/actions/workflows/strength-ios.yml>), whose jobs were all green on it.

**Verified**

* **Core (`PulseStrengthCore`)**: 1172 unit tests on Linux (job `core-linux`, also with the Combine stand-in) and 1174 on macOS (jobs `apple` and `xcode26`) pass:
  reducer, presenter, snapshot and summary builders, persistence, the phone <-> Watch sync protocol (acknowledgements, optimistic
  replay, delivery fuzzing with dropped, duplicated and reordered messages), exercise library and sample data.
* **Compiles**: `xcodegen generate`, then `xcodebuild` of the iOS app (with the widget extension and the embedded Watch app) and of the
  Watch scheme for the simulators, without code signing (job `apple`). Xcode 16, deployment targets iOS 17.0 / watchOS 10.0, Swift 5 mode.
  Jobs `apple` and `xcode26` (Xcode 26) both build the app with its widget extension (Live Activity, Home Screen, StandBy, iPad, Lock Screen,
  extras, controls) and the Watch app with its widget extension; the device-SDK build embeds both extensions.
* **Runs in a simulator** (job `visual`, artifact `strength-screens`): a 30-step XCUITest flow through the real app (start a workout, log
  sets, keypad, set detail, rest settings, options, form info, exercise list, picker with search and multi-select, create exercise,
  navigator, superset, undo, rest dock, pause/resume, finish, update-template alert, summary, history, exercise library and detail, empty
  workout, discard) with 55 screenshots; snapshot tests that render the Lock Screen and Dynamic Island (compact, minimal, expanded) for
  every phase and the Watch screens on five case sizes. The screenshots were compared with the design boards.
* **Widgets render** (job `visual`, the same artifact): `PulseStrengthWidgetSnapshots`, `PulseStrengthWatchWidgetSnapshots` and
  `PulseStrengthLiveSnapshots` draw the widget, complication and Live Activity views of the catalogue (`../widgets/SPEC.md`), light and dark, with the idealised
  preview data and with the empty state, and the live states of a running workout (the controls, which the system draws itself, and the variants that
  share a view with another id, such as the inline rest day LS-11, are not drawn separately): 128 iPhone widget images (`widget-*`), 15 Apple Watch widget
  images (`watchwidget-*`) and 107 Live Activity images (`live-*`). They were looked at against the design canvas. They are drawings of the
  views by `ImageRenderer`, not screenshots of the system's widgets (see below).
* **Dark mode, large text, small phone** (job `matrix`): the same tour on an iPhone 16 Pro in dark mode, at accessibility-extra-large text,
  and on an iPhone SE (3rd generation, 375 x 667 pt). On the SE the workout screen fits without page scrolling (only the set list scrolls
  inside the card) and nothing leaves the screen. Text follows Dynamic Type on every screen; the dense workout screen and the keypad are
  capped at `xxxLarge` so they keep fitting.
* **Reviews**: adversarial multi-lens reviews (API cross-checks, SwiftUI / ActivityKit / HealthKit / WatchConnectivity correctness,
  concurrency, end-to-end sync traces, design parity, project and CI) each followed by an independent skeptic that tried to refute
  every finding; the confirmed ones were fixed with regression tests where the logic is in Core. The Watch Health session code was
  also run against a fake HealthKit in a scratch harness.

**Not verified** (be careful before shipping)

* Everything the system does around a widget: the widget gallery and configuration, the container background (and its removal in StandBy, the
  tinted and the clear Home Screen modes), the Smart Stack and the Lock Screen layout, widget reloads and the reload budget, App Intents
  that run in an extension process, controls in Control Center and the Action button, a Live Activity's promotion, the Watch complications
  on a real watch face. The renders have no container background, no timers and no accented rendering.
* Anything on real hardware, see below. The simulator cannot show Live Activity buttons, Dynamic Island on a device, WatchConnectivity,
  Watch heart rate, HealthKit writes, or the rest notification. The Lock Screen and Dynamic Island screens are the SwiftUI views rendered
  directly (the same code the widget uses), not the system's presentation.
* The oldest runtime is not covered: the CI runner only offers iOS 18.5 and iOS 26.2 simulators, so the iOS 17.0 deployment target is
  compile-checked (the build enforces API availability) but has never been run on an iOS 17 runtime.
* The Watch app was rendered (snapshot tests) but not driven in a watchOS simulator; its Health session logic is covered by unit tests of
  the Core rules and a stub harness, not by a real session.
* VoiceOver, Reduce Motion and the landscape / iPad layouts were not exercised. Bundle ids, team, App Group and the exercise photos are
  placeholders / stand-ins (the photos have no cleared licence), see [Placeholders to replace](#placeholders-to-replace) and [Exercise photos](#exercise-photos).

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
* **Weigh-in reminder**: Settings (hub "More" menu) > turn the reminder on (the permission prompt), pick a time a minute or two ahead, lock the phone and
  wait: the notification, its "Log weight" text action (the weight appears in Settings > History and the reminder moves out by one interval), a tap that opens the
  entry sheet, and the hub card when the permission was refused. Also change the time zone and the clock and bring the app to the foreground.
* **Apple Health body weight**: Settings > Sync with Apple Health (the Health permission sheet lists Weight), a weight entered in the app appears in the Health app
  (Browse > Body Measurements > Weight) and disappears there when it is deleted in the app; a weight added in the Health app (or by a smart scale) appears under Settings > History as
  "Apple Health" after the app is opened again, cannot be swiped away, and counts as a weigh-in for the reminder; refusing "Weight" sharing shows the footer hint. Then open the detail
  of a barbell lift ("Relative strength") and of Push-up / Chest dip / Pull-up ("Best session load (est.)") with a weigh-in on record.
* **Widgets, controls and live surfaces**: add every family on a device (Home Screen small / medium / large / extra large, Lock Screen circular /
  rectangular / inline, StandBy) and check that a tap opens the right place; that the buttons (start, log set, nudge) work while the app is
  suspended; the tinted and clear Home Screen modes; the controls in Control Center and on the Lock Screen; the Action button (log set, skip
  rest, start next); a planned session (countdown on the Lock Screen and in the Dynamic Island, the notification at the start); the record flash
  and the finish card of the Live Activity; the weekly goal after a change in the hub; and the Watch complications and Smart Stack cards.
* Also worth a pass on a device: WatchConnectivity reachability and the "Watch not connected" / "Health access denied" banners,
  a workout written to Health by the phone when no Watch is used, Dynamic Island layouts on a 14 Pro or newer,
  VoiceOver in the active-workout screen, and Reduce Motion (form demos, heart beat).
