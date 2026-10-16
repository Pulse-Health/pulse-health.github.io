package health.pulse.strength.ui.detail

import health.pulse.strength.core.CompletedExercise
import health.pulse.strength.core.CompletedSet
import health.pulse.strength.core.CompletedWorkout
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import health.pulse.strength.core.Estimated1RM
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.FileStrengthPersistence
import health.pulse.strength.core.MuscleSets
import health.pulse.strength.core.PersonalRecord
import health.pulse.strength.core.SampleData
import health.pulse.strength.core.SetType
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.addingTimeInterval
import health.pulse.strength.ui.ScreenshotSupport
import health.pulse.strength.ui.components.LocalPulseClock
import health.pulse.strength.ui.components.PulseClock
import health.pulse.strength.ui.theme.PulseTheme
import java.time.Instant
import java.util.TimeZone
import java.util.UUID

/** Data for the detail and summary tests: deterministic around the frozen clock of the screenshot harness. */
internal object ResultFixtures {
    /** The frozen "now" of every screenshot: 2026-01-12 18:30 UTC. */
    val now: Instant = ScreenshotSupport.fixedNow

    /** Dates are local-day text, so the tests pin the zone. Call from `@Before`. */
    fun pinTimeZone() {
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
    }

    fun library(id: String): Exercise = checkNotNull(ExerciseLibrary.exercise(id)) { "unknown exercise $id" }

    fun work(kg: Double, reps: Int, rir: Int? = null) = CompletedSet(type = SetType.NORMAL, weightKg = kg, reps = reps, rir = rir)

    fun warmup(kg: Double, reps: Int) = CompletedSet(type = SetType.WARMUP, weightKg = kg, reps = reps)

    /** A store with the demo templates and history, seeded for [now] (bench: 3 sessions, the middle one a record). */
    fun demoStore(): StrengthStore = StrengthStore(FileStrengthPersistence.temporary(), seedDemoData = true, now = now)

    /** An empty store: a new user. */
    fun emptyStore(): StrengthStore = StrengthStore(null)

    /** A store holding exactly [workouts]. */
    fun storeWith(vararg workouts: CompletedWorkout): StrengthStore {
        val store = StrengthStore(null)
        for (workout in workouts) store.record(workout, null)
        return store
    }

    /** One finished workout that contains one exercise ([sets] are the logged sets), [daysAgo] days before [now]. */
    fun workout(
        exercise: Exercise,
        name: String,
        daysAgo: Double,
        sets: List<CompletedSet>,
        isPersonalRecord: Boolean = false,
        seed: Long = (daysAgo * 1000).toLong(),
    ): CompletedWorkout {
        val finishedAt = now.addingTimeInterval(-daysAgo * 86_400.0)
        val best = if (exercise.tracksWeight) {
            sets.filter { it.type != SetType.WARMUP }.maxOfOrNull { Estimated1RM.epley(it.weightKg, it.reps) } ?: 0.0
        } else {
            0.0
        }
        val volume = if (exercise.tracksWeight) sets.filter { it.type != SetType.WARMUP }.sumOf { it.weightKg * it.reps } else 0.0
        return CompletedWorkout(
            id = UUID(0x5E57, seed),
            name = name,
            templateID = null,
            startedAt = finishedAt.addingTimeInterval(-3_000.0),
            finishedAt = finishedAt,
            durationSeconds = 3_000,
            volumeKg = volume,
            loggedSets = sets.size,
            averageHeartRate = null,
            averageRIR = null,
            exercises = listOf(
                CompletedExercise(
                    id = UUID(0xE8, seed),
                    exerciseID = exercise.id,
                    name = exercise.name,
                    muscle = exercise.muscle,
                    mediaKey = exercise.mediaKey,
                    tracking = exercise.tracking,
                    sets = sets,
                    isPersonalRecord = isPersonalRecord,
                    bestE1RM = best,
                ),
            ),
            personalRecords = emptyList(),
            muscleSets = listOf(MuscleSets(exercise.muscle, sets.count { it.type != SetType.WARMUP })),
        )
    }

    /** The first demo workout of [SampleData] that contains a record: "Upper A · Push", 10 days ago (bench 85 kg × 5). */
    fun demoRecordWorkout(): CompletedWorkout = SampleData.history(now).first { it.personalRecords.isNotEmpty() }

    /** A workout with the six exercises of "Upper A · Push" plus extra rows, to check long lists. */
    fun manyExercisesWorkout(count: Int = 14): CompletedWorkout {
        val ids = listOf(
            "bench", "incline", "ohp", "lateral", "pushdown", "crossover", "squat", "legpress", "pullup", "brow", "pulldown",
            "curl", "plank", "facepull", "calf", "legext",
        )
        val exercises = (0 until count).map { index ->
            val exercise = library(ids[index % ids.size])
            val sets = when (exercise.tracking) {
                TrackingKind.WEIGHT_REPS -> listOf(warmup(40.0, 8), work(60.0 + index, 8, 2), work(60.0 + index, 8, 2), work(60.0 + index, 7, 1))
                TrackingKind.REPS_ONLY -> listOf(work(0.0, 8, 2), work(0.0, 8, 2), work(0.0, 7, 1))
                TrackingKind.DURATION -> listOf(work(0.0, 45), work(0.0, 40))
            }
            CompletedExercise(
                id = UUID(0xE8, index.toLong()),
                exerciseID = exercise.id + "-$index",
                name = exercise.name,
                muscle = exercise.muscle,
                mediaKey = exercise.mediaKey,
                tracking = exercise.tracking,
                sets = sets,
                isPersonalRecord = index % 5 == 0,
                bestE1RM = 0.0,
            )
        }
        val base = SampleData.history(now).first()
        return base.copy(
            id = UUID(0x5E57, 99),
            name = "Full body · Long session",
            durationSeconds = 5 * 3600 + 17 * 60,
            exercises = exercises,
            loggedSets = exercises.sumOf { it.sets.size },
            volumeKg = 18_432.5,
            personalRecords = listOf(
                PersonalRecord("bench", library("bench").name, 85.0, 5, 99.17, 95.0),
                PersonalRecord("squat", library("squat").name, 120.0, 3, 132.0, 131.6),
            ),
            muscleSets = listOf(
                MuscleSets(health.pulse.strength.core.MuscleGroup.CHEST, 12),
                MuscleSets(health.pulse.strength.core.MuscleGroup.BACK, 9),
                MuscleSets(health.pulse.strength.core.MuscleGroup.LEGS, 8),
                MuscleSets(health.pulse.strength.core.MuscleGroup.SHOULDERS, 5),
                MuscleSets(health.pulse.strength.core.MuscleGroup.ARMS, 3),
                MuscleSets(health.pulse.strength.core.MuscleGroup.CORE, 1),
            ),
        )
    }
}

/** Sets [content] in the Pulse theme with a frozen clock and no animations (what the screenshot harness does, without a PNG). */
internal fun ComposeContentTestRule.setPulse(
    dark: Boolean = false,
    now: Instant = ResultFixtures.now,
    content: @Composable () -> Unit,
) {
    setContent {
        CompositionLocalProvider(LocalPulseClock provides PulseClock(now = { now }, ticks = false)) {
            PulseTheme(darkTheme = dark, reduceMotion = true) { content() }
        }
    }
}
