package health.pulse.strength.core

import java.time.Instant
import java.util.UUID

/**
 * Demo templates, finished workouts and personal bests for demo seeding, previews and tests.
 *
 * Everything is derived from one set of definitions, so it is consistent: `now` is "today"; "Upper A · Push" was last done 5 days ago;
 * bench sessions exist 5 days ago (W 50×8, W 70×5, 80×6, 80×6, 80×5), 10 days ago (W 50×8, W 70×5, 80×6, 82.5×5, 85×5, the personal
 * record with an estimated 1RM of 99) and 15 days ago (W 50×8, 77.5×6 ×3); "Lower A · Quads" was done 7 days ago and "Upper B · Pull"
 * 3 days ago. The personal bests are the best sets of that history (bench: 85 kg × 5, 10 days ago). Ids are fixed, so repeated calls
 * return equal values.
 */
object SampleData {
    // region Public API

    /** The three demo templates: "Upper A · Push", "Lower A · Quads" and "Upper B · Pull" (never performed). */
    fun templates(): List<WorkoutTemplate> = listOf(upperPush(), lowerQuads(), upperPull())

    /** The demo templates with `lastPerformed` taken from the demo history of [now]. */
    fun templates(now: Instant): List<WorkoutTemplate> {
        val finished = history(now)
        return templates().map { template ->
            template.copy(lastPerformed = finished.firstOrNull { it.templateID == template.id }?.finishedAt)
        }
    }

    /** The five demo workouts, newest first: Upper B (3 days ago), Upper A (5), Lower A (7), Upper A (10, bench record), Upper A (15). */
    fun history(now: Instant): List<CompletedWorkout> {
        // Best estimated 1RMs from before the demo window. The bench best is beaten 10 days ago (the one personal record of the
        // demo); the others are already at their level, so no other exercise is flagged.
        val baseline = mutableMapOf(
            "bench" to 95.0, "incline" to 38.0, "ohp" to 58.4, "lateral" to 12.6, "pushdown" to 43.0, "crossover" to 22.0,
        )
        val workouts = mutableListOf<CompletedWorkout>()
        for (session in sessionDefinitions().sortedByDescending { it.daysAgo }) {
            workouts.add(makeWorkout(session, now, baseline))
        }
        return workouts.reversed()
    }

    /** The best set per exercise of the demo history (bench: 85 kg × 5, 10 days ago, estimated 1RM 99). */
    fun personalBests(now: Instant): Map<String, PersonalBest> {
        val bests = mutableMapOf<String, PersonalBest>()
        for (workout in history(now).reversed()) {
            for (entry in workout.exercises) {
                if (!(entry.bestE1RM > 0)) continue
                if (entry.bestE1RM > (bests[entry.exerciseID]?.estimated1RM ?: 0.0) + 1e-9) {
                    val best = bestSet(entry.sets)
                    bests[entry.exerciseID] = PersonalBest(
                        exerciseID = entry.exerciseID,
                        estimated1RM = entry.bestE1RM,
                        weightKg = best?.weightKg ?: 0.0,
                        reps = best?.reps ?: 0,
                        date = workout.finishedAt,
                    )
                }
            }
        }
        return bests
    }

    // endregion

    // region Templates

    private fun upperPush(): WorkoutTemplate = WorkoutTemplate(
        id = fixedID(1, 1),
        name = "Upper A · Push",
        entries = listOf(
            entry(1, "bench", listOf(planned(SetType.WARMUP, 50.0, 8), planned(SetType.WARMUP, 70.0, 5), planned(SetType.NORMAL, 82.5, 6), planned(SetType.NORMAL, 82.5, 6), planned(SetType.NORMAL, 85.0, 6)), rest = 150),
            entry(2, "incline", straight(3, 28.0, 10), rest = 90),
            entry(3, "ohp", straight(3, 45.0, 8), rest = 120),
            entry(4, "lateral", straight(3, 8.0, 15), rest = 60, group = "A"),
            entry(5, "pushdown", straight(3, 30.0, 12), rest = 60, group = "A"),
            entry(6, "crossover", straight(3, 15.0, 12), rest = 60),
        ),
    )

    private fun lowerQuads(): WorkoutTemplate = WorkoutTemplate(
        id = fixedID(1, 2),
        name = "Lower A · Quads",
        entries = listOf(
            entry(11, "squat", listOf(planned(SetType.WARMUP, 40.0, 8), planned(SetType.WARMUP, 60.0, 5), planned(SetType.NORMAL, 80.0, 6), planned(SetType.NORMAL, 80.0, 6), planned(SetType.NORMAL, 80.0, 6)), rest = 180),
            entry(12, "legpress", straight(3, 140.0, 10), rest = 120),
            entry(13, "lunge", straight(3, 12.0, 10), rest = 90),
            entry(14, "legext", straight(3, 45.0, 12), rest = 75),
            entry(15, "calf", straight(4, 60.0, 12), rest = 60),
        ),
    )

    private fun upperPull(): WorkoutTemplate = WorkoutTemplate(
        id = fixedID(1, 3),
        name = "Upper B · Pull",
        entries = listOf(
            entry(21, "pullup", straight(3, 0.0, 8), rest = 120),
            entry(22, "brow", listOf(planned(SetType.WARMUP, 40.0, 8), planned(SetType.NORMAL, 60.0, 8), planned(SetType.NORMAL, 60.0, 8), planned(SetType.NORMAL, 60.0, 8)), rest = 120),
            entry(23, "pulldown", straight(3, 55.0, 10), rest = 90),
            entry(24, "crow", straight(3, 50.0, 10), rest = 90),
            entry(25, "facepull", straight(3, 20.0, 15), rest = 60),
            entry(26, "curl", straight(3, 30.0, 10), rest = 75),
        ),
    )

    private fun entry(number: Int, exerciseID: String, sets: List<PlannedSet>, rest: Int, group: String? = null): TemplateEntry =
        TemplateEntry(id = fixedID(2, number), exercise = libraryExercise(exerciseID), plannedSets = sets, restSeconds = rest, supersetGroup = group)

    private fun planned(type: SetType, kg: Double, reps: Int): PlannedSet = PlannedSet(type = type, weightKg = kg, reps = reps)

    private fun straight(count: Int, kg: Double, reps: Int): List<PlannedSet> = List(count) { planned(SetType.NORMAL, kg, reps) }

    /** The built-in exercise [id]; the fallback only exists so a mistyped id can never crash a preview. */
    private fun libraryExercise(id: String): Exercise {
        ExerciseLibrary.exercise(id)?.let { return it }
        return Exercise(
            id = id,
            name = id,
            muscle = MuscleGroup.CORE,
            equipment = Equipment.OTHER,
            defaults = ExerciseDefaults(sets = 3, weightKg = 0.0, reps = 10, restSeconds = 60),
        )
    }

    // endregion

    // region History definitions

    private class SessionDefinition(
        val number: Int,
        val name: String,
        val templateID: UUID,
        val daysAgo: Int,
        val minutes: Int,
        val averageHeartRate: Int?,
        val lines: List<Pair<String, List<CompletedSet>>>,
    )

    private fun warmup(kg: Double, reps: Int): CompletedSet = CompletedSet(type = SetType.WARMUP, weightKg = kg, reps = reps)

    private fun work(kg: Double, reps: Int, rir: Int? = null): CompletedSet = CompletedSet(type = SetType.NORMAL, weightKg = kg, reps = reps, rir = rir)

    private fun sessionDefinitions(): List<SessionDefinition> {
        val upperA = fixedID(1, 1)
        val lowerA = fixedID(1, 2)
        val upperB = fixedID(1, 3)
        return listOf(
            SessionDefinition(
                1, "Upper B · Pull", upperB, daysAgo = 3, minutes = 52, averageHeartRate = 124,
                lines = listOf(
                    "pullup" to listOf(work(0.0, 8, 2), work(0.0, 8, 2), work(0.0, 7, 1)),
                    "brow" to listOf(warmup(40.0, 8), work(60.0, 8, 3), work(60.0, 8, 2), work(60.0, 7, 1)),
                    "pulldown" to listOf(work(55.0, 10), work(55.0, 10), work(55.0, 9)),
                    "crow" to listOf(work(50.0, 10), work(50.0, 10), work(50.0, 10)),
                    "facepull" to listOf(work(20.0, 15), work(20.0, 15), work(20.0, 15)),
                    "curl" to listOf(work(30.0, 10), work(30.0, 10), work(30.0, 9)),
                ),
            ),
            SessionDefinition(
                2, "Upper A · Push", upperA, daysAgo = 5, minutes = 49, averageHeartRate = 126,
                lines = listOf(
                    "bench" to listOf(warmup(50.0, 8), warmup(70.0, 5), work(80.0, 6, 3), work(80.0, 6, 2), work(80.0, 5, 1)),
                    "incline" to listOf(work(26.0, 10), work(26.0, 10), work(26.0, 9)),
                    "ohp" to listOf(work(45.0, 8), work(45.0, 8), work(45.0, 7)),
                    "lateral" to listOf(work(8.0, 15), work(8.0, 15), work(8.0, 14)),
                    "pushdown" to listOf(work(30.0, 12), work(30.0, 12), work(30.0, 11)),
                    "crossover" to listOf(work(15.0, 12), work(15.0, 12), work(15.0, 11)),
                ),
            ),
            SessionDefinition(
                3, "Lower A · Quads", lowerA, daysAgo = 7, minutes = 61, averageHeartRate = 118,
                lines = listOf(
                    "squat" to listOf(warmup(40.0, 8), warmup(60.0, 5), work(80.0, 6, 3), work(80.0, 6, 2), work(80.0, 6, 1)),
                    "legpress" to listOf(work(140.0, 10), work(140.0, 10), work(140.0, 10)),
                    "lunge" to listOf(work(12.0, 10), work(12.0, 10), work(12.0, 10)),
                    "legext" to listOf(work(45.0, 12), work(45.0, 12), work(45.0, 12)),
                    "calf" to listOf(work(60.0, 12), work(60.0, 12), work(60.0, 12), work(60.0, 12)),
                ),
            ),
            SessionDefinition(
                4, "Upper A · Push", upperA, daysAgo = 10, minutes = 56, averageHeartRate = 131,
                lines = listOf(
                    "bench" to listOf(warmup(50.0, 8), warmup(70.0, 5), work(80.0, 6, 3), work(82.5, 5, 2), work(85.0, 5, 1)),
                    "incline" to listOf(work(28.0, 10), work(30.0, 8), work(28.0, 9)),
                    "ohp" to listOf(work(45.0, 8), work(47.5, 6), work(50.0, 5)),
                    "lateral" to listOf(work(8.0, 15), work(8.0, 16), work(8.0, 17)),
                    "pushdown" to listOf(work(30.0, 12), work(30.0, 13), work(30.0, 12)),
                    "crossover" to listOf(work(15.0, 12), work(15.0, 13), work(15.0, 14)),
                ),
            ),
            SessionDefinition(
                5, "Upper A · Push", upperA, daysAgo = 15, minutes = 51, averageHeartRate = null,
                lines = listOf(
                    "bench" to listOf(warmup(50.0, 8), work(77.5, 6), work(77.5, 6), work(77.5, 6)),
                    "incline" to listOf(work(24.0, 10), work(24.0, 10), work(24.0, 10)),
                    "ohp" to listOf(work(42.5, 8), work(42.5, 8), work(42.5, 8)),
                    "lateral" to listOf(work(8.0, 14), work(8.0, 14), work(8.0, 14)),
                    "pushdown" to listOf(work(27.5, 12), work(27.5, 12), work(27.5, 12)),
                    "crossover" to listOf(work(15.0, 12), work(15.0, 12), work(15.0, 12)),
                ),
            ),
        )
    }

    /** Builds one finished workout; [baseline] holds the best e1RM known before it and is raised by it (oldest workout first). */
    private fun makeWorkout(session: SessionDefinition, now: Instant, baseline: MutableMap<String, Double>): CompletedWorkout {
        val exercises = mutableListOf<CompletedExercise>()
        val records = mutableListOf<PersonalRecord>()
        var volume = 0.0
        var loggedSets = 0
        val rirValues = mutableListOf<Int>()
        val muscleCounts = mutableMapOf<MuscleGroup, Int>()

        for ((index, line) in session.lines.withIndex()) {
            val exercise = libraryExercise(line.first)
            val sets = line.second
            val workingSets = sets.filter { it.type != SetType.WARMUP }
            val best = if (exercise.tracksWeight) bestSet(sets) else null
            val bestValue = best?.e1RM ?: 0.0
            val previous = baseline[exercise.id] ?: 0.0
            val isRecord = previous > 0 && bestValue > previous + 0.05
            baseline[exercise.id] = maxOf(previous, bestValue)

            if (isRecord && best != null) {
                records.add(
                    PersonalRecord(
                        exerciseID = exercise.id,
                        exerciseName = exercise.name,
                        weightKg = best.weightKg,
                        reps = best.reps,
                        estimated1RM = bestValue,
                        previousBest = previous,
                    ),
                )
            }
            if (exercise.tracksWeight) {
                volume += workingSets.fold(0.0) { acc, set -> acc + set.weightKg * set.reps.toDouble() }
            }
            loggedSets += sets.size
            rirValues.addAll(sets.mapNotNull { it.rir })
            muscleCounts[exercise.muscle] = (muscleCounts[exercise.muscle] ?: 0) + workingSets.size

            exercises.add(
                CompletedExercise(
                    id = fixedID(4, session.number * 100 + index + 1),
                    exerciseID = exercise.id,
                    name = exercise.name,
                    muscle = exercise.muscle,
                    mediaKey = exercise.mediaKey,
                    tracking = exercise.tracking,
                    sets = sets,
                    isPersonalRecord = isRecord,
                    bestE1RM = bestValue,
                ),
            )
        }

        val muscleSets = muscleCounts
            .filter { it.value > 0 }
            .map { MuscleSets(muscle = it.key, sets = it.value) }
            .sortedWith { lhs, rhs -> if (lhs.sets != rhs.sets) rhs.sets.compareTo(lhs.sets) else lhs.muscle.rawValue.compareTo(rhs.muscle.rawValue) }

        val finishedAt = now.addingTimeInterval(-session.daysAgo.toDouble() * 86_400.0)
        val duration = session.minutes * 60
        return CompletedWorkout(
            id = fixedID(3, session.number),
            name = session.name,
            templateID = session.templateID,
            startedAt = finishedAt.addingTimeInterval(-duration.toDouble()),
            finishedAt = finishedAt,
            durationSeconds = duration,
            volumeKg = volume,
            loggedSets = loggedSets,
            averageHeartRate = session.averageHeartRate,
            averageRIR = if (rirValues.isEmpty()) null else rirValues.sum().toDouble() / rirValues.size.toDouble(),
            exercises = exercises,
            personalRecords = records,
            muscleSets = muscleSets,
        )
    }

    /** The non-warm-up set with the highest Epley estimate (first on a tie). */
    private fun bestSet(sets: List<CompletedSet>): StrengthData.Companion.BestSet? {
        var best: StrengthData.Companion.BestSet? = null
        for (set in sets) {
            if (set.type == SetType.WARMUP) continue
            val value = Estimated1RM.epley(set.weightKg, set.reps)
            if (value > (best?.e1RM ?: 0.0)) best = StrengthData.Companion.BestSet(value, set.weightKg, set.reps)
        }
        return best
    }

    /** A UUID that never changes: `5EED<group as 4 hex digits>-0000-4000-8000-<index as 12 hex digits>`. */
    private fun fixedID(group: Int, index: Int): UUID = UUID.fromString("5EED" + hex(group, 4) + "-0000-4000-8000-" + hex(index, 12))

    private fun hex(value: Int, width: Int): String {
        val digits = value.toString(16).uppercase()
        return "0".repeat(maxOf(0, width - digits.length)) + digits
    }

    // endregion
}
