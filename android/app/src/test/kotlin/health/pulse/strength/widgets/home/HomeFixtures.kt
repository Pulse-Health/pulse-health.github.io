package health.pulse.strength.widgets.home

import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.BodyMap
import health.pulse.strength.core.widgets.FreshnessStatus
import health.pulse.strength.core.widgets.MuscleFreshness
import health.pulse.strength.core.widgets.MuscleLevel
import health.pulse.strength.core.widgets.MuscleSetsProgress
import health.pulse.strength.core.widgets.SetsStatus
import health.pulse.strength.core.widgets.WeeklySetsSummary
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.YearSummary
import health.pulse.strength.core.widgets.preview
import java.time.Instant
import java.util.UUID

/** Snapshots the widget tests start from. */
internal object HomeFixtures {
    /** The idealised sample every widget is designed against (3 of 4 workouts, a fresh record, 3 templates). */
    val preview: WidgetSnapshot get() = WidgetSnapshot.preview

    /**
     * What the builder produces with no history at all (`WidgetSnapshot.empty`): no templates, a week of zeros, every muscle ready and
     * never trained, no sets, no lifts, an empty month, no block. Derived from the preview so the calendar parts stay consistent.
     */
    val empty: WidgetSnapshot
        get() {
            val sample = preview
            val week = sample.week.copy(
                completed = 0,
                streakWeeks = 0,
                lastWorkoutAt = null,
                daysSinceLastWorkout = null,
                days = sample.week.days.map { it.copy(sessions = 0, label = null) },
            )
            val sets = WeeklySetsSummary(
                muscles = MuscleGroup.entries.map { muscle ->
                    val major = muscle in setOf(MuscleGroup.CHEST, MuscleGroup.BACK, MuscleGroup.SHOULDERS, MuscleGroup.LEGS)
                    MuscleSetsProgress(muscle, sets = 0, targetLow = if (major) 10 else 6, targetHigh = if (major) 14 else 10, status = SetsStatus.UNDER)
                },
                totalSets = 0,
                totalTarget = 48,
                setsToGo = 48,
                laggingMuscle = MuscleGroup.CHEST,
            )
            return sample.copy(
                week = week,
                nextUp = null,
                templates = emptyList(),
                lastSession = null,
                latestPR = null,
                overload = null,
                freshness = MuscleGroup.entries.map { MuscleFreshness(it, daysSince = null, status = FreshnessStatus.READY) },
                weeklySets = sets,
                lifts = emptyList(),
                month = sample.month.copy(sessionCount = 0, days = sample.month.days.map { it.copy(level = 0, sessions = 0) }),
                plateaus = emptyList(),
                year = YearSummary(year = sample.year.year, tonnes = 0.0, sessionCount = 0, monthlyTonnes = List(12) { 0.0 }),
                block = null,
                formCue = null,
                loadedBar = null,
                strengthRatio = null,
                restDay = null,
                tomorrow = null,
                bodyMap = BodyMap(levels = MuscleGroup.entries.map { MuscleLevel(it, 0) }, untouched = MuscleGroup.entries, message = ""),
                readiness = null,
                partners = emptyList(),
                active = null,
            )
        }

    /** The workout the Live Update and the widgets know about while one runs: "Upper A · Push", set 3 of 5 of the bench press. */
    fun runningWorkout() = WorkoutSnapshot(
        workoutID = UUID.fromString("00000000-0000-4000-8000-0000000000c1"),
        revision = 3,
        workoutName = "Upper A · Push",
        activeStart = Instant.parse("2026-10-17T09:00:00Z"),
        isPaused = false,
        elapsedWhenPaused = 0,
        phase = SnapshotPhase.LOGGING,
        exerciseName = "Bench Press",
        exerciseIndex = 0,
        exerciseCount = 6,
        setLabel = "Set 3 of 5",
        tracking = TrackingKind.WEIGHT_REPS,
        weightText = "80",
        repsText = "6",
        repsUnit = "reps",
        showsWeight = true,
        restTotalSeconds = 90,
        volumeText = "1,200",
        loggedSets = 12,
        totalSets = 20,
        nextSetText = "Set 3 · 80 kg × 6",
    )
}
