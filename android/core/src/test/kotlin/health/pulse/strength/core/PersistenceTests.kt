package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.StrengthDataTests.SvcSyncFix
import java.io.File
import java.io.IOException
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.After
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

// Port of PersistenceTests.swift against FileStrengthPersistence(directory: File).
//
// Not ported: the App Group test and everything about acknowledged-commands.json (Watch sync), see the porting report.
// Adapted: the exact-JSON test (the Kotlin format is kotlinx.serialization, not Foundation's JSONEncoder).

class PersistenceTests {
    @get:Rule
    val folder = TemporaryFolder()

    private val now = SvcSyncFix.epoch

    private val temporaryDirectories = mutableListOf<File>()

    @After
    fun removeTemporaryDirectories() {
        for (directory in temporaryDirectories) directory.deleteRecursively()
    }

    /** A fresh persistence in a temporary directory that is removed when the test ends. */
    private fun makePersistence(): FileStrengthPersistence = FileStrengthPersistence(folder.newFolder())

    /** The data files of the directory (the staging folder, which is empty after every write, is checked on its own). */
    private fun fileNames(persistence: FileStrengthPersistence): List<String> =
        (persistence.directory.list() ?: emptyArray()).filter { it != FileStrengthPersistence.STAGING_DIRECTORY }.sorted()

    private fun stagedFiles(persistence: FileStrengthPersistence): List<String> =
        (File(persistence.directory, FileStrengthPersistence.STAGING_DIRECTORY).list() ?: emptyArray()).sorted()

    private fun text(persistence: FileStrengthPersistence, name: String): String =
        runCatching { File(persistence.directory, name).readText(Charsets.UTF_8) }.getOrDefault("")

    private fun file(persistence: FileStrengthPersistence, name: String): File = File(persistence.directory, name)

    // region Empty and missing

    @Test
    fun testEverythingReadsAsEmptyBeforeAnythingWasSaved() {
        val persistence = makePersistence()
        assertThat(persistence.loadActiveWorkout()).isNull()
        assertThat(persistence.loadTemplates()).isEqualTo(emptyList<WorkoutTemplate>())
        assertThat(persistence.loadHistory()).isEqualTo(emptyList<CompletedWorkout>())
        assertThat(persistence.loadCustomExercises()).isEqualTo(emptyList<Exercise>())
        assertThat(persistence.loadPersonalBests()).isEqualTo(emptyMap<String, PersonalBest>())
    }

    @Test
    fun testTemporaryPersistenceUsesADistinctDirectoryEachTime() {
        val first = FileStrengthPersistence.temporary()
        val second = FileStrengthPersistence.temporary()
        temporaryDirectories.add(first.directory)
        temporaryDirectories.add(second.directory)
        assertThat(first.directory).isNotEqualTo(second.directory)
        assertThat(first.directory.isDirectory).isTrue()
        assertThat(second.directory.isDirectory).isTrue()
    }

    // endregion

    // region Round trips

    @Test
    fun testActiveWorkoutRoundTrip() {
        val persistence = makePersistence()
        val state = SvcSyncFix.richState()
        persistence.saveActiveWorkout(state)
        assertThat(persistence.loadActiveWorkout()).isEqualTo(state)
        assertThat(fileNames(persistence)).isEqualTo(listOf("active-workout.json"))
    }

    @Test
    fun testSavingNilDeletesTheActiveWorkoutAndDeletingTwiceIsFine() {
        val persistence = makePersistence()
        persistence.saveActiveWorkout(SvcSyncFix.richState())
        persistence.saveActiveWorkout(null)
        assertThat(persistence.loadActiveWorkout()).isNull()
        assertThat(fileNames(persistence)).isEmpty()
        persistence.saveActiveWorkout(null)      // does not throw
    }

    @Test
    fun testTemplatesRoundTripKeepsOrderAndDates() {
        val persistence = makePersistence()
        val templates = SampleData.templates(now)
        persistence.saveTemplates(templates)
        assertThat(persistence.loadTemplates()).isEqualTo(templates)
    }

    @Test
    fun testHistoryRoundTrip() {
        val persistence = makePersistence()
        val history = SampleData.history(now)
        persistence.saveHistory(history)
        assertThat(persistence.loadHistory()).isEqualTo(history)
    }

    @Test
    fun testCustomExercisesRoundTrip() {
        val persistence = makePersistence()
        val exercises = listOf(
            Exercise.custom(name = "Zercher squat", muscle = MuscleGroup.LEGS, equipment = Equipment.BARBELL, tracking = TrackingKind.WEIGHT_REPS, id = "custom-1"),
            Exercise.custom(name = "Dead hang", muscle = MuscleGroup.BACK, equipment = Equipment.BODYWEIGHT, tracking = TrackingKind.DURATION, id = "custom-2"),
        )
        persistence.saveCustomExercises(exercises)
        assertThat(persistence.loadCustomExercises()).isEqualTo(exercises)
    }

    @Test
    fun testPersonalBestsRoundTrip() {
        val persistence = makePersistence()
        val bests = SampleData.personalBests(now)
        assertThat(bests).isNotEmpty()
        persistence.savePersonalBests(bests)
        assertThat(persistence.loadPersonalBests()).isEqualTo(bests)
    }

    @Test
    fun testSavingEmptyCollectionsReadsBackEmpty() {
        val persistence = makePersistence()
        persistence.saveTemplates(SampleData.templates())
        persistence.saveTemplates(emptyList())
        assertThat(persistence.loadTemplates()).isEqualTo(emptyList<WorkoutTemplate>())
        persistence.savePersonalBests(mapOf("bench" to PersonalBest(exerciseID = "bench", estimated1RM = 99.0, weightKg = 85.0, reps = 5, date = now)))
        persistence.savePersonalBests(emptyMap())
        assertThat(persistence.loadPersonalBests()).isEqualTo(emptyMap<String, PersonalBest>())
    }

    @Test
    fun testASecondInstanceOnTheSameDirectorySeesTheData() {
        val persistence = makePersistence()
        persistence.saveHistory(SampleData.history(now))
        val other = FileStrengthPersistence(directory = persistence.directory)
        assertThat(other.loadHistory()).isEqualTo(SampleData.history(now))
    }

    // endregion

    // region File format

    /**
     * Adapted from the Swift test of the same name. Swift asserted the exact bytes of Foundation's encoder (sorted keys,
     * "…:00.000Z" dates); kotlinx.serialization writes the dates as Instant.toString ("…:00Z") and class properties in declaration
     * order. What is kept: ISO-8601 dates, the personal-best keys in sorted order, and identical bytes when the same value is
     * written again (whatever order the map was built in).
     */
    @Test
    fun testFilesUseSortedKeysAndISO8601Dates() {
        val persistence = makePersistence()
        val bench = PersonalBest(exerciseID = "bench", estimated1RM = 99.5, weightKg = 85.0, reps = 5, date = now)
        val squat = PersonalBest(exerciseID = "squat", estimated1RM = 96.0, weightKg = 80.0, reps = 6, date = now)
        val calf = PersonalBest(exerciseID = "calf", estimated1RM = 84.0, weightKg = 60.0, reps = 12, date = now)
        persistence.savePersonalBests(linkedMapOf("squat" to squat, "bench" to bench, "calf" to calf))
        val first = text(persistence, "personal-bests.json")
        assertWithMessage(first).that(first).contains("\"2026-10-13T19:30:00Z\"")
        val positions = listOf("bench", "calf", "squat").map { first.indexOf("\"$it\":{") }
        assertWithMessage(first).that(positions.contains(-1)).isFalse()
        assertThat(positions[0]).isLessThan(positions[1])
        assertThat(positions[1]).isLessThan(positions[2])
        // Writing the same value again gives identical bytes.
        persistence.savePersonalBests(linkedMapOf("calf" to calf, "bench" to bench, "squat" to squat))
        assertThat(text(persistence, "personal-bests.json")).isEqualTo(first)
    }

    @Test
    fun testFilesAreReadableJSON() {
        val persistence = makePersistence()
        persistence.saveActiveWorkout(SvcSyncFix.richState())
        persistence.saveTemplates(SampleData.templates())
        persistence.saveHistory(SampleData.history(now))
        for (name in listOf("active-workout.json", "templates.json", "history.json")) {
            val parsed = runCatching { Json.parseToJsonElement(file(persistence, name).readText()) }
            assertWithMessage(name).that(parsed.isSuccess).isTrue()
        }
    }

    /** Dates in the "standard ISO-8601" form without fractional seconds, and with milliseconds as the Swift core writes them, both load. */
    @Test
    fun testFilesWrittenWithTheStandardISO8601StrategyStillLoad() {
        val persistence = makePersistence()
        val json = "{\"bench\":{\"exerciseID\":\"bench\",\"estimated1RM\":99,\"weightKg\":85,\"reps\":5,\"date\":\"2026-10-13T19:30:00Z\"}}"
        file(persistence, "personal-bests.json").writeText(json)
        assertThat(persistence.loadPersonalBests()["bench"]?.date).isEqualTo(now)

        val withMilliseconds = json.replace("19:30:00Z", "19:30:00.000Z")
        file(persistence, "personal-bests.json").writeText(withMilliseconds)
        assertThat(persistence.loadPersonalBests()["bench"]?.date).isEqualTo(now)
    }

    /**
     * Extra (not in PersistenceTests.swift): the Kotlin format is not byte-identical to Swift's, so the tolerance of old and newer
     * files is asserted directly. A file without the optional / defaulted fields of an older build, and with fields a newer
     * build added, still loads.
     */
    @Test
    fun testUnknownKeysAndMissingOptionalFieldsAreTolerated() {
        val persistence = makePersistence()
        val state = SvcSyncFix.richState()
        persistence.saveActiveWorkout(state)
        val root = (Json.parseToJsonElement(text(persistence, "active-workout.json")) as JsonObject).toMutableMap()
        for (key in listOf("undo", "heartRateSum", "heartRateCount", "usedWatch", "pausedTotal")) assertThat(root.remove(key)).isNotNull()
        root["futureField"] = JsonPrimitive("from a newer build")
        file(persistence, "active-workout.json").writeText(JsonObject(root).toString())
        val loaded = persistence.loadActiveWorkout()
        assertThat(loaded).isEqualTo(state.copy(undo = null, heartRateSum = 0, heartRateCount = 0, usedWatch = false, pausedTotal = 0.0))

        val bests = "{\"bench\":{\"exerciseID\":\"bench\",\"estimated1RM\":99,\"weightKg\":85,\"reps\":5,\"date\":\"2026-10-13T19:30:00Z\",\"note\":\"new\"}}"
        file(persistence, "personal-bests.json").writeText(bests)
        assertThat(persistence.loadPersonalBests()["bench"]?.reps).isEqualTo(5)
    }

    // endregion

    // region Atomic writes and robustness

    @Test
    fun testWritesLeaveNoTemporaryFilesBehind() {
        val persistence = makePersistence()
        for (round in 0 until 5) {
            persistence.saveHistory(SampleData.history(now).take(round))
            persistence.saveActiveWorkout(SvcSyncFix.richState())
            persistence.saveTemplates(SampleData.templates())
        }
        assertThat(fileNames(persistence)).isEqualTo(listOf("active-workout.json", "history.json", "templates.json"))
    }

    @Test
    fun testAShorterSaveFullyReplacesALongerOne() {
        val persistence = makePersistence()
        persistence.saveHistory(SampleData.history(now))
        persistence.saveHistory(emptyList())
        assertThat(persistence.loadHistory()).isEqualTo(emptyList<CompletedWorkout>())
        assertThat(text(persistence, "history.json")).isEqualTo("[]")
    }

    @Test
    fun testCorruptFilesReadAsEmptyValues() {
        val persistence = makePersistence()
        val garbage: List<ByteArray> = listOf(
            ByteArray(0),
            "not json at all".toByteArray(),
            "{".toByteArray(),
            byteArrayOf(0xFF.toByte(), 0xFE.toByte(), 0x00, 0x01),
            "null".toByteArray(),
            "42".toByteArray(),
        )
        for (data in garbage) {
            for (name in listOf("active-workout.json", "templates.json", "history.json", "custom-exercises.json", "personal-bests.json")) {
                file(persistence, name).writeBytes(data)
            }
            assertThat(persistence.loadActiveWorkout()).isNull()
            assertThat(persistence.loadTemplates()).isEqualTo(emptyList<WorkoutTemplate>())
            assertThat(persistence.loadHistory()).isEqualTo(emptyList<CompletedWorkout>())
            assertThat(persistence.loadCustomExercises()).isEqualTo(emptyList<Exercise>())
            assertThat(persistence.loadPersonalBests()).isEqualTo(emptyMap<String, PersonalBest>())
        }
    }

    @Test
    fun testWrongShapeFilesReadAsEmpty() {
        val persistence = makePersistence()
        file(persistence, "templates.json").writeText("{\"a\":1}")
        file(persistence, "personal-bests.json").writeText("[1,2,3]")
        assertThat(persistence.loadTemplates()).isEqualTo(emptyList<WorkoutTemplate>())
        assertThat(persistence.loadPersonalBests()).isEqualTo(emptyMap<String, PersonalBest>())
    }

    @Test
    fun testAnUnreadableElementIsSkippedAndTheRestIsKept() {
        val persistence = makePersistence()
        val templates = SampleData.templates()
        persistence.saveTemplates(templates)
        val original = text(persistence, "templates.json")
        // Insert a broken element between the first and second template.
        val broken = Json.parseToJsonElement("{\"id\":\"oops\",\"name\":5}")
        val parts = (Json.parseToJsonElement(original) as JsonArray).toMutableList()
        parts.add(1, broken)
        file(persistence, "templates.json").writeText(JsonArray(parts).toString())
        assertThat(persistence.loadTemplates()).isEqualTo(templates)

        persistence.savePersonalBests(SampleData.personalBests(now))
        val bests = (Json.parseToJsonElement(text(persistence, "personal-bests.json")) as JsonObject).toMutableMap<String, JsonElement>()
        val count = bests.size
        bests["broken"] = JsonPrimitive("not a personal best")
        file(persistence, "personal-bests.json").writeText(JsonObject(bests).toString())
        assertThat(persistence.loadPersonalBests()).hasSize(count)
        assertThat(persistence.loadPersonalBests()["broken"]).isNull()
    }

    @Test
    fun testSavingRecreatesAMissingDirectory() {
        val persistence = makePersistence()
        assertThat(persistence.directory.deleteRecursively()).isTrue()
        persistence.saveTemplates(SampleData.templates())
        assertThat(persistence.loadTemplates()).isEqualTo(SampleData.templates())
    }

    @Test
    fun testSavingFailsWithAnErrorWhenTheDirectoryCannotBeCreated() {
        val blocker = folder.newFile("PulseStrength-blocker")
        blocker.writeText("file")
        val persistence = FileStrengthPersistence(directory = File(blocker, "inner"))
        assertThrows(IOException::class.java) { persistence.saveHistory(emptyList()) }
        assertThat(persistence.loadHistory()).isEqualTo(emptyList<CompletedWorkout>())
        assertThat(persistence.loadActiveWorkout()).isNull()
    }

    @Test
    fun testConcurrentSavesNeverCorruptTheFile() {
        val persistence = makePersistence()
        val histories = (0 until 6).map { SampleData.history(now).take(it) }
        val pool = Executors.newFixedThreadPool(8)
        try {
            val tasks = (0 until 60).map { index ->
                Callable {
                    runCatching { persistence.saveHistory(histories[index % histories.size]) }
                    persistence.loadHistory()
                }
            }
            pool.invokeAll(tasks).forEach { it.get() }
        } finally {
            pool.shutdownNow()
        }
        val loaded = persistence.loadHistory()
        assertWithMessage("loaded ${loaded.size} workouts").that(histories.contains(loaded)).isTrue()
        assertThat(fileNames(persistence)).isEqualTo(listOf("history.json"))
    }

    // endregion

    // region Staging folder (writes are staged outside the files that the Android backup copies)

    @Test
    fun testWritesAreStagedInASubfolderThatIsEmptyAfterwards() {
        val persistence = makePersistence()
        persistence.saveHistory(SampleData.history(now))
        persistence.saveTemplates(SampleData.templates())
        persistence.saveActiveWorkout(null)
        assertThat(stagedFiles(persistence)).isEmpty()
        assertWithMessage("no temporary file next to the data").that(persistence.directory.list()!!.filter { it.endsWith(".tmp") }).isEmpty()
        assertThat(persistence.loadHistory()).isEqualTo(SampleData.history(now))
    }

    @Test
    fun testALeftoverFromAKilledWriteIsSweptButAFreshOneIsNot() {
        val directory = folder.newFolder()
        val staging = File(directory, FileStrengthPersistence.STAGING_DIRECTORY).apply { mkdirs() }
        val stale = File(staging, "history.json.dead.tmp").apply { writeText("[]") }
        val fresh = File(staging, "history.json.alive.tmp").apply { writeText("[]") }
        assertThat(stale.setLastModified(System.currentTimeMillis() - 10 * 60_000L)).isTrue()

        FileStrengthPersistence(directory)

        assertWithMessage("a write that never finished is removed").that(stale.exists()).isFalse()
        assertWithMessage("a write that may be running right now is left alone").that(fresh.exists()).isTrue()
    }

    @Test
    fun testTheStagingFolderNeverCountsAsData() {
        val persistence = makePersistence()
        persistence.saveHistory(SampleData.history(now))
        File(File(persistence.directory, FileStrengthPersistence.STAGING_DIRECTORY), "junk.tmp").writeText("not json")
        assertThat(persistence.loadHistory()).isEqualTo(SampleData.history(now))
        assertThat(persistence.loadTemplates()).isEmpty()
    }

    // endregion
}
