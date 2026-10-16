package health.pulse.strength.core.widgets

import health.pulse.strength.core.CompletedExercise
import health.pulse.strength.core.CompletedSet
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.HeartRateSample
import health.pulse.strength.core.MuscleSets
import health.pulse.strength.core.PersonalRecord
import health.pulse.strength.core.PlannedSet
import health.pulse.strength.core.SetType
import health.pulse.strength.core.StrengthData
import health.pulse.strength.core.StrengthDataTests.SvcDataFix
import health.pulse.strength.core.StrengthDataTests.SvcSyncFix
import health.pulse.strength.core.TemplateEntry
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.core.addingTimeInterval
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.UUID

/** Builders for the widget snapshot tests: dates in a named time zone, finished workouts and templates with fixed ids. */
internal object WidFix {
    /** 2026-10-16T09:41:00Z, a Friday: the `now` of the demo data and of the golden file. */
    val now: Instant = Instant.ofEpochSecond(1_792_143_660)

    fun context(zone: String = "UTC", goal: Int = 4, bodyweightKg: Double? = null): WidgetContext =
        WidgetContext(weeklyGoal = goal, bodyweightKg = bodyweightKg, zone = ZoneId.of(zone))

    /** The moment of a civil date and time in [zone]. */
    fun date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Int = 0, zone: String = "UTC"): Instant =
        ZonedDateTime.of(year, month, day, hour, minute, second, 0, ZoneId.of(zone)).toInstant()

    fun uuid(n: Int): UUID = SvcSyncFix.uuid(n)

    // region Finished workouts

    fun set(kg: Double, reps: Int, type: SetType = SetType.NORMAL, at: Instant? = null): CompletedSet =
        CompletedSet(type = type, weightKg = kg, reps = reps, loggedAt = at)

    /** A completed exercise of the library with the best Epley estimate of its working sets as `bestE1RM` unless [best] says otherwise. */
    fun lift(exerciseID: String, sets: List<CompletedSet>, best: Double? = null, n: Int = 0): CompletedExercise =
        SvcDataFix.entry(exerciseID, sets, best = best, n = n)

    fun workout(
        n: Int,
        name: String = "Upper A · Push",
        at: Instant,
        templateID: UUID? = null,
        durationSeconds: Int = 3_000,
        volumeKg: Double = 1_000.0,
        exercises: List<CompletedExercise> = emptyList(),
        muscles: List<MuscleSets> = emptyList(),
        records: List<PersonalRecord> = emptyList(),
        heartRate: List<HeartRateSample>? = null,
        startedAt: Instant? = null,
    ): CompletedWorkout = CompletedWorkout(
        id = uuid(n),
        name = name,
        templateID = templateID,
        startedAt = startedAt ?: at.addingTimeInterval(-durationSeconds.toDouble()),
        finishedAt = at,
        durationSeconds = durationSeconds,
        volumeKg = volumeKg,
        loggedSets = exercises.sumOf { it.sets.size },
        averageHeartRate = null,
        averageRIR = null,
        exercises = exercises,
        personalRecords = records,
        muscleSets = muscles,
        heartRateSeries = heartRate,
    )

    /** A workout [daysAgo] days before [now], at the same time of day. */
    fun workout(n: Int, name: String = "Upper A · Push", daysAgo: Double, templateID: UUID? = null, volumeKg: Double = 1_000.0): CompletedWorkout =
        workout(n, name, at = now.addingTimeInterval(-daysAgo * 86_400), templateID = templateID, volumeKg = volumeKg)

    // endregion

    // region Templates

    fun entry(exerciseID: String, sets: List<PlannedSet>, rest: Int = 90): TemplateEntry =
        TemplateEntry(exercise = ExerciseLibrary.exercise(exerciseID)!!, plannedSets = sets, restSeconds = rest)

    fun planned(count: Int, kg: Double, reps: Int): List<PlannedSet> = List(count) { PlannedSet(weightKg = kg, reps = reps) }

    fun template(n: Int, name: String, entries: List<TemplateEntry> = emptyList(), last: Instant? = null): WorkoutTemplate =
        WorkoutTemplate(id = uuid(1_000 + n), name = name, entries = entries, lastPerformed = last)

    // endregion

    // region Snapshots

    fun snapshot(data: StrengthData, context: WidgetContext = context(), now: Instant = WidFix.now): WidgetSnapshot =
        WidgetSnapshotBuilder.make(data, context, now)

    fun snapshot(
        history: List<CompletedWorkout>,
        templates: List<WorkoutTemplate> = emptyList(),
        context: WidgetContext = context(),
        now: Instant = WidFix.now,
    ): WidgetSnapshot = snapshot(StrengthData(templates = templates, history = history), context, now)

    // endregion
}

/** The workout with [exercises] and the set count that goes with them. */
internal fun CompletedWorkout.withExercises(exercises: List<CompletedExercise>): CompletedWorkout =
    copy(exercises = exercises, loggedSets = exercises.sumOf { it.sets.size })

/** The workout with [muscles] as its sets per muscle group. */
internal fun CompletedWorkout.withMuscles(muscles: List<MuscleSets>): CompletedWorkout = copy(muscleSets = muscles)

/** The same workout [days] days earlier. */
internal fun CompletedWorkout.movedBack(days: Double): CompletedWorkout =
    copy(startedAt = startedAt.addingTimeInterval(-days * 86_400), finishedAt = finishedAt.addingTimeInterval(-days * 86_400))
