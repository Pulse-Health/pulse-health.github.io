package health.pulse.strength.core

import java.time.Instant
import java.util.UUID

/**
 * The only code that applies a [WorkoutAction] to a [WorkoutState] (port of the design's Active.dc.html logic).
 *
 * The reducer is pure: it returns a new state and never changes the one it is given.
 */
object WorkoutReducer {
    /** How long a removed exercise or deleted set can be restored with `Undo`, in seconds. */
    const val undoWindow: Double = 6.0

    /** Heaviest weight a set can hold (1,000,000 kg). Larger values are clamped to it; the keypad's six characters stay below it. */
    const val maximumWeightKg: Double = 1_000_000.0

    /** Longest rest an exercise can be given (one hour). Larger values are clamped to it; the rest presets stop at 5:00. */
    const val maximumRestSeconds: Int = 3_600

    /**
     * Shortest time between two samples of `WorkoutState.heartRateSeries` (30 seconds). Samples that arrive sooner still update the
     * current heart rate and the average, but are not kept in the series.
     */
    const val heartRateSampleInterval: Double = 30.0

    /**
     * Most samples `WorkoutState.heartRateSeries` keeps (360, three hours at one per 30 seconds). Once it is full, later samples are
     * not added: the series keeps the start of the workout, and the average still counts every sample.
     */
    const val maximumHeartRateSamples: Int = 360

    /** Applies [action] to [state]; `revision` grows by one when the state changed (never for heart-rate samples). */
    fun reduce(state: WorkoutState, action: WorkoutAction, now: Instant): WorkoutState {
        var next = apply(action, state, now)
        next = next.copy(currentIndex = next.clampedIndex)
        if (action !is WorkoutAction.UpdateHeartRate && next != state) {
            next = next.copy(revision = if (next.revision == Int.MAX_VALUE) Int.MAX_VALUE else next.revision + 1)
        }
        return next
    }

    // region Dispatch

    private fun apply(action: WorkoutAction, s: WorkoutState, now: Instant): WorkoutState = when (action) {
        is WorkoutAction.ToggleSet -> {
            val (k, i) = locate(s, action.exerciseID, action.setID) ?: return s
            if (s.exercises[k].sets[i].isDone) {
                s.updateSet(k, i) { it.copy(isDone = false, doneAt = null) }
            } else {
                markDone(s, k, i, now)
            }
        }
        is WorkoutAction.LogSet -> {
            val (k, i) = locate(s, action.exerciseID, action.setID) ?: return s
            if (s.exercises[k].sets[i].isDone) s else markDone(s, k, i, now)
        }
        WorkoutAction.LogNextSet -> {
            val target = WorkoutTargets.nextPending(s) ?: return s
            markDone(s.copy(currentIndex = target.exerciseIndex), target.exerciseIndex, target.setIndex, now)
        }
        is WorkoutAction.SetWeight -> {
            val (k, i) = locate(s, action.exerciseID, action.setID) ?: return s
            val value = roundedWeight(action.kg) ?: return s
            s.updateSet(k, i) { it.copy(weightKg = value) }
        }
        is WorkoutAction.SetReps -> {
            val (k, i) = locate(s, action.exerciseID, action.setID) ?: return s
            s.updateSet(k, i) { it.copy(reps = clampReps(action.reps)) }
        }
        is WorkoutAction.NudgeNextSet -> nudgeNextSet(s, action.weightSteps, action.repsSteps)
        is WorkoutAction.SetSetType -> {
            val (k, i) = locate(s, action.exerciseID, action.setID) ?: return s
            s.updateSet(k, i) { it.copy(type = action.type) }
        }
        is WorkoutAction.SetRIR -> {
            val (k, i) = locate(s, action.exerciseID, action.setID) ?: return s
            s.updateSet(k, i) { it.copy(rir = action.rir?.let(::clampRIR)) }
        }
        is WorkoutAction.ToggleLastSetRIR -> toggleLastSetRIR(s, action.value)
        is WorkoutAction.AddSet -> addSet(s, action.exerciseID)
        is WorkoutAction.DeleteSet -> deleteSet(s, action.exerciseID, action.setID, now)
        is WorkoutAction.SetNote -> {
            val k = s.exerciseIndex(action.exerciseID) ?: return s
            s.updateExercise(k) { it.copy(note = action.note) }
        }

        is WorkoutAction.GoTo -> s.copy(currentIndex = clampIndex(action.index, s.exercises.size))
        WorkoutAction.NextExercise -> s.copy(currentIndex = clampIndex(s.clampedIndex + 1, s.exercises.size))
        WorkoutAction.PreviousExercise -> s.copy(currentIndex = clampIndex(s.clampedIndex - 1, s.exercises.size))

        is WorkoutAction.AddExercises -> addExercises(s, action.exercises)
        is WorkoutAction.RemoveExercise -> removeExercise(s, action.exerciseID, now)
        is WorkoutAction.MoveExercise -> moveExercise(s, action.from, action.to)
        is WorkoutAction.MoveExerciseBy -> {
            val k = s.exerciseIndex(action.exerciseID) ?: return s
            val target = k.toLong() + action.delta.toLong()
            if (target > Int.MAX_VALUE || target < Int.MIN_VALUE) s else moveExercise(s, k, target.toInt())
        }
        is WorkoutAction.ReplaceExercise -> replaceExercise(s, action.exerciseID, action.with, now)
        is WorkoutAction.ToggleSuperset -> toggleSuperset(s, action.exerciseID)
        is WorkoutAction.SetRest -> {
            val k = s.exerciseIndex(action.exerciseID) ?: return s
            s.updateExercise(k) { it.copy(restSeconds = clampRest(action.seconds)) }
        }

        is WorkoutAction.AdjustRest -> adjustRest(s, action.seconds, now)
        WorkoutAction.SkipRest -> s.copy(rest = null)
        is WorkoutAction.SetAutoStartRest -> s.copy(settings = s.settings.copy(autoStartRest = action.value))
        is WorkoutAction.SetAlertWhenRestEnds -> s.copy(settings = s.settings.copy(alertWhenRestEnds = action.value))

        WorkoutAction.Pause -> pause(s, now)
        WorkoutAction.Resume -> resume(s, now)
        WorkoutAction.Undo -> undo(s, now)
        is WorkoutAction.UpdateHeartRate -> {
            val bpm = action.bpm
            if (bpm != null && bpm in 30..240) {
                keepHeartRateSample(
                    s.copy(heartRate = bpm, heartRateSum = s.heartRateSum + bpm, heartRateCount = s.heartRateCount + 1),
                    bpm,
                    now,
                )
            } else {
                s.copy(heartRate = bpm)
            }
        }
        is WorkoutAction.SetUsedWatch -> s.copy(usedWatch = action.value)
        is WorkoutAction.Rename -> s.copy(name = action.name)
    }

    // endregion

    // region Lookup and clamping helpers

    private fun WorkoutState.updateExercise(k: Int, transform: (WorkoutExercise) -> WorkoutExercise): WorkoutState =
        copy(exercises = exercises.toMutableList().also { it[k] = transform(it[k]) })

    private fun WorkoutState.updateSet(k: Int, i: Int, transform: (LoggedSet) -> LoggedSet): WorkoutState =
        updateExercise(k) { entry -> entry.copy(sets = entry.sets.toMutableList().also { it[i] = transform(it[i]) }) }

    /** Exercise index and set index of a set, null when either id is unknown. */
    private fun locate(s: WorkoutState, exerciseID: UUID, setID: UUID): Pair<Int, Int>? {
        val k = s.exerciseIndex(exerciseID) ?: return null
        val i = s.exercises[k].sets.indexOfFirst { it.id == setID }
        if (i < 0) return null
        return k to i
    }

    private fun clampIndex(index: Int, count: Int): Int = if (count > 0) maxOf(0, minOf(index, count - 1)) else 0

    private fun clampReps(reps: Int): Int = maxOf(0, minOf(reps, 999))

    private fun clampRIR(value: Int): Int = maxOf(0, minOf(value, 4))

    private fun clampRest(seconds: Int): Int = maxOf(0, minOf(seconds, maximumRestSeconds))

    /** Weight clamped to 0...[maximumWeightKg] and rounded to 0.01 kg; null (ignored) for NaN and +infinity. */
    private fun roundedWeight(kg: Double): Double? {
        if (kg.isNaN()) return null
        val lowerBounded = maxOf(0.0, kg)
        if (!lowerBounded.isFinite()) return null
        return (minOf(lowerBounded, maximumWeightKg) * 100).roundedAwayFromZero() / 100
    }

    private fun saturatingSum(a: Int, b: Int): Int = (a.toLong() + b.toLong()).coerceIn(Int.MIN_VALUE.toLong(), Int.MAX_VALUE.toLong()).toInt()

    /** Fresh pending sets for an exercise, from its library defaults. */
    private fun defaultSets(exercise: Exercise): List<LoggedSet> {
        val defaults = exercise.defaults
        val weight = roundedWeight(defaults.weightKg) ?: 0.0
        return List(maxOf(0, defaults.sets)) { LoggedSet(type = SetType.NORMAL, weightKg = weight, reps = clampReps(defaults.reps)) }
    }

    /** A workout entry for [exercise] with default sets and default rest. */
    private fun makeEntry(
        exercise: Exercise,
        id: UUID = UUID.randomUUID(),
        group: String? = null,
        templateEntryID: UUID? = null,
    ): WorkoutExercise = WorkoutExercise(
        id = id,
        exercise = exercise,
        sets = defaultSets(exercise),
        restSeconds = clampRest(exercise.defaults.restSeconds),
        supersetGroup = group,
        note = "",
        templateEntryID = templateEntryID,
    )

    // endregion

    // region Logging and rest start

    /**
     * Rest after a set: warm-ups rest 40 % of the exercise rest (rounded to 5 s, at least 30 s), other sets the full rest.
     * An exercise rest of 0 means the timer is off: no rest after a set of any type.
     */
    private fun restSeconds(exercise: WorkoutExercise, set: LoggedSet): Int {
        val base = maxOf(0, exercise.restSeconds)
        if (base <= 0) return 0
        if (set.type != SetType.WARMUP) return base
        val scaled = (base.toDouble() * 0.4 / 5).roundedAwayFromZero() * 5
        return maxOf(30, scaled.toInt())
    }

    /** Marks a pending set done and applies the follow-up: last logged, superset advance, rest start. */
    private fun markDone(state: WorkoutState, k: Int, i: Int, now: Instant): WorkoutState {
        var s = state
        val entry = s.exercises[k]
        val set = entry.sets[i]
        s = s.updateSet(k, i) { it.copy(isDone = true, doneAt = now) }.copy(lastLogged = SetRef(exerciseID = entry.id, setID = set.id))
        var seconds = restSeconds(entry, set)
        val group = entry.supersetGroup
        if (group != null) {
            val members = s.exercises.indices.filter { s.exercises[it].supersetGroup == group }
            val last = members.lastOrNull()
            val first = members.firstOrNull()
            if (last != null && k < last) {
                s = s.copy(currentIndex = k + 1)
                seconds = 0
            } else if (first != null) {
                s = s.copy(currentIndex = first)
            }
        }
        s = if (s.settings.autoStartRest && seconds > 0) {
            s.copy(
                rest = RestState(
                    endsAt = now.addingTimeInterval(seconds.toDouble()),
                    totalSeconds = seconds,
                    frozenRemaining = if (s.isPaused) seconds.toDouble() else null,
                ),
            )
        } else {
            s.copy(rest = null)
        }
        return s
    }

    private fun nudgeNextSet(s: WorkoutState, weightSteps: Int, repsSteps: Int): WorkoutState {
        val target = WorkoutTargets.nextPending(s) ?: return s
        val k = target.exerciseIndex
        val i = target.setIndex
        val exercise = s.exercises[k].exercise
        var set = s.exercises[k].sets[i]
        if (weightSteps != 0 && exercise.tracksWeight) {
            val steps = maxOf(-1000, minOf(1000, weightSteps)).toDouble()
            set = set.copy(weightKg = roundedWeight(set.weightKg + steps * exercise.weightStepKg) ?: set.weightKg)
        }
        if (repsSteps != 0) {
            val steps = maxOf(-1000, minOf(1000, repsSteps))
            set = set.copy(reps = clampReps(saturatingSum(set.reps, steps * exercise.repsStep)))
        }
        return s.updateSet(k, i) { set }
    }

    private fun toggleLastSetRIR(s: WorkoutState, value: Int): WorkoutState {
        val ref = s.lastLogged ?: return s
        val (k, i) = locate(s, ref.exerciseID, ref.setID) ?: return s
        val clamped = clampRIR(value)
        return s.updateSet(k, i) { it.copy(rir = if (it.rir == clamped) null else clamped) }
    }

    // endregion

    // region Heart rate series

    /**
     * [s] with the sample at [now] added to the series when at least [heartRateSampleInterval] seconds passed since the last kept one
     * and the series is not full. A clock that moved back keeps nothing until it passes the last sample again.
     */
    private fun keepHeartRateSample(s: WorkoutState, bpm: Int, now: Instant): WorkoutState {
        if (s.heartRateSeries.size >= maximumHeartRateSamples) return s
        val last = s.heartRateSeries.lastOrNull()
        if (last != null && now.timeIntervalSince(last.at) < heartRateSampleInterval) return s
        return s.copy(heartRateSeries = s.heartRateSeries + HeartRateSample(bpm = bpm, at = now))
    }

    // endregion

    // region Sets

    private fun addSet(s: WorkoutState, exerciseID: UUID): WorkoutState {
        val k = s.exerciseIndex(exerciseID) ?: return s
        val entry = s.exercises[k]
        val last = entry.sets.lastOrNull()
        val weight: Double
        val reps: Int
        if (last != null) {
            weight = last.weightKg
            reps = last.reps
        } else {
            weight = roundedWeight(entry.exercise.defaults.weightKg) ?: 0.0
            reps = clampReps(entry.exercise.defaults.reps)
        }
        return s.updateExercise(k) {
            it.copy(sets = it.sets + LoggedSet(type = SetType.NORMAL, weightKg = weight, reps = reps, isDone = false, rir = null))
        }
    }

    private fun deleteSet(s: WorkoutState, exerciseID: UUID, setID: UUID, now: Instant): WorkoutState {
        val (k, i) = locate(s, exerciseID, setID) ?: return s
        val removed = s.exercises[k].sets[i]
        return s.updateExercise(k) { entry -> entry.copy(sets = entry.sets.toMutableList().also { it.removeAt(i) }) }.copy(
            lastLogged = if (s.lastLogged?.setID == setID) null else s.lastLogged,
            undo = UndoEntry(
                payload = UndoPayload.DeletedSet(exerciseID = exerciseID, index = i, set = removed),
                title = "Set deleted",
                expiresAt = now.addingTimeInterval(undoWindow),
            ),
        )
    }

    // endregion

    // region Exercise list

    private fun addExercises(s: WorkoutState, exercises: List<Exercise>): WorkoutState {
        if (exercises.isEmpty()) return s
        val wasEmpty = s.exercises.isEmpty()
        val appended = s.copy(exercises = s.exercises + exercises.map { makeEntry(it) })
        return if (wasEmpty) appended.copy(currentIndex = 0) else appended
    }

    /** When a superset group is left with a single member, that member leaves the group too. */
    private fun releaseOrphan(s: WorkoutState, group: String?): WorkoutState {
        if (group == null) return s
        val members = s.exercises.indices.filter { s.exercises[it].supersetGroup == group }
        if (members.size == 1) return s.updateExercise(members[0]) { it.copy(supersetGroup = null) }
        return s
    }

    private fun removeExercise(state: WorkoutState, exerciseID: UUID, now: Instant): WorkoutState {
        val at = state.exerciseIndex(exerciseID) ?: return state
        val removed = state.exercises[at]
        var s = state.copy(exercises = state.exercises.toMutableList().also { it.removeAt(at) })
        s = releaseOrphan(s, removed.supersetGroup)
        var currentIndex = s.currentIndex
        if (at < currentIndex) currentIndex -= 1
        currentIndex = clampIndex(currentIndex, s.exercises.size)
        return s.copy(
            currentIndex = currentIndex,
            lastLogged = if (s.lastLogged?.exerciseID == removed.id) null else s.lastLogged,
            undo = UndoEntry(
                payload = UndoPayload.RemovedExercise(index = at, exercise = removed),
                title = "Removed " + removed.exercise.name,
                expiresAt = now.addingTimeInterval(undoWindow),
            ),
        )
    }

    /** Moves the exercise at [from] so it ends up at [to]; the current exercise stays selected. */
    private fun moveExercise(s: WorkoutState, from: Int, to: Int): WorkoutState {
        val count = s.exercises.size
        if (!(from >= 0 && from < count && to >= 0 && to < count && from != to)) return s
        val currentID = s.exercises[s.clampedIndex].id
        val list = s.exercises.toMutableList()
        val item = list.removeAt(from)
        list.add(to, item)
        val index = list.indexOfFirst { it.id == currentID }
        return s.copy(exercises = list, currentIndex = if (index >= 0) index else s.currentIndex)
    }

    private fun replaceExercise(s: WorkoutState, exerciseID: UUID, replacement: Exercise, now: Instant): WorkoutState {
        val k = s.exerciseIndex(exerciseID) ?: return s
        val old = s.exercises[k]
        var next = s.updateExercise(k) {
            makeEntry(replacement, id = old.id, group = old.supersetGroup, templateEntryID = old.templateEntryID)
        }
        if (next.lastLogged?.exerciseID == old.id) next = next.copy(lastLogged = null)
        // A deleted set of the old exercise no longer fits the new one.
        val payload = next.undo?.payload
        if (payload is UndoPayload.DeletedSet && payload.exerciseID == old.id) next = next.copy(undo = null)
        // Replacing throws away what was logged on the old exercise (and its note): keep it restorable for a few seconds. An exercise
        // with no logged set and no note has only planned values to lose, which are cheap to enter again, so it leaves a pending undo
        // of something else alone.
        if (old.sets.any { it.isDone } || old.note.isNotEmpty()) {
            next = next.copy(
                undo = UndoEntry(
                    payload = UndoPayload.ReplacedExercise(old),
                    title = "Replaced " + old.exercise.name,
                    expiresAt = now.addingTimeInterval(undoWindow),
                ),
            )
        }
        return next
    }

    private fun toggleSuperset(s: WorkoutState, exerciseID: UUID): WorkoutState {
        val k = s.exerciseIndex(exerciseID) ?: return s
        val existing = s.exercises[k].supersetGroup
        if (existing != null) {
            return releaseOrphan(s.updateExercise(k) { it.copy(supersetGroup = null) }, existing)
        }
        if (k + 1 >= s.exercises.size) return s
        val group = s.exercises[k + 1].supersetGroup ?: freeGroup(s)
        return s.updateExercise(k) { it.copy(supersetGroup = group) }.updateExercise(k + 1) { it.copy(supersetGroup = group) }
    }

    /** First of A...E not used by any exercise, else "Z". */
    private fun freeGroup(s: WorkoutState): String {
        val used = s.exercises.mapNotNull { it.supersetGroup }.toSet()
        for (letter in listOf("A", "B", "C", "D", "E")) if (letter !in used) return letter
        return "Z"
    }

    // endregion

    // region Rest timer and pause

    private fun adjustRest(s: WorkoutState, seconds: Int, now: Instant): WorkoutState {
        val current = s.rest
        if (current == null) {
            if (seconds <= 0) return s
            return s.copy(
                rest = RestState(
                    endsAt = now.addingTimeInterval(seconds.toDouble()),
                    totalSeconds = seconds,
                    frozenRemaining = if (s.isPaused) seconds.toDouble() else null,
                ),
            )
        }
        val delta = seconds.toDouble()
        var rest = current.copy(totalSeconds = maxOf(5, saturatingSum(current.totalSeconds, seconds)))
        if (s.isPaused || rest.frozenRemaining != null) {
            val frozen = rest.frozenRemaining ?: maxOf(0.0, rest.endsAt.timeIntervalSince(now))
            rest = rest.copy(frozenRemaining = maxOf(0.0, frozen + delta))
        } else {
            val base = if (rest.endsAt.isAfter(now)) rest.endsAt else now
            val moved = base.addingTimeInterval(delta)
            rest = rest.copy(endsAt = if (moved.isAfter(now)) moved else now)
        }
        return s.copy(rest = rest)
    }

    private fun pause(s: WorkoutState, now: Instant): WorkoutState {
        if (s.pausedAt != null) return s
        val rest = s.rest?.let { it.copy(frozenRemaining = maxOf(0.0, it.endsAt.timeIntervalSince(now))) }
        return s.copy(pausedAt = now, rest = rest)
    }

    private fun resume(state: WorkoutState, now: Instant): WorkoutState {
        var s = state
        val pausedAt = s.pausedAt
        if (pausedAt != null) {
            s = s.copy(pausedTotal = s.pausedTotal + maxOf(0.0, now.timeIntervalSince(pausedAt)), pausedAt = null)
        }
        val rest = s.rest
        val frozen = rest?.frozenRemaining
        if (rest != null && frozen != null) {
            s = s.copy(rest = rest.copy(endsAt = now.addingTimeInterval(maxOf(0.0, frozen)), frozenRemaining = null))
        }
        return s
    }

    // endregion

    // region Undo

    private fun undo(state: WorkoutState, now: Instant): WorkoutState {
        val entry = state.undo ?: return state
        val s = state.copy(undo = null)
        if (now.isAfter(entry.expiresAt)) return s
        return when (val payload = entry.payload) {
            is UndoPayload.RemovedExercise -> {
                val exercise = payload.exercise
                if (s.exercises.any { it.id == exercise.id }) return s
                var restored = exercise
                // Its partner may have left the group when it was removed; a group never has a single member.
                val group = restored.supersetGroup
                if (group != null && s.exercises.none { it.supersetGroup == group }) restored = restored.copy(supersetGroup = null)
                val at = maxOf(0, minOf(payload.index, s.exercises.size))
                val list = s.exercises.toMutableList().also { it.add(at, restored) }
                s.copy(exercises = list, currentIndex = at)
            }
            is UndoPayload.DeletedSet -> {
                val k = s.exerciseIndex(payload.exerciseID) ?: return s
                if (s.exercises.any { e -> e.sets.any { it.id == payload.set.id } }) return s
                val at = maxOf(0, minOf(payload.index, s.exercises[k].sets.size))
                s.updateExercise(k) { entry2 -> entry2.copy(sets = entry2.sets.toMutableList().also { it.add(at, payload.set) }) }
            }
            is UndoPayload.ReplacedExercise -> {
                val original = payload.exercise
                // The replacement carries the entry id of the original; if that entry is gone the undo has nothing to swap back.
                val k = s.exerciseIndex(original.id) ?: return s
                val current = s.exercises[k]
                // Swapping back would throw away what was logged on the replacement in the meantime: then the undo is simply spent.
                if (current.sets.any { it.isDone } || current.note.isNotEmpty()) return s
                // The superset group is whatever the entry belongs to now (its partner may have been toggled since); a group never has
                // a single member.
                s.updateExercise(k) { original.copy(supersetGroup = current.supersetGroup) }.copy(currentIndex = k)
            }
        }
    }

    // endregion
}
