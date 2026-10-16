package health.pulse.strength.core

import java.time.Instant
import java.util.UUID

/** Turns a [WorkoutState] into the display-ready [ActiveWorkoutPresentation] (port of `renderVals` in the design's Active.dc.html). */
object WorkoutPresenter {
    /** Builds the presentation of [state] at [now]; [recovery] supplies the muscle recovery percentages (0...100). */
    fun present(state: WorkoutState, now: Instant, recovery: RecoveryProvider): ActiveWorkoutPresentation {
        val totals = PresenterSupport.totals(state)
        val currentIndex = state.clampedIndex
        val diff = TemplateDiff.compute(state)

        return ActiveWorkoutPresentation(
            header = makeHeader(state, now, totals, currentIndex),
            navigator = makeNavigator(state, currentIndex),
            card = state.currentExercise?.let { makeCard(it, state, recovery) },
            dock = makeDock(state, now),
            undoText = makeUndoText(state, now),
            isEmpty = state.exercises.isEmpty(),
            totals = totals,
            finishCheck = makeFinishCheck(totals, diff, state.templateID),
        )
    }

    // region Header, navigator, undo

    private fun makeHeader(
        state: WorkoutState,
        now: Instant,
        totals: ActiveWorkoutPresentation.Totals,
        currentIndex: Int,
    ): ActiveWorkoutPresentation.Header {
        var clock = NumberText.clock(state.elapsedSeconds(now))
        if (state.isPaused) clock = "Paused · $clock"

        val segments = state.exercises.mapIndexed { index, entry ->
            ActiveWorkoutPresentation.Segment(
                fraction = if (entry.sets.isEmpty()) 0.0 else entry.doneCount.toDouble() / entry.sets.size.toDouble(),
                isCurrent = index == currentIndex,
            )
        }

        val bpm = state.heartRate?.takeIf { it > 0 }
        return ActiveWorkoutPresentation.Header(
            title = state.name,
            clockText = clock,
            isPaused = state.isPaused,
            volumeText = NumberText.thousands(totals.volumeKg),
            setsText = "${totals.loggedSets} of ${totals.totalSets}",
            heartRateText = bpm?.toString() ?: "–",
            hasHeartRate = bpm != null,
            segments = segments,
        )
    }

    private fun makeNavigator(state: WorkoutState, currentIndex: Int): ActiveWorkoutPresentation.Navigator? {
        if (state.exercises.isEmpty()) return null
        return ActiveWorkoutPresentation.Navigator(
            position = currentIndex + 1,
            total = state.exercises.size,
            canGoPrevious = currentIndex > 0,
            canGoNext = currentIndex < state.exercises.size - 1,
        )
    }

    private fun makeUndoText(state: WorkoutState, now: Instant): String? {
        val undo = state.undo ?: return null
        return if (!now.isAfter(undo.expiresAt)) undo.title else null
    }

    // endregion

    // region Card and rows

    private fun makeCard(entry: WorkoutExercise, state: WorkoutState, recovery: RecoveryProvider): ActiveWorkoutPresentation.Card {
        val exercise = entry.exercise
        val percent = maxOf(0, minOf(100, recovery(exercise.muscle)))
        val analysis = PresenterSupport.analyse(entry)
        val level = if (percent >= 80) {
            ActiveWorkoutPresentation.RecoveryLevel.GOOD
        } else if (percent >= 60) {
            ActiveWorkoutPresentation.RecoveryLevel.FAIR
        } else {
            ActiveWorkoutPresentation.RecoveryLevel.LOW
        }

        val weightTitle = when (exercise.tracking) {
            TrackingKind.WEIGHT_REPS -> "kg"
            TrackingKind.REPS_ONLY -> "Added"
            TrackingKind.DURATION -> ""
        }

        val group = entry.supersetGroup?.takeIf { it.isNotEmpty() }
        return ActiveWorkoutPresentation.Card(
            exerciseID = entry.id,
            exercise = exercise,
            recoveryPercent = percent,
            recoveryLevel = level,
            supersetLabel = group?.let { "Superset $it" },
            restSeconds = entry.restSeconds,
            restText = NumberText.rest(entry.restSeconds),
            note = entry.note,
            weightColumnTitle = weightTitle,
            repsColumnTitle = if (exercise.tracking == TrackingKind.DURATION) "Sec" else "Reps",
            coachTip = if (state.rest == null) PresenterSupport.coachTip(entry, analysis.baseline) else null,
            rows = makeRows(entry, analysis.sets),
        )
    }

    private fun makeRows(entry: WorkoutExercise, analysis: List<PresenterSupport.SetAnalysis>): List<ActiveWorkoutPresentation.SetRow> {
        val exercise = entry.exercise
        var workingNumber = 0
        var nextFound = false
        val rows = ArrayList<ActiveWorkoutPresentation.SetRow>(entry.sets.size)

        for ((index, set) in entry.sets.withIndex()) {
            val number = when (set.type) {
                SetType.WARMUP -> "W"
                SetType.DROP -> "D"
                SetType.FAILURE -> "F"
                SetType.NORMAL -> {
                    workingNumber += 1
                    workingNumber.toString()
                }
            }
            val isNext = !set.isDone && !nextFound
            if (isNext) nextFound = true
            val info = analysis[index]

            rows.add(
                ActiveWorkoutPresentation.SetRow(
                    id = set.id,
                    number = number,
                    type = set.type,
                    previousText = PresenterSupport.previousText(exercise, index),
                    weightText = PresenterSupport.weightText(set, exercise),
                    repsText = set.reps.toString(),
                    weightEditable = exercise.tracksWeight,
                    isDone = set.isDone,
                    isNext = isNext,
                    isPersonalRecord = info.isRecord,
                    estimated1RM = if (info.isRecord) PresenterSupport.wholeKilograms(info.e1RM) else null,
                    rir = set.rir,
                    rirText = if (set.isDone) set.rir?.let(PresenterSupport::rirText) else null,
                    accessibilityLabel = PresenterSupport.accessibilityLabel(index, set, exercise),
                ),
            )
        }
        return rows
    }

    // endregion

    // region Rest dock

    private fun makeDock(state: WorkoutState, now: Instant): ActiveWorkoutPresentation.Dock? {
        val rest = state.rest ?: return null
        val entry = state.currentExercise ?: return null
        val remaining = PresenterSupport.restRemainingSeconds(state, now) ?: return null

        val finished = remaining == 0
        val total = rest.totalSeconds
        val fraction = if (finished) {
            1.0
        } else if (total > 0) {
            maxOf(0.0, minOf(1.0, remaining.toDouble() / total.toDouble()))
        } else {
            0.0
        }

        val lastSet = lastLoggedSet(state)
        val showsRIR = lastSet?.let { it.isDone && it.type != SetType.WARMUP } ?: false
        return ActiveWorkoutPresentation.Dock(
            phase = if (finished) ActiveWorkoutPresentation.DockPhase.FINISHED else ActiveWorkoutPresentation.DockPhase.RUNNING,
            remainingSeconds = remaining,
            totalSeconds = total,
            fraction = fraction,
            remainingText = if (finished) "Go" else NumberText.rest(remaining),
            nextSetText = nextSetText(entry),
            showsRIR = showsRIR,
            rirSelection = if (lastSet != null && showsRIR) lastSet.rir else null,
            isPaused = state.isPaused,
        )
    }

    /** The set `lastLogged` points at, when it still exists. */
    private fun lastLoggedSet(state: WorkoutState): LoggedSet? {
        val ref = state.lastLogged ?: return null
        val entry = state.exercises.firstOrNull { it.id == ref.exerciseID } ?: return null
        return entry.sets.firstOrNull { it.id == ref.setID }
    }

    /** "Next · Set 2 · 82.5 kg × 6" for the first pending set of the card, or "All sets logged". */
    private fun nextSetText(entry: WorkoutExercise): String {
        var workingNumber = 0
        for (set in entry.sets) {
            var number = ""
            when (set.type) {
                SetType.WARMUP -> {}
                SetType.DROP -> number = "D"
                SetType.FAILURE -> number = "F"
                SetType.NORMAL -> {
                    workingNumber += 1
                    number = workingNumber.toString()
                }
            }
            if (set.isDone) continue
            val label = if (set.type == SetType.WARMUP) "Warm-up" else "Set $number"
            return "Next · $label · " + PresenterSupport.workText(set, entry.exercise)
        }
        return "All sets logged"
    }

    // endregion

    // region Finish check

    private fun makeFinishCheck(
        totals: ActiveWorkoutPresentation.Totals,
        diff: TemplateDiff,
        templateID: UUID?,
    ): ActiveWorkoutPresentation.FinishCheck {
        val logged = totals.loggedSets
        val unlogged = maxOf(0, totals.totalSets - logged)

        val title = if (logged == 0) "Nothing logged yet" else "Finish workout?"
        val message = if (logged == 0) {
            "Log at least one set to save this workout."
        } else if (unlogged > 0) {
            "$unlogged " + (if (unlogged == 1) "set is" else "sets are") + " not logged yet and will be left out."
        } else {
            "All sets are logged. Nice work."
        }

        return ActiveWorkoutPresentation.FinishCheck(
            loggedSets = logged,
            unloggedSets = unlogged,
            canFinish = logged > 0,
            title = title,
            message = message,
            templateDiff = diff,
            diffMessage = "Changes: " + diff.summary + ".",
            asksToUpdateTemplate = !diff.isEmpty && templateID != null,
        )
    }

    // endregion
}

/** Calculations and texts shared by the presenter, the summary builder and the snapshot builder. */
internal object PresenterSupport {
    /** A personal record must beat the running best by more than this many kilograms of estimated 1RM. */
    const val recordMargin = 0.05

    /** Estimated 1RM and personal-record flag of one set. */
    data class SetAnalysis(
        /** Epley estimate for logged-or-pending non-warm-up sets of weight-tracking exercises, else 0. */
        val e1RM: Double,
        /** A logged set that beat the running baseline by more than [recordMargin] (never without history). */
        val isRecord: Boolean,
    )

    /** Per-set analysis plus the final running baseline. */
    data class Analysis(val sets: List<SetAnalysis>, val baseline: Double)

    // region Totals

    fun totals(state: WorkoutState): ActiveWorkoutPresentation.Totals {
        var logged = 0
        var all = 0
        var volume = 0.0
        var completed = 0
        for (entry in state.exercises) {
            all += entry.sets.size
            logged += entry.doneCount
            volume += volumeKg(entry)
            if (entry.isComplete) completed += 1
        }
        return ActiveWorkoutPresentation.Totals(loggedSets = logged, totalSets = all, volumeKg = volume, completedExercises = completed)
    }

    /** Weight x reps of the logged, non-warm-up sets of a weight-tracking exercise. */
    fun volumeKg(entry: WorkoutExercise): Double {
        if (!entry.exercise.tracksWeight) return 0.0
        var volume = 0.0
        for (set in entry.sets) {
            if (set.isDone && set.type.countsTowardVolume) volume += set.weightKg * set.reps.toDouble()
        }
        return volume
    }

    /** Largest whole-kilogram value shown for an estimate; anything above (only possible for a state the reducer did not produce) clamps. */
    private const val wholeKilogramLimit = 1_000_000_000.0

    /** A kilogram value rounded to a whole number for display, never failing: non-finite gives 0, huge values clamp. */
    fun wholeKilograms(value: Double): Int {
        if (!value.isFinite()) return 0
        return maxOf(-wholeKilogramLimit, minOf(value.roundedAwayFromZero(), wholeKilogramLimit)).toInt()
    }

    // endregion

    // region Personal records

    /**
     * Per-set analysis in set order plus the final running baseline (previous best raised by the logged sets).
     *
     * The baseline starts at `previousBestE1RM` and rises with every logged set that beats it; without history
     * (`previousBestE1RM == 0`) no set is flagged.
     */
    fun analyse(entry: WorkoutExercise): Analysis {
        val exercise = entry.exercise
        val hasHistory = exercise.previousBestE1RM > 0
        var baseline = maxOf(0.0, exercise.previousBestE1RM)
        val result = ArrayList<SetAnalysis>(entry.sets.size)

        for (set in entry.sets) {
            var e1RM = if (exercise.tracksWeight && set.type.countsTowardVolume) {
                Estimated1RM.epley(set.weightKg, set.reps)
            } else {
                0.0
            }
            // A weight so large that the estimate overflows (a state not produced by the reducer) is not a usable estimate.
            if (!e1RM.isFinite()) e1RM = 0.0
            val isRecord = set.isDone && hasHistory && e1RM > baseline + recordMargin
            if (set.isDone && e1RM > baseline) baseline = e1RM
            result.add(SetAnalysis(e1RM = e1RM, isRecord = isRecord))
        }
        return Analysis(result, baseline)
    }

    // endregion

    // region Coach tip

    /** "85 kg × 6 on your last set would beat your best estimated 1RM of 99 kg." or null. */
    fun coachTip(entry: WorkoutExercise, baseline: Double): String? {
        val exercise = entry.exercise
        if (!(exercise.tracksWeight && exercise.previousBestE1RM > 0)) return null
        val pending = entry.sets.filter { !it.isDone && it.type != SetType.WARMUP }
        val target = pending.lastOrNull { it.type == SetType.NORMAL } ?: pending.lastOrNull() ?: return null
        if (target.reps <= 0) return null
        val weight = lowestBeatingWeight(baseline, target.reps, exercise.weightStepKg) ?: return null
        return NumberText.kg(weight) + " kg × ${target.reps} on your last set would beat your best estimated 1RM of " +
            NumberText.thousands(baseline) + " kg."
    }

    /** The lowest multiple of [step] whose Epley estimate with [reps] exceeds [baseline] by more than the record margin. */
    fun lowestBeatingWeight(baseline: Double, reps: Int, step: Double): Double? {
        if (!(baseline.isFinite() && baseline > 0 && reps > 0 && step > 0 && step.isFinite())) return null
        val threshold = baseline + recordMargin
        fun beats(weight: Double): Boolean = Estimated1RM.epley(weight, reps) > threshold

        val minimum = threshold / (1 + reps.toDouble() / 30)
        var multiples = (minimum / step).roundedUp()
        if (!(multiples.isFinite() && multiples < 1e9)) return null
        multiples = maxOf(1.0, multiples)
        // Correct a possible off-by-one from floating point rounding in either direction.
        var guardCount = 0
        while (multiples > 1 && beats((multiples - 1) * step) && guardCount < 8) {
            multiples -= 1
            guardCount += 1
        }
        while (!beats(multiples * step) && guardCount < 16) {
            multiples += 1
            guardCount += 1
        }
        val weight = multiples * step
        return if (beats(weight)) weight else null
    }

    // endregion

    // region Rest

    /** Whole seconds of rest left (rounded up, frozen while paused); null without a rest. */
    fun restRemainingSeconds(state: WorkoutState, now: Instant): Int? {
        val rest = state.rest ?: return null
        val seconds = rest.frozenRemaining ?: rest.endsAt.timeIntervalSince(state.pausedAt ?: now)
        if (!seconds.isFinite()) return 0
        // A tiny tolerance keeps floating-point noise (95.0000002 s) from showing one second too many.
        val rounded = (maxOf(0.0, seconds) - 1e-6).roundedUp()
        return maxOf(0.0, minOf(rounded, 1_000_000_000.0)).toInt()
    }

    // endregion

    // region Texts

    /** "RIR 3" or "RIR 4+". */
    fun rirText(rir: Int): String = if (rir >= 4) "RIR 4+" else "RIR " + maxOf(0, rir).toString()

    /** "82.5" for weight-tracking exercises, "BW" for reps-only, "–" for durations. */
    fun weightText(set: LoggedSet, exercise: Exercise): String = when (exercise.tracking) {
        TrackingKind.WEIGHT_REPS -> NumberText.kg(set.weightKg)
        TrackingKind.REPS_ONLY -> "BW"
        TrackingKind.DURATION -> "–"
    }

    /** "82.5 kg × 6", "8 reps" or "45 s": what a set asks for. */
    fun workText(set: LoggedSet, exercise: Exercise): String = when (exercise.tracking) {
        TrackingKind.WEIGHT_REPS -> NumberText.kg(set.weightKg) + " kg × ${set.reps}"
        TrackingKind.REPS_ONLY -> "${set.reps} reps"
        TrackingKind.DURATION -> "${set.reps} s"
    }

    /** Text for the PREVIOUS column: "80 × 6", "8 reps", "45 s" or "–" without history. */
    fun previousText(exercise: Exercise, setIndex: Int): String {
        if (exercise.previousSets.isEmpty()) return "–"
        val previous = exercise.previousSets[minOf(maxOf(0, setIndex), exercise.previousSets.size - 1)]
        return when (exercise.tracking) {
            TrackingKind.WEIGHT_REPS -> NumberText.kg(previous.weightKg) + " × ${previous.reps}"
            TrackingKind.REPS_ONLY -> "${previous.reps} reps"
            TrackingKind.DURATION -> "${previous.reps} s"
        }
    }

    /** "Set 3, working set, 82.5 kilograms, 6 reps, logged". */
    fun accessibilityLabel(setIndex: Int, set: LoggedSet, exercise: Exercise): String {
        val typeName = when (set.type) {
            SetType.NORMAL -> "working set"
            SetType.WARMUP -> "warm-up"
            SetType.DROP -> "drop set"
            SetType.FAILURE -> "failure set"
        }
        val parts = mutableListOf("Set ${setIndex + 1}", typeName)
        when (exercise.tracking) {
            TrackingKind.WEIGHT_REPS -> {
                val kg = NumberText.kg(set.weightKg)
                parts.add(kg + if (kg == "1") " kilogram" else " kilograms")
                parts.add("${set.reps}" + if (set.reps == 1) " rep" else " reps")
            }
            TrackingKind.REPS_ONLY -> {
                parts.add("bodyweight")
                parts.add("${set.reps}" + if (set.reps == 1) " rep" else " reps")
            }
            TrackingKind.DURATION -> parts.add("${set.reps}" + if (set.reps == 1) " second" else " seconds")
        }
        parts.add(if (set.isDone) "logged" else "not logged")
        return parts.joinToString(", ")
    }

    // endregion
}
