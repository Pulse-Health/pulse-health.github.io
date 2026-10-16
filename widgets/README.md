# Pulse Strength widgets, controls and live surfaces

Every glanceable surface of Pulse Strength on iOS and Android, built from one data contract. The design is the canvas
"Pulse Strength Widget Ideas" (<https://claude.ai/artifact/7FzgYpmWrz8cY1wfaHxpMM>); the catalogue with its 68 stable ids (`HS-01` ... `WI-11`), the
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
* **Kotlin core and Android**: `./gradlew :core:test :app:testDebugUnitTest :wear:testDebugUnitTest :app:lintDebug :wear:lintDebug` and the debug builds in `strength-android`
  (887 core tests, which include the comparison with `fixtures/golden-sample.json`, 1213 app tests, 236 watch tests, lint without errors); the R8 release builds of both apps were assembled and linted locally (CI builds the debug variants).
  The Glance widgets are inflated and drawn into PNGs by Robolectric (`app/build/screens/widgets*`); the Wear tiles and complications are checked as data.
* **Not covered anywhere**: widget gallery and configuration flows, Smart Stack ranking, Control Center and Action button behaviour, Live Update promotion on Android 16,
  Wear OS tile and complication behaviour on a watch, App Intent execution from an extension process, and the Watch to phone round trips.

## As built: where the implementation differs from the canvas

The rules behind every number are fixed in `SPEC.md` (section 2 and "Readings of section 2 fixed by the Swift implementation"). These are the places where a
surface differs from the canvas or from the mapping table, and why:

**Android, Home Screen and tablet.** The template launcher has one button per row (a play badge) instead of a separate "Start" pill, so each row is one 48 dp
target and one TalkBack action. SB-01 has no StandBy layout on Android: the same two widgets are offered in the `keyguard` category. HS-06 uses the dynamic-colour theme.
Small sizes drop lines instead of overflowing. Glance corner radii work from Android 12 (API 31), so cards are square below.

**Android, Lock Screen and extras.** While a workout runs, the quick-start and next-workout widgets (LS-04, LS-05, the inline ones) show and open the running workout.
WI-02 has extra states (paused, all sets logged, rest over) so none is blank, and draws set dots where the canvas shows "last time 8, 7, 6", which is not in the snapshot.
WI-06 shows the next template on a training day. WI-07 shows the estimated 1RM when there is no body weight. WI-03 and WI-09 show their "Invite a partner" / "Connect Pulse"
states because the standalone build has no partners or readiness.

**Android, live surfaces.** LA-01 ... LA-10 decorate the one ongoing notification (promoted notifications allow no custom views): colour is never the only carrier, the
"current member" of a superset is written "(now)", the status-bar chip carries one text (heart rate wins over the set dots while logging). The coach tip has a third
button, Skip. The planned-session alarms are inexact (no `SCHEDULE_EXACT_ALARM`), so "Time to train" can come minutes late in Doze. The Finish tile opens the running workout
(the app asks for the confirmation) and the Rest tile opens bench mode. SB-04 (night mode) is the red palette of bench mode.

**Android, Wear OS.** WA-03 is an ordinary tile (there are no relevance entries on Wear). The rest tile puts Skip before +15 s so the double-tap target is Skip. Tiles cannot
hide, so the record tile says "Latest record" after 24 hours. The lift-trend sparkline is an inline image. From Wear OS 4 the rest gauge is live; on Wear OS 3 it shows the
value of the last update and the countdown digits still tick. The Start complication opens the watch app, which asks the phone.

**iOS.** The Watch widgets' "Start" opens the Watch app: a start request from the Watch to the phone does not exist yet. SB-03 needs iPad support in the host app. The widget
renders are `ImageRenderer` drawings, so they show no container background, timers or tinting.

**Both.** Weights are kilograms (the unit setting of the Pulse app is not handled). The Android data model has no training plans, rep ranges, entry notes or stored body weight
(`nextUp` plan fields stay empty; the weekly goal is a setting, 1 to 7, default 4). Neither platform has readiness or partners without the wider Pulse app.

## Changing the contract

Edit `tools/schema.py`, run `python3 widgets/tools/generate.py`, commit the generated Swift and Kotlin files, then adapt the two builders (the golden test tells you where they
disagree: `UPDATE_GOLDEN=1 swift test --package-path ios/Packages/PulseStrengthKit --filter WidgetSnapshotGoldenTests` rewrites the golden file on the Swift side).
