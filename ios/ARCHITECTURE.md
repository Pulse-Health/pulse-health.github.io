# Pulse Strength: architecture and build contract

The strength-workout feature of Pulse for iPhone, Apple Watch, the Lock Screen (Live Activity) and
the Dynamic Island. It implements the design canvas "Pulse Gym & Strength"
(<https://claude.ai/artifact/M24e88tBek3xkMcwaPAepp>). The design source files (the HTML boards of that canvas, which are not part of this repository)
were the reference while building: `Active.dc.html` for behaviour (its `<script>` is the logic that the reducer and presenter port), the markup for
layout, sizes, colours and copy.

The Pulse app repository is not available to this build, so the feature is a self-contained Swift
package (`PulseStrengthKit`) plus a host Xcode project (XcodeGen spec) that runs it standalone. The
integration seams are protocols and plain closures (see "Integration with the Pulse app").

## 1. Repository layout (`ios/`)

```
ios/
  ARCHITECTURE.md            this file
  README.md                  setup, capabilities, verification status
  project.yml                XcodeGen spec: app, widget extension, watch app, visual-test targets, schemes
  PulseStrength.xcodeproj/   generated from project.yml and committed (open it in Xcode; regenerate only after editing project.yml)
  Config/Signing.xcconfig    DEVELOPMENT_TEAM and PULSE_APP_BUNDLE_ID (optional git-ignored Signing.local.xcconfig overrides them)
  Packages/PulseStrengthKit/
    Package.swift
    Sources/
      PulseStrengthCore/     platform neutral (Foundation only): models, reducer, presenter, stores, sync
      PulseStrengthActivity/ iOS: ActivityAttributes + command bus (shared by app and widget)
      PulseStrengthIOS/      iOS: SwiftUI screens, services (Live Activity manager, notifications, HealthKit, Watch bridge)
        Resources/ExerciseMedia/*.jpg   form demo frames "<mediaKey>-a.jpg" / "-b.jpg" (placeholders of unverified provenance, see README "Exercise photos")
      PulseStrengthWatchUI/  watchOS: SwiftUI screens, workout session, WatchConnectivity client
    Tests/PulseStrengthCoreTests/
  Apps/
    PulseStrength/           iOS host app (entry point, Info.plist, entitlements, assets)
    PulseStrengthWidgets/    widget extension (WidgetBundle entry point, Info.plist)
    Shared/Intents/          App Intents (LiveActivityIntent) compiled into BOTH the app and the widget extension
    Shared/LiveActivity/     Lock Screen + Dynamic Island views, compiled into the widget extension
    PulseStrengthWatch/      watchOS app (entry point, Info.plist, entitlements, assets)
    PulseStrengthUITests/            UI test: walks the iPhone app in the simulator (screenshots)
    PulseStrengthLiveSnapshotTests/  draws the Lock Screen and Dynamic Island views into PNG files
    PulseStrengthWatchSnapshotTests/ draws the Watch pages into PNG files
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
`SideEffects.swift`. Read them first. Every public struct of `Presentation.swift` (`ActiveWorkoutPresentation` and its nested `Segment`, `Header`,
`Navigator`, `SetRow`, `Card`, `Dock`, `Totals`, `FinishCheck`), `Snapshot.swift` (`WorkoutSnapshot`) and `Completed.swift` (including `ExerciseSession`,
`ExerciseRecordRow`, `ExerciseHistory`) has an explicit `public init` with every stored property as a parameter (labels in declaration order; an
optional property defaults to nil), so code outside the module (UI fixtures, snapshot tests) can construct them; a Swift memberwise initializer would
be internal. Public API to implement, by file:

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
    public static let maximumWeightKg: Double               // 1_000_000 (rule 3)
    public static let maximumRestSeconds: Int               // 3_600 (rule 7)
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
   A set becoming done: `lastLogged = SetRef`; rest seconds = 0 when the exercise's `restSeconds` is 0 (the timer is Off: no rest after a
   set of ANY type, warm-ups included), else warm-up ? `max(30, round(rest*0.4/5)*5)` : the
   exercise's `restSeconds`. Superset: take the indexes of exercises sharing the (non-nil) `supersetGroup`; if the
   exercise is not the last of the group, `currentIndex = index + 1` and no rest starts; otherwise
   `currentIndex = first index of the group` and rest starts. Not in a superset: `currentIndex` unchanged.
   Starting rest: `settings.autoStartRest && seconds > 0` -> `rest = RestState(endsAt: now + seconds, totalSeconds: seconds,
   frozenRemaining: paused ? seconds : nil)`, otherwise `rest = nil`. `logSet` on a done set is a no-op.
   `logNextSet` first moves `currentIndex` to the exercise of `WorkoutTargets.nextPending`, then logs that set.
3. `setWeight` clamps to 0...`maximumWeightKg` (1,000,000 kg; the keypad's six characters stay below it) and rounds to 0.01; NaN and
   +infinity are ignored (not representable). `setReps` clamps to 0...999; neither changes `isDone`.
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
   sets and default rest; into an empty workout it sets `currentIndex = 0`. `setRest` sets `restSeconds`, clamped to
   0...`maximumRestSeconds` (3,600 s; the rest presets stop at 5:00); default rests are clamped the same way.
   `WorkoutTemplate.estimatedMinutes` counts a rest outside that range (a template that did not come through the reducer) as the nearest bound,
   and follows rule 2: 45 s of work per set plus the rest after it (warm-up rule as above), nothing for an exercise whose rest is 0.
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
  set that beats it; no PR when `previousBestE1RM == 0`. `estimated1RM` = rounded e1RM for such sets, as a whole number that clamps at
  1,000,000,000 (the presenter never traps on a state the reducer did not produce); an estimate that is not finite counts as 0. `rirText` = "RIR n" / "RIR 4+" only
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
    public static let pendingLifetime: TimeInterval = 15      // how long the Watch keeps showing an edit the phone has not acknowledged
    public static let queuedPendingLifetime: TimeInterval = 7200   // the same for a command the transport holds in its guaranteed queue (transferUserInfo)
    public static let staleEnvelopeWindow: TimeInterval = 120 // an envelope of ANOTHER workout sent up to this long before the newest one applied is late/replayed
    public static let lateCommandWindow: TimeInterval = 120   // a command this late still acts at its issuedAt (the time of the tap)
    public static let pendingCapacity = 64                    // unacknowledged edits the Watch keeps (the oldest is forgotten beyond that)
    public static let acknowledgementWindow = 64              // command ids every envelope acknowledges (the most recent)
    public static let acknowledgedMemory = 256                // command ids the phone remembers
    /// First-generation rule: no local state, a different workout id, or a STRICTLY higher revision. Kept for compatibility; the mirror
    /// no longer uses it (an optimistic Watch raises its local revision above the phone's and would ignore every envelope).
    public static func isNewer(_ incoming: WorkoutState, than local: WorkoutState?) -> Bool
    /// The mirror's rule: true for another workout (or none shown, or no phone revision known), else `incoming.revision >= authoritativeRevision`.
    public static func shouldAdopt(incoming: WorkoutState, authoritativeRevision: Int?, currentWorkoutID: UUID?) -> Bool
    /// Pending edits minus the acknowledged ones and those older than their lifetime (`pendingLifetime`; `queuedPendingLifetime` for the ids in `queued`).
    public static func remainingPending(_ pending: [RemoteCommand], acknowledged: [UUID], now: Date, queued: Set<UUID> = []) -> [RemoteCommand]
    public static func lifetime(of command: RemoteCommand, queued: Set<UUID>) -> TimeInterval
    /// The phone's state with the pending edits replayed on top, in order, each with `now: command.issuedAt`.
    public static func rebase(_ authoritative: WorkoutState, replaying pending: [RemoteCommand]) -> WorkoutState
}
public struct RemoteCommand { id: UUID; action: WorkoutAction; origin: ActionOrigin; issuedAt: Date; workoutID: UUID?; senderID: UUID?; sequence: Int? }   // Watch -> phone; workoutID, senderID, sequence nil in old payloads
public struct SyncEnvelope { state: WorkoutState?; endedWorkoutID: UUID?; sentAt: Date; ackedCommandIDs: [UUID]; discarded: Bool?; isFromLegacyPhone: Bool }   // phone -> Watch; ackedCommandIDs [] in old payloads, and isFromLegacyPhone (not on the wire, not in ==) true when the key was missing; discarded (decodeIfPresent, nil in old payloads) says how endedWorkoutID ended: true = thrown away (Discard Workout, or a finish with no logged set), false = finished and recorded, nil = not said
public protocol WorkoutSideEffect { /* workoutStarted, workoutChanged, workoutEnded as before, plus: */
    func commandIssued(_ command: RemoteCommand)    // default: nothing. The mirror made `command` of an action taken on the Watch (see "Sync protocol")
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
    public func loadAcknowledgedCommands() -> [UUID];      public func saveAcknowledgedCommands(_ v: [UUID]) throws   // acknowledged-commands.json, the last 256 ids, oldest first
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
    @discardableResult
    public func record(_ completed: CompletedWorkout, updateTemplate: WorkoutTemplate?) -> Result<Void, Error>   // history, bests, template.lastPerformed, persists
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
    public func receive(_ command: RemoteCommand)                    // authority: acknowledge the id, dedupe (SeenCommands), then send(action, origin: command.origin)
    public func receive(_ envelope: SyncEnvelope)                    // mirror: adopt per SyncReconciler.shouldAdopt, replay unacknowledged edits; nil state = ended
    public func makeEnvelope(now: Date) -> SyncEnvelope              // authority: state (or nil + last ended id) + the last 64 acknowledged command ids
    public var pendingCommands: [RemoteCommand] { get }              // mirror: edits shown on top of the phone's state that are not acknowledged yet
    public var authoritativeRevision: Int? { get }                   // mirror: revision of the last phone state adopted for the running workout
    public var lastEndDiscarded: Bool { get }                        // how the workout that ended last ended (true = thrown away); set before the effects' workoutEnded run, which on a mirror always get completed == nil
    public var lastEndNoticeSentAt: Date? { get }                    // mirror: when the phone sent the envelope that ended that workout (nil: it ended on this side); set before workoutEnded too
    public var nextPendingExpiry: Date? { get }                      // mirror: when the oldest unacknowledged edit stops being shown (nil: none)
    @discardableResult public func expirePending() -> Bool           // mirror: drop the edits past their lifetime, show the phone's last state + the rest; true when one was dropped
    public func markQueued(commandID: UUID)                          // mirror: the transport queued this command (transferUserInfo): keep its edit for queuedPendingLifetime
    public func presentation(now: Date) -> ActiveWorkoutPresentation?
    public func snapshot(now: Date) -> WorkoutSnapshot?
    public func templateDiff() -> TemplateDiff
    @discardableResult public func finish(updateTemplate: Bool) -> CompletedWorkout?   // builds summary, records it, clears state, notifies effects
    public func discard()
}
```
Roles: the authority (phone) persists after every change and `receive(command)` ends in `send(action, origin: command.origin)`; the mirror (Watch)
never persists. `finish` also ends a mirror locally. Both are implemented by `WorkoutEngine`; `WorkoutController` forwards to it.

#### Sync protocol (optimistic edits, acknowledgements)

Delivery between phone and Watch is unreliable: a command can arrive twice (`sendMessage` AND `transferUserInfo`), late, out of order or never; envelopes
can arrive out of order or be coalesced by `updateApplicationContext`. The Watch applies its own taps at once and the phone's envelopes acknowledge them.

*Authority (phone).*
* `receive(command)` records the command id as acknowledged in EVERY case: applied, duplicate (`SeenCommands`, 256 ids, drops it), changed nothing, or no
  workout running. A repeated id moves to the most recent position. A command whose `workoutID` is not the running workout is not applied (a late command
  of an earlier workout cannot act on the next one; an action that names exercise or set ids is a no-op in any other workout anyway, an action without ids
  such as `logNextSet` or `skipRest` is not, hence the `workoutID`); a sender that names none (older Watch app) is applied to whatever runs.
* The acknowledged ids are saved to `acknowledged-commands.json` (the last 256, written after the state was saved) and read back by `restore()`: a command
  redelivered after a phone relaunch is dropped as a duplicate, and the first envelope after the relaunch still acknowledges what the phone applied before
  it. A crash between the two writes can only apply a command again, never lose one.
* Order of absolute edits. The Watch's two channels (`sendMessage`, `transferUserInfo`) have no common order, so the mirror numbers its commands
  (`senderID` = one per Watch launch, `sequence` 1, 2, 3 ...). For each value an absolute action sets (`setWeight`, `setReps`, `setSetType`, `setRIR` per
  set; `setNote`, `setRest` per exercise) the phone remembers the newest command applied (128 values) and drops a command of the SAME sender with a lower
  sequence (acknowledged, not applied): the user's last tap wins. A command without numbers, or from another launch of the Watch, is applied in arrival order.
  Cumulative actions (`nudgeNextSet`, `adjustRest`, `logNextSet`, `toggleSet`) are not ordered.
* Late commands. A command that arrives up to `lateCommandWindow` (120 s) after its `issuedAt` is reduced at `issuedAt` (the rest timer starts at the tap,
  as the Watch showed it, and Watch and phone agree after the acknowledgement); a stamp further in the past, or in the future, is not trusted and acts at the
  time of delivery.
* `makeEnvelope(now:)` carries the current state, or no state plus `endedWorkoutID` (the workout that ended last, nil if none ended since launch), and
  `ackedCommandIDs` = the last 64 acknowledged ids, oldest first. The bridge pushes it after every change (except heart-rate samples) AND after every
  inbound command, even when the state did not change: that envelope is the acknowledgement of a duplicate or a no-op.

*Mirror (Watch).*
* `send(action, origin: .watch)` applies the reducer locally, then creates ONE `RemoteCommand(action:origin: .watch, issuedAt: clock, workoutID: shown
  workout, senderID, sequence)`, appends it to `pendingCommands` (at most 64) and calls `commandIssued` on the effects (after `workoutChanged`);
  `WatchConnectivityClient` sends it from there. No command for `.updateHeartRate` (its own message), for another origin or for an action that changes
  nothing. The commands are announced in the order they were made also when an effect edits from inside `workoutChanged` or `commandIssued` (a nested
  `send` is announced after the one in progress).
* `receive(envelope)` adopts when `SyncReconciler.shouldAdopt`: the workout id differs, or `envelope.state.revision >= authoritativeRevision` (the revision
  of the last ADOPTED phone state, not of the optimistically edited local copy). A lower revision is stale and ignored; an equal one is adopted because it
  may only carry acknowledgements, but nothing is published when the resulting state is identical. On adoption: pending edits whose id is in
  `ackedCommandIDs`, and those older than their lifetime of the Watch clock, are removed; the phone's state becomes the base; the remaining pending edits are
  replayed on it in order with the reducer, each at its own `issuedAt`; `authoritativeRevision` is updated; the state is published. The Watch therefore
  always shows `phone's truth + its unacknowledged taps`: no flicker when an acknowledgement is late, a lost tap disappears after 15 s, a tap whose
  targets the phone has deleted does nothing (the phone wins), a tap the phone found to be a no-op is dropped when it is acknowledged.
* Lifetime of an unacknowledged edit. 15 s (`pendingLifetime`) is a loss detector for a command sent with `sendMessage`. A command the client put into the
  `transferUserInfo` queue (the phone is out of reach; the client reports it with `markQueued(commandID:)`) is delivered whenever the phone is back, so its edit
  stays shown for `queuedPendingLifetime` (2 h, longer than a workout): the sets logged while the phone is away do not vanish after 15 s, and do not blink out
  when the first envelope after the outage arrives. The lifetime is also enforced WITHOUT an envelope: a command that is really lost (the phone crashed
  handling it, the payload was undecodable) makes the phone change nothing and send nothing, so the client runs a timer on `nextPendingExpiry` that calls
  `expirePending()` (drops the edits past their lifetime and shows the phone's last state with the rest on top; keeps the Watch's own heart rate) and then
  asks the phone for its state, in case the dropped command did reach it and only its acknowledgement was lost.
* Ordering of envelopes. `newestSentAt` is the newest `sentAt` of any phone envelope applied (state or end notice); it survives the end of a workout. An
  envelope for ANOTHER workout than the one shown is ignored when it was sent up to `staleEnvelopeWindow` (120 s) before it: a late or replayed message of an
  earlier workout (a coalesced end notice, `requestState` re-reading a lagging `receivedApplicationContext`) cannot bring a finished workout back. Older ones
  are adopted, so a phone clock that was set back far cannot lock the Watch out of new workouts. The remembered end of a workout (8 workouts) carries the
  `sentAt` of the phone's end notice: a state of that workout sent before (or at) the notice is a late message and ignored; a state sent after it is the
  phone restoring the workout (the kept active-workout file, below) and is adopted again (`workoutStarted`). A workout the Watch ended itself
  stays ended whatever arrives.
* A phone build without acknowledgements (an envelope whose `ackedCommandIDs` key is missing, `isFromLegacyPhone`) will never acknowledge anything: the Watch
  drops its pending edits on adopting such an envelope, so the phone's state wins as it did before acknowledgements existed. Without this a new Watch app
  would show its own non-idempotent taps (nudge, rest adjustment) twice for 15 s.
* `receive(envelope)` NEVER calls `workoutChanged` (no echo, so no command); it calls `workoutStarted(state)` when the envelope is for another workout id
  than the one shown, and `workoutEnded(previous, completed: nil)` when the workout ends.
* A restarted Watch has no state and no revision: it adopts the first envelope it receives (e.g. the answer to `requestState`), later ones correct it.

*Envelope without a state* (`endedWorkoutID` = the workout the phone says ended):

| Watch shows | `endedWorkoutID` | effect |
|---|---|---|
| nothing | nil | nothing happens; no id is remembered (it must not block the next state of any workout) |
| nothing | X | X is remembered: a late state of X (sent before the notice) is ignored |
| W | W | W ends (`workoutEnded`) and is remembered |
| W | X ≠ W | W keeps running and X is remembered (a late notice of an earlier workout); unless the notice was sent after the last state adopted for W, then W is a ghost the Watch never heard ended and ends |
| W | nil | the legacy "no workout" notice: W ends, but its id is NOT remembered, so the phone's next state for W is adopted again (the notice named nobody); unless it was sent BEFORE the state last adopted for W (a stale application context the Watch re-read on a wrist raise, after W had been adopted from a message), then it is ignored |

*How a workout ended.* The phone says it with `discarded` on the end notice (`makeEnvelope` writes it whenever it names `endedWorkoutID`): `discard()` and a
`finish` with no logged set (the engine discards that) are `true`, a recorded finish is `false`. The mirror stores the outcome in `lastEndDiscarded` before it
tells the effects. A notice that does not say (an older phone build, the legacy "no workout" notice, a ghost workout whose own end the Watch never heard: the
flag then belongs to another workout) counts as a discard when the Watch's copy has no logged set, the phone's own rule for a finish. The Watch uses it to save
the Health workout (`false`) or throw it away (`true`, no summary page). `lastEndNoticeSentAt` says WHEN the phone ended it (the `sentAt` of the envelope that ended
the workout here, the legacy "no workout" notice and a ghost's revealing notice included; an ignored notice sets nothing): a Watch that learns of the end late (the phone
finished while the link was down) ends its Health workout then (`SyncReconciler.healthWorkoutEnd`) and builds its summary for that time. An end notice that reaches a Watch
with NO workout ends nothing in the engine and tells no effect (it only remembers the id); the Watch environment sees it through the client's `onEnvelope` hook and decides about
a Health session nobody claimed with `SyncReconciler.endNotice(sentAt:settlesSessionStartedAt:)` (5.5).

Known limits: a command redelivered after more than 256 later commands would run again (`SeenCommands` and the saved acknowledgements hold 256 ids); a
command that reaches the phone after the Watch dropped it (15 s, or the queued lifetime) is still applied and shows up with the next envelope; cumulative
edits (`nudgeNextSet`, `adjustRest`) that reach the phone out of order are applied in arrival order, and a command of an earlier launch of the Watch app is not
ordered against one of the next launch; the ordering rules use the phone's clock for `sentAt` (it is assumed not to jump back by more than 120 s) and the
Watch's clock for `issuedAt`; a `sendMessage` that fails after the client handed it over moves to the system queue on its own and is not reported as queued, so its
edit keeps the 15 s lifetime (the set can blink out and come back when the phone finally gets the command); `PhoneWatchBridge` hands each inbound message to the main
actor in a task of its own, which does not promise first-in-first-out; a phone that restores a LOWER revision than the Watch adopted (the active-workout file could not be written) is not followed
until its revision catches up or the Watch restarts; a jump from workout W1 to W2 on the Watch (the end notice was lost) does not call `workoutEnded(W1)` (the Watch environment notices the new id in `workoutStarted` and
ends the Health session of W1 itself, see 5.5).

`record` always updates the store in memory; its result is `.failure(error)` when the workout could not be written to the history file (the
only place its sets are kept: the personal bests are re-read from the history, so a failed write of the bests or the template is only
reported through `StrengthDataModel.lastPersistenceError`). `finish` then still returns the completed workout and ends the workout, but it
does NOT delete `active-workout.json`: that file stays the last saved copy of the sets and the engine's `lastPersistenceError` carries the
error. The next launch restores the workout (`restoreFromDisk`); finishing it again records it by its id, so it is never saved twice. Starting
another workout replaces the kept file; the history is rewritten in full by the next successful save. A normal finish deletes the file.

`SampleData`: `public enum SampleData { static func templates() -> [WorkoutTemplate]  // "Upper A · Push" (the 6 exercises of the design with
the same sets), "Lower A · Quads", "Upper B · Pull"; static func history(now: Date) -> [CompletedWorkout]; static func personalBests(now:) }`
used for `seedDemoData` and SwiftUI previews. Make the sample data consistent: today is the `now` argument; "Upper A · Push" was last done
5 days ago (the Strength hub says so), bench sessions exist 5 days ago (W 50×8, W 70×5, 80×6, 80×6, 80×5), 10 days ago (…, 82.5×5, 85×5 = personal
record, estimated 1RM 99), 15 days ago (W 50×8, 77.5×6 ×3); "Lower A · Quads" 7 days ago; personal best bench e1RM 99 (85 kg × 5, 10 days ago).
`seedDemoData` also seeds templates and history only when the store is empty. The "Upper A · Push" template is the design's workout: bench
(warm-up 50×8, warm-up 70×5, 82.5×6, 82.5×6, 85×6, rest 150), incline 3×28×10 (rest 90), ohp 3×45×8 (rest 120), lateral 3×8×15 and pushdown
3×30×12 (both rest 60, superset A), crossover 3×15×12 (rest 60).

### 3.5 `BodyWeight.swift` (area: body weight and the weigh-in reminder)

The user's body weight, kept in kilograms like every weight of the feature, and the reminder that asks for regular updates. Foundation only, tested on Linux
(`BodyWeightTests.swift`). Body weight is separate from the loads of the logged sets.

```swift
public struct BodyWeightEntry: Codable, Hashable, Sendable, Identifiable { public var id: UUID; public var date: Date; public var kg: Double }
public enum BodyWeightRules {
    public static let minimumKg: Double, maximumKg: Double               // 20 ... 500
    public static func normalised(_ kg: Double) -> Double?              // rounded to 0.1; nil for NaN / infinite / out of range
    public static func parse(_ text: String) -> Double?                 // "82.5", "82,5", " 82.5 kg "; nil for anything else
}
public enum WeighInInterval: String, Codable, CaseIterable, Identifiable { case weekly, everyTwoWeeks, monthly }
public struct WeighInPreferences: Codable, Hashable, Sendable {          // off by default; a missing key in the file reads as its default
    public var isEnabled: Bool; public var interval: WeighInInterval; public var hour: Int; public var minute: Int; public var enabledAt: Date?
    public mutating func setEnabled(_ enabled: Bool, now: Date)          // turning on from off remembers `now` in enabledAt
}
public enum WeighInSchedule {                                            // pure: the caller passes the clock and the calendar
    public static let maximumReminders = 3
    public static func dueDate(lastWeighIn: Date?, preferences: WeighInPreferences, calendar: Calendar) -> Date?
    public static func isDue(lastWeighIn: Date?, preferences: WeighInPreferences, now: Date, calendar: Calendar) -> Bool
    public static func reminders(lastWeighIn: Date?, preferences: WeighInPreferences, now: Date, calendar: Calendar, count: Int) -> [Date]
}
```
* `StrengthData` gains `bodyWeights` (newest first) and `weighIn`; `StrengthDataModel` / `StrengthStore` gain `recordBodyWeight(kg:date:)` (nil and nothing saved for an implausible
  weight), `deleteBodyWeight(id:)`, `setWeighInPreferences(_:)`, `latestBodyWeight`, `isWeighInDue(now:)`. They are saved in `body-weights.json` and `weigh-in-preferences.json`
  (an unreadable file reads as empty / the defaults). The demo seed does not touch them.
* The reminder is **rolling**: it counts from the latest weigh-in (before the first one, from `enabledAt`) and is due one interval later at the chosen time of day, so logging a
  weight moves the next reminder out. Reminder dates are `due`, `due + 1 interval`, ... (each counted from `due`, so a month-end does not drift), only those after `now`, at most three.
  The clock time survives a daylight-saving change (calendar arithmetic).

**Apple Health (phase 2).** `BodyWeightEntry` has `source` (`.app`, entered here / `.health`, read from Health; a file without the key reads as `.app`) and `healthSampleID`.
`WeighInPreferences.syncWithHealth` (off by default) turns the exchange on. `StrengthData.mergeHealthBodyWeights(_:)` adds `HealthBodyWeightSample`s that are new: a sample is skipped when
its `sampleID` was already read, when its `externalID` (`HKMetadataKeyExternalUUID`) is the id of an entry that is here (the app saved it to Health itself), or when the weight is not
plausible. Entries read from Health are read-only (`deleteBodyWeight` returns false for them: the app cannot delete other apps' samples, and the next read would bring them back); an
imported weight also counts as a weigh-in for the reminder. `StrengthStore` reports the user's own weigh-ins through `onBodyWeightSaved` / `onBodyWeightRemoved` (not the imported ones)
and `StrengthStore.importHealthBodyWeights(_:)`. iOS: `BodyWeightHealthSync` (internal, live environment only) requests `bodyMass` share + read when the user turns the sync on (not at
launch), saves each new weigh-in as an `HKQuantitySample` tagged with the entry id, deletes that sample when the entry is deleted, and reads the newest 400 body-mass samples
(`HKSampleQueryDescriptor`) at launch, when the app becomes active and when the sync is turned on. HealthKit hides whether READ access was refused; Settings only reports a refused save.
Info.plist: both Health usage strings mention body weight.

**Using the weight (phase 3).** Record rows of the exercise detail ("Personal Records"), added by `StrengthData.history(for:now:)` only when there is a weigh-in:
barbell lifts get "Relative strength" (the best estimated 1RM divided by the body weight in force on the day it was set, "1.5× bodyweight"); push-up, chest dip and pull-up
(`BodyweightLoad.factor`: 0.64, 0.95, 1.0, rough estimates) get "Best session load (est.)" (working reps x share x the body weight in force on the session day). `bodyWeightKg(at:)` is the
latest weigh-in on or before the date, or the first one ever for earlier dates. Workout volume, personal bests and the summary are unchanged (bodyweight exercises still count 0 kg there).

iOS (`PulseStrengthIOS`): `WeightReminderScheduler` (internal) subscribes to the store and keeps up to three non-repeating `UNCalendarNotificationTrigger` requests
(`StrengthConfig.weightReminderIDPrefix` + ".0", ".1", ".2") in step with it; it is created by `StrengthAppEnvironment.live()` only (previews and UI tests have none: no
notifications, no prompts) and refreshed when the app becomes active. The weigh-in code does not ask for the notification permission at launch (the launch request of `PulseServices.requestPermissions()` is for the rest alert and also
covers the reminder); turning the reminder on asks again if the user has not decided yet (`StrengthAppEnvironment.requestWeightReminderPermission()`). The notification carries a "Log weight" text-input action (category
`weightReminderCategoryID`): a typed weight is recorded without opening the app, anything that does not parse opens the entry instead. Tapping the notification, or opening
`pulse-strength://weight`, sets `StrengthAppEnvironment.showsWeightEntry`, which `PulseStrengthRootView` presents as `BodyWeightEntrySheet` (not while a workout is in progress).
`UNUserNotificationCenter` has one delegate, so `StrengthNotificationDelegate.shared` serves the rest alert and the weigh-in reminder. Screens: `StrengthSettingsView` (hub "More" menu >
Settings: weight, history with swipe to delete, reminder switch / frequency / time, next reminder date), `BodyWeightEntrySheet`, and the "Time to update your weight" card at the top of the hub
while the reminder is on and a weigh-in is due (the in-app half of the reminder, for users who refused notifications).

### 3.6 Plans, rep ranges, entry notes, plan import (`WorkoutPlan.swift`, `Models.swift`, `StrengthData.swift`, `WorkoutFactory.swift`)

A **plan** is a rotation of saved templates, deliberately not a calendar: nothing in it knows a weekday.

```swift
public struct WorkoutPlan: Identifiable, Codable, Hashable, Sendable {
    var id: UUID; var name: String
    var templateIDs: [UUID]      // rotation order; an id without a template is passed over
    var nextIndex: Int           // index into templateIDs of the workout that is next
    var daysPerWeek: Int?        // only a target the hub shows next to "done in the last 7 days"
    var isActive: Bool           // at most one plan is active
}
```

* `nextWorkout(in:)` is the workout at `nextIndex` (the first existing one after it, wrapping). `advance(after:)` moves `nextIndex` to the
  workout after the given template, so doing Push before Upper simply continues after Push. `skip(in:)` passes over the next workout.
* `StrengthData.record` advances every plan that contains the finished workout's template, once per workout id (recording the same workout
  again does not move the rotation again). A workout without a template changes no plan.
* `StrengthData.nextTemplate()` is what the hub recommends: the active plan's next workout; without an active plan (or when none of its
  templates exists) `TemplateRotation.next(in:)`, the rotation over all templates (the one after the most recently performed) that the hub
  had before plans existed.
* Plans are stored in `plans.json` (`FileStrengthPersistence.loadPlans/savePlans`, same lossy list reading as the other files).
  `StrengthStore` publishes `plans` and offers `savePlan`, `activatePlan`, `deletePlan` (the templates stay), `skipNextWorkout`, `importPlan`.

Two optional fields carry what a coach's plan says about a workout: `PlannedSet.repsMax` (a rep range: `reps` is the lower end,
`repsText` prints "8–10") and `TemplateEntry.note` (technique cues, substitutions). Both are **optional on purpose**: the stores skip a list
element that does not decode, so a new required key would have made every older saved template disappear. `WorkoutFactory.makeWorkout` copies
the note into the workout exercise's note; `updatedTemplate` / `template(from:)` copy a non-blank note back, and `updatedTemplate` keeps a
set's range until the reps done reach its top. The workout itself still has one target per set (`LoggedSet.reps`), so nothing in the Watch
sync or the Live Activity changed.

**Import.** `PlanBundle` (`version`, `plans`, `templates`, `customExercises`) is the file format of `yt_workout.py`'s `pulse-import.json`;
the hub's "Import Plan…" (a `fileImporter` for JSON) calls `StrengthStore.importPlan(from:)`. `PlanBundle.decode` refuses a file that is not
a bundle (`PlanImportError.unreadable`), is newer than `currentVersion` or holds no templates. `StrengthData.importBundle` then
`sanitized()`s it (names trimmed, reps/weights/rest clamped to what the reducer accepts, a range only when its top is above its bottom,
built-in exercises replaced by the library's definition, custom exercises never over a built-in id, unknown plan entries dropped) and merges
by id: a known template is replaced but keeps its `lastPerformed`; a known plan keeps its place in the rotation and its active flag; a new
plan becomes the active one. Importing the same file twice therefore changes nothing but the content it carries.

## 4. Verification policy

* Core: `swift build` + `swift test` on Linux must pass; each area ships tests (`Tests/PulseStrengthCoreTests/<Area>Tests.swift`).
  Status (Linux, Swift 6.1, zero warnings): `swift test` runs 700 tests, `swift test -Xswiftc -DPULSE_COMBINE_SHIM` runs 716 (the controller and
  store only compile with Combine or the stand-in); all pass. The sync protocol (3.4) has `SyncProtocolTests.swift`: scenarios on an in-memory
  phone / Watch link that delivers, delays, duplicates, reorders and drops messages, the pure adoption rules, and a seeded fuzz of 320 runs of
  40 steps that ends with full delivery and asserts that the Watch equals the phone and that no command ran twice. `SyncHardeningTests.swift` holds one
  regression test (or more) per finding of the sync review: envelope order and restored workouts, the lifetime of unacknowledged edits and the expiry
  timer, command order, late commands and sequence numbers, the phone relaunch, a phone without acknowledgements, the controller forwards.
  `SyncChannelFuzzTests.swift` is a second fuzzer with a closer model of the transports (a one-slot application context, a fast and a slow Watch -> phone
  channel, delivery delays, Watch restarts, phone relaunches, lost commands, workouts that end every other step) that also models the Watch client
  (`markQueued`, the expiry timer): the Watch never goes back to an older workout, equals the phone even when no last envelope comes, and no command runs
  twice across a relaunch. `SyncWatchHealthTests.swift` covers the end outcome (`SyncEnvelope.discarded`, `lastEndDiscarded`: what the phone says for a discard, a
  finish and an empty finish, what the Watch concludes when the notice does not say, ghost workouts, the codec and older payloads) and a stale "no workout"
  notice after a workout was adopted. `SyncWatchHealth2Tests.swift` covers when the phone ended the workout (`lastEndNoticeSentAt`: late, legacy and ghost notices,
  ignored notices, workouts that ended on the Watch itself, the controller forwards) with the Health end time rule (`SyncReconciler.healthWorkoutEnd`), and the rule
  that decides whether an end notice received without a workout belongs to a Health session nobody claimed (`SyncReconciler.endNotice(sentAt:settlesSessionStartedAt:)`).
* Apple-only files cannot be compiled on Linux: they are syntax-checked with `swiftc -parse` while writing, reviewed adversarially against the
  iOS 17 / watchOS 10 SDK APIs, and compiled and exercised by the macOS CI jobs (`apple`, `visual`, `matrix`). The README's "Verification status"
  lists what is verified and what needs real hardware.


## 5. Apple targets contract

None of this code can be compiled on Linux. Each file is wrapped in `#if os(iOS)` (or `os(watchOS)`), is syntax-checked with
`swiftc -parse`, and is compiled for real by the GitHub Actions workflow (`.github/workflows/strength-ios.yml`, macOS runner). Write
conservative, documented SwiftUI/ActivityKit/HealthKit/WatchConnectivity code for iOS 17 / watchOS 10. No `#Preview` blocks (use
`StrengthAppEnvironment.preview()` if a preview is wanted), no third-party packages, no private API.

### 5.1 Identifiers and capabilities

* Bundle ids: app `health.pulse.strength`, widget extension `health.pulse.strength.widgets`, watch app `health.pulse.strength.watchkitapp`.
  `StrengthConfig.appGroupID` = `group.health.pulse.strength` is reserved for sharing data with the Pulse app (the standalone build declares no App Group); URL scheme `pulse-strength`. The bundle id and the team live in `Config/Signing.xcconfig`. All are placeholders to replace.
* iOS app: HealthKit (read heart rate; share workouts and active energy), Push-less Live Activities
  (`NSSupportsLiveActivities` = YES, `NSSupportsLiveActivitiesFrequentUpdates` = YES), `NSHealthShareUsageDescription`,
  `NSHealthUpdateUsageDescription`, URL type for the scheme, Notifications (time-sensitive rest alert).
* Watch app: HealthKit, `WKBackgroundModes` = `workout-processing`, `WKCompanionAppBundleIdentifier` = the iOS bundle id, usage descriptions.
* Widget extension: no capability (`NSSupportsLiveActivities` is read from the host app); `NSExtension` point `com.apple.widgetkit-extension`.

### 5.2 Design tokens
`Sources/PulseStrengthIOS/PulseTheme.swift` is written and is the only source of colours, fonts, card/button/chip/segmented styles for
iOS views (`PulseTheme.*`, `PulseFont.*`, `.pulseCard()`, `.pulseNumber(size)`, `PulsePrimaryButtonStyle`, `PulseTintButtonStyle`,
`PulsePillButtonStyle`, `PulsePlainButtonStyle`, `PulseChip`, `PulseSegmented`, `SetType.badgeBackground/Foreground`). Extend it only by
adding to it in your own file via extensions.

*Dynamic Type.* Text sizes are design sizes that grow with the user's text size and are identical at the default size: use
`.pulseFont(size, weight, design:, relativeTo:)` and `.pulseNumber(size, weight, relativeTo:)` instead of a fixed `Font.system(size:)`;
`@PulseScaled` (a `@ScaledMetric` wrapper) gives the scaled number itself (Text concatenation, shapes, charts); `.pulseScaledFrame(minHeight:)`
replaces fixed heights that contain text; `PulseDynamicType.screenRange` (up to accessibility3) caps every screen and
`PulseDynamicType.activeWorkoutRange` (up to xxxLarge) caps the dense workout screen, the rest dock and the keypad. Icon glyph sizes inside fixed frames stay fixed. Light values equal the design; dark values are provided. Watch and widget targets have their
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
Rest end feedback: `UINotificationFeedbackGenerator` plus a VoiceOver "Rest over" announcement (`RestEndFeedback`, one helper) when the dock phase turns `.finished` while the app is active
and `alertWhenRestEnds` is on. `ActiveWorkoutView` plays it while the workout screen is open, `PulseStrengthRootView` (on the in-progress bar) while the workout is minimised; the system
notification stays suppressed in the foreground (`StrengthNotificationDelegate`). While the Watch banner state is on (not connected, Health denied) the header shows "–" and a still grey heart
instead of the last heart rate; the Health-denied banner button opens the Health app (`x-apple-health://`, undocumented) and falls back to the app's page in Settings.

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
public struct FormInfoSheet: View { public init(exercise: Exercise, onShowHistory: (() -> Void)? = nil) }     // large demo, muscles, how-to cues, "History & records" row (only when onShowHistory is set; the module-internal `ActiveFormInfoHost` in ActiveWorkoutView.swift hosts it in a NavigationStack and pushes ExerciseDetailView, and both ActiveWorkoutView and ExerciseListSheet present that host, so the row is there wherever the form sheet is opened from), attribution line
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
    public static func live(seedDemoData: Bool = false) -> StrengthAppEnvironment   // app-group persistence, fallback Application Support/PulseStrength; installs services; restoreFromDisk()
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
    public func waitForPendingUpdates() async         // returns when the Live Activity updates queued so far reached ActivityKit (LiveActivityManager.waitUntilIdle)
}
```
* `LiveActivityManager: WorkoutSideEffect` starts the Live Activity on `workoutStarted`, updates it on every change (content = `SnapshotBuilder.make(from:now:)`, `staleDate` = `restEndsAt` while an unpaused rest runs, else nil; throttle
  heart-rate-only updates to one per 10 s; never update from `workoutChanged` caused by `.updateHeartRate` more often), ends it on `workoutEnded`; re-attaches to an existing activity after relaunch. ActivityKit allows 4 KB for the attributes and the content state together, so the names that go into it (`workoutName` in the attributes and the snapshot, `exerciseName`, `nextExerciseName`) are cut to 60 Unicode scalars plus "…" inside the manager (start, update and final content); the Core snapshot, and with it the Watch screens, keeps the full names.
* `RestNotificationScheduler` schedules a time-sensitive local notification at the rest end (identifier `StrengthConfig.restNotificationID`), cancels it on skip / pause / finish / discard, only when `settings.alertWhenRestEnds`; foreground presentation suppressed.
* `HealthKitWorkoutWriter` writes an `HKWorkout` (traditional strength training) with `HKWorkoutBuilder` when a workout is finished and `state.usedWatch == false`; with the Watch recording, the Watch saves it. It saves a workout id once: the core can finish the same workout twice (after a failed history write the next launch restores and finishes it again), so the writer keeps the ids it saved (the last 64, in `UserDefaults`; the id is added after `finishWorkout` succeeded, so a failed write is retried) and ignores a workout it already saved or is saving. A `finishWorkout` completion without an error is a success even when the `HKWorkout` is nil (HealthKit's documented answer while the device is locked), so the id is recorded and the workout is not written twice. The phone does not know when a pause happened, only the total (`CompletedWorkout.finishedAt - startedAt - durationSeconds`): a paused workout gets one `HKWorkoutEvent` pause / resume pair of that length, strictly inside start...end and added before `endCollection` (a rejected event is logged and the workout is still saved), so Health's duration equals the app's, as on the Watch.
* `PhoneWatchBridge` (WCSession): pushes `controller.makeEnvelope(now:)` after every state change (`updateApplicationContext`, plus `sendMessage` when reachable) and, after every inbound `.command`, again when the command caused no push itself (a duplicate or no-op: the envelope is the acknowledgement; see 3.4), answers `.requestState`, turns inbound `.command` / `.heartRate` / `.watchSession` messages into controller calls, launches the Watch app with `HKHealthStore.startWatchApp(with:)` when a workout starts and the Watch app is installed.

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
all `LiveActivityIntent` with `@Parameter` properties, a no-argument `init()`, a convenience init with the arguments, `static var title`, `openAppWhenRun = false`, `isDiscoverable = false` (AppIntent, iOS 17.0+: Siri, Spotlight and Shortcuts do not list them; the Live Activity buttons still run them).
`perform()` forwards to `WorkoutCommandBus.shared.perform(action, origin: .liveActivity)` (String ids parsed with `UUID(uuidString:)`, invalid -> no-op) and returns `.result()`. The handler `StrengthAppEnvironment` installs applies the action with `controller.send` and then awaits `PulseServices.waitForPendingUpdates()` (the queued ActivityKit work), so `perform()` returns only after the new content reached ActivityKit: an app the intent launched in the background may be suspended right after `perform()` returns.

`Apps/Shared/LiveActivity/` (widget extension sources; imports ActivityKit, WidgetKit, SwiftUI, AppIntents, the package modules): `public struct WorkoutLiveActivity: Widget` using
`ActivityConfiguration(for: WorkoutActivityAttributes.self)`; the extension's `@main WidgetBundle` only lists it. Lock Screen view and Dynamic Island (compact leading/trailing, minimal,
expanded leading/trailing/center/bottom) follow `LockScreen.dc.html` and `DynamicIsland.dc.html`: phases `.logging` (set label, kg and reps with - / + `Button(intent: NudgeSetIntent(...))`,
"Log set" `Button(intent: LogSetIntent(...))`), `.resting` (countdown `Text(timerInterval:countsDown:)`, ring via `ProgressView(timerInterval:countsDown:)`, "Next" text, -15 s / +15 s / Skip intents),
`.restOver` ("Go" + Log set), `.complete` ("All sets logged", tap opens the app; a workout without any set, `totalSets == 0`, is `.complete` for the builder but the views show the barbell and "No exercises yet" / "No sets yet" with a hint instead). `widgetURL(StrengthConfig.workoutURL)`. Paused: frozen values (`elapsedWhenPaused`, `restFrozenRemaining`) and a
"Paused" label. Always dark styling. A widget view cannot tick on its own, so the rest end is handled with the staleness date: `LiveActivityManager` (5.3) sets
`ActivityContent.staleDate = restEndsAt` while a rest runs and the views treat `context.isStale && phase == .resting` as `.restOver` ("Go" + Log set); the countdown text stops at 0:00 meanwhile.

### 5.5 Apple Watch (`PulseStrengthWatchUI`)

Files: `WatchEnvironment.swift`, `WatchConnectivityClient.swift`, `WatchWorkoutSession.swift`, `WatchTheme.swift`, `WatchRootView.swift`, `LogSetPage.swift`, `RestPage.swift`,
`MetricsPage.swift`, `WatchIdleView.swift`, `WatchSummaryView.swift`, `WatchAppDelegate.swift`.
```swift
@MainActor public final class WatchEnvironment: ObservableObject { public let controller: WorkoutController; public static let shared: WatchEnvironment; public init() }   // mirror role, WatchConnectivityClient + WatchWorkoutSession registered as effects
public struct WatchRootView: View { public init(environment: WatchEnvironment) }
public final class WatchAppDelegate: NSObject, WKApplicationDelegate { public func handle(_ workoutConfiguration: HKWorkoutConfiguration); public func handleActiveWorkoutRecovery() }   // handle starts the session when the phone launches the Watch app; handleActiveWorkoutRecovery takes over the session the system kept alive after a crash
```
Screens follow `Watch.dc.html` (three screens): vertical-page `TabView` (`.verticalPage`): Log set (exercise name + time, "Set 4 of 5", weight with - / + and Digital Crown,
reps with - / +, green "Log set"), Rest (draining ring + countdown, next set text, -15 / skip / +15, auto-selected while resting, haptic when over: `WatchRestAlert` in `WatchRootView.swift` schedules it for the rest's end time from the controller's state, so it plays on any page and with the wrist down), Metrics (elapsed in yellow, heart
rate with beat, volume, sets). Idle state ("Start a workout on your iPhone"), summary at the end. Actions go through `controller.send(..., origin: .watch)`, which applies them at once and issues one `RemoteCommand` per tap (`WorkoutSideEffect.commandIssued`); `WatchConnectivityClient` sends that command (`sendMessage` when reachable and no older message waits in the `transferUserInfo` queue, else `transferUserInfo`, which keeps the order and is reported to the controller as `markQueued`; it no longer builds commands itself), runs the timer that expires a lost edit (`nextPendingExpiry`, `expirePending()`, then `requestState`) and the phone's next envelope acknowledges it, so the screens keep showing unacknowledged taps on top of the phone's state (see "Sync protocol" in 3.4); the target set ids come from
`controller.snapshot(now:)`; crown uses absolute `setWeight` after idle, buttons use `nudgeNextSet`. `WatchEnvironment` also publishes `session: WatchWorkoutSession` (`@Published isRecording`, `authorizationDenied`), `isPhoneReachable`, `endedSummary: WatchEndedSummary?` (+ `dismissSummary()`) and
`requestStateFromPhone()`; `public struct WatchEndedSummary: Equatable { workoutName, durationText, volumeText, setsText, averageHeartRateText }` is built from the last known state when the workout ends.
`WatchWorkoutSession` runs `HKWorkoutSession` +
`HKLiveWorkoutBuilder` (`.traditionalStrengthTraining`, indoor), streams heart rate to the phone (`SyncMessage.heartRate`, at most every 5 s), reports `.watchSession(isRecording:)` and ends when the
phone ends the workout.

*Health session lifecycle (`WatchEnvironment` owns the rules, `WatchWorkoutSession` the HealthKit calls).*
* Save or discard. `WatchWorkoutSession.end(save: Bool = true, endDate: Date? = nil)`: `true` ends the collection and `finishWorkout`s (saved to Health), `false` calls
  `HKWorkoutBuilder.discardWorkout()` (nothing reaches Health; a discard wins when the session is already ending, unless a start is queued behind it: a call while a
  restart is queued is about the QUEUED session, so it only cancels the start and never decides how the ending session is finalized). `handleWorkoutEnded` passes
  `save: !controller.lastEndDiscarded`, so a workout the user discarded on the phone, or finished with nothing logged, is not saved by the Watch, and no
  "Workout Complete" page is built for it. The phone writes no Health workout itself while the Watch records (`usedWatch`), so a finish is always saved by exactly one side.
  The 45 s check for a phone-launched session that never receives a workout ends it with `save: false`; a builder that cannot start collecting is discarded too.
  End time. `handleWorkoutEnded` also passes `endDate: controller.lastEndNoticeSentAt` (when the phone ended the workout), and the session ends the Health collection
  there when `SyncReconciler.healthWorkoutEnd` accepts it (more than 5 s before the Watch's own moment, after the session's start): a finish while the link was down
  does not stretch Health's duration, which matches the summary's. If HealthKit refuses the earlier end, the collection ends at the Watch's own moment instead, so the
  workout is saved either way.
* One session per workout. `WatchEnvironment` remembers which workout the session records (`sessionWorkoutID`; nil for a session started by a phone launch
  before its workout arrived, which the first state claims). A state of ANOTHER workout (the end notice of the first was lost: `updateApplicationContext` keeps
  only the latest value) ends the old session first (saved when the Watch saw a logged set) and the new session is queued behind it.
  `WatchAppDelegate.applicationDidBecomeActive` runs the same reconciliation, so a start that failed in the background (for example `errorBackgroundWorkoutSessionNotAllowed`) is
  retried in the foreground. A session never runs without a workout: the end of the workout, the replacement and the 45 s check all end it.
  A workout whose session the Watch ended with a save is remembered (the last 8 ids, in `UserDefaults`): when the phone restores it (its history write failed and the next
  launch restored it) it gets NO second session, which would save an overlapping Health workout when it is finished again. A session that ends by itself while the
  workout runs (another app takes the workout session, or HealthKit fails it) has saved what it recorded (`WatchWorkoutSession.onEndedByItself`): the session the next
  `applicationDidBecomeActive` starts for the same workout begins now, not at the workout's start, so the two Health workouts do not overlap.
* Pause. The environment forwards `state.isPaused` of every published state to `WatchWorkoutSession.setPaused(_:)`, which pauses / resumes the
  `HKWorkoutSession` (a pause that arrives before the session runs is applied when it does), so Health's duration, heart rate and energy leave out the pauses
  like the app's own duration does. The session remembers the phone's last pause state (`phonePaused`) even when it equalled the session's, so a session recovered
  after a crash takes the phone's state (reported while it was being recovered) instead of the one it had when the app crashed, and applies it once it is in hand. The
  delegate's `running` and `paused` reports re-apply the wanted state, so a pause or a resume that was skipped because the session had not changed state yet is applied
  as soon as it has.
* Crash recovery. `WatchAppDelegate.handleActiveWorkoutRecovery()` (watchOS 7) calls `WatchWorkoutSession.recover()`: `HKHealthStore.recoverActiveWorkoutSession`
  returns the surviving session, the Watch attaches a new data source and the delegates, and the phone is asked for the workout. Without a workout after 45 s the
  recovered session is ended and saved (it recorded a real workout before the crash), unless the phone's end notice says its workout was discarded: a notice that
  reached the Watch while it had no workout (the answer to `requestState`) is kept by the environment and decides when the check fires, or at once if the session is in
  hand. It counts only when it was sent after the session began (`SyncReconciler.endNotice(sentAt:settlesSessionStartedAt:)`; the start is `HKWorkoutSession.startDate`):
  an older notice is an earlier workout's (the Watch re-reads the last delivered context whenever it wakes). A notice that does not say (`discarded == nil`) leaves the
  save, and a finished one ends the saved session at the phone's time. The check keeps the more conservative decision: the phone launching the app while the recovered
  session runs does not turn the pending save into a discard. Known limit: the notice names the workout that ended LAST; if the phone also started and discarded a
  later workout before the Watch recovered, its flag decides for the recovered one.

### 5.6 Project, CI, docs

`project.yml` (XcodeGen) defines targets PulseStrength (iOS app, embeds the widget extension and the Watch app; sources `Apps/PulseStrength` + `Apps/Shared/Intents`), PulseStrengthWidgets
(app-extension; sources `Apps/PulseStrengthWidgets` + `Apps/Shared/Intents` + `Apps/Shared/LiveActivity`), PulseStrengthWatch (watchOS app) with the package products as dependencies, entitlements and Info.plist properties from 5.1, schemes. `Apps/*` contains the `@main` entry points, plists, entitlements,
asset catalogs (AccentColor, placeholder AppIcon). `.github/workflows/strength-ios.yml`: Linux job (`swift test`, with and without `-Xswiftc -DPULSE_COMBINE_SHIM`) and a macOS job
(`swift test` of the package on macOS, `xcodegen generate` plus a check that the committed `PulseStrength.xcodeproj` is unchanged, `xcodebuild build` of the iOS and watchOS schemes for the simulators with `CODE_SIGNING_ALLOWED=NO`). `README.md`
documents setup, what is verified and what is not, integration with the Pulse app (replace `RecoveryProvider`, the App Group id, the bundle ids, the media source), and the
source of the form photos (Free Exercise DB; they are placeholders with no cleared image licence, see "Exercise photos").
