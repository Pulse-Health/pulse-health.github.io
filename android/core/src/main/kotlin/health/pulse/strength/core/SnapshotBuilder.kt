package health.pulse.strength.core

import health.pulse.strength.core.widgets.CoachTipBrief
import health.pulse.strength.core.widgets.FinishBrief
import health.pulse.strength.core.widgets.PRMoment
import health.pulse.strength.core.widgets.PlateBrief
import health.pulse.strength.core.widgets.SupersetBrief
import health.pulse.strength.core.widgets.SupersetMember
import health.pulse.strength.core.widgets.WidgetSessions
import health.pulse.strength.core.widgets.WidgetText
import java.time.Instant

/**
 * Builds the small [WorkoutSnapshot] shown by the ongoing notification and the other live surfaces.
 *
 * Besides the flat fields it carries the live context that follows from the state alone (widgets/SPEC.md section 2, "Live moments"):
 * the set dots of the shown exercise (`exerciseDoneSets`, `exerciseSetCount`), the running `superset`, the `plates` of the target set
 * and the `coachTip` shown while resting. The record `moment` and the `finish` card depend on what just happened, not on the state,
 * so the app sets them ([prMoment], [finishBrief]).
 */
object SnapshotBuilder {
    /** Seconds a record banner stays when the app does not say otherwise. */
    const val defaultMomentLifetime: Double = 4.0

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
            superset = supersetBrief(state, shownIndex),
            plates = plateBrief(targetSet, shown?.exercise),
            coachTip = coachTipBrief(state, phase),
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
     * The running superset when the exercise at [shownIndex] is in one: the exercises that share its group, in workout order.
     *
     * * `label` is the group ("A"); the members are tagged with it and their position ("A1", "A2", ...).
     * * `rounds` is the set count of the first member. `round` is the round in progress, 1-based and capped at `rounds`: the rounds
     *   every member has finished plus one. Counting from the least advanced member (members without sets are left out) keeps the
     *   round right after the first member has logged and the second is next, which is when the live card shows "A2 2/3"; the first
     *   member's count alone would already move on to the next round there. Whenever the first member is the next to log the two
     *   readings agree.
     * * `detail` is "<weight text> × <reps>" ("10 × 12", "BW × 12") of the member's next pending set, or of its last set when it has
     *   none left; a duration exercise reads "45 s", since it has no weight to put in front. Empty without sets.
     * * `isDone` tells whether the member's set of this round is logged; a member that has no set in the round counts as done when it
     *   has no pending set. `isCurrent` marks the shown exercise.
     *
     * null for an exercise without a group and for a group of one (the reducer never leaves one behind).
     */
    private fun supersetBrief(state: WorkoutState, shownIndex: Int): SupersetBrief? {
        val shown = state.exercises.getOrNull(shownIndex) ?: return null
        val group = shown.supersetGroup?.takeIf { it.isNotEmpty() } ?: return null
        val members = state.exercises.filter { it.supersetGroup == group }
        if (members.size < 2) return null

        val rounds = maxOf(1, members[0].sets.size)
        val finishedRounds = members.filter { it.sets.isNotEmpty() }.minOfOrNull { it.doneCount } ?: 0
        val round = minOf(rounds, finishedRounds + 1)
        return SupersetBrief(
            label = group,
            round = round,
            rounds = rounds,
            members = members.mapIndexed { position, member ->
                val nextSet = member.sets.firstOrNull { !it.isDone } ?: member.sets.lastOrNull()
                SupersetMember(
                    tag = group + (position + 1),
                    name = member.exercise.name,
                    detail = nextSet?.let { supersetDetail(it, member.exercise) } ?: "",
                    isDone = member.sets.getOrNull(round - 1)?.isDone ?: member.sets.none { !it.isDone },
                    isCurrent = member.id == shown.id,
                )
            },
        )
    }

    /** "10 × 12", "BW × 12" or, for a duration, "45 s". */
    private fun supersetDetail(set: LoggedSet, exercise: Exercise): String =
        if (exercise.tracking == TrackingKind.DURATION) "${set.reps} s" else PresenterSupport.weightText(set, exercise) + " × ${set.reps}"

    /**
     * The plates to load for [set] when [exercise] is a barbell weight exercise (`Exercise.supportsPlates`), by `PlateCalculator.plan`
     * with the exercise's own bar. `summary` joins the plates of one side with " + " ("20 + 10 + 2.5").
     *
     * null without a set, for other equipment, below the weight of the empty bar, and when no plate is needed (the bare bar, or a
     * weight smaller than the smallest plate on each side): there is nothing to show beside the Log button then.
     */
    private fun plateBrief(set: LoggedSet?, exercise: Exercise?): PlateBrief? {
        if (set == null || exercise == null || !exercise.supportsPlates) return null
        val plan = PlateCalculator.plan(set.weightKg, exercise.barKg) ?: return null
        if (plan.perSide.isEmpty()) return null
        return PlateBrief(
            totalKg = set.weightKg,
            barKg = exercise.barKg,
            perSide = plan.perSide,
            leftoverKg = plan.leftoverKg,
            summary = WidgetText.platesText(plan.perSide),
        )
    }

    /**
     * The one-tap suggestion for the next set, only while [phase] is resting.
     *
     * It needs the last logged set (`WorkoutState.lastLogged`) to still be logged, to be a non-warm-up set of a weight exercise with
     * [coachTipMinimumRIR] or more reps in reserve, and the same exercise to have a pending working set (the first one; warm-ups do not
     * count, and a weight that is not above zero gives no tip). Then `suggestedWeightKg` is that set's weight plus the exercise's
     * weight step (rounded to 0.01), `suggestedWeightText` "82.5 kg", `keepWeightText` "Keep 80", `subtitle` "3 reps in reserve on
     * set 2" ("4+" for the top value, which stands for four or more) and `text` "Try 82.5 kg on set 3.". Set numbers count every set
     * of the exercise, like the snapshot's `setLabel`. The suggestion names its own set and exercise: with a superset that is the
     * exercise just logged, not necessarily the target of the Log button.
     */
    private fun coachTipBrief(state: WorkoutState, phase: SnapshotPhase): CoachTipBrief? {
        if (phase != SnapshotPhase.RESTING) return null
        val reference = state.lastLogged ?: return null
        val entry = state.exercises.firstOrNull { it.id == reference.exerciseID } ?: return null
        val loggedIndex = entry.sets.indexOfFirst { it.id == reference.setID }
        if (loggedIndex < 0) return null
        val logged = entry.sets[loggedIndex]
        val reserve = logged.rir ?: return null
        if (!logged.isDone || logged.type == SetType.WARMUP || !entry.exercise.tracksWeight || reserve < coachTipMinimumRIR) return null
        val pendingIndex = entry.sets.indexOfFirst { !it.isDone && it.type != SetType.WARMUP }
        if (pendingIndex < 0) return null
        val pending = entry.sets[pendingIndex]
        if (!pending.weightKg.isFinite() || pending.weightKg <= 0) return null

        val suggested = WidgetText.hundredth(pending.weightKg + entry.exercise.weightStepKg)
        val suggestedText = NumberText.kg(suggested) + " kg"
        return CoachTipBrief(
            subtitle = (if (reserve >= 4) "4+" else reserve.toString()) + " reps in reserve on set ${loggedIndex + 1}",
            text = "Try $suggestedText on set ${pendingIndex + 1}.",
            suggestedWeightKg = suggested,
            suggestedWeightText = suggestedText,
            keepWeightText = "Keep " + NumberText.kg(pending.weightKg),
            targetSetID = pending.id.toString(),
            targetExerciseID = entry.id.toString(),
        )
    }

    // endregion

    // region Moments the app decides on

    /**
     * A [PRMoment] when the change from [old] to [new] logged a set that is a personal record (the presenter's rule: a logged,
     * non-warm-up weight set whose Epley estimate beats the running best by more than 0.05; nothing without a previous best), else
     * null. The moment expires [lifetime] seconds after [now] (a negative or non-finite lifetime counts as none and as the default);
     * the app sends the clearing update at `expiresAt`.
     *
     * A set is *new* when it is a record in [new] and was not one in [old] (a set that was pending, absent or no record before, found
     * by its id), so a change that does not touch the sets (a heart-rate sample, a pause) and a record that was already there give
     * null. Two states of different workouts give null: nothing was logged in the workout being shown. When several sets became
     * records at once (a bulk change, an undo and redo) the one with the highest estimate is reported, the later one on a tie.
     *
     * The text fields follow the snapshot's own: `weightText` "85" and `repsText` "5" carry no unit. `estimated1RM` is the estimate in
     * whole kilograms. `deltaKg` is the difference of the whole-kilogram estimates between the set and the running best it beat (the
     * previous best raised by the sets logged before it, so a second record in a session reports its gain over the first), at least 1
     * so a record never reads "+0 kg".
     */
    fun prMoment(old: WorkoutState, new: WorkoutState, now: Instant, lifetime: Double = defaultMomentLifetime): PRMoment? {
        if (old.id != new.id) return null
        var best: Candidate? = null
        for (entry in new.exercises) {
            val analysis = PresenterSupport.analyse(entry).sets
            val earlier = old.exercises.firstOrNull { it.id == entry.id }?.let { it to PresenterSupport.analyse(it).sets }
            for ((index, set) in entry.sets.withIndex()) {
                if (!analysis[index].isRecord) continue
                if (earlier != null) {
                    val before = earlier.first.sets.indexOfFirst { it.id == set.id }
                    if (before >= 0 && earlier.second[before].isRecord) continue
                }
                if (analysis[index].e1RM >= (best?.estimate ?: 0.0)) {
                    best = Candidate(entry.exercise.name, set, analysis[index].e1RM, analysis[index].baselineBefore)
                }
            }
        }
        val record = best ?: return null

        val seconds = if (lifetime.isFinite()) maxOf(0.0, lifetime) else defaultMomentLifetime
        val estimate = PresenterSupport.wholeKilograms(record.estimate)
        return PRMoment(
            exerciseName = record.exerciseName,
            weightText = NumberText.kg(record.set.weightKg),
            repsText = record.set.reps.toString(),
            estimated1RM = estimate,
            deltaKg = maxOf(1, estimate - PresenterSupport.wholeKilograms(record.baseline)),
            expiresAt = now.addingTimeInterval(seconds),
        )
    }

    /** A record set with its estimate and the running best it beat. */
    private class Candidate(val exerciseName: String, val set: LoggedSet, val estimate: Double, val baseline: Double)

    /**
     * The final card for a finished workout: the duration in whole minutes (a half rounds up), the logged sets, the volume in tonnes
     * with one decimal and no trailing zero ("9.1", "9"), the number of records, and whether Health has it.
     */
    fun finishBrief(completed: CompletedWorkout, savedToHealth: Boolean): FinishBrief = FinishBrief(
        workoutName = completed.name,
        durationMinutes = WidgetSessions.roundedMinutes(completed.durationSeconds),
        sets = maxOf(0, completed.loggedSets),
        volumeText = NumberText.kg((maxOf(0.0, completed.volumeKg) / 100).roundedAwayFromZero() / 10),
        personalRecordCount = completed.personalRecords.size,
        savedToHealth = savedToHealth,
    )

    // endregion
}
