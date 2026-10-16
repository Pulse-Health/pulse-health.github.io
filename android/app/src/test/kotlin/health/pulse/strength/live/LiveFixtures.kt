package health.pulse.strength.live

import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutSnapshot
import health.pulse.strength.core.widgets.CoachTipBrief
import health.pulse.strength.core.widgets.FinishBrief
import health.pulse.strength.core.widgets.PRMoment
import health.pulse.strength.core.widgets.PlateBrief
import health.pulse.strength.core.widgets.SupersetBrief
import health.pulse.strength.core.widgets.SupersetMember
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.preview
import java.time.Instant
import java.util.UUID

/** The instant every live-package test pretends to be at. */
internal val NOW: Instant = Instant.parse("2026-10-16T09:41:00Z")

internal val EXERCISE_ID: UUID = UUID.fromString("00000000-0000-4000-8000-0000000000e1")
internal val SET_ID: UUID = UUID.fromString("00000000-0000-4000-8000-0000000000f1")

/** A workout at set 4 of 5 of the bench press, 38 minutes in, 12 of 20 sets logged. */
internal fun loggingSnapshot(): WorkoutSnapshot = WorkoutSnapshot(
    workoutID = UUID.fromString("00000000-0000-4000-8000-0000000000a1"),
    revision = 3,
    workoutName = "Upper A · Push",
    activeStart = NOW.minusSeconds(38 * 60L + 2),
    isPaused = false,
    elapsedWhenPaused = 0,
    phase = SnapshotPhase.LOGGING,
    exerciseName = "Bench Press",
    exerciseIndex = 0,
    exerciseCount = 3,
    targetExerciseID = EXERCISE_ID,
    targetSetID = SET_ID,
    setLabel = "Set 4 of 5",
    tracking = TrackingKind.WEIGHT_REPS,
    weightText = "82.5",
    repsText = "6",
    repsUnit = "reps",
    showsWeight = true,
    restTotalSeconds = 0,
    volumeText = "4,980",
    loggedSets = 12,
    totalSets = 20,
    nextSetText = "Set 4 · 82.5 kg × 6",
    nextExerciseName = "Incline Dumbbell Press",
    exerciseDoneSets = 3,
    exerciseSetCount = 5,
)

/** The same workout in the middle of a rest that has [remaining] seconds left (of 120). */
internal fun restingSnapshot(remaining: Long = 84): WorkoutSnapshot = loggingSnapshot().copy(
    phase = SnapshotPhase.RESTING,
    restStartedAt = NOW.plusSeconds(remaining - 120),
    restEndsAt = NOW.plusSeconds(remaining),
    restTotalSeconds = 120,
)

internal fun completeSnapshot(): WorkoutSnapshot = loggingSnapshot().copy(
    phase = SnapshotPhase.COMPLETE,
    targetExerciseID = null,
    targetSetID = null,
    setLabel = "All sets logged",
    weightText = "–",
    repsText = "–",
    nextSetText = "All sets logged",
    loggedSets = 20,
    exerciseDoneSets = 5,
)

internal fun pausedSnapshot(): WorkoutSnapshot = loggingSnapshot().copy(isPaused = true, elapsedWhenPaused = 24 * 60 + 18)

internal fun moment(expiresIn: Long = 4): PRMoment = PRMoment(
    exerciseName = "Bench Press",
    weightText = "85",
    repsText = "5",
    estimated1RM = 99,
    deltaKg = 4,
    expiresAt = NOW.plusSeconds(expiresIn),
)

internal fun superset(): SupersetBrief = SupersetBrief(
    label = "A",
    round = 2,
    rounds = 3,
    members = listOf(
        SupersetMember(tag = "A1", name = "Lateral Raise", detail = "10 × 12", isDone = true),
        SupersetMember(tag = "A2", name = "Triceps Pushdown", detail = "25 × 12", isCurrent = true),
    ),
)

internal fun plates(): PlateBrief = PlateBrief(totalKg = 85.0, barKg = 20.0, perSide = listOf(20.0, 10.0, 2.5), summary = "20 + 10 + 2.5")

internal fun coachTip(): CoachTipBrief = CoachTipBrief(
    subtitle = "3 reps in reserve on set 2",
    text = "Coach: add 2.5 kg for set 3 to stay at 1–2 RIR.",
    suggestedWeightKg = 82.5,
    suggestedWeightText = "82.5 kg",
    keepWeightText = "Keep 80",
    targetSetID = SET_ID.toString(),
    targetExerciseID = EXERCISE_ID.toString(),
)

internal fun finishBrief(): FinishBrief = FinishBrief(
    workoutName = "Upper A · Push",
    durationMinutes = 52,
    sets = 22,
    volumeText = "9.1",
    personalRecordCount = 1,
    savedToHealth = true,
)

/** The idealised preview snapshot with [active] as the running workout. */
internal fun previewWith(active: WorkoutSnapshot?): WidgetSnapshot = WidgetSnapshot.preview.copy(active = active)
