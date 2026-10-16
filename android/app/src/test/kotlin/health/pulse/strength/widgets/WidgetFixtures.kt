package health.pulse.strength.widgets

import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.BodyMap
import health.pulse.strength.core.widgets.MuscleLevel
import health.pulse.strength.core.widgets.MuscleSetsProgress
import health.pulse.strength.core.widgets.SetsStatus
import health.pulse.strength.core.widgets.WeeklySetsSummary
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.preview
import java.time.Instant
import java.util.UUID

/** Snapshots the widget tests start from: the idealised preview, a fresh install, and a running workout in each phase. */
internal object WidgetFixtures {
    val preview: WidgetSnapshot get() = WidgetSnapshot.preview

    /** `generatedAt` of the preview: a Saturday, 2026-10-17 09:41 UTC. */
    val now: Instant = Instant.parse("2026-10-17T09:41:00Z")

    /** What a fresh install holds: the preview's shape with no history, no plan and nothing from the host app. */
    fun empty(): WidgetSnapshot {
        val base = preview
        return base.copy(
            week = base.week.copy(
                completed = 0,
                streakWeeks = 0,
                lastWorkoutAt = null,
                daysSinceLastWorkout = null,
                days = base.week.days.map { it.copy(sessions = 0, label = null) },
            ),
            nextUp = null,
            templates = emptyList(),
            lastSession = null,
            latestPR = null,
            overload = null,
            freshness = emptyList(),
            weeklySets = WeeklySetsSummary(
                muscles = MuscleGroup.entries.map { MuscleSetsProgress(it, sets = 0, status = SetsStatus.UNDER) },
                totalSets = 0,
                totalTarget = 48,
                setsToGo = 48,
                laggingMuscle = MuscleGroup.CHEST,
            ),
            lifts = emptyList(),
            plateaus = emptyList(),
            month = base.month.copy(sessionCount = 0, days = base.month.days.map { it.copy(level = 0, sessions = 0) }),
            year = base.year.copy(tonnes = 0.0, sessionCount = 0, monthlyTonnes = List(12) { 0.0 }),
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

    /** The shown set of a running "Upper A · Push" workout; [phase] and [tracking] choose the situation. */
    fun active(
        phase: SnapshotPhase = SnapshotPhase.LOGGING,
        tracking: TrackingKind = TrackingKind.WEIGHT_REPS,
        isPaused: Boolean = false,
        restRemainingSeconds: Long = 75,
        at: Instant = now,
    ): WorkoutSnapshot {
        val resting = phase == SnapshotPhase.RESTING
        val complete = phase == SnapshotPhase.COMPLETE
        val timed = tracking == TrackingKind.DURATION
        return WorkoutSnapshot(
            workoutID = UUID.fromString("00000000-0000-4000-8000-0000000000c1"),
            revision = 12,
            workoutName = "Upper A · Push",
            activeStart = at.minusSeconds(1260),
            isPaused = isPaused,
            elapsedWhenPaused = if (isPaused) 1260 else 0,
            phase = phase,
            exerciseName = if (timed) "Plank" else if (tracking == TrackingKind.REPS_ONLY) "Pull-up" else "Bench Press",
            exerciseIndex = 0,
            exerciseCount = 6,
            targetExerciseID = if (complete) null else UUID.fromString("00000000-0000-4000-8000-0000000000d1"),
            targetSetID = if (complete) null else UUID.fromString("00000000-0000-4000-8000-0000000000e1"),
            setLabel = if (complete) "All sets logged" else "Set 2 of 5",
            tracking = tracking,
            weightText = when (tracking) {
                TrackingKind.WEIGHT_REPS -> "82.5"
                TrackingKind.REPS_ONLY -> "BW"
                TrackingKind.DURATION -> "–"
            },
            repsText = if (timed) "45" else "6",
            repsUnit = if (timed) "sec" else "reps",
            showsWeight = tracking == TrackingKind.WEIGHT_REPS,
            restStartedAt = if (resting) at.minusSeconds(120 - restRemainingSeconds) else null,
            restEndsAt = if (resting) at.plusSeconds(restRemainingSeconds) else null,
            restTotalSeconds = if (resting) 120 else 0,
            restFrozenRemaining = if (resting && isPaused) restRemainingSeconds.toInt() else null,
            heartRate = 118,
            volumeText = "3,420",
            loggedSets = if (complete) 20 else 6,
            totalSets = 20,
            nextSetText = if (complete) "All sets logged" else "Set 3 · 82.5 kg × 6",
            exerciseDoneSets = 1,
            exerciseSetCount = 5,
        )
    }
}
