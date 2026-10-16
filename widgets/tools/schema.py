"""Single source of truth for the widget data contract shared by iOS (Swift) and Android (Kotlin).

`generate.py` turns this file into
  * ios/Packages/PulseStrengthKit/Sources/PulseStrengthCore/Widgets/WidgetSnapshot.generated.swift
  * android/core/src/main/kotlin/health/pulse/strength/core/widgets/WidgetSnapshot.generated.kt

Both platforms build a `WidgetSnapshot` from their own store (see widgets/SPEC.md for the exact rules) and every
widget, tile, complication, Live Activity / Live Update and control reads only from it, so a surface never touches the
workout engine or the history files directly.

Type syntax of a field: scalar `String Int Double Bool Date UUID`, another type of this file, `[T]` for a list, `T?` for an
optional. `External` types are written by hand on each platform (see EXTERNAL).
Swift `Date` is Kotlin `java.time.Instant`; Swift `UUID` is a Kotlin `String` holding the lower-case uuid text.
Default value spellings: `nil`, `[]`, numbers, `true`/`false`, `""`.
"""

# Types that exist already / are hand written on both platforms.
EXTERNAL = ["MuscleGroup", "WorkoutSnapshot"]

# (name, doc, [cases])
ENUMS = [
    ("FreshnessStatus",
     "How recently a muscle group was trained: `ready` from 4 days (or never), `recovering` 2-3 days, `worked` today or yesterday.",
     ["ready", "recovering", "worked"]),
    ("SetsStatus",
     "Where a muscle group's weekly set count sits against its target range.",
     ["under", "onTarget", "over"]),
    ("TrendStatus",
     "Direction of a lift's estimated 1RM over its last sessions.",
     ["rising", "flat", "falling"]),
    ("BlockCellState",
     "One cell of the training-block grid.",
     ["done", "planned", "missed", "upcoming"]),
    ("TimelineKind",
     "One stretch of a finished session: time under load, a normal rest, or a break longer than 3 minutes.",
     ["lifting", "rest", "longRest"]),
]

# (name, doc, [(field, type, default or None, doc or "")])
STRUCTS = [
    # ------------------------------------------------------------------------------------------------ week / next up
    ("DayCell", "One day of the current week (Monday first).", [
        ("date", "Date", None, "Start of the day in the snapshot's time zone."),
        ("letter", "String", None, "Single-letter weekday: M T W T F S S."),
        ("sessions", "Int", "0", "Finished workouts that day."),
        ("label", "String?", "nil", "Initials of the first workout's name that day (\"UA\" for \"Upper A · Push\")."),
        ("isToday", "Bool", "false", ""),
        ("isFuture", "Bool", "false", ""),
    ]),
    ("WeekSummary", "Progress toward the weekly workout goal.", [
        ("weekStart", "Date", None, "Monday 00:00 of the current week."),
        ("goal", "Int", "4", "Workouts per week the user aims for (1...7)."),
        ("completed", "Int", "0", "Finished workouts this week."),
        ("streakWeeks", "Int", "0", "Consecutive weeks that met the goal (this week counts once it is met)."),
        ("lastWorkoutAt", "Date?", "nil", ""),
        ("daysSinceLastWorkout", "Int?", "nil", "Calendar days between the last workout and today; nil without history."),
        ("days", "[DayCell]", "[]", "Always 7 entries, Monday to Sunday."),
    ]),
    ("PlannedExerciseBrief", "One exercise of a template, for previews.", [
        ("exerciseID", "String", None, ""),
        ("name", "String", None, ""),
        ("muscle", "MuscleGroup", None, ""),
        ("setCount", "Int", "0", "All planned sets including warm-ups."),
        ("summary", "String", '""', "Working sets x heaviest weight (\"3 × 85\"), \"3 × 12\" for reps, \"3 × 45 s\" for time."),
    ]),
    ("NextUpSummary", "The template the user should train next.", [
        ("templateID", "UUID", None, ""),
        ("name", "String", None, ""),
        ("splitLabel", "String", None, "Text after the last \"·\" plus \" day\" (\"Push day\"), else the name."),
        ("exerciseCount", "Int", "0", ""),
        ("setCount", "Int", "0", ""),
        ("estimatedMinutes", "Int", "0", ""),
        ("lastPerformedAt", "Date?", "nil", ""),
        ("daysSince", "Int?", "nil", ""),
        ("planName", "String?", "nil", "Name of the active training plan when the template is its next workout."),
        ("planPosition", "Int?", "nil", "1-based position of the template in the active plan's rotation."),
        ("planCount", "Int?", "nil", "Number of workouts in the active plan's rotation."),
        ("exercises", "[PlannedExerciseBrief]", "[]", "Every template entry in order."),
    ]),
    ("TemplateSummary", "A saved template, for launchers.", [
        ("templateID", "UUID", None, ""),
        ("name", "String", None, ""),
        ("exerciseCount", "Int", "0", ""),
        ("estimatedMinutes", "Int", "0", ""),
        ("lastPerformedAt", "Date?", "nil", ""),
        ("daysSince", "Int?", "nil", ""),
        ("isSuggested", "Bool", "false", "True for the template that is `nextUp`."),
    ]),
    # ------------------------------------------------------------------------------------------------ last session
    ("TimelineSegment", "A stretch of the finished session's timeline.", [
        ("kind", "TimelineKind", None, ""),
        ("seconds", "Int", "0", ""),
    ]),
    ("HeartRateBar", "One bucket of the session's heart-rate curve.", [
        ("bpm", "Int", "0", ""),
        ("isEffort", "Bool", "false", "True when the bucket is above the session mean (a working set), false for recovery."),
    ]),
    ("SessionSummary", "The most recent finished workout.", [
        ("workoutID", "UUID", None, ""),
        ("name", "String", None, ""),
        ("finishedAt", "Date", None, ""),
        ("durationMinutes", "Int", "0", ""),
        ("loggedSets", "Int", "0", ""),
        ("volumeKg", "Double", "0", ""),
        ("averageHeartRate", "Int?", "nil", ""),
        ("peakHeartRate", "Int?", "nil", ""),
        ("personalRecordCount", "Int", "0", ""),
        ("timeline", "[TimelineSegment]", "[]", "Empty when the workout has no set timestamps (older history)."),
        ("underTensionPercent", "Int?", "nil", "Share of the duration spent lifting."),
        ("longBreakCount", "Int", "0", "Breaks longer than 3 minutes."),
        ("heartRateBars", "[HeartRateBar]", "[]", "At most 16 buckets; empty without heart-rate samples."),
    ]),
    # ------------------------------------------------------------------------------------------------ records / targets
    ("PRSummary", "The newest personal record.", [
        ("exerciseID", "String", None, ""),
        ("exerciseName", "String", None, ""),
        ("weightKg", "Double", "0", ""),
        ("reps", "Int", "0", ""),
        ("estimated1RM", "Double", "0", ""),
        ("deltaKg", "Double", "0", "Estimated 1RM minus the previous best."),
        ("achievedAt", "Date", None, ""),
        ("isFresh", "Bool", "false", "Within 24 hours of the snapshot."),
    ]),
    ("OverloadTarget", "What to lift today to beat last time (progressive overload).", [
        ("exerciseID", "String", None, ""),
        ("exerciseName", "String", None, ""),
        ("lastWeightKg", "Double", "0", ""),
        ("lastReps", "Int", "0", ""),
        ("lastDaysAgo", "Int?", "nil", ""),
        ("targetWeightKg", "Double", "0", ""),
        ("targetReps", "Int", "0", ""),
        ("targetSets", "Int", "0", "Planned working sets."),
        ("deltaKg", "Double", "0", "Target minus last weight."),
    ]),
    # ------------------------------------------------------------------------------------------------ muscles
    ("MuscleFreshness", "Recovery of one muscle group.", [
        ("muscle", "MuscleGroup", None, ""),
        ("daysSince", "Int?", "nil", "nil when never trained."),
        ("status", "FreshnessStatus", None, ""),
    ]),
    ("MuscleSetsProgress", "Sets of one muscle group this week.", [
        ("muscle", "MuscleGroup", None, ""),
        ("sets", "Int", "0", ""),
        ("targetLow", "Int", "10", ""),
        ("targetHigh", "Int", "14", ""),
        ("status", "SetsStatus", None, ""),
    ]),
    ("WeeklySetsSummary", "Working sets this week against the target.", [
        ("muscles", "[MuscleSetsProgress]", "[]", "All six groups in MuscleGroup order."),
        ("totalSets", "Int", "0", "Sets across the four major groups (chest, back, shoulders, legs)."),
        ("totalTarget", "Int", "48", "12 per major group."),
        ("setsToGo", "Int", "0", "max(0, totalTarget - totalSets)."),
        ("laggingMuscle", "MuscleGroup?", "nil", "Major group with the lowest sets / 12."),
    ]),
    # ------------------------------------------------------------------------------------------------ lifts
    ("TrendPoint", "One session's best estimated 1RM.", [
        ("date", "Date", None, ""),
        ("value", "Double", "0", ""),
    ]),
    ("LiftTrend", "Estimated-1RM trend of one exercise.", [
        ("exerciseID", "String", None, ""),
        ("name", "String", None, ""),
        ("points", "[TrendPoint]", "[]", "Oldest first, at most the last 6 sessions."),
        ("currentE1RM", "Double", "0", "Latest point."),
        ("bestE1RM", "Double", "0", ""),
        ("prIndex", "Int?", "nil", "Index into `points` of the best point when it beat every earlier one."),
        ("sessionCount", "Int", "0", "Sessions in the last 90 days."),
        ("deltaKg", "Double", "0", "Latest minus the one before; 0 with a single point."),
    ]),
    ("PlateauFlag", "A lift that has stalled (or is climbing).", [
        ("exerciseID", "String", None, ""),
        ("name", "String", None, ""),
        ("status", "TrendStatus", None, ""),
        ("flatSessions", "Int", "0", "Sessions in a row without a new best."),
        ("tip", "String?", "nil", "Only on the first flat lift."),
    ]),
    # ------------------------------------------------------------------------------------------------ calendar views
    ("MonthDay", "One day of the month heatmap.", [
        ("day", "Int", None, "Day of month, 1-based."),
        ("level", "Int", "0", "0 none, 1...3 by volume relative to the month's heaviest day."),
        ("sessions", "Int", "0", ""),
        ("isToday", "Bool", "false", ""),
        ("isFuture", "Bool", "false", ""),
    ]),
    ("MonthSummary", "Calendar heatmap of the current month (Monday first).", [
        ("monthStart", "Date", None, ""),
        ("title", "String", None, "English month name (\"October\")."),
        ("leadingBlankDays", "Int", "0", "Empty cells before day 1 (0...6)."),
        ("sessionCount", "Int", "0", ""),
        ("days", "[MonthDay]", "[]", ""),
    ]),
    ("YearSummary", "Tonnage this calendar year.", [
        ("year", "Int", None, ""),
        ("tonnes", "Double", "0", "Sum of workout volume / 1000."),
        ("sessionCount", "Int", "0", ""),
        ("monthlyTonnes", "[Double]", "[]", "12 entries, January first."),
    ]),
    ("BlockCell", "A cell of the block grid.", [
        ("state", "BlockCellState", None, ""),
    ]),
    ("BlockRow", "One template across the weeks of the block.", [
        ("label", "String", None, ""),
        ("cells", "[BlockCell]", "[]", "One per week of the block (4)."),
    ]),
    ("TrainingBlock", "A derived 4-week block (see SPEC), for large iPad / tablet widgets.", [
        ("name", "String", None, "\"Block 2\""),
        ("weekIndex", "Int", "1", "1-based week inside the block."),
        ("weekCount", "Int", "4", ""),
        ("rows", "[BlockRow]", "[]", "At most 4 templates."),
        ("sessionsDone", "Int", "0", ""),
        ("sessionsPlanned", "Int", "0", "goal x weeks elapsed in the block."),
        ("sessionsMissed", "Int", "0", ""),
        ("liftName", "String?", "nil", ""),
        ("liftDeltaKg", "Double?", "nil", "Estimated-1RM change of the most trained lift over the block."),
    ]),
    # ------------------------------------------------------------------------------------------------ small cards
    ("FormCue", "One coaching cue of today's first lift.", [
        ("exerciseID", "String", None, ""),
        ("exerciseName", "String", None, ""),
        ("cue", "String", None, ""),
        ("index", "Int", "1", "1-based."),
        ("count", "Int", "1", ""),
    ]),
    ("LoadedBar", "The plates for today's heaviest barbell set.", [
        ("exerciseID", "String", None, ""),
        ("exerciseName", "String", None, ""),
        ("totalKg", "Double", "0", ""),
        ("barKg", "Double", "20", ""),
        ("platesPerSide", "[Double]", "[]", "Heaviest first."),
        ("leftoverKg", "Double", "0", ""),
        ("summary", "String", '""', "\"20 + 10 + 2.5\""),
    ]),
    ("StrengthRatio", "A main lift against bodyweight.", [
        ("exerciseID", "String", None, ""),
        ("exerciseName", "String", None, ""),
        ("estimated1RM", "Double", "0", ""),
        ("bodyweightKg", "Double?", "nil", "From Health / Health Connect; nil when unknown."),
        ("ratio", "Double?", "nil", ""),
        ("goalRatio", "Double", "1.5", ""),
    ]),
    ("RestDaySuggestion", "Recovery content for a rest day.", [
        ("title", "String", None, ""),
        ("focus", "String", None, ""),
        ("minutes", "Int", "10", ""),
        ("reason", "String", '"Rest day"', ""),
    ]),
    ("TomorrowPlan", "Tomorrow's session, for night mode.", [
        ("templateName", "String", None, ""),
        ("plannedMinuteOfDay", "Int?", "nil", "Typical start time inferred from history, minutes after midnight."),
        ("weekday", "String", None, "English weekday name."),
        ("note", "String", '"Gym bag ready?"', ""),
        ("isInferred", "Bool", "true", ""),
    ]),
    ("MuscleLevel", "Training load of one muscle group this week.", [
        ("muscle", "MuscleGroup", None, ""),
        ("level", "Int", "0", "0 none, 1 <5 sets, 2 5-9 sets, 3 10+ sets."),
    ]),
    ("BodyMap", "Muscle map data.", [
        ("levels", "[MuscleLevel]", "[]", "All six groups."),
        ("untouched", "[MuscleGroup]", "[]", "Groups with zero sets this week."),
        ("message", "String", '""', "\"Legs untouched. Lower A is next in line.\""),
    ]),
    ("ReadinessSummary", "Readiness from the wider Pulse app (host provided).", [
        ("score", "Int", "0", "0...100"),
        ("label", "String", '""', ""),
        ("message", "String", '""', ""),
        ("source", "String", '"Pulse"', ""),
    ]),
    ("PartnerWeek", "A training partner's week (host provided).", [
        ("name", "String", None, ""),
        ("initials", "String", None, ""),
        ("completed", "Int", "0", ""),
        ("goal", "Int", "4", ""),
        ("closedWeek", "Bool", "false", ""),
    ]),
    # ------------------------------------------------------------------------------------------------ the snapshot
    ("WidgetSnapshot", "Everything a widget, tile, complication or control shows; one JSON file per device.", [
        ("schemaVersion", "Int", "1", ""),
        ("generatedAt", "Date", None, ""),
        ("timeZoneID", "String", '"UTC"', "IANA id used for every day bucket."),
        ("week", "WeekSummary", None, ""),
        ("nextUp", "NextUpSummary?", "nil", "nil without templates."),
        ("templates", "[TemplateSummary]", "[]", "In store order."),
        ("lastSession", "SessionSummary?", "nil", ""),
        ("latestPR", "PRSummary?", "nil", ""),
        ("overload", "OverloadTarget?", "nil", ""),
        ("freshness", "[MuscleFreshness]", "[]", "Six entries in MuscleGroup order."),
        ("weeklySets", "WeeklySetsSummary", None, ""),
        ("lifts", "[LiftTrend]", "[]", "Up to 8, most trained first."),
        ("month", "MonthSummary", None, ""),
        ("plateaus", "[PlateauFlag]", "[]", "Up to 4."),
        ("year", "YearSummary", None, ""),
        ("block", "TrainingBlock?", "nil", ""),
        ("formCue", "FormCue?", "nil", ""),
        ("loadedBar", "LoadedBar?", "nil", ""),
        ("strengthRatio", "StrengthRatio?", "nil", ""),
        ("restDay", "RestDaySuggestion?", "nil", "Set only on a rest day."),
        ("tomorrow", "TomorrowPlan?", "nil", ""),
        ("bodyMap", "BodyMap", None, ""),
        ("readiness", "ReadinessSummary?", "nil", "Host provided; nil in the standalone build."),
        ("partners", "[PartnerWeek]", "[]", "Host provided; empty in the standalone build."),
        ("active", "WorkoutSnapshot?", "nil", "The running workout (the Live Activity content); nil when none."),
    ]),
    # ------------------------------------------------------------------------------------------------ live moments (inside WorkoutSnapshot)
    ("PRMoment", "A personal record just logged; shown for a few seconds in the Live Activity.", [
        ("exerciseName", "String", None, ""),
        ("weightText", "String", None, ""),
        ("repsText", "String", None, ""),
        ("estimated1RM", "Int", "0", ""),
        ("deltaKg", "Int", "0", ""),
        ("expiresAt", "Date", None, "The app sends a clearing update at this time."),
    ]),
    ("SupersetMember", "One exercise of the running superset.", [
        ("tag", "String", None, "\"A1\""),
        ("name", "String", None, ""),
        ("detail", "String", '""', "\"10 × 12\""),
        ("isDone", "Bool", "false", "This round's set is logged."),
        ("isCurrent", "Bool", "false", ""),
    ]),
    ("SupersetBrief", "The running superset.", [
        ("label", "String", None, "\"A\""),
        ("round", "Int", "1", "1-based."),
        ("rounds", "Int", "1", ""),
        ("members", "[SupersetMember]", "[]", ""),
    ]),
    ("PlateBrief", "Plates for the target set.", [
        ("totalKg", "Double", "0", ""),
        ("barKg", "Double", "20", ""),
        ("perSide", "[Double]", "[]", "Heaviest first."),
        ("leftoverKg", "Double", "0", ""),
        ("summary", "String", '""', "\"20 + 10 + 2.5\""),
    ]),
    ("CoachTipBrief", "A one-tap suggestion for the next set, shown while resting.", [
        ("title", "String", '"Felt easy?"', ""),
        ("subtitle", "String", '""', "\"3 reps in reserve on set 2\""),
        ("text", "String", None, ""),
        ("suggestedWeightKg", "Double", "0", ""),
        ("suggestedWeightText", "String", None, "\"82.5 kg\""),
        ("keepWeightText", "String", None, "\"Keep 80\""),
        ("targetSetID", "UUID", None, "The set the suggestion applies to."),
        ("targetExerciseID", "UUID", None, ""),
    ]),
    ("FinishBrief", "The finished workout, shown on the Lock Screen for a few hours.", [
        ("workoutName", "String", None, ""),
        ("durationMinutes", "Int", "0", ""),
        ("sets", "Int", "0", ""),
        ("volumeText", "String", '"0"', "Tonnes with one decimal (\"9.1\")."),
        ("personalRecordCount", "Int", "0", ""),
        ("savedToHealth", "Bool", "false", ""),
    ]),
]
