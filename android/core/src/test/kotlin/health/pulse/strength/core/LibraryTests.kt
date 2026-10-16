package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import java.io.File
import org.junit.Test

// Port of LibraryTests.swift.

class LibraryTests {

    // region Fixtures

    /** One row of the design table, reduced to the fields that are easy to compare in bulk. */
    private class Row(
        val id: String,
        val muscle: MuscleGroup,
        val equipment: Equipment,
        val tracking: TrackingKind,
        val media: String?,
        val e1RM: Double,
        val previousSetCount: Int,
        val sets: Int,
        val kg: Double,
        val reps: Int,
        val rest: Int,
        val cueCount: Int,
    )

    private fun row(
        id: String, muscle: MuscleGroup, equipment: Equipment, tracking: TrackingKind, media: String?,
        e1RM: Double, previousSetCount: Int, sets: Int, kg: Double, reps: Int, rest: Int, cueCount: Int,
    ): Row = Row(id, muscle, equipment, tracking, media, e1RM, previousSetCount, sets, kg, reps, rest, cueCount)

    /**
     * All 36 rows of the design array `L`, in design order (id, muscle, equipment, tracking, media key,
     * previous best e1RM, number of previous sets, default sets, kg, reps, rest, number of cues).
     */
    private val designTable: List<Row>
        get() = listOf(
            row("bench", MuscleGroup.CHEST, Equipment.BARBELL, TrackingKind.WEIGHT_REPS, "bench", 99.0, 5, 3, 60.0, 8, 150, 3),
            row("incline", MuscleGroup.CHEST, Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS, "incline", 38.0, 3, 3, 24.0, 10, 90, 3),
            row("crossover", MuscleGroup.CHEST, Equipment.CABLE, TrackingKind.WEIGHT_REPS, "crossover", 22.0, 3, 3, 15.0, 12, 60, 3),
            row("pushup", MuscleGroup.CHEST, Equipment.BODYWEIGHT, TrackingKind.REPS_ONLY, "pushup", 0.0, 1, 3, 0.0, 12, 60, 3),
            row("cpress", MuscleGroup.CHEST, Equipment.MACHINE, TrackingKind.WEIGHT_REPS, null, 0.0, 0, 3, 40.0, 10, 90, 2),
            row("dips", MuscleGroup.CHEST, Equipment.BODYWEIGHT, TrackingKind.REPS_ONLY, null, 0.0, 0, 3, 0.0, 8, 90, 2),
            row("pullup", MuscleGroup.BACK, Equipment.BODYWEIGHT, TrackingKind.REPS_ONLY, "pullup", 0.0, 1, 3, 0.0, 8, 120, 3),
            row("pulldown", MuscleGroup.BACK, Equipment.CABLE, TrackingKind.WEIGHT_REPS, "pulldown", 0.0, 1, 3, 50.0, 10, 90, 3),
            row("brow", MuscleGroup.BACK, Equipment.BARBELL, TrackingKind.WEIGHT_REPS, "brow", 0.0, 1, 3, 50.0, 8, 120, 3),
            row("crow", MuscleGroup.BACK, Equipment.CABLE, TrackingKind.WEIGHT_REPS, "crow", 0.0, 1, 3, 45.0, 10, 90, 3),
            row("dbrow", MuscleGroup.BACK, Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS, null, 0.0, 0, 3, 24.0, 10, 90, 2),
            row("deadlift", MuscleGroup.BACK, Equipment.BARBELL, TrackingKind.WEIGHT_REPS, "deadlift", 0.0, 1, 3, 80.0, 5, 180, 3),
            row("facepull", MuscleGroup.SHOULDERS, Equipment.CABLE, TrackingKind.WEIGHT_REPS, "facepull", 0.0, 1, 3, 20.0, 15, 60, 3),
            row("ohp", MuscleGroup.SHOULDERS, Equipment.BARBELL, TrackingKind.WEIGHT_REPS, "ohp", 58.0, 3, 3, 40.0, 8, 120, 3),
            row("dbpress", MuscleGroup.SHOULDERS, Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS, null, 0.0, 0, 3, 18.0, 10, 90, 2),
            row("lateral", MuscleGroup.SHOULDERS, Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS, "lateral", 12.5, 3, 3, 8.0, 15, 60, 3),
            row("rdelt", MuscleGroup.SHOULDERS, Equipment.MACHINE, TrackingKind.WEIGHT_REPS, null, 0.0, 0, 3, 25.0, 12, 60, 2),
            row("curl", MuscleGroup.ARMS, Equipment.BARBELL, TrackingKind.WEIGHT_REPS, "curl", 0.0, 1, 3, 30.0, 10, 75, 3),
            row("dbcurl", MuscleGroup.ARMS, Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS, "dbcurl", 0.0, 1, 3, 12.0, 10, 75, 3),
            row("hammer", MuscleGroup.ARMS, Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS, null, 0.0, 0, 3, 12.0, 10, 75, 2),
            row("pushdown", MuscleGroup.ARMS, Equipment.CABLE, TrackingKind.WEIGHT_REPS, "pushdown", 43.0, 3, 3, 30.0, 12, 60, 3),
            row("skull", MuscleGroup.ARMS, Equipment.BARBELL, TrackingKind.WEIGHT_REPS, "skull", 0.0, 1, 3, 25.0, 10, 75, 3),
            row("ohtri", MuscleGroup.ARMS, Equipment.CABLE, TrackingKind.WEIGHT_REPS, null, 0.0, 0, 3, 20.0, 12, 60, 2),
            row("preacher", MuscleGroup.ARMS, Equipment.MACHINE, TrackingKind.WEIGHT_REPS, null, 0.0, 0, 3, 25.0, 10, 75, 2),
            row("squat", MuscleGroup.LEGS, Equipment.BARBELL, TrackingKind.WEIGHT_REPS, "squat", 0.0, 1, 3, 60.0, 6, 180, 3),
            row("legpress", MuscleGroup.LEGS, Equipment.MACHINE, TrackingKind.WEIGHT_REPS, "legpress", 0.0, 1, 3, 120.0, 10, 120, 3),
            row("rdl", MuscleGroup.LEGS, Equipment.BARBELL, TrackingKind.WEIGHT_REPS, "rdl", 0.0, 1, 3, 60.0, 8, 120, 3),
            row("lunge", MuscleGroup.LEGS, Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS, null, 0.0, 0, 3, 12.0, 10, 90, 2),
            row("legext", MuscleGroup.LEGS, Equipment.MACHINE, TrackingKind.WEIGHT_REPS, "legext", 0.0, 1, 3, 40.0, 12, 75, 3),
            row("legcurl", MuscleGroup.LEGS, Equipment.MACHINE, TrackingKind.WEIGHT_REPS, "legcurl", 0.0, 1, 3, 30.0, 12, 75, 3),
            row("calf", MuscleGroup.LEGS, Equipment.MACHINE, TrackingKind.WEIGHT_REPS, "calf", 0.0, 1, 4, 60.0, 12, 60, 3),
            row("hipthrust", MuscleGroup.LEGS, Equipment.BARBELL, TrackingKind.WEIGHT_REPS, "hipthrust", 0.0, 1, 3, 70.0, 8, 90, 3),
            row("plank", MuscleGroup.CORE, Equipment.BODYWEIGHT, TrackingKind.DURATION, "plank", 0.0, 1, 3, 0.0, 45, 45, 3),
            row("cablecrunch", MuscleGroup.CORE, Equipment.CABLE, TrackingKind.WEIGHT_REPS, "cablecrunch", 0.0, 1, 3, 30.0, 15, 60, 3),
            row("hlr", MuscleGroup.CORE, Equipment.BODYWEIGHT, TrackingKind.REPS_ONLY, null, 0.0, 0, 3, 0.0, 10, 60, 2),
            row("abwheel", MuscleGroup.CORE, Equipment.OTHER, TrackingKind.REPS_ONLY, null, 0.0, 0, 3, 0.0, 8, 60, 2),
        )

    /** The 25 media keys named in ARCHITECTURE.md. */
    private val designMediaKeys: List<String> = listOf(
        "bench", "incline", "ohp", "lateral", "pushdown", "crossover", "pullup", "pulldown", "brow", "squat",
        "deadlift", "curl", "pushup", "legpress", "rdl", "plank", "hipthrust", "crow", "facepull", "dbcurl",
        "skull", "legcurl", "legext", "calf", "cablecrunch",
    )

    /**
     * The directory of the form-demo frames. The Android app has not copied them yet, so the check looks them up in the iOS package of
     * this repository (walking up from the working directory of the test run, `android/core`).
     */
    private fun mediaDirectory(): File? {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            val candidate = File(dir, "ios/Packages/PulseStrengthKit/Sources/PulseStrengthIOS/Resources/ExerciseMedia")
            if (candidate.isDirectory) return candidate
            dir = dir.parentFile
        }
        return null
    }

    private fun ids(exercises: List<Exercise>): List<String> = exercises.map { it.id }

    private fun filtered(query: String, muscle: MuscleGroup? = null, equipment: Equipment? = null): List<String> =
        ids(ExerciseLibrary.filter(ExerciseLibrary.builtIn, query, muscle, equipment))

    /** Asserts every field of `actual` against the hand-transcribed `expected` exercise. */
    private fun assertSame(actual: Exercise?, expected: Exercise) {
        if (actual == null) {
            throw AssertionError("exercise ${expected.id} is missing")
        }
        val tag = expected.id
        assertWithMessage("id $tag").that(actual.id).isEqualTo(expected.id)
        assertWithMessage("name $tag").that(actual.name).isEqualTo(expected.name)
        assertWithMessage("muscle $tag").that(actual.muscle).isEqualTo(expected.muscle)
        assertWithMessage("secondary $tag").that(actual.secondary).isEqualTo(expected.secondary)
        assertWithMessage("equipment $tag").that(actual.equipment).isEqualTo(expected.equipment)
        assertWithMessage("tracking $tag").that(actual.tracking).isEqualTo(expected.tracking)
        assertWithMessage("mediaKey $tag").that(actual.mediaKey).isEqualTo(expected.mediaKey)
        assertWithMessage("previousBestE1RM $tag").that(actual.previousBestE1RM).isEqualTo(expected.previousBestE1RM)
        assertWithMessage("previousSets $tag").that(actual.previousSets).isEqualTo(expected.previousSets)
        assertWithMessage("defaults $tag").that(actual.defaults).isEqualTo(expected.defaults)
        assertWithMessage("cues $tag").that(actual.cues).isEqualTo(expected.cues)
        assertWithMessage("barKg $tag").that(actual.barKg).isEqualTo(expected.barKg)
        assertWithMessage("isCustom $tag").that(actual.isCustom).isEqualTo(expected.isCustom)
    }

    private fun sets(vararg pairs: Pair<Double, Int>): List<PreviousSet> = pairs.map { PreviousSet(weightKg = it.first, reps = it.second) }

    // endregion

    // region Library contents

    @Test
    fun testBuiltInHasExactly36Exercises() {
        assertThat(ExerciseLibrary.builtIn.size).isEqualTo(36)
        assertThat(designTable.size).isEqualTo(36)
    }

    @Test
    fun testIDsAreUnique() {
        val all = ids(ExerciseLibrary.builtIn)
        assertThat(all.toSet().size).isEqualTo(all.size)
        assertThat(all.any { it.isEmpty() }).isFalse()
    }

    @Test
    fun testLibraryOrderMatchesDesign() {
        assertThat(ids(ExerciseLibrary.builtIn)).isEqualTo(designTable.map { it.id })
    }

    @Test
    fun testEveryRowMatchesDesignTable() {
        for ((exercise, expected) in ExerciseLibrary.builtIn.zip(designTable)) {
            val tag = expected.id
            assertWithMessage(tag).that(exercise.id).isEqualTo(expected.id)
            assertWithMessage("muscle $tag").that(exercise.muscle).isEqualTo(expected.muscle)
            assertWithMessage("equipment $tag").that(exercise.equipment).isEqualTo(expected.equipment)
            assertWithMessage("tracking $tag").that(exercise.tracking).isEqualTo(expected.tracking)
            assertWithMessage("media $tag").that(exercise.mediaKey).isEqualTo(expected.media)
            assertWithMessage("e1RM $tag").that(exercise.previousBestE1RM).isEqualTo(expected.e1RM)
            assertWithMessage("previous sets $tag").that(exercise.previousSets.size).isEqualTo(expected.previousSetCount)
            assertWithMessage("default sets $tag").that(exercise.defaults.sets).isEqualTo(expected.sets)
            assertWithMessage("default kg $tag").that(exercise.defaults.weightKg).isEqualTo(expected.kg)
            assertWithMessage("default reps $tag").that(exercise.defaults.reps).isEqualTo(expected.reps)
            assertWithMessage("default rest $tag").that(exercise.defaults.restSeconds).isEqualTo(expected.rest)
            assertWithMessage("cue count $tag").that(exercise.cues.size).isEqualTo(expected.cueCount)
        }
    }

    @Test
    fun testBarWeightAndCustomFlag() {
        for (exercise in ExerciseLibrary.builtIn) {
            assertWithMessage(exercise.id).that(exercise.barKg).isEqualTo(if (exercise.id == "skull") 10.0 else 20.0)
            assertWithMessage(exercise.id).that(exercise.isCustom).isFalse()
        }
    }

    @Test
    fun testDataInvariants() {
        for (exercise in ExerciseLibrary.builtIn) {
            assertWithMessage(exercise.id).that(exercise.name.isEmpty()).isFalse()
            assertWithMessage(exercise.id).that(exercise.secondary.isEmpty()).isFalse()
            assertWithMessage(exercise.id).that(exercise.cues.size).isAtLeast(2)
            assertWithMessage(exercise.id).that(exercise.cues.any { it.isEmpty() }).isFalse()
            assertWithMessage(exercise.id).that(exercise.defaults.sets).isGreaterThan(0)
            assertWithMessage(exercise.id).that(exercise.defaults.reps).isGreaterThan(0)
            assertWithMessage(exercise.id).that(exercise.defaults.restSeconds).isAtLeast(0)
            if (exercise.previousBestE1RM > 0) {
                assertWithMessage(exercise.id).that(exercise.tracking).isEqualTo(TrackingKind.WEIGHT_REPS)
                assertWithMessage(exercise.id).that(exercise.previousSets).isNotEmpty()
            }
            if (exercise.tracking != TrackingKind.WEIGHT_REPS) {
                assertWithMessage(exercise.id).that(exercise.defaults.weightKg).isEqualTo(0.0)
                assertWithMessage(exercise.id).that(exercise.previousBestE1RM).isEqualTo(0.0)
            }
            if (exercise.mediaKey == null) {
                assertWithMessage(exercise.id).that(exercise.previousSets).isEmpty()
            }
        }
    }

    @Test
    fun testExerciseLookup() {
        for (exercise in ExerciseLibrary.builtIn) {
            assertThat(ExerciseLibrary.exercise(exercise.id)).isEqualTo(exercise)
        }
        assertThat(ExerciseLibrary.exercise("bench")?.name).isEqualTo("Barbell bench press")
        assertThat(ExerciseLibrary.exercise("Bench")).isNull()
        assertThat(ExerciseLibrary.exercise("")).isNull()
        assertThat(ExerciseLibrary.exercise("custom-123")).isNull()
    }

    // endregion

    // region Spot checks against the prototype

    @Test
    fun testBenchPress() {
        assertSame(
            ExerciseLibrary.exercise("bench"),
            Exercise(
                id = "bench", name = "Barbell bench press", muscle = MuscleGroup.CHEST, secondary = "Shoulders · Triceps",
                equipment = Equipment.BARBELL, tracking = TrackingKind.WEIGHT_REPS, mediaKey = "bench", previousBestE1RM = 99.0,
                previousSets = sets(50.0 to 8, 70.0 to 5, 80.0 to 6, 80.0 to 6, 80.0 to 5),
                defaults = ExerciseDefaults(sets = 3, weightKg = 60.0, reps = 8, restSeconds = 150),
                cues = listOf(
                    "Pull your shoulder blades back and down and keep your feet planted.",
                    "Lower the bar to mid-chest with your elbows about 45–60° from your body.",
                    "Press up and slightly back until your arms are straight.",
                ),
                barKg = 20.0, isCustom = false,
            ),
        )
    }

    @Test
    fun testInclineDumbbellPress() {
        assertSame(
            ExerciseLibrary.exercise("incline"),
            Exercise(
                id = "incline", name = "Incline dumbbell press", muscle = MuscleGroup.CHEST, secondary = "Shoulders · Triceps",
                equipment = Equipment.DUMBBELL, tracking = TrackingKind.WEIGHT_REPS, mediaKey = "incline", previousBestE1RM = 38.0,
                previousSets = sets(26.0 to 10, 26.0 to 10, 26.0 to 9),
                defaults = ExerciseDefaults(sets = 3, weightKg = 24.0, reps = 10, restSeconds = 90),
                cues = listOf(
                    "Set the bench to 30–45° and keep your back flat on the pad.",
                    "Lower the dumbbells to chest level with your elbows under your wrists.",
                    "Press up without letting the weights drift apart.",
                ),
                barKg = 20.0, isCustom = false,
            ),
        )
    }

    @Test
    fun testPushUpIsRepsOnly() {
        assertSame(
            ExerciseLibrary.exercise("pushup"),
            Exercise(
                id = "pushup", name = "Push-up", muscle = MuscleGroup.CHEST, secondary = "Shoulders · Triceps",
                equipment = Equipment.BODYWEIGHT, tracking = TrackingKind.REPS_ONLY, mediaKey = "pushup", previousBestE1RM = 0.0,
                previousSets = sets(0.0 to 15),
                defaults = ExerciseDefaults(sets = 3, weightKg = 0.0, reps = 12, restSeconds = 60),
                cues = listOf(
                    "Hands under your shoulders, body in one straight line.",
                    "Lower your chest to just above the floor with your elbows about 45° out.",
                    "Press back up without sagging at the hips.",
                ),
                barKg = 20.0, isCustom = false,
            ),
        )
    }

    @Test
    fun testMachineChestPressHasNoMediaAndNoHistory() {
        assertSame(
            ExerciseLibrary.exercise("cpress"),
            Exercise(
                id = "cpress", name = "Machine chest press", muscle = MuscleGroup.CHEST, secondary = "Shoulders · Triceps",
                equipment = Equipment.MACHINE, tracking = TrackingKind.WEIGHT_REPS, mediaKey = null, previousBestE1RM = 0.0,
                previousSets = emptyList(),
                defaults = ExerciseDefaults(sets = 3, weightKg = 40.0, reps = 10, restSeconds = 90),
                cues = listOf(
                    "Set the seat so the handles line up with mid-chest.",
                    "Press forward until your arms are almost straight, then return slowly.",
                ),
                barKg = 20.0, isCustom = false,
            ),
        )
    }

    @Test
    fun testSkullCrusherUsesTenKiloBar() {
        assertSame(
            ExerciseLibrary.exercise("skull"),
            Exercise(
                id = "skull", name = "Skull crusher", muscle = MuscleGroup.ARMS, secondary = "Triceps · Forearms",
                equipment = Equipment.BARBELL, tracking = TrackingKind.WEIGHT_REPS, mediaKey = "skull", previousBestE1RM = 0.0,
                previousSets = sets(25.0 to 10),
                defaults = ExerciseDefaults(sets = 3, weightKg = 25.0, reps = 10, restSeconds = 75),
                cues = listOf(
                    "Lie on a bench holding the bar over your chest with straight arms.",
                    "Bend only at the elbows to lower the bar toward your forehead.",
                    "Extend back up without letting your elbows flare.",
                ),
                barKg = 10.0, isCustom = false,
            ),
        )
    }

    @Test
    fun testPlankTracksDuration() {
        assertSame(
            ExerciseLibrary.exercise("plank"),
            Exercise(
                id = "plank", name = "Plank", muscle = MuscleGroup.CORE, secondary = "Abs",
                equipment = Equipment.BODYWEIGHT, tracking = TrackingKind.DURATION, mediaKey = "plank", previousBestE1RM = 0.0,
                previousSets = sets(0.0 to 45),
                defaults = ExerciseDefaults(sets = 3, weightKg = 0.0, reps = 45, restSeconds = 45),
                cues = listOf(
                    "Elbows under your shoulders, body in a straight line from head to heels.",
                    "Squeeze your glutes and brace your abs.",
                    "Breathe steadily and stop when your hips start to sag.",
                ),
                barKg = 20.0, isCustom = false,
            ),
        )
    }

    @Test
    fun testStandingCalfRaiseHasFourDefaultSets() {
        assertSame(
            ExerciseLibrary.exercise("calf"),
            Exercise(
                id = "calf", name = "Standing calf raise", muscle = MuscleGroup.LEGS, secondary = "Calves",
                equipment = Equipment.MACHINE, tracking = TrackingKind.WEIGHT_REPS, mediaKey = "calf", previousBestE1RM = 0.0,
                previousSets = sets(60.0 to 12),
                defaults = ExerciseDefaults(sets = 4, weightKg = 60.0, reps = 12, restSeconds = 60),
                cues = listOf(
                    "Place the balls of your feet on the platform with your heels hanging off.",
                    "Rise as high as you can and pause at the top.",
                    "Lower into a deep stretch before the next rep.",
                ),
                barKg = 20.0, isCustom = false,
            ),
        )
    }

    @Test
    fun testLegExtensionKeepsApostrophes() {
        assertSame(
            ExerciseLibrary.exercise("legext"),
            Exercise(
                id = "legext", name = "Leg extension", muscle = MuscleGroup.LEGS, secondary = "Quads",
                equipment = Equipment.MACHINE, tracking = TrackingKind.WEIGHT_REPS, mediaKey = "legext", previousBestE1RM = 0.0,
                previousSets = sets(45.0 to 12),
                defaults = ExerciseDefaults(sets = 3, weightKg = 40.0, reps = 12, restSeconds = 75),
                cues = listOf(
                    "Align your knees with the machine's pivot and sit back in the seat.",
                    "Extend until your legs are straight and squeeze your quads.",
                    "Lower under control and don't let the stack crash.",
                ),
                barKg = 20.0, isCustom = false,
            ),
        )
    }

    @Test
    fun testLateralRaiseHasHistoryAndApostrophe() {
        assertSame(
            ExerciseLibrary.exercise("lateral"),
            Exercise(
                id = "lateral", name = "Dumbbell lateral raise", muscle = MuscleGroup.SHOULDERS, secondary = "Side delts",
                equipment = Equipment.DUMBBELL, tracking = TrackingKind.WEIGHT_REPS, mediaKey = "lateral", previousBestE1RM = 12.5,
                previousSets = sets(8.0 to 15, 8.0 to 15, 8.0 to 14),
                defaults = ExerciseDefaults(sets = 3, weightKg = 8.0, reps = 15, restSeconds = 60),
                cues = listOf(
                    "Stand tall with a slight bend in your elbows.",
                    "Raise the dumbbells out to the sides until they reach shoulder height.",
                    "Lower slowly and don't swing your torso.",
                ),
                barKg = 20.0, isCustom = false,
            ),
        )
    }

    @Test
    fun testAbWheelIsOtherEquipment() {
        assertSame(
            ExerciseLibrary.exercise("abwheel"),
            Exercise(
                id = "abwheel", name = "Ab wheel rollout", muscle = MuscleGroup.CORE, secondary = "Shoulders",
                equipment = Equipment.OTHER, tracking = TrackingKind.REPS_ONLY, mediaKey = null, previousBestE1RM = 0.0,
                previousSets = emptyList(),
                defaults = ExerciseDefaults(sets = 3, weightKg = 0.0, reps = 8, restSeconds = 60),
                cues = listOf(
                    "Start on your knees with the wheel under your shoulders.",
                    "Roll out as far as you can keep your back flat, then pull back in.",
                ),
                barKg = 20.0, isCustom = false,
            ),
        )
    }

    @Test
    fun testPersonalBestsOfTheDesign() {
        val expected: Map<String, Double> = mapOf(
            "bench" to 99.0, "incline" to 38.0, "crossover" to 22.0, "ohp" to 58.0, "lateral" to 12.5, "pushdown" to 43.0,
        )
        for (exercise in ExerciseLibrary.builtIn) {
            assertWithMessage(exercise.id).that(exercise.previousBestE1RM).isEqualTo(expected[exercise.id] ?: 0.0)
        }
    }

    @Test
    fun testDerivedBehaviourOfLibraryEntries() {
        assertThat(ExerciseLibrary.exercise("bench")?.weightStepKg).isEqualTo(2.5)
        assertThat(ExerciseLibrary.exercise("incline")?.weightStepKg).isEqualTo(2.0)
        assertThat(ExerciseLibrary.exercise("plank")?.repsStep).isEqualTo(5)
        assertThat(ExerciseLibrary.exercise("bench")?.supportsPlates).isEqualTo(true)
        assertThat(ExerciseLibrary.exercise("legpress")?.supportsPlates).isEqualTo(false)
        assertThat(ExerciseLibrary.exercise("pullup")?.tracksWeight).isEqualTo(false)
    }

    // endregion

    // region Media keys and frames

    @Test
    fun testExactly25DistinctMediaKeys() {
        val keys = ExerciseLibrary.builtIn.mapNotNull { it.mediaKey }
        assertThat(keys.toSet().size).isEqualTo(25)
        assertWithMessage("each media key belongs to exactly one exercise").that(keys.size).isEqualTo(25)
        assertThat(designMediaKeys.toSet().size).isEqualTo(25)
        assertThat(keys.toSet()).isEqualTo(designMediaKeys.toSet())
    }

    @Test
    fun testMediaKeysMatchesBuiltIn() {
        assertThat(ExerciseLibrary.mediaKeys).isEqualTo(ExerciseLibrary.builtIn.mapNotNull { it.mediaKey })
        assertThat(ExerciseLibrary.mediaKeys.size).isEqualTo(25)
        assertThat(ExerciseLibrary.mediaKeys.toSet().size).isEqualTo(25)
        assertThat(ExerciseLibrary.mediaKeys.toSet()).isEqualTo(designMediaKeys.toSet())
    }

    @Test
    fun testEveryMediaKeyHasBothFramesOnDisk() {
        val directory = mediaDirectory()
        assertWithMessage("missing directory ios/Packages/PulseStrengthKit/Sources/PulseStrengthIOS/Resources/ExerciseMedia").that(directory).isNotNull()
        for (key in ExerciseLibrary.mediaKeys) {
            for (frame in listOf("a", "b")) {
                val file = File(directory, "$key-$frame.jpg")
                assertWithMessage("missing $key-$frame.jpg").that(file.isFile).isTrue()
                val data = file.readBytes()
                assertWithMessage("$key-$frame.jpg is too small").that(data.size).isGreaterThan(1000)
                assertWithMessage("$key-$frame.jpg is not a JPEG").that(data.take(2)).isEqualTo(listOf(0xFF.toByte(), 0xD8.toByte()))
            }
        }
    }

    // endregion

    // region Filter

    @Test
    fun testBlankFilterReturnsEverythingSortedByName() {
        val expected = listOf(
            "abwheel", "squat", "bench", "curl", "brow", "crossover", "cablecrunch", "dips", "deadlift",
            "dbcurl", "lateral", "dbpress", "facepull", "hammer", "hlr", "hipthrust", "incline", "pulldown",
            "legext", "legpress", "legcurl", "cpress", "dbrow", "ohp", "ohtri", "plank", "preacher", "pullup",
            "pushup", "rdelt", "rdl", "crow", "skull", "calf", "pushdown", "lunge",
        )
        assertThat(expected.size).isEqualTo(36)
        assertThat(filtered("")).isEqualTo(expected)
        assertThat(filtered("   \t\n ")).isEqualTo(expected)
        assertThat(filtered("", null, null)).isEqualTo(expected)
    }

    @Test
    fun testSingleTokenMatchesNameMuscleEquipmentAndSecondary() {
        assertThat(filtered("bench")).isEqualTo(listOf("bench"))
        assertThat(filtered("press")).isEqualTo(listOf("bench", "dbpress", "incline", "legpress", "cpress", "ohp"))
        assertWithMessage("secondary text is searched").that(filtered("side")).isEqualTo(listOf("lateral"))
        assertWithMessage("secondary text is searched").that(filtered("calves")).isEqualTo(listOf("calf"))
        assertThat(filtered("cable")).isEqualTo(listOf("crossover", "cablecrunch", "facepull", "pulldown", "ohtri", "crow", "pushdown"))
        assertWithMessage("equipment is searched").that(filtered("bodyweight")).isEqualTo(listOf("dips", "hlr", "plank", "pullup", "pushup"))
        assertWithMessage("muscle is searched").that(filtered("core")).isEqualTo(listOf("abwheel", "cablecrunch", "hlr", "plank"))
        assertThat(filtered("other")).isEqualTo(listOf("abwheel"))
    }

    @Test
    fun testMuscleTextMatchesBeyondTheName() {
        // "leg" is in four names; "Legs" is the muscle of eight exercises; Hanging leg raise is the only overlap.
        assertThat(filtered("leg").size).isEqualTo(9)
        assertThat(filtered("leg")).contains("hlr")
        assertThat(filtered("legs").size).isEqualTo(8)
        assertThat(filtered("legs")).doesNotContain("hlr")
    }

    @Test
    fun testAllTokensMustMatchInAnyOrderAcrossFields() {
        assertThat(filtered("press chest")).isEqualTo(listOf("bench", "incline", "cpress"))
        assertThat(filtered("chest press")).isEqualTo(listOf("bench", "incline", "cpress"))
        assertThat(filtered("triceps barbell")).isEqualTo(listOf("bench", "ohp", "skull"))
        assertThat(filtered("barbell triceps")).isEqualTo(listOf("bench", "ohp", "skull"))
        assertThat(filtered("press chest zzz")).isEqualTo(emptyList<String>())
        assertThat(filtered("zzz")).isEqualTo(emptyList<String>())
        assertThat(filtered("bench dumbbell")).isEqualTo(emptyList<String>())
    }

    @Test
    fun testTokensAreSplitOnAnyWhitespaceAndIgnoreCase() {
        val expected = listOf("bench", "incline", "cpress")
        assertThat(filtered("  chest \t press\n")).isEqualTo(expected)
        assertThat(filtered("CHEST PRESS")).isEqualTo(expected)
        assertThat(filtered("ChEsT   pReSs")).isEqualTo(expected)
        assertThat(filtered("BENCH")).isEqualTo(listOf("bench"))
        assertThat(filtered("  bench  ")).isEqualTo(listOf("bench"))
    }

    @Test
    fun testPartialTokensMatchAsSubstrings() {
        assertThat(filtered("benc")).isEqualTo(listOf("bench"))
        assertThat(filtered("ench")).isEqualTo(listOf("bench"))
        assertThat(filtered("pushd")).isEqualTo(listOf("pushdown"))
        assertThat(filtered("dumb curl")).isEqualTo(listOf("dbcurl", "hammer"))
    }

    @Test
    fun testMuscleFilter() {
        assertThat(filtered("", MuscleGroup.CORE)).isEqualTo(listOf("abwheel", "cablecrunch", "hlr", "plank"))
        assertThat(filtered("", MuscleGroup.SHOULDERS)).isEqualTo(listOf("lateral", "dbpress", "facepull", "ohp", "rdelt"))
        val counts = listOf(
            MuscleGroup.CHEST to 6, MuscleGroup.BACK to 6, MuscleGroup.SHOULDERS to 5, MuscleGroup.ARMS to 7, MuscleGroup.LEGS to 8, MuscleGroup.CORE to 4,
        )
        assertThat(counts.fold(0) { acc, pair -> acc + pair.second }).isEqualTo(36)
        for ((muscle, count) in counts) {
            val result = ExerciseLibrary.filter(ExerciseLibrary.builtIn, "", muscle, null)
            assertWithMessage(muscle.title).that(result.size).isEqualTo(count)
            assertWithMessage(muscle.title).that(result.all { it.muscle == muscle }).isTrue()
        }
    }

    @Test
    fun testEquipmentFilter() {
        assertThat(filtered("", null, Equipment.OTHER)).isEqualTo(listOf("abwheel"))
        assertThat(filtered("", null, Equipment.BODYWEIGHT)).isEqualTo(listOf("dips", "hlr", "plank", "pullup", "pushup"))
        val counts = listOf(
            Equipment.BARBELL to 9, Equipment.DUMBBELL to 7, Equipment.CABLE to 7, Equipment.MACHINE to 7, Equipment.BODYWEIGHT to 5, Equipment.OTHER to 1,
        )
        assertThat(counts.fold(0) { acc, pair -> acc + pair.second }).isEqualTo(36)
        for ((equipment, count) in counts) {
            val result = ExerciseLibrary.filter(ExerciseLibrary.builtIn, "", null, equipment)
            assertWithMessage(equipment.title).that(result.size).isEqualTo(count)
            assertWithMessage(equipment.title).that(result.all { it.equipment == equipment }).isTrue()
        }
    }

    @Test
    fun testMuscleEquipmentAndQueryCombine() {
        assertThat(filtered("", MuscleGroup.ARMS, Equipment.BARBELL)).isEqualTo(listOf("curl", "skull"))
        assertThat(filtered("curl", MuscleGroup.ARMS)).isEqualTo(listOf("curl", "dbcurl", "hammer", "preacher"))
        assertThat(filtered("curl", MuscleGroup.LEGS)).isEqualTo(listOf("legcurl"))
        assertThat(filtered("curl", MuscleGroup.ARMS, Equipment.DUMBBELL)).isEqualTo(listOf("dbcurl", "hammer"))
        assertThat(filtered("curl", MuscleGroup.CHEST)).isEqualTo(emptyList<String>())
        assertThat(filtered("", MuscleGroup.CORE, Equipment.BARBELL)).isEqualTo(emptyList<String>())
        assertThat(filtered("press", MuscleGroup.SHOULDERS, Equipment.BARBELL)).isEqualTo(listOf("ohp"))
    }

    @Test
    fun testResultsAreSortedByNameIgnoringCaseThenID() {
        fun make(id: String, name: String, secondary: String = ""): Exercise =
            Exercise.custom(name, MuscleGroup.CHEST, Equipment.OTHER, TrackingKind.WEIGHT_REPS, id).copy(secondary = secondary)

        val pool = listOf(
            make("x3", "banana"), make("x2", "apple"), make("x1", "Apple"),
            make("x4", "Cherry"), make("x0", "apple"), make("y", "Zucchini"),
        )
        val sorted = ExerciseLibrary.filter(pool, "", null, null)
        assertThat(ids(sorted)).isEqualTo(listOf("x0", "x1", "x2", "x3", "x4", "y"))
        // The input order must not matter.
        assertThat(ids(ExerciseLibrary.filter(pool.reversed(), "", null, null))).isEqualTo(ids(sorted))
        // Plain code unit ordering would put "Cherry" and "Zucchini" before "apple".
        assertThat(ids(sorted).indexOf("x4")).isEqualTo(4)
    }

    @Test
    fun testIdenticalNameAndIDKeepInputOrder() {
        val first = Exercise.custom("Twin", MuscleGroup.BACK, Equipment.CABLE, TrackingKind.WEIGHT_REPS, "same").copy(secondary = "first")
        val second = Exercise.custom("Twin", MuscleGroup.BACK, Equipment.CABLE, TrackingKind.WEIGHT_REPS, "same").copy(secondary = "second")
        assertThat(ExerciseLibrary.filter(listOf(first, second), "", null, null).map { it.secondary }).isEqualTo(listOf("first", "second"))
        assertThat(ExerciseLibrary.filter(listOf(second, first), "", null, null).map { it.secondary }).isEqualTo(listOf("second", "first"))
    }

    @Test
    fun testFilterSearchesTheGivenListIncludingCustomExercises() {
        val custom = Exercise.custom("Zercher squat", MuscleGroup.LEGS, Equipment.BARBELL, TrackingKind.WEIGHT_REPS, "custom-zercher")
        val pool = ExerciseLibrary.builtIn + custom
        val result = ExerciseLibrary.filter(pool, "squat", null, null)
        assertThat(ids(result)).isEqualTo(listOf("squat", "custom-zercher"))
        assertWithMessage("the Custom secondary text is searched")
            .that(ids(ExerciseLibrary.filter(pool, "custom", null, null))).isEqualTo(listOf("custom-zercher"))
        assertThat(ExerciseLibrary.filter(emptyList(), "squat", null, null)).isEmpty()
        assertThat(ExerciseLibrary.filter(emptyList(), "", MuscleGroup.LEGS, Equipment.BARBELL)).isEmpty()
    }

    @Test
    fun testFilterIgnoresCaseOfNonASCIIText() {
        val custom = Exercise.custom("Écarté couché", MuscleGroup.CHEST, Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS, "custom-ecarte")
        assertThat(ids(ExerciseLibrary.filter(listOf(custom), "écarté", null, null))).isEqualTo(listOf("custom-ecarte"))
        assertThat(ids(ExerciseLibrary.filter(listOf(custom), "ÉCARTÉ COUCHÉ", null, null))).isEqualTo(listOf("custom-ecarte"))
    }

    @Test
    fun testFilterDoesNotChangeTheLibrary() {
        val before = ExerciseLibrary.builtIn.toList()
        filtered("press", MuscleGroup.CHEST, Equipment.BARBELL)
        assertThat(ExerciseLibrary.builtIn).isEqualTo(before)
    }

    @Test
    fun testFilterAgreesWithAnIndependentOracleOnRandomQueries() {
        val pool = listOf(
            "press", "bench", "curl", "cable", "dumbbell", "chest", "legs", "triceps", "·", "raise", "BAR",
            "side", "x", "e", "up", "Core", "mach", "  ", "zz",
        )
        val rng = LibraryFuzzRNG(20251013L)
        repeat(300) {
            val tokenCount = rng.nextBelow(4)
            val query = List(tokenCount) { pool[rng.nextBelow(pool.size)] }.joinToString(" ")
            val muscle: MuscleGroup? = if (rng.nextBelow(3) == 0) MuscleGroup.entries[rng.nextBelow(6)] else null
            val equipment: Equipment? = if (rng.nextBelow(3) == 0) Equipment.entries[rng.nextBelow(6)] else null
            val result = ExerciseLibrary.filter(ExerciseLibrary.builtIn, query, muscle, equipment)
            val tokens = query.split(' ').filter { it.isNotEmpty() }
            val expected = mutableListOf<Exercise>()
            for (exercise in ExerciseLibrary.builtIn) {
                if (muscle != null && exercise.muscle != muscle) continue
                if (equipment != null && exercise.equipment != equipment) continue
                val text = "${exercise.name} ${exercise.muscle.rawValue} ${exercise.equipment.rawValue} ${exercise.secondary}"
                if (tokens.all { text.contains(it, ignoreCase = true) }) expected.add(exercise)
            }
            assertWithMessage("query '$query' $muscle $equipment").that(ids(result).toSet()).isEqualTo(ids(expected).toSet())
            assertThat(result.size).isEqualTo(expected.size)
            val names = result.map { it.name.lowercase() }
            assertWithMessage("query '$query'").that(names).isEqualTo(names.sorted())
        }
    }

    // endregion

    // region Kotlin-only additions (no Swift test): Swift's Unicode whitespace rules for search tokens and trimmed names
    //
    // Swift splits the query with `Character.isWhitespace` and trims custom names with `.whitespacesAndNewlines`; both are the Unicode
    // White_Space set (U+0009...U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000...U+200A, U+2028, U+2029, U+202F, U+205F, U+3000).
    // Kotlin's `\s` is ASCII only and `String.trim()` uses a different set (it has U+001C...U+001F, it lacks U+0085).

    @Test
    fun testKotlinOnlyFilterSplitsTokensOnUnicodeWhitespaceLikeSwift() {
        val expected = listOf("bench", "incline", "cpress")
        val separators = listOf(
            " ", "　", "\u0085", " ", " ", " ", " ", " ", " ", "\u000B", "\u000C", "\r\n",
        )
        for (separator in separators) {
            val tag = separator.map { "U+%04X".format(it.code) }.joinToString(" ")
            assertWithMessage("separator $tag").that(filtered("chest${separator}press")).isEqualTo(expected)
            assertWithMessage("padded by $tag").that(filtered("$separator${separator}chest$separator$separator press$separator")).isEqualTo(expected)
        }
        // Not whitespace for Swift (control separators, zero-width characters): the query stays one token that matches nothing.
        for (character in listOf("\u001C", "\u001D", "\u001E", "\u001F", "​", "﻿")) {
            assertWithMessage("U+%04X is not a separator".format(character[0].code)).that(filtered("chest${character}press")).isEmpty()
        }
    }

    @Test
    fun testKotlinOnlyCustomExerciseNameIsTrimmedLikeFoundation() {
        fun nameOf(raw: String): String = Exercise.custom(raw, MuscleGroup.CHEST, Equipment.OTHER, TrackingKind.WEIGHT_REPS, "custom-x").name
        assertThat(nameOf(" Row　\n")).isEqualTo("Row")
        assertThat(nameOf("\u0085Row ")).isEqualTo("Row")
        assertThat(nameOf("  \u0085 ")).isEqualTo("Custom exercise")
        // Not whitespace for Foundation, so not trimmed.
        assertThat(nameOf("\u001FRow\u001C")).isEqualTo("\u001FRow\u001C")
        assertThat(nameOf("\u001F")).isEqualTo("\u001F")
    }

    /**
     * Pins the generator to the Swift algorithm (output `state >> 11`); the expected numbers were computed independently with
     * explicit 64-bit wrap-around.
     */
    @Test
    fun testKotlinOnlyFuzzRNGMatchesTheSwiftAlgorithm() {
        val rng = LibraryFuzzRNG(20251013L)
        assertThat(List(5) { rng.next() }).isEqualTo(
            listOf(113655989075032L, 8403532295817558L, 5813805562074199L, 3087477620228109L, 901617398960704L),
        )
    }

    // endregion

    /** Seeded linear congruential generator, so the fuzz test is deterministic (same constants and output shift as Swift). */
    private class LibraryFuzzRNG(seed: Long) {
        private var state: Long = seed

        fun next(): Long {
            state = state * 6_364_136_223_846_793_005L + 1_442_695_040_888_963_407L
            return state ushr 11
        }

        /** A value in 0..<bound. */
        fun nextBelow(bound: Int): Int = (next() % bound.toLong()).toInt()
    }
}
