package health.pulse.strength.core.widgets

import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.SetType
import health.pulse.strength.core.WorkoutTemplate
import java.util.UUID

/** How recently and how much each muscle group was trained (widgets/SPEC.md section 2: freshness, weeklySets, bodyMap). */
internal object WidgetMuscles {
    /** The four groups that count toward the weekly volume target; arms and core are trained on the side. */
    val majors: List<MuscleGroup> = listOf(MuscleGroup.CHEST, MuscleGroup.BACK, MuscleGroup.SHOULDERS, MuscleGroup.LEGS)

    /** Weekly sets that each major group should reach, and the total over the four. */
    const val setsPerMajor = 12
    const val totalTarget = 48

    // region Freshness

    /**
     * All six groups in [MuscleGroup] order with the days since the latest workout that trained the group (a `muscleSets` entry with
     * sets); null when never. Status: null or 4+ days is ready, 2 or 3 recovering, 0 or 1 worked.
     */
    fun freshness(history: WidgetHistory): List<MuscleFreshness> = MuscleGroup.entries.map { muscle ->
        val latest = history.entries
            .map { it.workout }
            .filter { workout -> workout.muscleSets.any { it.muscle == muscle && it.sets > 0 } }
            .maxWithOrNull(compareBy { it.finishedAt })
        val days = latest?.let { history.daysAgo(it.finishedAt) }
        val status = when {
            days == null || days >= 4 -> FreshnessStatus.READY
            days >= 2 -> FreshnessStatus.RECOVERING
            else -> FreshnessStatus.WORKED
        }
        MuscleFreshness(muscle = muscle, daysSince = days, status = status)
    }

    // endregion

    // region Weekly sets

    /** The sets of each group in this week's workouts (the sum of their `muscleSets`). */
    fun setsThisWeek(history: WidgetHistory): Map<MuscleGroup, Int> {
        val sets = HashMap<MuscleGroup, Int>()
        for (entry in history.thisWeek) {
            for (item in entry.workout.muscleSets) sets[item.muscle] = (sets[item.muscle] ?: 0) + item.sets
        }
        return sets
    }

    /** The weekly target range of a group: 10...14 sets for chest, back, shoulders and legs, 6...10 for arms and core. */
    fun target(muscle: MuscleGroup): IntRange = if (muscle in majors) 10..14 else 6..10

    /**
     * This week's sets per group against its target. `totalSets` adds the four major groups against 48 (12 each); `laggingMuscle` is
     * the major with the fewest sets (the first in [MuscleGroup] order on a tie), null once every major reached 12.
     */
    fun weeklySets(sets: Map<MuscleGroup, Int>): WeeklySetsSummary {
        val muscles = MuscleGroup.entries.map { muscle ->
            val count = sets[muscle] ?: 0
            val range = target(muscle)
            val status = when {
                count < range.first -> SetsStatus.UNDER
                count > range.last -> SetsStatus.OVER
                else -> SetsStatus.ON_TARGET
            }
            MuscleSetsProgress(muscle = muscle, sets = count, targetLow = range.first, targetHigh = range.last, status = status)
        }
        val total = majors.sumOf { sets[it] ?: 0 }
        var lagging: MuscleGroup? = null
        var laggingSets = Int.MAX_VALUE
        for (muscle in MuscleGroup.entries) {
            if (muscle !in majors) continue
            val count = sets[muscle] ?: 0
            if (count >= setsPerMajor || count >= laggingSets) continue
            lagging = muscle
            laggingSets = count
        }
        return WeeklySetsSummary(
            muscles = muscles,
            totalSets = total,
            totalTarget = totalTarget,
            setsToGo = maxOf(0, totalTarget - total),
            laggingMuscle = lagging,
        )
    }

    // endregion

    // region Body map

    /**
     * How much of the week each group had (0 none, 1 up to 4 sets, 2 up to 9, 3 from 10), the groups without a set, and a sentence
     * about the first major group left out.
     *
     * The sentence names that group ("Legs untouched.") and, when a saved template trains it, the one with the most non-warm-up
     * planned sets of it: " Lower A is next in line." when that template is [nextUp], else " Try Lower A." (the name up to " ·").
     * When every major group was trained: "Every major group has been trained this week."
     */
    fun bodyMap(sets: Map<MuscleGroup, Int>, templates: List<WorkoutTemplate>, nextUp: UUID?): BodyMap {
        val levels = MuscleGroup.entries.map { muscle ->
            val count = sets[muscle] ?: 0
            MuscleLevel(muscle = muscle, level = if (count == 0) 0 else if (count < 5) 1 else if (count < 10) 2 else 3)
        }
        val untouched = MuscleGroup.entries.filter { (sets[it] ?: 0) == 0 }
        val missing = MuscleGroup.entries.firstOrNull { it in majors && (sets[it] ?: 0) == 0 }
            ?: return BodyMap(levels = levels, untouched = untouched, message = "Every major group has been trained this week.")
        var message = missing.title + " untouched."
        val template = templateTraining(missing, templates)
        if (template != null) {
            val name = WidgetText.shortName(template.name)
            message += if (template.id == nextUp) " $name is next in line." else " Try $name."
        }
        return BodyMap(levels = levels, untouched = untouched, message = message)
    }

    /** The template with the most non-warm-up planned sets of [muscle] (the first in store order on a tie); null when none has one. */
    private fun templateTraining(muscle: MuscleGroup, templates: List<WorkoutTemplate>): WorkoutTemplate? {
        var best: WorkoutTemplate? = null
        var bestSets = 0
        for (template in templates) {
            val count = template.entries
                .filter { it.exercise.muscle == muscle }
                .sumOf { entry -> entry.plannedSets.count { it.type != SetType.WARMUP } }
            if (count > bestSets) {
                best = template
                bestSets = count
            }
        }
        return best
    }

    // endregion
}
