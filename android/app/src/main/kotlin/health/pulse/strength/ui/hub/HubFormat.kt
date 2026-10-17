package health.pulse.strength.ui.hub

import health.pulse.strength.core.ActiveWorkoutPresentation
import health.pulse.strength.core.CompletedSet
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.Estimated1RM
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.NumberText
import health.pulse.strength.core.RecoveryProvider
import health.pulse.strength.core.SetType
import health.pulse.strength.core.TemplateEntry
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.core.roundedAwayFromZero
import health.pulse.strength.core.roundedDown
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters

// Text, rotation, muscle and coach rules of the hub (port of HubFormat, HubRotation, HubMuscles and HubCoach of StrengthHubView.swift).
// Everything here is plain Kotlin on the core types, so it is unit tested without a UI; no function reads the system clock or
// depends on the locale's number formatting (dates take an explicit zone and "today").

/** Sessions, logged sets and volume of one calendar week. */
internal data class HubWeekStats(val sessions: Int, val sets: Int, val volumeKg: Double)

internal object HubFormat {
    private val monthNames = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

    /** The design's weekly session target ("2 of 4"). */
    const val SESSION_GOAL = 4

    /** What stands where a figure has nothing to show yet (an empty week, a workout without weight). */
    const val NO_VALUE = "–"

    fun exercises(count: Int): String = if (count == 1) "1 exercise" else "$count exercises"

    fun sets(count: Int): String = if (count == 1) "1 set" else "$count sets"

    /** "6 exercises · about 55 min", plus an optional suffix ("next up", "last done 5 days ago"). */
    fun templateSubtitle(template: WorkoutTemplate, suffix: String?): String {
        var text = exercises(template.entries.size) + " · about ${template.estimatedMinutes} min"
        if (suffix != null) text += " · $suffix"
        return text
    }

    /** "last done 5 days ago" for a template that was performed, else null. */
    fun lastDoneSuffix(template: WorkoutTemplate, today: LocalDate, zone: ZoneId): String? =
        template.lastPerformed?.let { "last done " + daysAgo(it, today, zone) }

    /**
     * "Oct 8, 18:10" (24-hour clock, English month names, no locale dependence). The month comes from the Gregorian (ISO) calendar
     * the month names belong to, in [zone].
     */
    fun dateTime(date: Instant, zone: ZoneId): String {
        val time = date.atZone(zone)
        return monthNames[time.monthValue - 1] + " " + time.dayOfMonth + ", " + twoDigits(time.hour) + ":" + twoDigits(time.minute)
    }

    /** The dialog text while another workout runs. */
    fun busyMessage(workoutName: String?): String {
        val name = workoutName ?: "your current workout"
        return "Finish or discard $name before starting another workout."
    }

    /** "52m" (the design shows minutes only, "61m" for 1 h 1 min). */
    fun duration(seconds: Int): String = "${(maxOf(0, seconds) / 60.0).roundedAwayFromZero().toInt()}m"

    /** "8,420 kg". */
    fun volume(kg: Double): String = NumberText.thousands(kg) + " kg"

    /** Like [volume], and a dash for no weight at all (an empty week, a body-weight workout) instead of "0 kg". */
    fun volumeOrDash(kg: Double): String = if (kg > 0) volume(kg) else NO_VALUE

    /** "today", "yesterday", "5 days ago", "3 weeks ago", "2 months ago" (calendar days in [zone]). */
    fun daysAgo(date: Instant, today: LocalDate, zone: ZoneId): String {
        val days = ChronoUnit.DAYS.between(date.atZone(zone).toLocalDate(), today)
        if (days <= 0) return "today"
        if (days == 1L) return "yesterday"
        if (days < 14) return "$days days ago"
        if (days < 60) return "${days / 7} weeks ago"
        return "${days / 30} months ago"
    }

    /** Sessions, logged sets and volume of the calendar week of [today] (the week starts on [firstDayOfWeek]). */
    fun weekStats(history: List<CompletedWorkout>, today: LocalDate, zone: ZoneId, firstDayOfWeek: DayOfWeek): HubWeekStats {
        val firstDay = today.with(TemporalAdjusters.previousOrSame(firstDayOfWeek))
        val start = firstDay.atStartOfDay(zone).toInstant()
        val end = firstDay.plusDays(7).atStartOfDay(zone).toInstant()
        var sessions = 0
        var sets = 0
        var volume = 0.0
        for (workout in history) {
            if (workout.finishedAt.isBefore(start) || !workout.finishedAt.isBefore(end)) continue
            sessions += 1
            sets += workout.loggedSets
            volume += workout.volumeKg
        }
        return HubWeekStats(sessions, sets, volume)
    }

    /** The exercise name without its equipment prefix, lower case: "Barbell bench press" -> "bench press". */
    fun shortName(exercise: Exercise): String {
        var name = exercise.name
        val prefix = exercise.equipment.title.lowercase() + " "
        if (name.lowercase().startsWith(prefix)) name = name.drop(prefix.length)
        return name.lowercase()
    }

    /** "5 sets · 85 kg × 6 · Rest 2:30" (last working set of the plan). */
    fun planSummary(entry: TemplateEntry): String {
        val parts = mutableListOf(sets(entry.plannedSets.size))
        val working = entry.plannedSets.lastOrNull { it.type != SetType.WARMUP } ?: entry.plannedSets.lastOrNull()
        if (working != null) {
            when (entry.exercise.tracking) {
                TrackingKind.WEIGHT_REPS -> parts.add(NumberText.kg(working.weightKg) + " kg × " + working.reps)
                TrackingKind.REPS_ONLY -> parts.add("${working.reps} reps")
                TrackingKind.DURATION -> parts.add("${working.reps} s")
            }
        }
        if (entry.restSeconds > 0) parts.add("Rest " + NumberText.rest(entry.restSeconds))
        entry.supersetGroup?.let { parts.add("Superset $it") }
        return parts.joinToString(" · ")
    }

    /** "W 50×8 · 82.5×6" for weight exercises, "12 reps" / "45 s" otherwise. */
    fun setsText(sets: List<CompletedSet>, tracking: TrackingKind): String =
        sets.joinToString(" · ") { item ->
            val prefix = if (item.type == SetType.NORMAL) "" else item.type.badge + " "
            when (tracking) {
                TrackingKind.WEIGHT_REPS -> prefix + NumberText.kg(item.weightKg) + "×" + item.reps
                TrackingKind.REPS_ONLY -> prefix + "${item.reps} reps"
                TrackingKind.DURATION -> prefix + "${item.reps} s"
            }
        }

    /** "Avg RIR" value: the mean to one decimal. */
    fun averageRIR(rir: Double): String = NumberText.kg((rir * 10).roundedAwayFromZero() / 10)

    /** The "PR" tag of a workout row ("1 PR", "2 PR"). */
    fun personalRecordTag(count: Int): String = "$count PR"

    /** "85 kg × 6 · est. 1RM 99 kg". */
    fun recordText(weightKg: Double, reps: Int, estimated1RM: Double): String =
        NumberText.kg(weightKg) + " kg × " + reps + " · est. 1RM " + NumberText.kg(estimated1RM.roundedAwayFromZero()) + " kg"

    private fun twoDigits(value: Int): String = if (value < 10) "0$value" else value.toString()
}

/** The recommendation of the hub: the template after the most recently performed one. */
internal object HubRotation {
    /**
     * The template to do next: the one after the most recently performed template in the list, wrapping around (Upper A, Lower A,
     * Upper B, then Upper A again). Without a performed template it is the first one; a single template recommends itself; no
     * template at all gives null (the first-run state).
     */
    fun next(templates: List<WorkoutTemplate>): WorkoutTemplate? {
        if (templates.isEmpty()) return null
        var latestIndex: Int? = null
        var latestDate: Instant? = null
        for ((index, template) in templates.withIndex()) {
            val date = template.lastPerformed ?: continue
            if (latestDate == null || date.isAfter(latestDate)) {
                latestDate = date
                latestIndex = index
            }
        }
        val last = latestIndex ?: return templates[0]
        return templates[(last + 1) % templates.size]
    }
}

/** One muscle chip of the recommended card: "Chest 88%" with a recovery dot. */
internal data class HubMuscleChip(val id: String, val title: String, val percent: Int)

internal object HubMuscles {
    /** Order of the recovery grid in the design. */
    val displayOrder: List<MuscleGroup> =
        listOf(MuscleGroup.CHEST, MuscleGroup.SHOULDERS, MuscleGroup.ARMS, MuscleGroup.BACK, MuscleGroup.LEGS, MuscleGroup.CORE)

    fun percent(muscle: MuscleGroup, recovery: RecoveryProvider): Int = maxOf(0, minOf(100, recovery(muscle)))

    fun level(percent: Int): ActiveWorkoutPresentation.RecoveryLevel = when {
        percent >= 80 -> ActiveWorkoutPresentation.RecoveryLevel.GOOD
        percent >= 60 -> ActiveWorkoutPresentation.RecoveryLevel.FAIR
        else -> ActiveWorkoutPresentation.RecoveryLevel.LOW
    }

    fun levelTitle(percent: Int): String = when (level(percent)) {
        ActiveWorkoutPresentation.RecoveryLevel.GOOD -> "Good"
        ActiveWorkoutPresentation.RecoveryLevel.FAIR -> "Fair"
        ActiveWorkoutPresentation.RecoveryLevel.LOW -> "Low"
    }

    fun readinessTitle(percent: Int): String = when (level(percent)) {
        ActiveWorkoutPresentation.RecoveryLevel.GOOD -> "Ready"
        ActiveWorkoutPresentation.RecoveryLevel.FAIR -> "Fair"
        ActiveWorkoutPresentation.RecoveryLevel.LOW -> "Low"
    }

    /** Mean recovery of all muscle groups, rounded (88, 100, 82, 79, 64, 100 -> 86). */
    fun readiness(recovery: RecoveryProvider): Int {
        val all = MuscleGroup.entries
        if (all.isEmpty()) return 0
        val total = all.sumOf { percent(it, recovery) }
        return (total.toDouble() / all.size).roundedAwayFromZero().toInt()
    }

    /** The template's muscle groups, most exercises first (ties keep the order of first use). */
    fun musclesUsed(template: WorkoutTemplate): List<MuscleGroup> {
        val counts = linkedMapOf<MuscleGroup, Int>()
        for (entry in template.entries) counts[entry.exercise.muscle] = (counts[entry.exercise.muscle] ?: 0) + 1
        // sortedByDescending is stable: ties keep the order of first use.
        return counts.keys.sortedByDescending { counts.getValue(it) }
    }

    /** Up to three chips "Chest 88%". */
    fun chips(template: WorkoutTemplate, recovery: RecoveryProvider): List<HubMuscleChip> =
        musclesUsed(template).take(3).map { muscle ->
            val value = percent(muscle, recovery)
            HubMuscleChip(id = muscle.rawValue, title = muscle.title + " $value%", percent = value)
        }

    /** "Chest" or "Chest and shoulders". */
    fun sentenceSubject(muscles: List<MuscleGroup>): String {
        val first = muscles.firstOrNull() ?: return ""
        if (muscles.size > 1) return first.title + " and " + muscles[1].title.lowercase()
        return first.title
    }

    /** True when [sentenceSubject] takes "are": two groups, or one group whose name is a plural noun ("Legs are", "Chest is"). */
    fun isPlural(muscles: List<MuscleGroup>): Boolean {
        if (muscles.size > 1) return true
        return when (muscles.firstOrNull()) {
            MuscleGroup.SHOULDERS, MuscleGroup.ARMS, MuscleGroup.LEGS -> true
            MuscleGroup.CHEST, MuscleGroup.BACK, MuscleGroup.CORE, null -> false
        }
    }
}

/** The coach note of the recommended card. */
internal object HubCoach {
    /**
     * "Chest and shoulders are recovered. Aim for 85 kg × 6 on your last bench press set."
     *
     * [exercise] returns an exercise with the user's remembered results overlaid. [hasResults] says whether the user really logged
     * the exercise (a personal best or a finished workout): the built-in library carries placeholder "previous results" that are not
     * the user's, so a first-run user never gets an "Aim for" target built from them.
     */
    fun message(
        template: WorkoutTemplate,
        recovery: RecoveryProvider,
        exercise: (String) -> Exercise?,
        hasResults: (String) -> Boolean,
    ): String? {
        val sentences = listOfNotNull(readinessSentence(template, recovery), targetSentence(template, exercise, hasResults))
        if (sentences.isEmpty()) return null
        return sentences.joinToString(" ")
    }

    private fun readinessSentence(template: WorkoutTemplate, recovery: RecoveryProvider): String? {
        val lead = HubMuscles.musclesUsed(template).take(2)
        if (lead.isEmpty()) return null
        val tired = lead.filter { HubMuscles.percent(it, recovery) < 60 }
        if (tired.isEmpty()) {
            return HubMuscles.sentenceSubject(lead) + (if (HubMuscles.isPlural(lead)) " are recovered." else " is recovered.")
        }
        return HubMuscles.sentenceSubject(tired) + (if (HubMuscles.isPlural(tired)) " are still recovering." else " is still recovering.")
    }

    /** The first weight exercise with a history: the lightest weight on its last working set that beats the best estimated 1RM. */
    private fun targetSentence(template: WorkoutTemplate, exercise: (String) -> Exercise?, hasResults: (String) -> Boolean): String? {
        for (entry in template.entries) {
            val resolved = exercise(entry.exercise.id) ?: entry.exercise
            if (!resolved.tracksWeight || !hasResults(resolved.id) || resolved.previousBestE1RM <= 0) continue
            val normal = entry.plannedSets.lastOrNull { it.type == SetType.NORMAL }
            val planned = normal ?: entry.plannedSets.lastOrNull { it.type != SetType.WARMUP }
            if (planned == null || planned.reps <= 0) continue
            val weight = beatingWeight(resolved, planned.reps)
            return "Aim for ${NumberText.kg(weight)} kg × ${planned.reps} on your last ${HubFormat.shortName(resolved)} set."
        }
        return null
    }

    internal fun beatingWeight(exercise: Exercise, reps: Int): Double {
        val step = maxOf(0.5, exercise.weightStepKg)
        val target = exercise.previousBestE1RM + 0.05
        val factor = 1 + reps.toDouble() / 30
        var weight = maxOf(step, (target / factor / step).roundedDown() * step)
        var iterations = 0
        while (Estimated1RM.epley(weight, reps) <= target && iterations < 400) {
            weight += step
            iterations += 1
        }
        return weight
    }
}
