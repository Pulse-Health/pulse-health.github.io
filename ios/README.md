# Pulse Strength for Apple platforms

The strength-workout feature of Pulse for **iPhone**, **Apple Watch**, the **Lock Screen** (Live Activity) and the
**Dynamic Island**. It implements the design "Pulse Gym & Strength" as real Swift: a strength hub with templates and
history, the active-workout screen (set table, keypad, rest timer, supersets, undo, PR detection, coach tip), the
workout summary, a Watch app that mirrors the workout and records heart rate, and a Live Activity that logs sets and
controls the rest timer from the Lock Screen.

The Pulse app repository is not part of this build, so the feature is a self-contained Swift package
(`PulseStrengthKit`) plus a small host Xcode project that runs it standalone. The integration points with the Pulse app
are listed under [Integrating with the Pulse app](#integrating-with-the-pulse-app).

> **Status in one paragraph.** The platform-neutral core is unit-tested on Linux. The Apple-only code (iOS UI, Watch,
> Live Activity) was written **without access to the Apple SDKs** and has not been opened in Xcode by its authors.
> The GitHub Actions workflow `strength-ios` compiles it for real. See [Verification status](#verification-status)
> before trusting any of it.

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
* **XcodeGen 2.38 or newer**: `brew install xcodegen`. `project.yml` pins the Xcode 15.3 project format
  (`options.projectFormat`), because XcodeGen 2.45+ would otherwise write the Xcode 16 format, which Xcode 15.4 cannot open.
* iOS 17 / watchOS 10 or later on the simulator or the device. The Dynamic Island needs an iPhone 14 Pro or newer
  (or such a simulator); the Lock Screen presentation works on every iPhone with iOS 17.
* To run only the Core tests: any Swift 5.9+ toolchain on Linux or macOS (CI uses `swift:6.1` on Linux).

## Generate the project and run it

```sh
cd ios
xcodegen generate            # writes PulseStrength.xcodeproj (git-ignored; regenerate after changing project.yml)
open PulseStrength.xcodeproj
```

### Simulator

1. Pick the **PulseStrength** scheme and an iPhone simulator, then Run. The scheme builds the app, the widget extension
   and the Watch app (the iOS app embeds both).
2. The first launch seeds demo templates and history (see [Placeholders](#placeholders-to-replace)).
3. Start a workout from the hub. To see the Live Activity, lock the simulator (Device > Lock, Cmd-L) while a workout runs;
   use an iPhone 14 Pro or newer simulator to see the Dynamic Island as well.
4. For the Watch app, use a simulator pair (iPhone + Apple Watch, created in Xcode > Window > Devices and Simulators),
   run the **PulseStrengthWatch** scheme on the Watch simulator, then start a workout on the paired iPhone simulator.
   The simulator has no real heart-rate sensor; Watch heart rate needs a real Watch.

### Real device

1. Put your Apple Developer team id into `DEVELOPMENT_TEAM` in `project.yml` (`settings.base`; the three targets inherit it)
   and run `xcodegen generate` again. A team picked only in Xcode's Signing & Capabilities tab is lost on the next generate.
2. Change `PULSE_APP_BUNDLE_ID` (`project.yml`) to an id you own; the widget (`.widgets`) and Watch (`.watchkitapp`)
   ids derive from it. Register the App Group id from [Placeholders](#placeholders-to-replace) for your team.
3. Enable Developer Mode on the iPhone and the Watch, select the PulseStrength scheme and the iPhone, Run. The Watch app
   installs through the companion app; allow Health access on both devices when asked.
4. The entitlements need capabilities that a free personal team may not be able to provision (HealthKit, App Groups, Time
   Sensitive Notifications). If Xcode refuses to sign with a free team, remove the offending entry from the `.entitlements`
   file for local experiments: without App Groups the app stores its data in Application Support (the Live Activity
   buttons still reach the app); without the time-sensitive entitlement the rest alert may be delivered as an ordinary notification.

### Command-line build without code signing (what CI does)

```sh
cd ios && xcodegen generate
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
| `PulseStrengthLiveSnapshots` (`PulseStrengthLiveSnapshotTests`, no host app) | Lock Screen card, Dynamic Island compact / minimal / expanded in 11 workout states, plus contact sheets | `live-NN-*.png` (about 53), `live-measurements.txt` (sizes and limit violations) |
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

**Run it locally** (macOS, Xcode 16; the UI flow needs the software keyboard, so disconnect the hardware keyboard in the
Simulator, I/O > Keyboard):

```sh
cd ios && xcodegen generate
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
6. Data lives as JSON files in the App Group container (`FileStrengthPersistence`); `StrengthStore` holds templates, history,
   custom exercises and personal bests.
7. Live Activity buttons are App Intents compiled into app and extension; they call `WorkoutCommandBus`, whose handler the
   app installs when `StrengthAppEnvironment` starts (the app waits up to 3 s for a background launch).
8. Phone and Watch exchange `SyncEnvelope`s / `RemoteCommand`s over WatchConnectivity. The Watch applies its taps at once and the
   phone acknowledges every command in its next envelope (duplicates are dropped by command id); the Watch shows the phone's
   state with its unacknowledged taps on top ("Sync protocol" in `ARCHITECTURE.md` 3.4).
9. Clock-driven UI uses `TimelineView`; the Live Activity uses `Text(timerInterval:)` and a stale date, because a widget cannot tick.
10. Contracts, file by file: [`ARCHITECTURE.md`](ARCHITECTURE.md).

## Placeholders to replace

Everything below is a stand-in until the feature lives inside the Pulse app.

| Placeholder | Value | Where to change it |
| --- | --- | --- |
| Bundle ids | `health.pulse.strength`, `.widgets`, `.watchkitapp` | `PULSE_APP_BUNDLE_ID` in `project.yml` (the Watch `Info.plist` reads it for `WKCompanionAppBundleIdentifier`) |
| Notification id | `health.pulse.strength.rest` | `StrengthConfig.restNotificationID` (Core); only a label, it does not have to match the bundle id |
| App Group | `group.health.pulse.strength` | `StrengthConfig.appGroupID` (Core), `Apps/PulseStrength/PulseStrength.entitlements`, `Apps/PulseStrengthWidgets/PulseStrengthWidgets.entitlements`; register the group in the developer portal |
| URL scheme | `pulse-strength://workout` | `StrengthConfig.urlScheme` / `workoutURL` and `CFBundleURLTypes` in `Apps/PulseStrength/Info.plist` |
| Team | empty | `DEVELOPMENT_TEAM` in `project.yml` |
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
| iOS app | HealthKit (reads heart rate and active energy, writes workouts); App Groups; Live Activities (`NSSupportsLiveActivities`, `NSSupportsLiveActivitiesFrequentUpdates`, no push token: the app updates the activity locally); Time Sensitive Notifications (the rest alert); the notification permission is requested at runtime by `PulseServices.requestPermissions()`; URL type `pulse-strength`. No background mode is declared because none is needed. |
| Widget extension | App Groups; `NSExtension` point `com.apple.widgetkit-extension`. `NSSupportsLiveActivities` is read from the host app. |
| Watch app | HealthKit; Background Modes: Workout processing (`WKBackgroundModes` = `workout-processing`); `WKApplication`, `WKCompanionAppBundleIdentifier`, `WKRunsIndependentlyOfCompanionApp` = false (the Watch needs the phone). The Watch does not use the App Group (it keeps no files). |

## Exercise photos

The form-demo frames in `Packages/PulseStrengthKit/Sources/PulseStrengthIOS/Resources/ExerciseMedia` come from the
[Free Exercise DB](https://github.com/yuhonas/free-exercise-db), released under the Unlicense (public domain): 25
exercises, two frames each. The app shows the line "Demo photos: Free Exercise DB (public domain)." in the form sheets.
They are demo material: the real Pulse app may prefer licensed GIFs or video with a consistent look, which the media seam
above allows without touching the rest of the feature.

## Verification status

* **Core (`PulseStrengthCore`)**: unit-tested on Linux (`swift test`, with and without the Combine shim, the `core-linux` CI job).
  It contains the reducer, presenter, snapshot and summary builders, persistence, sync codec, exercise library and sample data.
* **Apple-only code** (iOS screens and sheets, services, Watch app, Live Activity and intents, the three entry points,
  `project.yml`, plists, entitlements, asset catalogs): written **without access to the Apple SDKs**. These files were
  syntax-checked with `swiftc -parse` on Linux and reviewed by hand against the iOS 17 / watchOS 10 APIs, and nothing
  more: no type check, no build, no run. `project.yml` was written against the XcodeGen documentation and source but
  XcodeGen itself was never run on it. The first real compile happens in the `apple` job of the `strength-ios` workflow
  (`xcodegen generate`, `swift test` on macOS, `xcodebuild` of the iOS and watchOS schemes for the simulators).
  Expect to fix compiler errors and generator issues on the first run; the job uploads the full logs as an artifact and
  prints the unique `error:` lines when a step fails.
* **Visual tests** (the three test targets under `Apps/` and the `visual` job, see [Screenshots in CI](#screenshots-in-ci)):
  written under the same conditions and not compiled or run by their authors. They are not part of the `PulseStrength` and
  `PulseStrengthWatch` schemes, so a problem in them cannot break the `apple` job. What the screens look like and how the
  app behaves at runtime is only known once someone has looked at the `strength-screens` artifact.
* **CI status: see the latest run of strength-ios** (<https://github.com/Pulse-Health/pulse-health.github.io/actions/workflows/strength-ios.yml>).
  This README does not claim a result; update this line only once the `apple` job has been seen green.

### Must be tested on real hardware

CI and the simulators cannot show any of these, and none of them has been tried:

* **Live Activity buttons**: "Log set", the -/+ steppers, -15 s / +15 s / Skip from the Lock Screen and the Dynamic Island, including
  the case where the app was suspended or terminated and the intent launches it in the background (command-bus hand-over within 3 s,
  state restored from the App Group), the "Go" state after the stale date, and the paused presentation.
* **Watch heart rate**: the `HKWorkoutSession` / `HKLiveWorkoutBuilder` on a real Watch, the first samples after the phone launches the
  Watch app with `startWatchApp(with:)`, the throttled stream to the phone (the header and the Live Activity), the Health permission flow,
  and the workout saved by the Watch when `usedWatch` is true.
* **Rest notification**: the time-sensitive local notification at the end of the rest with the app in the background and the phone
  locked, its cancellation on skip, pause, finish and discard, the haptic when the rest ends in the foreground, and the Watch haptic.
* Also worth a pass on a device: WatchConnectivity reachability and the "Watch not connected" / "Health access denied" banners,
  a workout written to Health by the phone when no Watch is used, Dynamic Island layouts on a 14 Pro or newer, Dark Mode,
  Dynamic Type and VoiceOver in the active-workout screen, and Reduce Motion (form demos, heart beat).
