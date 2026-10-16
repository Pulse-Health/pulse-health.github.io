package health.pulse.strength.core

import health.pulse.strength.core.widgets.CoachTipBrief
import health.pulse.strength.core.widgets.FinishBrief
import health.pulse.strength.core.widgets.PRMoment
import health.pulse.strength.core.widgets.PlateBrief
import health.pulse.strength.core.widgets.SupersetBrief
import health.pulse.strength.core.widgets.SupersetMember
import java.time.Instant

/**
 * Builds the small [WorkoutSnapshot] shown by the ongoing notification and the other live surfaces.
 *
 * `make` fills the transient parts that follow from the state alone (set dots, superset, plates, coach tip). The personal-record
 * moment and the finish card are decided by the app, with [prMoment] and [finishBrief] (widgets/SPEC.md section 2, "Live moments").
 */
object SnapshotBuilder {
    /** How long a personal-record moment stays in the snapshot, in seconds. */
    const val momentLifetime: Double = 4.0

    /** Reps in reserve from which the coach suggests a heavier next set. */
    private const val coachTipMinimumRIR = 3

    /** The snapshot of [state] at [now]; its target is the next pending set (`WorkoutTargets.nextPending`). */
    fun make(state: WorkoutState, now: Instant): WorkoutSnapshot {
        val target = WorkoutTargets.nextPending(state)
        val totals = PresenterSupport.totals(state)

        // The exercise shown is the one that owns the target set (the current one while it still has pending sets).
        val shownIndex = target?.exerciseIndex ?: state.clampedIndex
        val shown: WorkoutExercise? = if (state.exercises.isEmpty()) null else state.exercises[shownIndex]
        val targetSet: LoggedSet? = target?.let { state.exercises[it.exerciseIndex].sets[it.setIndex] }

        val remaining = PresenterSupport.restRemainingSeconds(state, now)
        val phase = if (target == null) {
            SnapshotPhase.COMPLETE
        } else if (remaining != null) {
            if (remaining > 0) SnapshotPhase.RESTING else SnapshotPhase.REST_OVER
        } else {
            SnapshotPhase.LOGGING
        }

        val tracking = shown?.exercise?.tracking ?: TrackingKind.WEIGHT_REPS
        val setLabel: String
        val nextSetText: String
        val weightText: String
        val repsText: String
        if (shown != null && target != null && targetSet != null) {
            val position = "Set ${target.setIndex + 1} of ${shown.sets.size}"
            setLabel = if (targetSet.type == SetType.WARMUP) "Warm-up · $position" else position
            nextSetText = nextText(targetSet, target.setIndex + 1, shown.exercise)
            weightText = PresenterSupport.weightText(targetSet, shown.exercise)
            repsText = targetSet.reps.toString()
        } else {
            setLabel = "All sets logged"
            nextSetText = "All sets logged"
            weightText = "–"
            repsText = "–"
        }

        val rest = state.rest
        return WorkoutSnapshot(
            workoutID = state.id,
            revision = state.revision,
            workoutName = state.name,
            activeStart = state.startedAt.addingTimeInterval(state.pausedTotal),
            isPaused = state.isPaused,
            elapsedWhenPaused = if (state.isPaused) state.elapsedSeconds(now) else 0,
            phase = phase,
            exerciseName = shown?.exercise?.name ?: "",
            exerciseIndex = shownIndex,
            exerciseCount = state.exercises.size,
            targetExerciseID = target?.let { state.exercises[it.exerciseIndex].id },
            targetSetID = targetSet?.id,
            setLabel = setLabel,
            tracking = tracking,
            weightText = weightText,
            repsText = repsText,
            repsUnit = if (tracking == TrackingKind.DURATION) "sec" else "reps",
            showsWeight = tracking == TrackingKind.WEIGHT_REPS,
            restStartedAt = rest?.endsAt?.addingTimeInterval(-rest.totalSeconds.toDouble()),
            restEndsAt = rest?.endsAt,
            restTotalSeconds = rest?.totalSeconds ?: 0,
            restFrozenRemaining = if (state.isPaused) remaining else null,
            heartRate = state.heartRate,
            volumeText = NumberText.thousands(totals.volumeKg),
            loggedSets = totals.loggedSets,
            totalSets = totals.totalSets,
            nextSetText = nextSetText,
            nextExerciseName = nextExerciseName(state, shownIndex),
            exerciseDoneSets = shown?.doneCount,
            exerciseSetCount = shown?.sets?.size,
            superset = shown?.let { superset(state, it) },
            plates = if (shown != null && targetSet != null) plates(shown.exercise, targetSet) else null,
            coachTip = if (phase == SnapshotPhase.RESTING) coachTip(state) else null,
        )
    }

    /** "Set 4 · 82.5 kg × 6", "Warm-up · 50 kg × 8", "Set 1 · 12 reps" or "Set 1 · 45 s". */
    private fun nextText(set: LoggedSet, position: Int, exercise: Exercise): String {
        val label = if (set.type == SetType.WARMUP) "Warm-up" else "Set $position"
        return label + " · " + PresenterSupport.workText(set, exercise)
    }

    /** The first exercise after [index] that still has pending sets. */
    private fun nextExerciseName(state: WorkoutState, index: Int): String? {
        if (index + 1 >= state.exercises.size) return null
        return state.exercises.subList(index + 1, state.exercises.size).firstOrNull { e -> e.sets.any { !it.isDone } }?.exercise?.name
    }

    // region Superset, plates and coach tip

    /**
     * The running superset of [shown], null when it is not in one. The members are tagged A1, A2, ... in workout order. The rounds are
     * the first member's set count; the round in progress is one more than the sets the least advanced member has logged, so it only
     * moves on once every member has logged its set of the round.
     */
    private fun superset(state: WorkoutState, shown: WorkoutExercise): SupersetBrief? {
        val group = shown.supersetGroup ?: return null
        val members = state.exercises.filter { it.supersetGroup == group }
        val first = members.firstOrNull() ?: return null
        val rounds = maxOf(1, first.sets.size)
        val round = minOf(members.minOf { it.doneCount } + 1, rounds)
        return SupersetBrief(
            label = group,
            round = round,
            rounds = rounds,
            members = members.mapIndexed { position, member ->
                // What the member asks for next: its first pending set, or its last set once it is finished.
                val shownSet = member.sets.firstOrNull { !it.isDone } ?: member.sets.lastOrNull()
                SupersetMember(
                    tag = group + (position + 1),
                    name = member.exercise.name,
                    detail = shownSet?.let { PresenterSupport.weightText(it, member.exercise) + " × " + it.reps } ?: "",
                    isDone = member.sets.getOrNull(round - 1)?.isDone == true,
                    isCurrent = member.id == shown.id,
                )
            },
        )
    }

    /** The plates of [targetSet] when [exercise] is a barbell weight exercise and the set is not lighter than the bar. */
    private fun plates(exercise: Exercise, targetSet: LoggedSet): PlateBrief? {
        if (!exercise.supportsPlates) return null
        val plan = PlateCalculator.plan(targetSet.weightKg, exercise.barKg) ?: return null
        return PlateBrief(
            totalKg = targetSet.weightKg,
            barKg = exercise.barKg,
            perSide = plan.perSide,
            leftoverKg = plan.leftoverKg,
            summary = plan.perSide.joinToString(" + ") { NumberText.kg(it) },
        )
    }

    /**
     * While resting: when the last logged set is a non-warm-up weight set with at least [coachTipMinimumRIR] reps in reserve and its
     * exercise still has a pending set, one more step of weight for that pending set.
     */
    private fun coachTip(state: WorkoutState): CoachTipBrief? {
        val ref = state.lastLogged ?: return null
        val entry = state.exercises.firstOrNull { it.id == ref.exerciseID } ?: return null
        val loggedIndex = entry.sets.indexOfFirst { it.id == ref.setID }
        if (loggedIndex < 0) return null
        val logged = entry.sets[loggedIndex]
        val rir = logged.rir ?: return null
        if (!logged.isDone || logged.type == SetType.WARMUP || !entry.exercise.tracksWeight || rir < coachTipMinimumRIR) return null
        val pendingIndex = entry.sets.indexOfFirst { !it.isDone }
        if (pendingIndex < 0) return null
        val pending = entry.sets[pendingIndex]
        val step = entry.exercise.weightStepKg
        return CoachTipBrief(
            subtitle = "$rir reps in reserve on set ${loggedIndex + 1}",
            text = "Add ${NumberText.kg(step)} kg for set ${pendingIndex + 1} to stay at 1–2 RIR.",
            suggestedWeightKg = pending.weightKg + step,
            suggestedWeightText = NumberText.kg(pending.weightKg + step) + " kg",
            keepWeightText = "Keep " + NumberText.kg(pending.weightKg),
            targetSetID = pending.id.toString(),
            targetExerciseID = entry.id.toString(),
        )
    }

    // endregion

    // region Moments the app decides on

    /**
     * A [PRMoment] when the change from [old] to [new] logged a personal-record set, else null. A record is the presenter's rule: a logged,
     * non-warm-up weight set whose Epley estimate beats the best before it by more than 0.05 kg (never without a previous best). The set
     * counts as logged by this change when it is done in [new] and was not done in [old]; with several, the highest estimate wins.
     *
     * The moment expires [lifetime] seconds after [now]; the app sends the clearing update at `expiresAt`.
     */
    fun prMoment(old: WorkoutState, new: WorkoutState, now: Instant, lifetime: Double = momentLifetime): PRMoment? {
        val alreadyDone = old.exercises.flatMap { it.sets }.filter { it.isDone }.mapTo(HashSet()) { it.id }
        var best: Candidate? = null
        for (entry in new.exercises) {
            val analysis = PresenterSupport.analyse(entry).sets
            var baseline = maxOf(0.0, entry.exercise.previousBestE1RM)
            for ((index, set) in entry.sets.withIndex()) {
                val estimate = analysis[index].e1RM
                if (set.isDone && set.id !in alreadyDone && analysis[index].isRecord && estimate > (best?.estimate ?: 0.0)) {
                    best = Candidate(entry, set, estimate, baseline)
                }
                // The same running best as `PresenterSupport.analyse`: it rises with every logged set that beats it.
                if (set.isDone && estimate > baseline) baseline = estimate
            }
        }
        val record = best ?: return null
        return PRMoment(
            exerciseName = record.entry.exercise.name,
            weightText = NumberText.kg(record.set.weightKg),
            repsText = record.set.reps.toString(),
            estimated1RM = PresenterSupport.wholeKilograms(record.estimate),
            deltaKg = PresenterSupport.wholeKilograms(record.estimate - record.baseline),
            expiresAt = now.addingTimeInterval(lifetime),
        )
    }

    /** A newly logged record set with its estimate and the best before it. */
    private class Candidate(val entry: WorkoutExercise, val set: LoggedSet, val estimate: Double, val baseline: Double)

    /** The final card for a finished workout: minutes, sets, tonnes with one decimal and the number of records. */
    fun finishBrief(completed: CompletedWorkout, savedToHealth: Boolean): FinishBrief = FinishBrief(
        workoutName = completed.name,
        durationMinutes = (completed.durationSeconds + 30) / 60,
        sets = completed.loggedSets,
        volumeText = NumberText.kg((completed.volumeKg / 100).roundedAwayFromZero() / 10),
        personalRecordCount = completed.personalRecords.size,
        savedToHealth = savedToHealth,
    )

    // endregion
}
