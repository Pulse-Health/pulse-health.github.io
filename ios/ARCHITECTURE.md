# Pulse Strength: architecture and build contract

The strength-workout feature of Pulse for iPhone, Apple Watch, the Lock Screen (Live Activity) and
the Dynamic Island. It implements the design canvas "Pulse Gym & Strength"
(<https://claude.ai/artifact/M24e88tBek3xkMcwaPAepp>). The design source files are in
`/tmp/claude-0/-home-user-pulse-health-github-io/454103a4-1a20-5eb6-93ba-38895136941b/scratchpad/cv/project/`
(`Active.dc.html` is the reference for behaviour: its `<script>` is the logic to port; the markup is the
reference for layout, sizes, colours and copy).

The Pulse app repository is not available to this build, so the feature is a self-contained Swift
package (`PulseStrengthKit`) plus a host Xcode project (XcodeGen spec) that runs it standalone. The
integration seams are protocols and plain closures (see "Integration with the Pulse app").

## 1. Repository layout (`ios/`)

```
ios/
  ARCHITECTURE.md            this file
  README.md                  setup, capabilities, verification status
  project.yml                XcodeGen spec: app, widget extension, watch app
  Packages/PulseStrengthKit/
    Package.swift
    Sources/
      PulseStrengthCore/     platform neutral (Foundation only): models, reducer, presenter, stores, sync
      PulseStrengthActivity/ iOS: ActivityAttributes + command bus (shared by app and widget)
      PulseStrengthIOS/      iOS: SwiftUI screens, services (Live Activity manager, notifications, HealthKit, Watch bridge)
        Resources/ExerciseMedia/*.jpg   form demo frames "<mediaKey>-a.jpg" / "-b.jpg" (public domain)
      PulseStrengthWatchUI/  watchOS: SwiftUI screens, workout session, WatchConnectivity client
    Tests/PulseStrengthCoreTests/
  Apps/
    PulseStrength/           iOS host app (entry point, Info.plist, entitlements, assets)
    PulseStrengthWidgets/    widget extension (WidgetBundle entry point, Info.plist)
    Shared/Intents/          App Intents (LiveActivityIntent) compiled into BOTH the app and the widget extension
    Shared/LiveActivity/     Lock Screen + Dynamic Island views, compiled into the widget extension
    PulseStrengthWatch/      watchOS app (entry point, Info.plist, entitlements, assets)
```

## 2. Platform and tooling

* iOS 17+, watchOS 10+, Swift 5.9 language mode (`swift-tools-version: 5.9`), SwiftUI, no third-party dependencies.
* `PulseStrengthCore` imports Foundation only (plus `Combine` inside `#if canImport(Combine)`). It must build
  and pass its tests on Linux with `swift test`. No `NumberFormatter`/`DateFormatter` with locale dependence:
  number text is formatted by hand ("." decimal, "," thousands) so output is identical everywhere.
* Every file of the Apple-only targets is wrapped in `#if os(iOS)` or `#if os(watchOS)` (whole file contents),
  so the package builds to empty modules on Linux.
* Code must be real, complete and compile-ready against the iOS 17 / watchOS 10 SDKs. No `TODO`, no
  `fatalError("not implemented")`, no placeholder views. If an API is uncertain, use the documented, widely used form.
* Weights are kilograms. `LoggedSet.reps` holds seconds for duration exercises.

## 3. Core contract (`PulseStrengthCore`)

Already written (do not change without updating this file and every user): `Models.swift`,
`WorkoutState.swift`, `WorkoutAction.swift`, `Presentation.swift`, `Snapshot.swift`, `Completed.swift`,
`SideEffects.swift`. Read them first. Public API to implement, by file:

### 3.1 `ExerciseLibrary.swift`, `Metrics.swift` (area: library and metrics)

```swift
public enum ExerciseLibrary {
    public static let builtIn: [Exercise]                       // the 36 exercises of the design (Active.dc.html, array `L`)
    public static func exercise(id: String) -> Exercise?
    public static let mediaKeys: [String]                       // every non-nil mediaKey in builtIn
    public static func filter(_ exercises: [Exercise], query: String, muscle: MuscleGroup?, equipment: Equipment?) -> [Exercise]
        // every whitespace separated token of `query` must occur (case-insensitive) in "name muscle equipment secondary";
        // result sorted by name (case-insensitive, then id)
}
public enum Estimated1RM {
    public static func epley(weightKg: Double, reps: Int) -> Double   // kg * (1 + reps/30); 0 if kg <= 0 or reps <= 0
}
public struct PlatePlan: Equatable, Sendable { public var perSide: [Double]; public var leftoverKg: Double }
public enum PlateCalculator {
    public static let availablePlates: [Double]                       // [25, 20, 15, 10, 5, 2.5, 1.25]
    public static func plan(totalKg: Double, barKg: Double) -> PlatePlan?   // nil when totalKg < barKg; greedy; leftover rounded to 0.01
}
public enum NumberText {
    public static func kg(_ value: Double) -> String        // 82.5 -> "82.5", 80 -> "80", 82.50001 -> "82.5" (round to 2 decimals, trim zeros)
    public static func thousands(_ value: Double) -> String // 1980.4 -> "1,980" (rounded, "," grouping)
    public static func clock(seconds: Int) -> String        // 72 -> "1:12", 3723 -> "1:02:03"
    public static func rest(seconds: Int) -> String         // 0 -> "Off", 150 -> "2:30"
}
```
Library data and media keys come from `Active.dc.html` (`IMG`/`L`): the 25 media keys are
bench, incline, ohp, lateral, pushdown, crossover, pullup, pulldown, brow, squat, deadlift, curl, pushup,
legpress, rdl, plank, hipthrust, crow, facepull, dbcurl, skull, legcurl, legext, calf, cablecrunch.
Keep ids, names, muscles, secondary text, equipment, tracking, previous best e1RM, previous sets, defaults
and cues exactly as in the design. `barKg` is 10 for "skull", else 20.

### 3.2 `WorkoutTargets.swift`, `WorkoutReducer.swift`, `WorkoutFactory.swift` (area: reducer)

```swift
public struct SetTarget: Hashable, Sendable { public var exerciseIndex: Int; public var setIndex: Int }
public enum WorkoutTargets {
    /// First pending set of the current exercise; else the first pending set of the following exercises,
    /// then of the earlier ones. nil when every set is logged (or there are no sets).
    public static func nextPending(in state: WorkoutState) -> SetTarget?
}
public enum WorkoutReducer {
    public static var undoWindow: TimeInterval { get }      // 6 seconds
    public static func reduce(_ state: inout WorkoutState, _ action: WorkoutAction, now: Date)
}
public enum WorkoutFactory {
    public static func makeEmpty(name: String, now: Date, id: UUID = UUID()) -> WorkoutState
    public static func makeWorkout(from template: WorkoutTemplate, now: Date, id: UUID = UUID()) -> WorkoutState
    public static func updatedTemplate(_ template: WorkoutTemplate, from state: WorkoutState) -> WorkoutTemplate
    public static func template(from state: WorkoutState, name: String) -> WorkoutTemplate   // "save as template"
}
```

Reducer rules (ported from `Active.dc.html`; `S` = state):

1. Pure given `(state, action, now)`; new entity ids use `UUID()`. After the switch, if `S` is unchanged
   nothing else happens; if it changed, `revision += 1`. Unknown ids / out-of-range indexes are no-ops.
   `currentIndex` is always within `0..<exercises.count` (0 when empty) after every action.
2. Logging (`toggleSet`, `logSet`, `logNextSet`): toggling a done set makes it pending (rir is kept, rest untouched).
   A set becoming done: `lastLogged = SetRef`; rest seconds = warm-up ? `max(30, round(rest*0.4/5)*5)` : the
   exercise's `restSeconds`. Superset: take the indexes of exercises sharing the (non-nil) `supersetGroup`; if the
   exercise is not the last of the group, `currentIndex = index + 1` and no rest starts; otherwise
   `currentIndex = first index of the group` and rest starts. Not in a superset: `currentIndex` unchanged.
   Starting rest: `settings.autoStartRest && seconds > 0` -> `rest = RestState(endsAt: now + seconds, totalSeconds: seconds,
   frozenRemaining: paused ? seconds : nil)`, otherwise `rest = nil`. `logSet` on a done set is a no-op.
   `logNextSet` first moves `currentIndex` to the exercise of `WorkoutTargets.nextPending`, then logs that set.
3. `setWeight` clamps to >= 0 and rounds to 0.01; `setReps` clamps to 0...999; neither changes `isDone`.
   `nudgeNextSet(weightSteps:repsSteps:)` edits the `nextPending` set: weight += steps * `exercise.weightStepKg`
   (>= 0, only for weight-tracking exercises), reps += steps * `exercise.repsStep` (clamped 0...999).
4. `setSetType`, `setRIR(rir)` (clamp 0...4, nil clears), `toggleLastSetRIR(v)` (applies to `lastLogged`; same value clears),
   `setNote`.
5. `addSet`: copies weight/reps of the last set (type normal, not done, no rir); with no sets uses the exercise defaults.
   `deleteSet`: removes it, sets `undo = UndoEntry(.set, title "Set deleted", expiresAt now + undoWindow)`, clears
   `lastLogged` when it pointed at that set.
6. `removeExercise`: removes it; if it was in a superset and exactly one member remains, that member leaves the group;
   `currentIndex` shifts down when an earlier exercise was removed, then clamps; `lastLogged` cleared if it pointed at it;
   `undo = UndoEntry(.exercise(index, exercise), title "Removed <name>", expiresAt now + undoWindow)`.
   `undo`: restores when an entry exists and `now <= expiresAt` (exercise re-inserted at its index, `currentIndex` set to it;
   set re-inserted at its index), and always clears the entry.
7. `moveExercise(from:to:)` and `moveExerciseBy(delta:)` reorder; `currentIndex` keeps following the same exercise.
   `replaceExercise` keeps the entry id and superset group, takes the new exercise with default sets (not done),
   its default rest, empty note; clears `lastLogged` if it pointed at it. `addExercises` appends entries with default
   sets and default rest; into an empty workout it sets `currentIndex = 0`. `setRest` sets `restSeconds` (>= 0).
8. `toggleSuperset(exerciseID)`: in a group -> leaves it (orphan clean-up as in rule 6); otherwise joins the NEXT exercise
   (no next -> no-op): both get the next exercise's group, or the first unused letter of A, B, C, D, E, Z.
9. Rest: `adjustRest(seconds)`: no rest and seconds > 0 -> start `now + seconds` (total = seconds); otherwise
   `endsAt = max(now, max(now, endsAt) + seconds)` and `totalSeconds = max(5, total + seconds)`; while paused adjust
   `frozenRemaining` instead (>= 0). `skipRest` -> `rest = nil`.
10. `pause`: if running `pausedAt = now`; an active rest gets `frozenRemaining = max(0, endsAt - now)`.
    `resume`: `pausedTotal += now - pausedAt`, `pausedAt = nil`, and a frozen rest gets `endsAt = now + frozen`.
11. `goTo`, `nextExercise`, `previousExercise` clamp. `setUsedWatch`, `rename`, `setAutoStartRest`,
    `setAlertWhenRestEnds` set the field. `updateHeartRate(bpm)` sets `heartRate` and, for a non-nil bpm in 30...240,
    adds it to `heartRateSum` / `heartRateCount`; it is the ONE action that does NOT bump `revision` (samples arrive every few seconds).
    Controllers and effects must not persist, broadcast or update the Live Activity for it more than once per 10 seconds.

Factory: `makeWorkout(from:)` creates entries with new ids, `templateEntryID` = entry id, sets from `plannedSets`
(new `LoggedSet` ids, not done), `templateBaseline` = the entry ids in order, `templateID`, `name`, `startedAt = now`.
`updatedTemplate` rebuilds `entries` from the current exercises (kept entries keep their id, new exercises get new
entry ids, planned sets = the current sets' type/weight/reps), keeps `id`, `name`, `lastPerformed`.

### 3.3 `WorkoutPresenter.swift`, `TemplateDiff+Compute.swift`, `SummaryBuilder.swift`, `SnapshotBuilder.swift` (area: presenter)

```swift
public enum WorkoutPresenter {
    public static func present(_ state: WorkoutState, now: Date, recovery: RecoveryProvider) -> ActiveWorkoutPresentation
}
public extension TemplateDiff { static func compute(for state: WorkoutState) -> TemplateDiff }
public enum SummaryBuilder { public static func build(from state: WorkoutState, finishedAt: Date) -> CompletedWorkout }
public enum SnapshotBuilder { public static func make(from state: WorkoutState, now: Date) -> WorkoutSnapshot }
```

Presenter rules (port of `renderVals` in `Active.dc.html`):

* Totals: logged sets, all sets, volume = sum of `weightKg * reps` over logged sets that are not warm-up and belong to
  weight-tracking exercises; completed exercises = exercises with >= 1 set and all done.
* Header: `clockText` = `NumberText.clock(elapsedSeconds)`; paused -> "Paused · " + clock. `volumeText` = thousands, `setsText` =
  "<logged> of <total>", `heartRateText` = bpm or "–". One `Segment` per exercise (fraction = done/total sets, `isCurrent`).
* Navigator is nil when empty; `position` is 1-based.
* Card for the current exercise: recovery percent from the provider, level good >= 80, fair >= 60, else low; `supersetLabel`
  "Superset <letter>"; `restText` via `NumberText.rest`; column titles: weightReps -> "kg"/"Reps", repsOnly -> "Added"/"Reps",
  duration -> ""/"Sec".
* Rows: `number` = "W"/"D"/"F" or the running number of normal sets; `previousText` from `exercise.previousSets[min(i, count-1)]`
  ("80 × 6", "8 reps", "45 s", "–" when none); `weightText` = `NumberText.kg` / "BW" / "–"; `weightEditable` only for weightReps;
  `isNext` = the first pending set of the card. Personal record: a logged, non-warm-up set of a weight-tracking exercise whose
  Epley e1RM exceeds the running baseline + 0.05, where the baseline starts at `previousBestE1RM` and rises with each logged
  set that beats it; no PR when `previousBestE1RM == 0`. `estimated1RM` = rounded e1RM for such sets. `rirText` = "RIR n" / "RIR 4+" only
  on logged sets. `accessibilityLabel` is a full sentence ("Set 3, working set, 82.5 kilograms, 6 reps, logged").
* Dock exists iff a rest exists and there is a current exercise. `remainingSeconds` = ceil of the remaining time (frozen while
  paused); finished when 0 (`remainingText` "Go", `fraction` 1); `nextSetText` = "Next · Set 4 · 82.5 kg × 6" (warm-up:
  "Next · Warm-up · 50 kg × 8"; repsOnly "8 reps", duration "45 s") or "All sets logged". `showsRIR` iff `lastLogged` resolves to a
  logged non-warm-up set; `rirSelection` its rir.
* `coachTip` (card): only while no rest runs, for weight-tracking exercises with `previousBestE1RM > 0` and at least one pending
  non-warm-up set. Baseline = the running best e1RM (previous best, raised by sets already logged today). Take the LAST pending
  normal set (else the last pending non-warm-up set), find the lowest weight (a multiple of `weightStepKg`, rounded up) whose Epley e1RM with
  that set's reps exceeds the baseline by more than 0.05. The set's current weight is irrelevant (it may already equal the target).
  Text: "85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg." (bench: pending 85 × 6 with previous best 99 gives exactly this).
* `undoText` = undo title while `now <= expiresAt`, else nil. `finishCheck`: `loggedSets`, `unloggedSets`, `canFinish = logged > 0`,
  title "Nothing logged yet" / "Finish workout?", message ("Log at least one set to save this workout." /
  "<n> set(s) is/are not logged yet and will be left out." / "All sets are logged. Nice work."), `templateDiff`, `diffMessage`
  "Changes: <summary>.", `asksToUpdateTemplate = !diff.isEmpty && templateID != nil`.
* `TemplateDiff.compute`: added = exercises with `templateEntryID == nil` or not in `templateBaseline`; removed = baseline ids with no
  matching exercise; reordered = the relative order of the common ids differs from the baseline.
* `SummaryBuilder`: only logged sets; volume as above; averageRIR over recorded rir; `durationSeconds` = elapsed at `finishedAt`;
  PR per exercise as in the presenter (baseline `previousBestE1RM`); `PersonalRecord.estimated1RM` = best e1RM of the exercise,
  weight/reps of that set; `muscleSets` = logged non-warm-up sets per muscle group (omit zeros, sort by sets desc then name);
  `averageHeartRate` = `state.averageHeartRate`.
* `SnapshotBuilder`: target = `WorkoutTargets.nextPending`; phase `complete` when no target, else `resting` / `restOver` / `logging`
  from the rest; `setLabel` = ("Warm-up · " if warm-up) + "Set <position among all sets> of <set count>"; `activeStart = startedAt +
  pausedTotal`; `elapsedWhenPaused`; `restStartedAt = restEndsAt - total`; `restFrozenRemaining` while paused; `weightText`/`repsText`/
  `repsUnit` ("reps"/"sec"); `showsWeight` = weight-tracking; `nextSetText` = "Set 4 · 82.5 kg × 6" style; `nextExerciseName` = the next
  exercise (after the current one) that still has pending sets; `volumeText` thousands.

### 3.4 `SyncCodec.swift`, `SyncReconciler.swift`, `Stores.swift`, `StrengthStore.swift`, `WorkoutController.swift`, `SampleData.swift` (area: services)

```swift
public enum SyncCodec {
    public static func encode(_ message: SyncMessage) throws -> [String: Any]      // ["m": <JSON Data>]
    public static func decode(_ payload: [String: Any]) throws -> SyncMessage
}
public struct SeenCommands: Sendable { public init(capacity: Int = 256); public mutating func insertIfNew(_ id: UUID) -> Bool }
public enum SyncReconciler {
    /// True when `incoming` should replace `local`: no local state, a different workout id, or a higher revision.
    public static func isNewer(_ incoming: WorkoutState, than local: WorkoutState?) -> Bool
}

public final class FileStrengthPersistence: @unchecked Sendable {
    public init(directory: URL)
    public static func appGroup(identifier: String) -> FileStrengthPersistence?     // Darwin only; nil elsewhere
    public static func temporary() -> FileStrengthPersistence                         // unique temp dir (tests, previews)
    public func loadActiveWorkout() -> WorkoutState?
    public func saveActiveWorkout(_ state: WorkoutState?) throws                    // nil deletes the file
    public func loadTemplates() -> [WorkoutTemplate];      public func saveTemplates(_ v: [WorkoutTemplate]) throws
    public func loadHistory() -> [CompletedWorkout];       public func saveHistory(_ v: [CompletedWorkout]) throws   // newest first
    public func loadCustomExercises() -> [Exercise];       public func saveCustomExercises(_ v: [Exercise]) throws
    public func loadPersonalBests() -> [String: PersonalBest]; public func savePersonalBests(_ v: [String: PersonalBest]) throws
}
```
JSON (ISO-8601 dates, sorted keys), atomic writes, missing/corrupt file -> empty value (never crash).

`#if canImport(Combine)` (Apple only), both `@MainActor final class ...: ObservableObject`:

```swift
public final class StrengthStore: ObservableObject {
    @Published public private(set) var templates: [WorkoutTemplate]
    @Published public private(set) var history: [CompletedWorkout]          // newest first
    @Published public private(set) var customExercises: [Exercise]
    @Published public private(set) var personalBests: [String: PersonalBest]
    public init(persistence: FileStrengthPersistence?, seedDemoData: Bool = false)
    /// builtIn + custom, with `previousBestE1RM` / `previousSets` overlaid from personal bests and history.
    public var exercises: [Exercise] { get }
    public func exercise(id: String) -> Exercise?
    public func addCustomExercise(_ exercise: Exercise)
    public func saveTemplate(_ template: WorkoutTemplate)
    public func record(_ completed: CompletedWorkout, updateTemplate: WorkoutTemplate?)   // history, bests, template.lastPerformed, persists
    public func history(for exerciseID: String, now: Date) -> ExerciseHistory
    public func reload()
}
public enum WorkoutRole { case authority, mirror }          // phone = authority, Watch = mirror
public final class WorkoutController: ObservableObject {
    @Published public private(set) var state: WorkoutState?          // nil = no active workout
    @Published public private(set) var lastCompleted: CompletedWorkout?
    public let store: StrengthStore
    public let role: WorkoutRole
    public var recovery: RecoveryProvider
    public init(store: StrengthStore, persistence: FileStrengthPersistence?, role: WorkoutRole = .authority,
                recovery: @escaping RecoveryProvider = DemoRecovery.provider, clock: @escaping @Sendable () -> Date = { Date() })
    public func addEffect(_ effect: WorkoutSideEffect)
    public func restoreFromDisk()                                    // on launch: reload the active workout and notify effects
    public func startWorkout(template: WorkoutTemplate?, name: String? = nil)   // nil template = empty workout named `name ?? "Workout"`
    public func send(_ action: WorkoutAction, origin: ActionOrigin = .phone)    // reduce, persist (authority), notify effects
    public func receive(_ command: RemoteCommand)                    // authority: dedupe by id (SeenCommands), then send(action, origin: command.origin)
    public func receive(_ envelope: SyncEnvelope)                    // mirror: adopt when SyncReconciler.isNewer; nil state = ended
    public func presentation(now: Date) -> ActiveWorkoutPresentation?
    public func snapshot(now: Date) -> WorkoutSnapshot?
    public func templateDiff() -> TemplateDiff
    @discardableResult public func finish(updateTemplate: Bool) -> CompletedWorkout?   // builds summary, records it, clears state, notifies effects
    public func discard()
}
```
Mirror role: `send` applies the reducer locally (optimistic) and notifies effects (the Watch effect forwards a `RemoteCommand`
when `origin == .watch`); `receive(envelope)` replaces local state and NEVER calls `workoutChanged` (no echo): it calls
`workoutStarted(state)` when an envelope for a different workout id arrives, and `workoutEnded(previousState, completed: nil)` when the
envelope carries no state. Authority role persists after every change; `receive(command)` ends in `send(action, origin: command.origin)`.
`finish` also ends a mirror locally.

`SampleData`: `public enum SampleData { static func templates() -> [WorkoutTemplate]  // "Upper A · Push" (the 6 exercises of the design with
the same sets), "Lower A · Quads", "Upper B · Pull"; static func history(now: Date) -> [CompletedWorkout]; static func personalBests(now:) }`
used for `seedDemoData` and SwiftUI previews. Make the sample data consistent: today is the `now` argument; "Upper A · Push" was last done
5 days ago (the Strength hub says so), bench sessions exist 5 days ago (W 50×8, W 70×5, 80×6, 80×6, 80×5), 10 days ago (…, 82.5×5, 85×5 = personal
record, estimated 1RM 99), 15 days ago (W 50×8, 77.5×6 ×3); "Lower A · Quads" 7 days ago; personal best bench e1RM 99 (85 kg × 5, 10 days ago).
`seedDemoData` also seeds templates and history only when the store is empty. The "Upper A · Push" template is the design's workout: bench
(warm-up 50×8, warm-up 70×5, 82.5×6, 82.5×6, 85×6, rest 150), incline 3×28×10 (rest 90), ohp 3×45×8 (rest 120), lateral 3×8×15 and pushdown
3×30×12 (both rest 60, superset A), crossover 3×15×12 (rest 60).

## 4. Verification policy

* Core: `swift build` + `swift test` on Linux must pass; each area ships tests (`Tests/PulseStrengthCoreTests/<Area>Tests.swift`).
* Apple-only files cannot be compiled on Linux: they are syntax-checked with `swiftc -parse`, then reviewed adversarially against the
  iOS 17 / watchOS 10 SDK APIs. The README states plainly that the Apple targets have not been built in Xcode.


## 5. Apple targets contract

None of this code can be compiled on Linux. Each file is wrapped in `#if os(iOS)` (or `os(watchOS)`), is syntax-checked with
`swiftc -parse`, and is compiled for real by the GitHub Actions workflow (`.github/workflows/strength-ios.yml`, macOS runner). Write
conservative, documented SwiftUI/ActivityKit/HealthKit/WatchConnectivity code for iOS 17 / watchOS 10. No `#Preview` blocks (use
`StrengthAppEnvironment.preview()` if a preview is wanted), no third-party packages, no private API.

### 5.1 Identifiers and capabilities

* Bundle ids: app `health.pulse.strength`, widget extension `health.pulse.strength.widgets`, watch app `health.pulse.strength.watchkitapp`.
  App Group `group.health.pulse.strength` (`StrengthConfig.appGroupID`); URL scheme `pulse-strength`. All are placeholders to replace.
* iOS app: HealthKit (read heart rate; share workouts and active energy), App Groups, Push-less Live Activities
  (`NSSupportsLiveActivities` = YES, `NSSupportsLiveActivitiesFrequentUpdates` = YES), `NSHealthShareUsageDescription`,
  `NSHealthUpdateUsageDescription`, URL type for the scheme, Notifications (time-sensitive rest alert).
* Watch app: HealthKit, `WKBackgroundModes` = `workout-processing`, `WKCompanionAppBundleIdentifier` = the iOS bundle id, usage descriptions.
* Widget extension: App Groups (`NSSupportsLiveActivities` is read from the host app); `NSExtension` point `com.apple.widgetkit-extension`.

### 5.2 Design tokens
`Sources/PulseStrengthIOS/PulseTheme.swift` is written and is the only source of colours, fonts, card/button/chip/segmented styles for
iOS views (`PulseTheme.*`, `PulseFont.*`, `.pulseCard()`, `.pulseNumber(size)`, `PulsePrimaryButtonStyle`, `PulseTintButtonStyle`,
`PulsePillButtonStyle`, `PulsePlainButtonStyle`, `PulseChip`, `PulseSegmented`, `SetType.badgeBackground/Foreground`). Extend it only by
adding to it in your own file via extensions. Light values equal the design; dark values are provided. Watch and widget targets have their
own small theme file (same hex values; the Watch and the Live Activity are always dark).

### 5.3 iOS screens and sheets: files and exact public initializers (`Sources/PulseStrengthIOS/`)

Visual reference for each: the design files in `.../scratchpad/cv/project/` (`Active.dc.html` + the `ActiveXxx.dc.html` state boards, `Main.dc.html` hub,
`Exercise.dc.html`, `Summary.dc.html`). Match layout, copy, sizes, colours and states. Views take their data from
`WorkoutController` (`@ObservedObject`) and `StrengthStore`; the clock-driven parts use
`TimelineView(.periodic(from: .now, by: 1))` with `controller.presentation(now: context.date)`.

**Area "active workout"** (`Components/`, `Screens/ActiveWorkoutView.swift`):
```swift
public struct ExerciseMediaView: View { public init(mediaKey: String?, cornerRadius: CGFloat = 12) }   // fills its frame; crossfades "<key>-a"/"<key>-b" from Bundle.module (loose .jpg resources), placeholder glyph when nil or missing; honours accessibilityReduceMotion
public struct ActiveWorkoutView: View {
    public init(controller: WorkoutController, store: StrengthStore,
                onMinimise: @escaping () -> Void, onFinished: @escaping (CompletedWorkout?) -> Void)   // nil = discarded
}
```
Layout (390 pt wide design, flexible): header (minimise chevron, title + clock, More menu, blue Finish pill; stats line Volume / Sets /
heart with beat animation; segmented progress strip under it), optional Watch banner (not connected / Health access denied: driven by
a `WatchStatus` value in `StrengthAppEnvironment`, passed through an `@Environment` key `\.watchStatus` defined in this area:
`public enum WatchStatus { case connected, notConnected, healthDenied }`, default `.connected`), navigator capsule "< 1 / 6 >" plus the
Edit pill, exercise card (media tile that opens the form sheet, name, recovery dot + "Chest · 88% recovered", Superset pill, options
button, set table with PREVIOUS / kg / reps columns, set rows with type badge button, tappable weight/reps cells opening the keypad, check
toggle, PR / RIR tags inside the row, next-set outline, "Add Set", rest chip, note field, coach tip), rest dock (ring, countdown, -15 / +15 /
Skip, "Reps left" selector, Dismiss when over), undo toast, empty state. Everything must fit on one screen without page scrolling; only the
sets list may scroll inside the card when there are many sets. The `ActiveSheet` enum (Identifiable) and all presentation logic live in
`ActiveWorkoutView`. Finish flow: `confirmationDialog` (Finish Workout / Keep Training / Discard Workout) -> discard alert, and the
three-button "Update template?" alert when `finishCheck.asksToUpdateTemplate`; then `controller.finish(updateTemplate:)` and `onFinished`.
Rest end feedback: `UINotificationFeedbackGenerator` when the dock phase turns `.finished` while the app is active.

**Area "sheets"** (`Sheets/`):
```swift
public enum PickerMode: Equatable { case add; case replace(exerciseID: UUID) }
public enum KeypadField: Equatable { case weight, reps }
public struct ExerciseListSheet: View { public init(controller: WorkoutController, store: StrengthStore) }          // List + onMove (edit mode active) reorder, rows with media, "3 of 5 sets", superset label, options button, "Add Exercise"; owns its nested sheets
public struct ExercisePickerSheet: View { public init(store: StrengthStore, controller: WorkoutController, mode: PickerMode) }   // search, muscle + equipment chips, multi-select (single in replace mode), create row -> CreateExerciseSheet, bottom action; dismisses itself
public struct CreateExerciseSheet: View { public init(initialName: String, onCreate: @escaping (Exercise) -> Void) }
public struct KeypadSheet: View { public init(controller: WorkoutController, ref: SetRef, initialField: KeypadField) }   // value cards, -/+ steppers (Exercise.weightStepKg/repsStep), "Use last", plate chips for barbells, 3x4 keypad, Next/Log set/Done
public struct SetDetailSheet: View { public init(controller: WorkoutController, ref: SetRef) }                   // set type list, RIR segmented (– 0 1 2 3 4+), delete
public struct RestSettingsSheet: View { public init(controller: WorkoutController, exerciseID: UUID) }            // presets Off 0:30 ... 5:00, auto-start toggle, alert toggle
public struct FormInfoSheet: View { public init(exercise: Exercise) }                                         // large demo, muscles, how-to cues, attribution line
public extension View {
    func exerciseOptionsDialog(controller: WorkoutController, exerciseID: Binding<UUID?>,
                               onShowInfo: @escaping (Exercise) -> Void, onShowRestSettings: @escaping (UUID) -> Void,
                               onReplace: @escaping (UUID) -> Void) -> some View   // confirmationDialog: Form & instructions, Rest timer, Replace, Superset, Move up/down, Remove
}
```
The keypad keeps its text buffer locally and dispatches `setWeight` / `setReps` after every key; "Log set" on the reps field dispatches `logSet`.

**Area "hub"** (`Screens/`, `StrengthAppEnvironment.swift`, `Components/WorkoutInProgressBar.swift`):
```swift
@MainActor public final class StrengthAppEnvironment: ObservableObject {
    public let persistence: FileStrengthPersistence
    public let store: StrengthStore
    public let controller: WorkoutController
    public let services: PulseServices
    @Published public var watchStatus: WatchStatus
    public static let shared: StrengthAppEnvironment            // live(); created lazily on the main actor; also registers the WorkoutCommandBus handler
    public static func live(seedDemoData: Bool = true) -> StrengthAppEnvironment   // app-group persistence, fallback Application Support/PulseStrength; installs services; restoreFromDisk()
    public static func preview(withActiveWorkout: Bool = false) -> StrengthAppEnvironment  // temporary persistence + sample data, no services
}
public struct StrengthHubView: View { public init(environment: StrengthAppEnvironment, onStart: @escaping (WorkoutTemplate?) -> Void, onResume: @escaping () -> Void) }
public struct ExerciseDetailView: View { public init(exercise: Exercise, store: StrengthStore) }
public struct WorkoutSummaryView: View { public init(workout: CompletedWorkout, onDone: @escaping () -> Void) }
public struct WorkoutInProgressBar: View { public init(presentation: ActiveWorkoutPresentation, onResume: @escaping () -> Void) }
public struct PulseStrengthRootView: View { public init(environment: StrengthAppEnvironment) }   // NavigationStack hub; fullScreenCover ActiveWorkoutView; summary cover; onOpenURL for pulse-strength://workout
```

**Area "services"** (`Services/`):
```swift
@MainActor public final class PulseServices {
    public init(controller: WorkoutController)       // creates the four effects below and registers them with controller.addEffect
    public func requestPermissions() async            // notifications + HealthKit authorisation
    public var onWatchStatusChange: ((WatchStatus) -> Void)?   // fed by PhoneWatchBridge (reachability) and HealthKitWorkoutWriter (denied); healthDenied wins
    public private(set) var watchStatus: WatchStatus
}
```
* `LiveActivityManager: WorkoutSideEffect` starts the Live Activity on `workoutStarted`, updates it on every change (content = `SnapshotBuilder.make(from:now:)`, `staleDate` = `restEndsAt` while an unpaused rest runs, else nil; throttle
  heart-rate-only updates to one per 10 s; never update from `workoutChanged` caused by `.updateHeartRate` more often), ends it on `workoutEnded`; re-attaches to an existing activity after relaunch.
* `RestNotificationScheduler` schedules a time-sensitive local notification at the rest end (identifier `StrengthConfig.restNotificationID`), cancels it on skip / pause / finish / discard, only when `settings.alertWhenRestEnds`; foreground presentation suppressed.
* `HealthKitWorkoutWriter` writes an `HKWorkout` (traditional strength training) with `HKWorkoutBuilder` when a workout is finished and `state.usedWatch == false`; with the Watch recording, the Watch saves it.
* `PhoneWatchBridge` (WCSession): pushes `SyncEnvelope` after every state change (`updateApplicationContext`, plus `sendMessage` when reachable), answers `.requestState`, turns inbound `.command` / `.heartRate` / `.watchSession` messages into controller calls, launches the Watch app with `HKHealthStore.startWatchApp(with:)` when a workout starts and the Watch app is installed.

### 5.4 Live Activity, Dynamic Island, App Intents

Why the intents are not in the package: a `LiveActivityIntent` is executed in the app's process but is referenced by the widget extension; Apple's
documented pattern is to compile the intent source into both targets, and intents inside a Swift package additionally need `AppIntentsPackage`
plumbing that only exists from iOS 17.4. So the intents and the widget views live in `Apps/Shared/` and are added to the Xcode targets as sources.

`PulseStrengthActivity` (package, iOS, linked by the app AND the widget extension):
```swift
public struct WorkoutActivityAttributes: ActivityAttributes { public typealias ContentState = WorkoutSnapshot; public var workoutID: UUID; public var workoutName: String; public init(workoutID: UUID, workoutName: String) }
public final class WorkoutCommandBus: @unchecked Sendable { public static let shared: WorkoutCommandBus
    public func install(_ handler: @escaping @Sendable (WorkoutAction, ActionOrigin) async -> Void)
    public func perform(_ action: WorkoutAction, origin: ActionOrigin) async    // waits up to 3 s for a handler (app launched in the background by an intent)
}
```
`Apps/Shared/Intents/StrengthIntents.swift` (compiled into app and extension; `import AppIntents`, `import PulseStrengthActivity`, `import PulseStrengthCore`):
`LogSetIntent(exerciseID: String, setID: String)`, `NudgeSetIntent(weightSteps: Int, repsSteps: Int)`, `AdjustRestIntent(seconds: Int)`, `SkipRestIntent()`,
all `LiveActivityIntent` with `@Parameter` properties, a no-argument `init()`, a convenience init with the arguments, `static var title`, `openAppWhenRun = false`.
`perform()` forwards to `WorkoutCommandBus.shared.perform(action, origin: .liveActivity)` (String ids parsed with `UUID(uuidString:)`, invalid -> no-op) and returns `.result()`.

`Apps/Shared/LiveActivity/` (widget extension sources; imports ActivityKit, WidgetKit, SwiftUI, AppIntents, the package modules): `public struct WorkoutLiveActivity: Widget` using
`ActivityConfiguration(for: WorkoutActivityAttributes.self)`; the extension's `@main WidgetBundle` only lists it. Lock Screen view and Dynamic Island (compact leading/trailing, minimal,
expanded leading/trailing/center/bottom) follow `LockScreen.dc.html` and `DynamicIsland.dc.html`: phases `.logging` (set label, kg and reps with - / + `Button(intent: NudgeSetIntent(...))`,
"Log set" `Button(intent: LogSetIntent(...))`), `.resting` (countdown `Text(timerInterval:countsDown:)`, ring via `ProgressView(timerInterval:countsDown:)`, "Next" text, -15 s / +15 s / Skip intents),
`.restOver` ("Go" + Log set), `.complete` ("All sets logged", tap opens the app). `widgetURL(StrengthConfig.workoutURL)`. Paused: frozen values (`elapsedWhenPaused`, `restFrozenRemaining`) and a
"Paused" label. Always dark styling. A widget view cannot tick on its own, so the rest end is handled with the staleness date: `LiveActivityManager` (5.3) sets
`ActivityContent.staleDate = restEndsAt` while a rest runs and the views treat `context.isStale && phase == .resting` as `.restOver` ("Go" + Log set); the countdown text stops at 0:00 meanwhile.

### 5.5 Apple Watch (`PulseStrengthWatchUI`)

Files: `WatchEnvironment.swift`, `WatchConnectivityClient.swift`, `WatchWorkoutSession.swift`, `WatchTheme.swift`, `WatchRootView.swift`, `LogSetPage.swift`, `RestPage.swift`,
`MetricsPage.swift`, `WatchIdleView.swift`, `WatchSummaryView.swift`, `WatchAppDelegate.swift`.
```swift
@MainActor public final class WatchEnvironment: ObservableObject { public let controller: WorkoutController; public static let shared: WatchEnvironment; public init() }   // mirror role, WatchConnectivityClient + WatchWorkoutSession registered as effects
public struct WatchRootView: View { public init(environment: WatchEnvironment) }
public final class WatchAppDelegate: NSObject, WKApplicationDelegate { public func handle(_ workoutConfiguration: HKWorkoutConfiguration) }   // starts the session when the phone launches the Watch app
```
Screens follow `Watch.dc.html` (three screens): vertical-page `TabView` (`.verticalPage`): Log set (exercise name + time, "Set 4 of 5", weight with - / + and Digital Crown,
reps with - / +, green "Log set"), Rest (draining ring + countdown, next set text, -15 / skip / +15, auto-selected while resting, haptic when over), Metrics (elapsed in yellow, heart
rate with beat, volume, sets). Idle state ("Start a workout on your iPhone"), summary at the end. Actions go through `controller.send(..., origin: .watch)`; the target set ids come from
`controller.snapshot(now:)`; crown uses absolute `setWeight` after idle, buttons use `nudgeNextSet`. `WatchEnvironment` also publishes `session: WatchWorkoutSession` (`@Published isRecording`, `authorizationDenied`), `isPhoneReachable`, `endedSummary: WatchEndedSummary?` (+ `dismissSummary()`) and
`requestStateFromPhone()`; `public struct WatchEndedSummary: Equatable { workoutName, durationText, volumeText, setsText, averageHeartRateText }` is built from the last known state when the workout ends.
`WatchWorkoutSession` runs `HKWorkoutSession` +
`HKLiveWorkoutBuilder` (`.traditionalStrengthTraining`, indoor), streams heart rate to the phone (`SyncMessage.heartRate`, at most every 5 s), reports `.watchSession(isRecording:)`, ends and saves
the workout when the phone ends the workout.

### 5.6 Project, CI, docs

`project.yml` (XcodeGen) defines targets PulseStrength (iOS app, embeds the widget extension and the Watch app; sources `Apps/PulseStrength` + `Apps/Shared/Intents`), PulseStrengthWidgets
(app-extension; sources `Apps/PulseStrengthWidgets` + `Apps/Shared/Intents` + `Apps/Shared/LiveActivity`), PulseStrengthWatch (watchOS app) with the package products as dependencies, entitlements and Info.plist properties from 5.1, schemes. `Apps/*` contains the `@main` entry points, plists, entitlements,
asset catalogs (AccentColor, placeholder AppIcon). `.github/workflows/strength-ios.yml`: Linux job (`swift test`, with and without `-Xswiftc -DPULSE_COMBINE_SHIM`) and a macOS job
(`swift test` of the package on macOS, `xcodegen generate`, `xcodebuild build` of the iOS and watchOS schemes for the simulators with `CODE_SIGNING_ALLOWED=NO`). `README.md`
documents setup, what is verified and what is not, integration with the Pulse app (replace `RecoveryProvider`, the App Group id, the bundle ids, the media source), and the
public-domain attribution of the form photos (Free Exercise DB, Unlicense).
