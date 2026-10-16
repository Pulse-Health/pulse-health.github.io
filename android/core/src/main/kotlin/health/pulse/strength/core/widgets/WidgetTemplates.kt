package health.pulse.strength.core.widgets

import health.pulse.strength.core.CompletedSet
import health.pulse.strength.core.Estimated1RM
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.NumberText
import health.pulse.strength.core.PlateCalculator
import health.pulse.strength.core.SetType
import health.pulse.strength.core.TemplateEntry
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutTemplate
import java.time.Instant
import java.util.UUID

/**
 * What the snapshot says about the saved templates: the next workout, the launcher list and the cards derived from the next
 * workout's exercises (widgets/SPEC.md section 2: nextUp, templates, overload, formCue, loadedBar).
 */
internal object WidgetTemplates {
    // region Next up and the launcher

    /**
     * The template to do next while no training plan is active: the one after the most recently performed template in the list,
     * wrapping around (Upper A, Lower A, Upper B, then Upper A again). Without a performed template it is the first one; a single
     * template recommends itself; the lowest index wins when several were performed at the same moment. null without templates.
     */
    fun nextTemplate(templates: List<WorkoutTemplate>): WorkoutTemplate? {
        if (templates.isEmpty()) return null
        var latestIndex: Int? = null
        var latestDate = Instant.MIN
        for ((index, template) in templates.withIndex()) {
            val date = template.lastPerformed
            if (date != null && date.isAfter(latestDate)) {
                latestDate = date
                latestIndex = index
            }
        }
        val last = latestIndex ?: return templates[0]
        return templates[(last + 1) % templates.size]
    }

    /** The template to train next and what to show of it. */
    fun nextUp(template: WorkoutTemplate, history: WidgetHistory): NextUpSummary = NextUpSummary(
        templateID = template.id.toString(),
        name = template.name,
        splitLabel = WidgetText.splitLabel(template.name),
        exerciseCount = template.entries.size,
        setCount = template.entries.sumOf { it.plannedSets.size },
        estimatedMinutes = template.estimatedMinutes,
        lastPerformedAt = template.lastPerformed,
        daysSince = template.lastPerformed?.let { history.daysAgo(it) },
        exercises = template.entries.map(::brief),
    )

    /** Every saved template in store order, with `isSuggested` on [suggested]. */
    fun launcher(templates: List<WorkoutTemplate>, suggested: UUID?, history: WidgetHistory): List<TemplateSummary> =
        templates.map { template ->
            TemplateSummary(
                templateID = template.id.toString(),
                name = template.name,
                exerciseCount = template.entries.size,
                estimatedMinutes = template.estimatedMinutes,
                lastPerformedAt = template.lastPerformed,
                daysSince = template.lastPerformed?.let { history.daysAgo(it) },
                isSuggested = template.id == suggested,
            )
        }

    private fun brief(entry: TemplateEntry): PlannedExerciseBrief = PlannedExerciseBrief(
        exerciseID = entry.exercise.id,
        name = entry.exercise.name,
        muscle = entry.exercise.muscle,
        setCount = entry.plannedSets.size,
        summary = summary(entry),
    )

    /**
     * The planned sets in a few characters. Working sets are the ones that are not warm-ups (all sets when there is no other).
     * Weight exercises: "3 × 85" (working sets × the heaviest working weight); reps only: "3 × 12" (the most reps); duration:
     * "3 × 45 s" (the longest time).
     */
    fun summary(entry: TemplateEntry): String {
        val working = entry.plannedSets.filter { it.type != SetType.WARMUP }
        val used = working.ifEmpty { entry.plannedSets }
        return when (entry.exercise.tracking) {
            TrackingKind.WEIGHT_REPS -> "${used.size} × " + NumberText.kg(used.maxOfOrNull { it.weightKg } ?: 0.0)
            TrackingKind.REPS_ONLY -> "${used.size} × ${used.maxOfOrNull { it.reps } ?: 0}"
            TrackingKind.DURATION -> "${used.size} × ${used.maxOfOrNull { it.reps } ?: 0} s"
        }
    }

    // endregion

    // region Overload

    /**
     * What to lift today to beat last time, for the first exercise of [template] that tracks weight, has a working set and has been
     * done before; null when there is none.
     *
     * The last time is the exercise's best working set (highest Epley estimate, the first on a tie) in the newest workout that
     * contains it. The plan is the entry's first working set: its reps and the number of working sets. When last time's reps reached
     * the planned reps the target adds the exercise's weight step and asks for the planned reps; otherwise it keeps the weight and
     * asks for one more rep than last time, at most the planned reps. (The SPEC writes these as products: `weight × reps`.)
     */
    fun overload(template: WorkoutTemplate, history: WidgetHistory): OverloadTarget? {
        for (entry in template.entries) {
            if (!entry.exercise.tracksWeight) continue
            val working = entry.plannedSets.filter { it.type != SetType.WARMUP }
            val first = working.firstOrNull() ?: continue
            val last = lastBestSet(entry.exercise.id, history) ?: continue
            val plannedReps = first.reps
            val targetWeight: Double
            val targetReps: Int
            if (last.set.reps >= plannedReps) {
                targetWeight = last.set.weightKg + entry.exercise.weightStepKg
                targetReps = plannedReps
            } else {
                targetWeight = last.set.weightKg
                targetReps = minOf(last.set.reps + 1, plannedReps)
            }
            return OverloadTarget(
                exerciseID = entry.exercise.id,
                exerciseName = entry.exercise.name,
                lastWeightKg = last.set.weightKg,
                lastReps = last.set.reps,
                lastDaysAgo = history.daysAgo(last.finishedAt),
                targetWeightKg = targetWeight,
                targetReps = targetReps,
                targetSets = working.size,
                deltaKg = targetWeight - last.set.weightKg,
            )
        }
        return null
    }

    private class LastSet(val set: CompletedSet, val finishedAt: Instant)

    /**
     * The best working set (highest Epley estimate, the first on a tie) of [exerciseID] in the newest workout that contains the
     * exercise, with that workout's finish time; null when the exercise was never done or that workout has no working set with a weight.
     */
    private fun lastBestSet(exerciseID: String, history: WidgetHistory): LastSet? {
        val workout = history.entries
            .map { it.workout }
            .filter { workout -> workout.exercises.any { it.exerciseID == exerciseID } }
            .maxWithOrNull(compareBy { it.finishedAt }) ?: return null
        var best: CompletedSet? = null
        var bestEstimate = 0.0
        for (exercise in workout.exercises) {
            if (exercise.exerciseID != exerciseID) continue
            for (set in exercise.sets) {
                if (set.type == SetType.WARMUP) continue
                val estimate = Estimated1RM.epley(set.weightKg, set.reps)
                if (estimate > bestEstimate) {
                    best = set
                    bestEstimate = estimate
                }
            }
        }
        return best?.let { LastSet(it, workout.finishedAt) }
    }

    // endregion

    // region Form cue and loaded bar

    /** One coaching cue of the first exercise of [template] that has cues. Which cue changes with the day: `(dayOfYear - 1) mod count`. */
    fun formCue(template: WorkoutTemplate, history: WidgetHistory): FormCue? {
        val exercise = template.entries.map { it.exercise }.firstOrNull { it.cues.isNotEmpty() } ?: return null
        val index = (WidgetCalendar.dayOfYear(history.today) - 1) % exercise.cues.size
        return FormCue(
            exerciseID = exercise.id,
            exerciseName = exercise.name,
            cue = exercise.cues[index],
            index = index + 1,
            count = exercise.cues.size,
        )
    }

    /**
     * The plates for the heaviest working set of [template] among its exercises that use plates (barbell, weight): the first entry on
     * a tie. null without such a set, and when the weight is below the empty bar.
     */
    fun loadedBar(template: WorkoutTemplate): LoadedBar? {
        var bestExercise: Exercise? = null
        var bestWeight = Double.NEGATIVE_INFINITY
        for (entry in template.entries) {
            if (!entry.exercise.supportsPlates) continue
            val heaviest = entry.plannedSets.filter { it.type != SetType.WARMUP }.maxOfOrNull { it.weightKg } ?: continue
            if (heaviest > bestWeight) {
                bestExercise = entry.exercise
                bestWeight = heaviest
            }
        }
        val exercise = bestExercise ?: return null
        val plan = PlateCalculator.plan(bestWeight, exercise.barKg) ?: return null
        return LoadedBar(
            exerciseID = exercise.id,
            exerciseName = exercise.name,
            totalKg = bestWeight,
            barKg = exercise.barKg,
            platesPerSide = plan.perSide,
            leftoverKg = plan.leftoverKg,
            summary = WidgetText.platesText(plan.perSide),
        )
    }

    // endregion
}
