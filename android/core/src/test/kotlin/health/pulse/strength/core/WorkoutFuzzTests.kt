package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import java.time.Instant
import java.util.UUID
import org.junit.Test

// Port of WorkoutFuzzTests.swift. The generator is the same Knuth MMIX LCG with the same seeds, so a run draws the same
// action kinds, indexes and values as the Swift run (only the freshly generated UUIDs differ).

/**
 * Seeded linear congruential generator (Knuth's MMIX constants): deterministic, no real randomness.
 * The Swift original works on `UInt64` with wrapping arithmetic; a `Long` has the same bits, and the output is taken with an
 * unsigned shift, so it is always non-negative (31 bits).
 */
internal class RedLCG(seed: Long) {
    private var state: Long = seed

    fun next(): Long {
        state = state * 6_364_136_223_846_793_005L + 1_442_695_040_888_963_407L
        return state ushr 33
    }

    /** A value in `lower..upper` (inclusive). */
    fun int(lower: Int, upper: Int): Int {
        val span = (upper - lower + 1).toLong()
        return lower + (next() % span).toInt()
    }

    /** True `percent` times out of 100. */
    fun chance(percent: Int): Boolean = int(0, 99) < percent

    fun <T> pick(items: List<T>): T = items[int(0, items.size - 1)]
}

/** Draws random but plausible actions for a state: mostly valid ids, sometimes unknown or mismatched ones. */
internal class RedActionGenerator(seed: Long) {
    val rng = RedLCG(seed)
    private var ghosts = 0

    /** Index of the last drawn action kind (for reproducibility checks). */
    var lastKind = 0
        private set

    private fun ghostID(): UUID {
        ghosts += 1
        return RedFix.uuid(0xDEAD, ghosts)
    }

    private fun exerciseID(s: WorkoutState): UUID {
        if (s.exercises.isEmpty() || rng.chance(8)) return ghostID()
        return s.exercises[rng.int(0, s.exercises.size - 1)].id
    }

    private fun target(s: WorkoutState): Pair<UUID, UUID> {
        val roll = rng.int(0, 99)
        val withSets = s.exercises.filter { it.sets.isNotEmpty() }
        if (roll < 88 && withSets.isNotEmpty()) {
            val entry = withSets[rng.int(0, withSets.size - 1)]
            return entry.id to entry.sets[rng.int(0, entry.sets.size - 1)].id
        }
        if (roll < 94 && s.exercises.isNotEmpty()) {
            return s.exercises[rng.int(0, s.exercises.size - 1)].id to ghostID()
        }
        return ghostID() to ghostID()
    }

    private fun weight(): Double =
        rng.pick(listOf(-5.0, 0.0, 0.004, 22.5, 47.5, 82.505, 100.0, 250.25, Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, 1e300))

    private fun exercises(): List<Exercise> {
        val count = rng.int(0, 3)
        return List(count) { rng.pick(RedFix.pool) }
    }

    fun next(s: WorkoutState): WorkoutAction {
        // Keep the workout from shrinking to nothing or growing without bound.
        if (s.exercises.size < 2 && rng.chance(50)) {
            lastKind = 28
            return WorkoutAction.AddExercises(exercises())
        }
        if (s.exercises.size > 9 && rng.chance(30)) {
            lastKind = 29
            return WorkoutAction.RemoveExercise(exerciseID(s))
        }
        // Right after a removal / deletion the user is likely to tap "Undo".
        if (s.undo != null && rng.chance(30)) {
            lastKind = 43
            return WorkoutAction.Undo
        }
        val kind = rng.int(0, 47)
        lastKind = kind
        val count = s.exercises.size
        return when (kind) {
            in 0..5 -> { val (e, st) = target(s); WorkoutAction.ToggleSet(e, st) }
            in 6..9 -> { val (e, st) = target(s); WorkoutAction.LogSet(e, st) }
            in 10..13 -> WorkoutAction.LogNextSet
            14 -> { val (e, st) = target(s); WorkoutAction.SetWeight(e, st, weight()) }
            15 -> {
                val (e, st) = target(s)
                WorkoutAction.SetReps(e, st, rng.pick(listOf(-50, 0, 1, 8, 12, 45, 999, 1_200, Int.MAX_VALUE, Int.MIN_VALUE)))
            }
            in 16..17 -> {
                val weightSteps = rng.pick(listOf(-3, -1, 0, 1, 2, 5, 100_000, Int.MIN_VALUE, Int.MAX_VALUE))
                val repsSteps = rng.pick(listOf(-5, -1, 0, 1, 3, 100_000, Int.MIN_VALUE, Int.MAX_VALUE))
                WorkoutAction.NudgeNextSet(weightSteps, repsSteps)
            }
            18 -> { val (e, st) = target(s); WorkoutAction.SetSetType(e, st, rng.pick(SetType.entries)) }
            19 -> { val (e, st) = target(s); WorkoutAction.SetRIR(e, st, rng.pick(listOf<Int?>(null, -2, 0, 1, 2, 3, 4, 9))) }
            in 20..21 -> WorkoutAction.ToggleLastSetRIR(rng.pick(listOf(-1, 0, 1, 2, 3, 4, 7)))
            22 -> WorkoutAction.AddSet(exerciseID(s))
            23 -> { val (e, st) = target(s); WorkoutAction.DeleteSet(e, st) }
            24 -> WorkoutAction.SetNote(exerciseID(s), rng.pick(listOf("", "slow", "belt on")))
            25 -> WorkoutAction.GoTo(rng.int(-3, count + 3))
            26 -> WorkoutAction.NextExercise
            27 -> WorkoutAction.PreviousExercise
            28 -> WorkoutAction.AddExercises(exercises())
            29 -> WorkoutAction.RemoveExercise(exerciseID(s))
            30 -> {
                val from = rng.int(-2, count + 1)
                val to = rng.int(-2, count + 1)
                WorkoutAction.MoveExercise(from, to)
            }
            31 -> {
                val id = exerciseID(s)
                WorkoutAction.MoveExerciseBy(id, rng.pick(listOf(-3, -1, 0, 1, 1, 2, 7, Int.MAX_VALUE, Int.MIN_VALUE)))
            }
            32 -> {
                val id = exerciseID(s)
                WorkoutAction.ReplaceExercise(id, rng.pick(RedFix.pool))
            }
            in 33..34 -> WorkoutAction.ToggleSuperset(exerciseID(s))
            35 -> {
                val id = exerciseID(s)
                WorkoutAction.SetRest(id, rng.pick(listOf(-30, 0, 30, 45, 60, 90, 150, 600, Int.MAX_VALUE, Int.MIN_VALUE)))
            }
            in 36..37 -> WorkoutAction.AdjustRest(rng.pick(listOf(-3_600, -15, -15, 15, 15, 30, 3_600, Int.MAX_VALUE, Int.MIN_VALUE)))
            38 -> WorkoutAction.SkipRest
            39 -> WorkoutAction.SetAutoStartRest(rng.chance(70))
            40 -> WorkoutAction.SetAlertWhenRestEnds(rng.chance(50))
            41 -> WorkoutAction.Pause
            42 -> WorkoutAction.Resume
            in 43..44 -> WorkoutAction.Undo
            45 -> WorkoutAction.UpdateHeartRate(rng.pick(listOf<Int?>(null, -1, 0, 29, 30, 95, 128, 180, 240, 241, 400)))
            46 -> WorkoutAction.SetUsedWatch(rng.chance(50))
            else -> WorkoutAction.Rename(rng.pick(listOf("", "Push", "Upper A · Push")))
        }
    }
}

class WorkoutFuzzTests {
    private companion object {
        const val stepsPerRun = 2_000
    }

    // region Fixtures

    private fun fixtures(): List<Pair<String, WorkoutState>> {
        val supersetHeavy = RedFix.state(
            listOf(
                RedFix.entry(1, RedFix.lateral, RedFix.normal(3, 8.0, 15), rest = 60, group = "A"),
                RedFix.entry(2, RedFix.pushdown, RedFix.normal(3, 30.0, 12), rest = 60, group = "A"),
                RedFix.entry(3, RedFix.bench, RedFix.normal(3, 80.0, 5), rest = 150, group = "B"),
                RedFix.entry(4, RedFix.ohp, RedFix.normal(3, 45.0, 8), rest = 120, group = "B"),
                RedFix.entry(5, RedFix.incline, RedFix.normal(3, 28.0, 10), rest = 90, group = "B"),
                RedFix.entry(6, RedFix.crossover, RedFix.normal(2, 15.0, 12), rest = 60),
                RedFix.entry(7, RedFix.pushup, RedFix.normal(2, 0.0, 12), rest = 60),
                RedFix.entry(8, RedFix.plank, RedFix.normal(2, 0.0, 45), rest = 45),
            ),
        )
        val pausedWithRest = RedFix.designState().copy(
            pausedAt = RedFix.at(30),
            pausedTotal = 10.0,
            rest = RestState(endsAt = RedFix.at(100), totalSeconds = 90, frozenRemaining = 70.0),
        )
        var halfDone = RedFix.designState()
        halfDone = RedFix.withDone(halfDone, 0, 0 until 5)
        halfDone = halfDone.copy(currentIndex = 1)
        return listOf(
            "design" to RedFix.designState(),
            "empty" to WorkoutState(id = RedFix.uuid(1, 3), name = "Empty", startedAt = RedFix.t0),
            "single plank set" to RedFix.state(listOf(RedFix.entry(1, RedFix.plank, RedFix.normal(1, 0.0, 45), rest = 45))),
            "supersets" to supersetHeavy,
            "paused with rest" to pausedWithRest,
            "half done" to halfDone,
        )
    }

    // endregion

    // region Runs

    /** Aggregated numbers of one run, used to show that the generator reached the interesting code. */
    private class RunStats {
        var changed = 0
        var undoRestored = 0
        var restsStarted = 0
        var supersetJumps = 0
        var emptied = 0
        val kinds = mutableListOf<Int>()
    }

    private fun run(label: String, start: WorkoutState, seed: Long, steps: Int): Pair<WorkoutState, RunStats> {
        val generator = RedActionGenerator(seed)
        var state = start
        val stats = RunStats()
        var now: Instant = RedFix.t0
        for (step in 1..steps) {
            // Time moves in whole seconds; mostly short gaps so the 6 s undo window is hit from both sides.
            if (generator.rng.chance(5)) {
                now = now.addingTimeInterval(300.0)
            } else if (!generator.rng.chance(10)) {
                now = now.addingTimeInterval(generator.rng.int(1, 9).toDouble())
            }
            val before = state
            val action = generator.next(before)
            stats.kinds.add(generator.lastKind)
            state = WorkoutReducer.reduce(state, action, now)
            val context = "[$label seed $seed step $step] $action"
            checkInvariants(state, before, action, now, context)

            // The same input must give the same output (apart from freshly generated ids).
            if (!RedFix.createsNewIDs(action)) {
                val again = WorkoutReducer.reduce(before, action, now)
                assertWithMessage("not deterministic $context").that(again).isEqualTo(state)
            }

            val withoutRevision = state.copy(revision = before.revision)
            if (withoutRevision != before) stats.changed += 1
            if (action is WorkoutAction.Undo) {
                val beforeCount = before.exercises.size + before.exercises.fold(0) { acc, e -> acc + e.sets.size }
                val afterCount = state.exercises.size + state.exercises.fold(0) { acc, e -> acc + e.sets.size }
                if (afterCount > beforeCount) stats.undoRestored += 1
            }
            val rest = state.rest
            if (rest != null && rest != before.rest) stats.restsStarted += 1
            if (action is WorkoutAction.ToggleSet && before.currentIndex != state.currentIndex) stats.supersetJumps += 1
            if (state.exercises.isEmpty()) stats.emptied += 1
        }
        return state to stats
    }

    @Test
    fun testRandomActionsKeepTheInvariants() {
        var changed = 0
        var undoRestored = 0
        var restsStarted = 0
        var supersetJumps = 0
        var emptied = 0
        for ((n, fixture) in fixtures().withIndex()) {
            val (label, start) = fixture
            val (_, stats) = run(label, start, seed = 0xC0FFEEL + n.toLong() * 7_919L, steps = stepsPerRun)
            changed += stats.changed
            undoRestored += stats.undoRestored
            restsStarted += stats.restsStarted
            supersetJumps += stats.supersetJumps
            emptied += stats.emptied
            assertWithMessage("too few effective actions in $label").that(stats.changed).isGreaterThan(stepsPerRun / 4)
        }
        // The runs must really have exercised these paths.
        assertThat(undoRestored).isGreaterThan(5)
        assertThat(restsStarted).isGreaterThan(100)
        assertThat(supersetJumps).isGreaterThan(20)
        assertThat(emptied).isGreaterThan(0)
    }

    @Test
    fun testRandomActionsWithSeveralSeedsOnTheDesignWorkout() {
        for (seed in listOf(1L, 2L, 3L, 4L, 5L, 6L, 7L, 8L)) {
            run("design", RedFix.designState(), seed = seed, steps = 500)
        }
    }

    @Test
    fun testTheGeneratorIsReproducible() {
        val first = run("design", RedFix.designState(), seed = 424_242L, steps = 400)
        val second = run("design", RedFix.designState(), seed = 424_242L, steps = 400)
        assertThat(first.second.kinds).isEqualTo(second.second.kinds)
        assertThat(first.second.changed).isEqualTo(second.second.changed)
        assertThat(first.first.exercises.map { it.exercise.id }).isEqualTo(second.first.exercises.map { it.exercise.id })
        assertThat(first.first.exercises.map { it.sets.size }).isEqualTo(second.first.exercises.map { it.sets.size })
        assertThat(first.first.revision).isEqualTo(second.first.revision)
        assertThat(first.first.currentIndex).isEqualTo(second.first.currentIndex)
    }

    @Test
    fun testTheGeneratorCoversEveryActionKind() {
        val generator = RedActionGenerator(99L)
        val state = RedFix.designState()
        val seen = mutableSetOf<Int>()
        repeat(5_000) {
            generator.next(state)
            seen.add(generator.lastKind)
        }
        assertThat(seen).isEqualTo((0..47).toSet())
    }

    @Test
    fun testLCGIsDeterministicAndStaysInRange() {
        val a = RedLCG(5L)
        val b = RedLCG(5L)
        repeat(1_000) {
            val value = a.int(-3, 4)
            assertThat(value).isEqualTo(b.int(-3, 4))
            assertThat(value in -3..4).isTrue()
        }
        val c = RedLCG(1L)
        val d = RedLCG(2L)
        assertThat(c.int(0, 1_000_000)).isNotEqualTo(d.int(0, 1_000_000))
    }

    /**
     * Kotlin-only addition (no Swift test): pins the generator to the Swift algorithm (`state &* 6364136223846793005 &+
     * 1442695040888963407`, output `state >> 33` on an unsigned 64-bit value). The expected numbers were computed independently
     * with explicit 64-bit wrap-around, so the Kotlin runs draw the same actions as the Swift runs for the same seeds.
     */
    @Test
    fun testKotlinOnlyLCGMatchesTheSwiftAlgorithm() {
        val five = RedLCG(5L)
        assertThat(List(5) { five.next() }).isEqualTo(listOf(1724882992L, 301167773L, 1762018234L, 664543405L, 950767375L))
        val coffee = RedLCG(0xC0FFEEL)
        assertThat(List(5) { coffee.next() }).isEqualTo(listOf(2050262658L, 1790554111L, 732548580L, 275558325L, 1125235454L))
        val percent = RedLCG(99L)
        assertThat(List(8) { percent.int(0, 99) }).isEqualTo(listOf(73, 76, 32, 77, 64, 78, 13, 0))
    }

    // endregion

    // region Invariants

    private fun checkInvariants(s: WorkoutState, b: WorkoutState, action: WorkoutAction, now: Instant, context: String) {
        // currentIndex within bounds (0 when empty)
        if (s.exercises.isEmpty()) {
            assertWithMessage("index of an empty workout $context").that(s.currentIndex).isEqualTo(0)
        } else {
            assertWithMessage("index ${s.currentIndex} out of bounds $context").that(s.currentIndex in 0 until s.exercises.size).isTrue()
        }

        // no duplicate ids
        val exerciseIDs = s.exercises.map { it.id }
        assertWithMessage("duplicate exercise ids $context").that(exerciseIDs.toSet().size).isEqualTo(exerciseIDs.size)
        val setIDs = s.exercises.flatMap { e -> e.sets.map { it.id } }
        assertWithMessage("duplicate set ids $context").that(setIDs.toSet().size).isEqualTo(setIDs.size)

        // a superset group never has a single member
        val groupSizes = mutableMapOf<String, Int>()
        for (entry in s.exercises) {
            entry.supersetGroup?.let { groupSizes[it] = (groupSizes[it] ?: 0) + 1 }
        }
        for ((group, size) in groupSizes) {
            assertWithMessage("single member superset $group $context").that(size).isAtLeast(2)
        }

        // rest totals >= 0 or nil; frozen exactly while paused
        val rest = s.rest
        if (rest != null) {
            assertWithMessage("negative rest total $context").that(rest.totalSeconds).isAtLeast(0)
            val frozen = rest.frozenRemaining
            if (frozen != null) {
                assertWithMessage("negative frozen rest $context").that(frozen).isAtLeast(0.0)
            }
            assertWithMessage("frozen iff paused $context").that(rest.frozenRemaining != null).isEqualTo(s.pausedAt != null)
        }
        for (entry in s.exercises) {
            assertWithMessage("negative exercise rest $context").that(entry.restSeconds).isAtLeast(0)
        }

        // revision never decreases and moves by exactly one for a real change (never for heart rate)
        val withoutRevision = s.copy(revision = b.revision)
        val changed = withoutRevision != b
        val isHeartRate = action is WorkoutAction.UpdateHeartRate
        assertWithMessage("revision decreased $context").that(s.revision).isAtLeast(b.revision)
        assertWithMessage("revision rule $context").that(s.revision).isEqualTo(b.revision + (if (changed && !isHeartRate) 1 else 0))

        // lastLogged always resolves to an existing set
        val ref = s.lastLogged
        if (ref != null) {
            val found = s.exercises.firstOrNull { it.id == ref.exerciseID }?.sets?.any { it.id == ref.setID } ?: false
            assertWithMessage("dangling lastLogged $context").that(found).isTrue()
        }

        // set values stay in their ranges
        for (entry in s.exercises) {
            for (set in entry.sets) {
                assertWithMessage("bad weight ${set.weightKg} $context").that(set.weightKg.isFinite() && set.weightKg >= 0).isTrue()
                assertWithMessage("bad reps ${set.reps} $context").that(set.reps in 0..999).isTrue()
                val rir = set.rir
                if (rir != null) assertWithMessage("bad rir $rir $context").that(rir in 0..4).isTrue()
            }
        }

        // pause bookkeeping
        assertWithMessage("pausedTotal decreased $context").that(s.pausedTotal).isAtLeast(b.pausedTotal)
        assertWithMessage(context).that(s.pausedTotal).isAtLeast(0.0)

        // heart-rate totals only grow, by at most one sample per update, and only for updates
        assertWithMessage(context).that(s.heartRateCount).isAtLeast(b.heartRateCount)
        assertWithMessage("heart rate count $context").that(s.heartRateCount).isAtMost(b.heartRateCount + (if (isHeartRate) 1 else 0))
        if (!isHeartRate) {
            assertWithMessage(context).that(s.heartRateSum).isEqualTo(b.heartRateSum)
            assertWithMessage(context).that(s.heartRate).isEqualTo(b.heartRate)
        }

        // the next pending set, when there is one, is pending; when there is none, everything is logged
        val target = WorkoutTargets.nextPending(s)
        if (target != null) {
            assertWithMessage("next pending is done $context").that(s.exercises[target.exerciseIndex].sets[target.setIndex].isDone).isFalse()
        } else {
            assertWithMessage("pending set not found $context").that(s.exercises.all { e -> e.sets.all { it.isDone } }).isTrue()
        }

        // pause freezes the remaining rest, resume thaws it from `now`, undo respects the window and always clears the entry
        when (action) {
            WorkoutAction.Pause -> {
                val before = b.rest
                if (b.pausedAt == null && before != null) {
                    assertWithMessage(context).that(s.pausedAt).isEqualTo(now)
                    assertWithMessage("pause freeze $context").that(s.rest?.frozenRemaining)
                        .isEqualTo(maxOf(0.0, before.endsAt.timeIntervalSince(now)))
                }
            }
            WorkoutAction.Resume -> {
                val frozen = b.rest?.frozenRemaining
                if (b.pausedAt != null && frozen != null) {
                    assertWithMessage(context).that(s.pausedAt).isNull()
                    assertWithMessage("resume thaw $context").that(s.rest?.endsAt).isEqualTo(now.addingTimeInterval(maxOf(0.0, frozen)))
                }
            }
            WorkoutAction.Undo -> {
                assertWithMessage("undo keeps its entry $context").that(s.undo).isNull()
                val entry = b.undo
                if (entry != null && now.isAfter(entry.expiresAt)) {
                    assertWithMessage("undo outside the window restored something $context").that(s.exercises).isEqualTo(b.exercises)
                }
            }
            else -> Unit
        }

        // an undo entry always expires after it was created within the window
        val undo = s.undo
        if (undo != null && undo.expiresAt != b.undo?.expiresAt) {
            assertWithMessage("undo title $context").that(undo.title == "Set deleted" || undo.title.startsWith("Removed ") || undo.title.startsWith("Replaced ")).isTrue()
        }
    }

    // endregion
}
