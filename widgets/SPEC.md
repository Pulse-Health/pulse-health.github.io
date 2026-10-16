# Pulse Strength widgets: specification (iOS and Android)

The design is the canvas "Pulse Strength Widget Ideas" (<https://claude.ai/artifact/7FzgYpmWrz8cY1wfaHxpMM>). Its eight boards
are the visual reference; this document is the contract. Every item of the catalogue below has a stable id (`HS-01` ...)
and must exist on both platforms, in the closest native form (section 3 lists the mapping).

* Data contract: `widgets/tools/schema.py` generates `WidgetSnapshot` for Swift and Kotlin. Never edit the `*.generated.*` files;
  change the schema, run `python3 widgets/tools/generate.py`, commit both. `widgets/fixtures/preview.json` (made by
  `make_preview.py`) is the idealised fixture for previews and snapshot tests.
* Surfaces never read the workout engine or the history files. They read the `WidgetSnapshot` file (and, while a workout
  runs, `WidgetSnapshot.active`, which is the Live Activity's `WorkoutSnapshot`) and send commands (section 5).
* Weights are kilograms everywhere. All text is English. Colours and type follow the canvas (section 7).

## 1. Catalogue

`S` small, `M` medium, `L` large, `XL` extra large. iOS family names are WidgetKit's.

### Home Screen (canvas board "Home Screen widgets")

| id | idea | content (snapshot fields) | iOS | Android |
|---|---|---|---|---|
| HS-01 | Next up | `nextUp` name, `exerciseCount`, `estimatedMinutes`; Start button | `NextUpWidget` S | `NextUpWidget` 2x2 |
| HS-02 | Weekly goal | `week.completed/goal`, `week.days` dots | `WeeklyGoalWidget` S | `WeeklyGoalWidget` 2x2 |
| HS-03 | PR spotlight | `latestPR` | `PRSpotlightWidget` S | `PrSpotlightWidget` 2x2 |
| HS-04 | Muscle freshness | `freshness` (four least recently trained) | `MuscleFreshnessWidget` S | `MuscleFreshnessWidget` 2x2 |
| HS-05 | Beat last time | `overload` (dark) | `OverloadWidget` S | `OverloadWidget` 2x2 |
| HS-06 | Tinted weekly goal | `WeeklyGoalWidget` in the system's tinted mode | `widgetRenderingMode == .accented` | monochrome / dynamic-colour theme (`GlanceTheme`) |
| HS-07 | Next workout, previewed | `nextUp.exercises` + Start | `NextUpWidget` M | `NextUpWidget` 4x2 |
| HS-08 | Weekly sets per muscle | `weeklySets` bars, under-target bars grey | `WeeklySetsWidget` M | `WeeklySetsWidget` 4x2 |
| HS-09 | Lift trend | `lifts` (configurable lift), sparkline, PR point gold | `LiftTrendWidget` M (AppIntentConfiguration) | `LiftTrendWidget` 4x2 (configuration activity) |
| HS-10 | Training week | `week.days` strip, `lastSession`, `latestPR`, Start | `TrainingWeekWidget` L | `TrainingWeekWidget` 4x4 |
| HS-11 | Template launcher | `templates`, one Start button each (+ Empty workout) | `TemplateLauncherWidget` L (interactive) | `TemplateLauncherWidget` 4x4 |
| HS-12 | Month heatmap | `month` | `MonthHeatmapWidget` L | `MonthHeatmapWidget` 4x4 |

### Lock Screen accessories (board "Lock Screen accessories")

iOS: `accessoryCircular`, `accessoryRectangular`, `accessoryInline` families of the widgets named. Android: small `GlanceAppWidget`s with
`widgetCategory="home_screen|keyguard"` (lock screen and glanceable hub on tablets, Android 15+); the inline items become 4x1 widgets.

| id | idea | content | iOS widget (family) | Android |
|---|---|---|---|---|
| LS-01 | Weekly goal gauge | `week` 3/4 gauge | `WeeklyGoalAccessoryWidget` (circular) | `WeeklyGoalCompactWidget` 1x1 |
| LS-02 | Days since training | `week.daysSinceLastWorkout` | `DaysSinceAccessoryWidget` (circular) | `DaysSinceWidget` 1x1 |
| LS-03 | Week streak | `week.streakWeeks` flame | `StreakAccessoryWidget` (circular) | `StreakWidget` 1x1 |
| LS-04 | Quick start | play glyph, starts `nextUp` | `NextUpAccessoryWidget` (circular) | `QuickStartWidget` 1x1 |
| LS-05 | Next workout | `nextUp` | `NextUpAccessoryWidget` (rectangular) | `NextUpCompactWidget` 3x1 |
| LS-06 | Volume progress | `weeklySets.totalSets/totalTarget`, lagging muscle | `WeeklySetsAccessoryWidget` (rectangular) | `WeeklySetsCompactWidget` 3x1 |
| LS-07 | Latest record | `latestPR` | `PRAccessoryWidget` (rectangular) | `PrCompactWidget` 3x1 |
| LS-08 | Overload target | `overload` | `OverloadAccessoryWidget` (rectangular) | `OverloadCompactWidget` 3x1 |
| LS-09 | Inline: weekly goal | "3 of 4 workouts this week" | `WeeklyGoalAccessoryWidget` (inline) | `InlineStatusWidget` 4x1 (text mode "week") |
| LS-10 | Inline: split | "Push day · last 5 days ago" | `NextUpAccessoryWidget` (inline) | `InlineStatusWidget` (mode "split") |
| LS-11 | Inline: rest day | "Rest day · back on Sat" | `NextUpAccessoryWidget` (inline, shown instead of LS-10 when `restDay != nil`) | `InlineStatusWidget` (mode "rest") |

### StandBy, iPad, tablet (board "StandBy & iPad")

| id | idea | iOS | Android |
|---|---|---|---|
| SB-01 | StandBy pair: Next up + weekly goal | `NextUpWidget` / `WeeklyGoalWidget` `systemSmall` laid out for StandBy (`widgetRenderingMode`, no container background) | the same widgets in the glanceable hub (`keyguard` category) |
| SB-02 | Bench mode: Live Activity full screen | the rest/logging Live Activity adapted with `isActivityFullscreen` (large ring and countdown) | `BenchModeActivity` (show-when-locked, keep-screen-on, big rest timer; opened from the Live Update and the widget) |
| SB-03 | iPad training block | `TrainingBlockWidget` `systemExtraLarge` (`block`) | `TrainingBlockWidget` 6x4 tablet widget |
| SB-04 | Night mode | `NextUpWidget` StandBy night rendering (`isLuminanceReduced`, red on black) using `tomorrow` | `BenchModeActivity` night theme (red on black) using `tomorrow` |

### Watch (board "Apple Watch")

iOS: WidgetKit on watchOS (new `PulseStrengthWatchWidgets` extension; accessory families, Smart Stack). Android: Wear OS complications, tiles
and an Ongoing Activity.

| id | idea | iOS | Android |
|---|---|---|---|
| WA-01 | Modular face set | accessory widgets: next up (rect), goal (circular), days since (circular), start (circular) | complications: next up (LONG_TEXT), goal (RANGED_VALUE), days since (SHORT_TEXT), start (SHORT_TEXT with action) |
| WA-02 | Live rest complication | `RestWidget` accessoryRectangular, `active` rest countdown | complication `RestComplication` (RANGED_VALUE + countdown) + Ongoing Activity |
| WA-03 | Smart Stack: Next up | `NextUpWatchWidget` (rect, `RelevanceConfiguration`/relevance entries at the usual hour) | `NextUpTile` |
| WA-04 | Smart Stack: Log set (double tap) | `LogSetWatchWidget` interactive button (first button = double-tap target) | `WorkoutTile` with a prominent Log set button |
| WA-05 | Smart Stack: Rest | `RestWatchWidget` (+15 s, Skip) | `WorkoutTile` rest state |
| WA-06 | Record card | `RecordWatchWidget` (24 h after a PR, else hidden) | `RecordTile` |
| WA-07 | Corner gauges | `accessoryCorner` weekly goal + split | complication RANGED_VALUE with short title |
| WA-08 | Lift trend complication | `accessoryRectangular` sparkline | `LiftTrendTile` |
| WA-09 | Set-by-set heart rate | `HeartRateWatchWidget` (`lastSession.heartRateBars`) | `HeartRateTile` |
| WA-10 | Inline + small circulars | split reminder, streak, weekly sets | complications SHORT_TEXT / LONG_TEXT |

### Live Activity next states (board "Live Activity, next states")

iOS: `WorkoutLiveActivity` gains states; the snapshot fields are in `WorkoutSnapshot` (`moment`, `superset`, `plates`, `coachTip`, `finish`,
`exerciseDoneSets/exerciseSetCount`). Android: the Live Update notification (Android 16 `Notification.ProgressStyle`, promoted ongoing, with an
ongoing foreground-service notification fallback on older versions) renders the same states; the status-bar chip text is the Dynamic Island's compact text.

| id | idea | trigger | iOS | Android |
|---|---|---|---|---|
| LA-01 | PR moment | `moment != nil` | gold banner for 4 s then rest | title "New record", chip text "PR", cleared at `expiresAt` |
| LA-02 | Superset round | `superset != nil` | two rows A1/A2, current in blue, Log A2 | expanded text lists the members, action "Log A2" |
| LA-03 | Plate math | `plates != nil` and phase logging | plate row beside the Log set button | big-text line "20 + 10 + 2.5 per side" |
| LA-04 | Coach tip | `coachTip != nil` and resting | tip text + two buttons (suggested weight, keep) | two actions |
| LA-05 | Finish card | `finish != nil` | stats grid, stays 2 h (`dismissalPolicy .after`) | summary notification, auto-cancel after 2 h |
| LA-06 | Pre-workout countdown | planned session in the future | `PlannedSessionAttributes` Live Activity (Start now / Snooze) | countdown notification via alarm + actions |
| LA-07 | DI compact: record flash | `moment != nil` | trailing "PR" in gold | chip text "PR" |
| LA-08 | DI compact: set dots | logging, `exerciseSetCount` | leading dots | chip text "3/4" |
| LA-09 | DI compact: superset round | `superset != nil` | leading "A2" trailing "2/3" | chip text "A2 2/3" |
| LA-10 | DI compact: heart rate | logging and `heartRate != nil` | trailing bpm | chip text "142" |

Compact priority (both platforms): `moment` > resting countdown > `superset` > logging (leading dots, trailing heart rate if known else the elapsed clock).

### Controls and Action button (board "Controls & Action button")

iOS: `ControlWidget`s (iOS 18) and one App Intent for the Action button. Android: Quick Settings `TileService`s, launcher shortcuts and a
transparent `PrimaryActionActivity` for hardware buttons (Pixel Quick Tap, Samsung side key, Assistant routines).

| id | idea | iOS | Android |
|---|---|---|---|
| CT-01 | Start next workout | `StartNextControl` | `StartNextTileService` |
| CT-02 | Log set | `LogSetControl` | `LogSetTileService` |
| CT-03 | Rest (live value) | `RestControl` (value = remaining time) | `RestTileService` (subtitle = remaining time) |
| CT-04 | +30 s rest | `AddRestControl` | `AddRestTileService` |
| CT-05 | Plate calculator | `PlatesControl` (opens the app on the plates sheet) | `PlatesTileService` |
| CT-06 | Pause / resume | `PauseControl` (toggle) | `PauseTileService` (toggle state) |
| CT-07 | Finish workout | `FinishControl` | `FinishTileService` |
| CT-08 | Next up (2x2) | `NextUpControl` | `NextUpTileService` (label shows the template) |
| CT-09 | Lock Screen slots | the same controls in the Lock Screen's two bottom slots | `Start`/`Log set` as lock-screen shortcuts are not available to apps; quick-settings tiles are on the lock screen (secure) |
| CT-10 | Action button: one intent, three meanings | `PrimaryActionIntent` (+ `AppShortcut`): logging -> log set, resting -> skip rest, idle -> start next | `PrimaryActionActivity` (static shortcut + `actions.intent.START_EXERCISE` capability) with the same three meanings |

### Wilder ideas (board "Wilder ideas")

| id | idea | content | iOS | Android |
|---|---|---|---|---|
| WI-01 | Body map | `bodyMap` | `BodyMapWidget` M | `BodyMapWidget` 4x2 |
| WI-02 | Log from the Home Screen | `active` steppers + Log set | `LogSetWidget` M (interactive) | `LogSetWidget` 4x2 |
| WI-03 | Gym partner | `partners` (empty state "Invite a partner") | `PartnerWidget` M | `PartnerWidget` 4x2 |
| WI-04 | Form cue | `formCue` | `FormCueWidget` S | `FormCueWidget` 2x2 |
| WI-05 | Loaded bar | `loadedBar` | `LoadedBarWidget` S | `LoadedBarWidget` 2x2 |
| WI-06 | Rest-day swap | `restDay` | `RestDayWidget` S | `RestDayWidget` 2x2 |
| WI-07 | Strength ratio | `strengthRatio` | `StrengthRatioWidget` S | `StrengthRatioWidget` 2x2 |
| WI-08 | Year in iron | `year` | `YearInIronWidget` S | `YearInIronWidget` 2x2 |
| WI-09 | Readiness to load | `readiness` (empty state "Connect Pulse") | `ReadinessWidget` M | `ReadinessWidget` 4x2 |
| WI-10 | Plateau watch | `plateaus` | `PlateauWidget` M | `PlateauWidget` 4x2 |
| WI-11 | Session timeline | `lastSession.timeline` | `SessionTimelineWidget` M | `SessionTimelineWidget` 4x2 |

Empty states: every widget must render something useful with no history (`WidgetSnapshot.empty(now:)`: no templates, zero week) and with
no snapshot file (use `preview` as the placeholder / gallery sample, never as live data).

## 2. How the numbers are computed (`WidgetSnapshotBuilder`)

Identical rules on Swift and Kotlin; both are tested against `widgets/fixtures/golden-sample.json` (the builder's output for the demo data
at `now = 2026-10-16T09:41:00Z`, time zone UTC, goal 4, no bodyweight), produced by the Swift tests and compared by the Kotlin tests.

Inputs: `StrengthData` (templates, plans, history newest first, custom exercises, personal bests, body weights), `WidgetContext` { `weeklyGoal` (1...7, default 4),
`bodyweightKg?` (overrides the stored body weight), `readiness?`, `partners`, `active: WorkoutSnapshot?`, `timeZone` }, `now`.

Calendar: the week is Monday 00:00 to the next Monday 00:00 in `timeZone`. "Calendar days between" A and B is the number of local midnights
crossed (so 23:50 yesterday is 1 day ago); a date in the future counts as 0. A workout belongs to the day of its `finishedAt`.

* **goal**: the active plan's `daysPerWeek` when it has one, else `context.weeklyGoal` (the user's setting, default 4), clamped to 1...7.
* **week**: `completed` = workouts that day-bucket into this week; `days[i]` has `sessions`, `label` = initials of the earliest workout of the day,
  `isToday`, `isFuture`; `lastWorkoutAt` = latest `finishedAt`; `daysSinceLastWorkout` = calendar days since it (nil without history);
  `streakWeeks`: count the weeks that met the goal going backwards from the current week; the current week counts when it already met the goal and
  is skipped (not a break) when it has not; stop at the first earlier week below the goal; cap 520.
* **initials(name)**: split on whitespace, drop tokens without a letter or digit (like "·"), two or more tokens -> first character of the first two,
  one token -> its first two characters, none -> "WO"; upper case. "Upper A · Push" -> "UA".
* **nextUp**: the template the app itself recommends, `StrengthData.nextTemplate()`: the next workout of the active training plan
  (`WorkoutPlan.nextWorkout`), and without a plan the template after the most recently performed one in store order, wrapping, the first
  when nothing was performed (`TemplateRotation.next`, lowest index on a tie). No templates -> nil. With an active plan that contains the
  template: `planName`, `planPosition` (1-based position in the plan's rotation) and `planCount`. `splitLabel`: text after the last "·"
  trimmed plus " day" ("Push day"), else the name. Exercise `summary`: weight-tracking -> `<working sets> × <heaviest working weight>` ("3 × 85",
  working = not warm-up, all sets when there is none), reps-only -> `<n> × <max reps>`, duration -> `<n> × <max seconds> s`.
* **templates**: store order; `isSuggested` for the nextUp template.
* **lastSession**: the workout with the greatest `finishedAt`. `durationMinutes` = round half up of seconds / 60. `peakHeartRate` and `heartRateBars` come
  from `CompletedWorkout.heartRateSeries`: with at least 4 samples, `min(16, count)` contiguous buckets of near-equal size (earlier buckets take the
  remainder), bar = rounded mean, `isEffort` = bar above the rounded mean of all samples; otherwise empty. `timeline` needs `CompletedSet.loggedAt`
  on at least 2 sets: sort the logged sets by time; for each set, gap = its time minus the previous set's time (the workout start for the first);
  `lifting = min(gap, 45 s)`, `rest = gap - lifting`; emit the rest (`longRest` when above 180 s, else `rest`; skip zero) then the lifting stretch
  (skip zero); merge neighbours of the same kind. `underTensionPercent` = round(100 × lifting / all); `longBreakCount` = number of `longRest`.
* **latestPR**: newest workout with personal records; the record with the highest `estimated1RM` (first on a tie); `deltaKg` = `estimated1RM -
  previousBest` (0 when `previousBest` is 0); `isFresh` = `0 <= now - achievedAt <= 24 h`.
* **overload**: only with a nextUp. Walk the template's entries; the first entry that tracks weight, has a working set and has history. Last = that
  exercise's best working set (highest Epley estimate, first on a tie) in the newest workout containing it. Planned reps = reps of the entry's first
  working set, planned sets = its working-set count. If `lastReps >= plannedReps` -> target = last weight + `exercise.weightStepKg` × `plannedReps`; else
  target = last weight × `min(lastReps + 1, plannedReps)`. `deltaKg` = target weight - last weight. None found -> nil.
* **freshness**: all six groups in `MuscleGroup` order. `daysSince` from the latest workout whose `muscleSets` has that group with sets > 0 (nil if none).
  Status: nil or >= 4 -> `ready`; 2...3 -> `recovering`; <= 1 -> `worked`.
* **weeklySets**: `sets` = sum of `muscleSets` of this week's workouts. Targets: chest, back, shoulders, legs 10...14; arms, core 6...10. Status `under`
  below the low bound, `over` above the high bound, else `onTarget`. `totalSets` = the four majors (chest, back, shoulders, legs), `totalTarget` = 48,
  `setsToGo` = max(0, 48 - total), `laggingMuscle` = the major with the lowest `sets / 12` (first on a tie), nil when all reach 12.
* **lifts**: weight-tracking exercises of the last 90 days ranked by number of distinct workouts (ties: most recent, then id); the top 8. Per lift the
  sessions oldest first; a session value = the greatest `CompletedExercise.bestE1RM` of the exercise in that workout (if 0, the best Epley estimate of its
  non-warm-up sets); `points` = the last 6 sessions of ALL history; values rounded to 0.1; `currentE1RM` = last, `bestE1RM` = max, `prIndex` = index of the
  max when it is strictly greater than every earlier value, else nil; `deltaKg` = last - previous (0 for one point); `sessionCount` = sessions in the last
  90 days.
* **month**: `leadingBlankDays` = (weekday of the 1st, Monday = 0). Per day: sessions and volume; `level` 0 without sessions, else by volume / the month's
  largest day volume: <= 1/3 -> 1, <= 2/3 -> 2, else 3 (a month whose volumes are all 0 gives 1).
* **plateaus**: the first 4 of `lifts` with at least 3 points. `best` = max value, `p` = index of the latest point that set a new best (strictly above every
  earlier point; the first point counts), `flatSessions` = `count - p`. `flatSessions >= 3` and `last >= 0.97 × best` -> `flat`; `flatSessions >= 2` and
  `last < 0.97 × best` -> `falling`; otherwise `rising`. The first `flat` entry gets the tip "Try 3 × 8 at about 90% for two weeks."
* **year**: calendar year of `now`: `tonnes` = sum of `volumeKg` / 1000, `sessionCount`, `monthlyTonnes[0...11]`; all rounded to 0.1.
* **block** (derived, there is no block concept in the app): nil without history. Anchor = Monday of the earliest workout's week; `n` = whole weeks from the
  anchor to this week's Monday; block number `n / 4 + 1`, `weekIndex = n % 4 + 1`, `weekCount` 4. Rows = the first 4 templates (store order) labelled with the
  text after "·" (else the name); cell k (1...4): after `weekIndex` -> `upcoming`; otherwise `done` when a workout of that template (by `templateID`, else by
  name) finished in that week, `planned` for the current week, `missed` for an earlier week. `sessionsDone` = workouts since the block start,
  `sessionsPlanned` = goal × weekIndex, `sessionsMissed` = number of `missed` cells. `liftName` / `liftDeltaKg` = the first lift of `lifts` and the change of
  its value from the last session before the block (or its first session inside it) to its latest; nil when it has fewer than two sessions.
* **formCue**: the first nextUp entry whose exercise has cues; `index` = `(dayOfYear - 1) mod count`, 1-based in the output.
* **loadedBar**: the nextUp entry with the heaviest working set among exercises with `supportsPlates` (first on a tie); `PlateCalculator.plan(total, bar)`;
  `summary` joins the plates with " + " using `NumberText.kg`.
* **strengthRatio**: the first of `lifts` whose id is `bench`, `squat`, `deadlift` or `ohp`; `estimated1RM` = its `bestE1RM`; `bodyweightKg` = `context.bodyweightKg`, else the latest `StrengthData.bodyWeights` entry (the app's own record,
  synced from Health), else nil; `ratio` = e1RM / bodyweight rounded to 0.01 (nil without bodyweight); `goalRatio` 1.5 / 2.0 / 2.5 / 1.0.
* **restDay**: no workout today and (a workout yesterday or the goal is met) -> one of four routines by weekday (Mon = 0): "10-min mobility / Hips and
  T-spine / 10", "8-min shoulder reset / Shoulders and upper back / 8", "12-min hips and hamstrings / Hips and hamstrings / 12", "6-min wrist and ankle prep /
  Wrists and ankles / 6"; reason "Rest day". Otherwise nil.
* **tomorrow**: only with a nextUp: its name, tomorrow's English weekday, `plannedMinuteOfDay` = median start time (`finishedAt - durationSeconds`, minutes
  after midnight in the zone) of the latest 10 workouts rounded to 5 minutes (nil without history), `isInferred` true.
* **bodyMap**: `level` from this week's sets of the group: 0 -> 0, 1...4 -> 1, 5...9 -> 2, 10+ -> 3. `untouched` = groups with 0 sets. `message`: the first
  untouched major in `MuscleGroup` order "X untouched." plus " <T> is next in line." when the template with the most non-warm-up planned sets of X is nextUp
  (else " Try <T>."), T = its name up to " ·"; no untouched major -> "Every major group has been trained this week."
* **readiness, partners, active**: copied from the context.

### Live moments (`SnapshotBuilder`, inside `WorkoutSnapshot`)

The Swift implementation is the reference (`Widgets/SnapshotBuilder+Moments.swift`, `LiveMomentsTests.swift`); Kotlin ports its tests. `moment` and `finish` are set by the app,
never by `SnapshotBuilder.make`.

* API the app uses: `SnapshotBuilder.prMoment(from: old, to: new, now:, lifetime: 4) -> PRMoment?` and `SnapshotBuilder.finishBrief(from: completed, savedToHealth:) -> FinishBrief`.
* **prMoment**: fires for a set that is a record in `new` and was not one in `old` (matched by set id, so editing a logged set into a record and undoing then re-logging one fire
  too); nil for a different workout id; with several new records the one with the highest estimate. `weightText` / `repsText` carry no unit (like the snapshot's own fields),
  `estimated1RM` is in whole kg, `deltaKg` = difference of the whole-kg estimates against the running best the set beat, at least 1 (never "+0 kg"). A non-finite or negative
  lifetime counts as the default 4 s.
* **finishBrief**: the duration is rounded half up like `lastSession`; `volumeText` is in tonnes with a trailing zero dropped ("9.1", "9").
* `exerciseDoneSets` / `exerciseSetCount`: of the shown exercise.
* **superset**: nil for a group of one or an empty group name. `label`; `rounds` = set count of the first member (members without sets are left out and count as done);
  `round` = rounds finished by the least advanced member + 1, capped at `rounds` (so it is 2 of 3 while A2 of round 2 is due); members tagged `A1`, `A2` ...; `detail` =
  "<weight text> × <reps>" of each member's next pending set (its last set when finished; a duration exercise reads "45 s"); `isDone` = that member's set of this round is
  logged; `isCurrent` = it is the shown one.
* **plates**: the target set belongs to a barbell weight exercise -> `PlateCalculator.plan` with the exercise's own bar; nil when no plate is needed (bare bar, below the bar,
  less than the smallest plate per side). Clients show nothing for nil.
* **coachTip**: only while `phase == resting` (not rest over). It applies to the first pending non-warm-up set of the exercise just logged (in a superset that is the member just
  logged, which is why it carries its own `targetSetID` / `targetExerciseID`) when the last logged set is a non-warm-up weight set with `rir >= 3` and the pending weight is above 0.
  `suggestedWeightKg` = that pending set's weight + `weightStepKg`, rounded to 0.01. Texts: `subtitle` "3 reps in reserve on set 3" ("4+" for RIR 4 and above), `text` "Try 85 kg on
  set 4.", `suggestedWeightText` "85 kg", `keepWeightText` "Keep 82.5". Set numbers count all sets, like `setLabel`.

### Readings of section 2 fixed by the Swift implementation (Kotlin follows them)

* **overload**: the formulas are (weight, reps) pairs: target = (last weight + `weightStepKg`) for `plannedReps` when `lastReps >= plannedReps`, else (last weight) for
  `min(lastReps + 1, plannedReps)`. With a rep range (`PlannedSet.repsMax`) the success test uses the top of the range and after adding weight the reps restart at the bottom.
  A reps-only or duration entry's `summary` uses the top of the range.
* **lifts**: `prIndex` is the first occurrence of the best and nil when that is the first of the (at most 6) points. "Last 90 days" means `finishedAt >= now - 90 × 86 400 s`.
  A session is a workout with at least one set of the exercise with an estimate above 0; the same exercise twice in a workout is one session.
* **tomorrow.plannedMinuteOfDay**: the median of an even count is the mean of the two middle start times; rounded to 5 minutes with halves up; 24:00 wraps to 0.
* **bodyMap.message**: when no template trains the untouched group the message is only "X untouched.".
* **lastSession.timeline**: instants are whole seconds; sets without `loggedAt` are ignored and do not count towards the two-set minimum; ties keep workout order; a set
  logged before the start gives a zero gap.
* **block**: the name is "Block N" (N = `n / 4 + 1`); `n` is never below 0; `sessionsDone` counts every workout dated on or after the block start.
* Future-dated workouts count in `week.completed` when their day is in this week, and in `year`; `lastWorkoutAt` is the newest overall with `daysSinceLastWorkout` 0.
* An unknown time zone id is written as "UTC".

### New persisted fields (additive, optional; old files still decode)

`LoggedSet.doneAt`, `CompletedSet.loggedAt` (stamped by the reducer when a set becomes done, `SummaryBuilder` copies it), `WorkoutState.heartRateSeries`
(at most one sample per 30 s, at most 360 samples) and `CompletedWorkout.heartRateSeries`. The reducer's `revision` rules do not change.

## 3. Platform mapping (summary)

| iOS | Android |
|---|---|
| App Group file `widget-snapshot.json` (written by the app, read by the extensions) | no file: the widgets live in the app's own process, so `StrengthRuntime.snapshots` (a `StateFlow<WidgetSnapshot>` kept by `LiveRuntime`) is the only copy; it is built again when the process starts |
| `WidgetCenter.reloadTimelines` | `GlanceAppWidget.updateAll`, tile `TileService.getUpdater`, complication `ComplicationDataSourceUpdateRequester` |
| App Intents (Button(intent:), ControlWidget) | Glance `ActionCallback`, `PendingIntent` broadcasts, `TileService` clicks |
| Live Activity / Dynamic Island | Live Update notification (`ProgressStyle`) + status-bar chip text |
| watchOS widget extension | `:wear` module (tiles, complications, Ongoing Activity) |
| StandBy | glanceable hub widgets (`keyguard` category) and `BenchModeActivity` |

## 4. Deep links

Scheme `pulse-strength` (iOS URL type, Android intent filter on `MainActivity`):

| URL | meaning |
|---|---|
| `pulse-strength://workout` | open the running workout (exists) |
| `pulse-strength://start?template=<uuid>` | start that template (opens the workout) |
| `pulse-strength://start-next` | start `nextUp` |
| `pulse-strength://start-empty?name=<text>` | start an empty workout with that name (rest-day routines use it) |
| `pulse-strength://exercise/<exerciseID>` | open the exercise detail |
| `pulse-strength://hub` | open the Strength hub |
| `pulse-strength://plates` | open the running workout on the plate calculator (the hub when none runs) |

## 5. Commands a surface can send

Both platforms route them to the same engine actions (iOS `WorkoutAction`, Android `WorkoutCommands`); all are idempotent where the engine is:

`startNext`, `startTemplate(id)`, `startEmpty(name)`, `logNextSet`, `logSet(exerciseID, setID)`, `nudge(weightSteps, repsSteps)`, `adjustRest(seconds)`, `skipRest`,
`pause`, `resume`, `finish`, `applyCoachTip(setID, weightKg)`, `primaryAction` (= `logNextSet` while logging, `skipRest` while resting, `startNext` with no workout,
`finish` is never implied).

iOS: a command from a widget or control runs through `WorkoutCommandBus` when the app process executes the intent, otherwise (extension process) it is
appended to the App Group command inbox (`pending-commands.json`) and the app drains it on a Darwin notification, at launch and when it becomes active
(`WidgetIntentDispatch.send`). An intent that must open the app (start a workout, plate calculator) calls `WidgetIntentDispatch.openApp(link)` and has
`openAppWhenRun = true`: the inbox then carries a deep link instead of an action, which the app handles like an opened URL.

## 6. Files and ownership (so parallel work merges cleanly)

Home Screen widgets and Lock Screen accessories are separate WidgetKit widgets (separate `kind`s): the Home Screen ones support
`systemSmall/Medium/Large/ExtraLarge`, the `*AccessoryWidget`s support the `accessory*` families. StandBy shows the Home Screen `systemSmall` widgets.

iOS (`ios/`):

| path | owner |
|---|---|
| `Packages/PulseStrengthKit/Sources/PulseStrengthCore/**` (builder, analytics, store, inbox, settings, reducer fields), `Tests/PulseStrengthCoreTests/**` | core |
| `Apps/Shared/Widgets/Home/` (HS-01...HS-12, SB-01, SB-03, SB-04) | home |
| `Apps/Shared/Widgets/Lock/` (LS-01...LS-11) | lock |
| `Apps/Shared/Widgets/Extras/` (WI-01...WI-11) | extras |
| `Apps/Shared/Widgets/Watch/` (WA-01...WA-10), `PulseStrengthIOS/Services/WatchWidgetSnapshotSender.swift`, the additive widget-snapshot key in `PhoneWatchBridge.swift` and `WatchConnectivityClient.swift`, `PulseStrengthWatchUI/WatchWidgetSnapshotReceiver.swift` | watch |
| `Apps/Shared/LiveActivity/**` (changes), `PulseStrengthIOS/Services/LiveActivityManager.swift`, `PulseStrengthIOS/Services/PlannedSessionManager.swift`, `Apps/Shared/Intents/LiveMomentIntents.swift`, `Apps/Shared/PlannedSession/` (LA-01...LA-10, SB-02) | live |
| `Apps/Shared/Controls/**`, `Apps/Shared/Intents/StrengthIntents.swift`, `Apps/Shared/Intents/WidgetIntentDispatch.swift`, `Apps/Shared/Intents/ControlIntents.swift` (CT-01...CT-10) | controls |
| `Apps/PulseStrengthWidgets/`, `Apps/PulseStrengthWatchWidgets/`, `project.yml`, entitlements and Info.plists, `PulseStrengthApp.swift`, `PulseStrengthIOS/` except the files named above, widget snapshot tests, CI, docs | integration |
| `Apps/Shared/Widgets/Common/` | read-only for everyone (integration changes it) |

Every area exposes ONE `WidgetBundle` (`HomeWidgetBundle`, `LockWidgetBundle`, `ExtrasWidgetBundle`, `WatchWidgetBundle`, `ControlsBundle`) in its own folder;
`PulseStrengthWidgetsBundle.swift` only composes them.

Android (`android/`), package `health.pulse.strength`:

| path | owner |
|---|---|
| `core/`, `app/.../runtime/`, `app/.../data/` | core (`StrengthRuntime` first exists as a preview-backed fake) |
| `app/.../ui/`, `MainActivity.kt`, `PulseApp.kt`, host manifest region | host |
| `app/.../widgets/home/`, `app/.../widgets/tablet/` (HS-01...HS-12, SB-01, SB-03) | glance-home |
| `app/.../widgets/lock/`, `app/.../widgets/extras/` (LS-01...LS-11, WI-01...WI-11) | glance-extras |
| `app/.../live/`, `app/.../controls/`, `res/xml/shortcuts.xml` (LA-01...LA-10, SB-02, SB-04, CT-01...CT-10) | system |
| `wear/` and `app/.../wear/` (WA-01...WA-10) | wear |
| `app/.../widgets/common/` | read-only for everyone (integration changes it) |

`AndroidManifest.xml`, `strings.xml` and `build.gradle.kts` have one marked region per owner; add only inside your region (a dependency you need that is not in
`build.gradle.kts` goes into your final report; the integrator adds it).

## 7. Look

Colours (from `PulseTheme`): green `#1B8448` (light) / `#30D158` (dark), progress `#2EC76B`, text `#000` / `#FFF`, secondary `#6B6B70` / `#98989D`, card `#FFF` / `#1C1C1E`,
ground `#F2F2F7` / `#000`, blue `#0066D6` / `#0A84FF`, PR gold fill `#FFF6D6` text `#7A5200` (dark `#FFD60A`), recovery good/fair/low `#34C759` / `#FFCC00` / `#FF3B30`,
heart `#FF3B30` / `#FF453A`. Type: SF (iOS) / system sans (Android), rounded tabular numerals for figures. Radius 22 pt on widget cards. Touch targets at least 44 pt / 48 dp.
Dark mode and the tinted / dynamic-colour modes must remain legible; never put important text only in a colour.

## 8. Verification

* Core: `swift test` (Linux) and `./gradlew :core:test` must pass; new rules need tests that name the rule (section 2).
* Apple-only code cannot be built on Linux: every file is syntax-checked with `swiftc -parse` and compiled by the `strength-ios` workflow; widget views are
  rendered into PNGs by the widget snapshot tests (one image per widget and family, light and dark).
* Android: `./gradlew :core:test :app:assembleDebug :wear:assembleDebug :app:lintDebug` must pass; Glance and tile logic that can run on the JVM is unit-tested.
* Nothing in this document has been run on a device or a watch; the README says so.
