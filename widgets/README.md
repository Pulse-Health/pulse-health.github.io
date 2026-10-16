# Pulse Strength widgets, controls and live surfaces

Every glanceable surface of Pulse Strength on iOS and Android, built from one data contract. The design is the canvas
"Pulse Strength Widget Ideas" (<https://claude.ai/artifact/7FzgYpmWrz8cY1wfaHxpMM>); the catalogue with its 66 stable ids (`HS-01` ... `WI-11`), the
exact rule behind every number and the platform mapping are in [`SPEC.md`](SPEC.md). Read that first; this file is the map of where things are.

## The idea in four lines

1. **One contract.** `tools/schema.py` describes `WidgetSnapshot` (and the `WorkoutSnapshot` fields for live surfaces); `tools/generate.py` writes the Swift and the
   Kotlin types and the preview fixture. CI (`widgets-contract`) fails when the generated files are stale.
2. **One builder per platform, same rules.** `WidgetSnapshotBuilder` (Swift: `PulseStrengthCore/Widgets`, Kotlin: `android/core/.../core/widgets`) turns the app's own data into the
   snapshot. Both are tested against `fixtures/golden-sample.json`, which the Swift test writes (`UPDATE_GOLDEN=1`) and the Kotlin test compares.
3. **Surfaces only read the snapshot** and send commands from a small vocabulary (`startNext`, `logNextSet`, `nudge`, `adjustRest`, `skipRest`, `pause`, ...,
   SPEC section 5) or open a `pulse-strength://` deep link (SPEC section 4). They never read the workout engine or the history files.
4. **The app keeps the snapshot current** (iOS `WidgetPublisher`, Android `LiveRuntime`) and tells every surface to refresh.

## Where things are

| Area (catalogue ids) | iOS (`ios/`) | Android (`android/`) |
|---|---|---|
| Contract, builder, rules | `Packages/PulseStrengthKit/Sources/PulseStrengthCore/Widgets/` (+ `Tests/PulseStrengthCoreTests/Widget*`, `LiveMomentsTests`) | `core/src/main/kotlin/health/pulse/strength/core/widgets/` |
| Snapshot file, command inbox, publisher | `WidgetSnapshotStore`, `WidgetCommandInbox` (App Group), `PulseStrengthIOS/Services/WidgetPublisher.swift`, `WidgetCommandDrain.swift` | `app/.../runtime/` (`StrengthRuntime`, `LiveRuntime`), `surfaces/Surfaces.kt` |
| Home Screen, StandBy, iPad (HS-01...HS-12, SB-01, SB-03, SB-04) | `Apps/Shared/Widgets/Home/` | `app/.../widgets/home/`, `widgets/tablet/` |
| Lock Screen / glanceable hub (LS-01...LS-11) | `Apps/Shared/Widgets/Lock/` | `app/.../widgets/lock/` |
| Wilder ideas (WI-01...WI-11) | `Apps/Shared/Widgets/Extras/` | `app/.../widgets/extras/` |
| Watch (WA-01...WA-10) | `Apps/Shared/Widgets/Watch/`, extension `Apps/PulseStrengthWatchWidgets/`, data path `WatchWidgetSnapshotSender` / `WatchWidgetSnapshotReceiver` | `wear/` (tiles, complications, Ongoing Activity) and `app/.../wear/PhoneWearSync.kt` |
| Live Activity / Live Update states, planned session, bench mode (LA-01...LA-10, SB-02) | `Apps/Shared/LiveActivity/`, `PulseStrengthActivity/PlannedSessionAttributes.swift`, `Services/LiveActivityManager.swift`, `Services/PlannedSessionManager.swift` | `app/.../live/` decorating the ongoing notification of `services/WorkoutNotifications.kt` |
| Controls, Action button, Quick Settings tiles, shortcuts (CT-01...CT-10) | `Apps/Shared/Controls/`, `Apps/Shared/Intents/` | `app/.../controls/`, `res/xml/shortcuts.xml` |
| Shared helpers | `Apps/Shared/Widgets/Common/` | `app/.../widgets/common/` |
| Tests that draw the widgets into PNGs | `Apps/PulseStrengthWidgetSnapshotTests/`, `PulseStrengthWatchWidgetSnapshotTests/`, `PulseStrengthLiveSnapshotTests/` | Robolectric render tests next to each area |

The widget extension (`Apps/PulseStrengthWidgets`) composes the iOS bundles, the Watch extension (`Apps/PulseStrengthWatchWidgets`) the Watch ones; Android registers its
widgets, tile services and complication services in the manifest of `:app` and `:wear`.

## Platform decisions worth knowing

* **Units.** Weights are kilograms everywhere (the unit setting of PR #12 is not handled by the widgets yet).
* **No network.** Widgets, tiles and notifications work from files on the device. The Android app still declares no `INTERNET` / `ACCESS_NETWORK_STATE` permission (the one that
  WorkManager, a dependency of Glance, adds is removed in the manifest; a unit test guards it).
* **iPad.** `SB-03` (the training block, `systemExtraLarge`) needs the host app to support iPad; the app is iPhone-only today, so the widget exists but the system will not offer it.
* **Watch.** `Start` on the Watch widgets opens the Watch app; starting a workout from the Watch needs a start request on the Watch to phone channel that does not exist yet.
* **Family in tests.** `widgetFamily` is read-only in SwiftUI's environment, so the widgets that depend on it take an explicit value for the snapshot tests (`familyOverride`,
  `HomeSurface`).

## Verification

Nothing in this folder has run on a device, a watch or an emulator. What has been checked, and by what:

* **Swift core** (`swift test`, Linux and macOS): the builder rules, the live moments, the persisted fields and the golden snapshot.
* **Apple code**: the `strength-ios` workflow compiles the app, the widget extension, the Watch app and the Watch widget extension with Xcode 16 and 26, and renders every widget
  view, light and dark, into PNGs (artifact `strength-screens`, files `widget-*`, `watchwidget-*`, `live-*`). The renders show layout, colour and text; they do not show the system's
  widget background, timers, StandBy tinting or any button behaviour.
* **Kotlin core and Android**: `./gradlew :core:test :app:testDebugUnitTest :wear:testDebugUnitTest :app:lintDebug :wear:lintDebug` and the debug builds in `strength-android`.
* **Not covered anywhere**: widget gallery and configuration flows, Smart Stack ranking, Control Center and Action button behaviour, Live Update promotion on Android 16,
  Wear OS tile and complication behaviour on a watch, App Intent execution from an extension process, and the Watch to phone round trips.

## Changing the contract

Edit `tools/schema.py`, run `python3 widgets/tools/generate.py`, commit the generated Swift and Kotlin files, then adapt the two builders (the golden test tells you where they
disagree: `UPDATE_GOLDEN=1 swift test --package-path ios/Packages/PulseStrengthKit --filter WidgetSnapshotGoldenTests` rewrites the golden file on the Swift side).
