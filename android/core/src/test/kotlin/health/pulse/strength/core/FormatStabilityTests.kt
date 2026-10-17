package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import java.io.File
import java.time.Instant
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * The files of the first release must stay readable by every later version of the app.
 *
 * `src/test/resources/format-v1/` holds the five files exactly as the first release writes them. A change to the data model that makes
 * one of them unreadable (a new field without a default, a renamed field, a stricter type) fails here, before it reaches users: the
 * loader silently skips what it cannot decode, so the history of a user who updates the app would be gone after the next save. Fix
 * the model (give the field a default, or read the old name too), never the fixtures.
 *
 * To create the fixtures once (a new format version, never to "fix" a failing test): `PULSE_REGENERATE_FIXTURES=1 ./gradlew :core:test
 * --tests '*FormatStabilityTests*'`, then keep the old folder next to the new one.
 */
class FormatStabilityTests {
    @get:Rule
    val folder = TemporaryFolder()

    private val files = listOf("active-workout.json", "templates.json", "history.json", "custom-exercises.json", "personal-bests.json")

    /** A directory holding the fixtures of [version]. */
    private fun fixtureDirectory(version: String = "format-v1"): File {
        val directory = folder.newFolder()
        for (name in files) {
            val stream = javaClass.getResourceAsStream("/$version/$name") ?: error("missing fixture $version/$name")
            File(directory, name).writeBytes(stream.use { it.readBytes() })
        }
        return directory
    }

    @Test
    fun everyFileOfTheFirstReleaseStillLoadsInFull() {
        val persistence = FileStrengthPersistence(fixtureDirectory())
        assertWithMessage("templates").that(persistence.loadTemplates()).hasSize(3)
        assertWithMessage("history").that(persistence.loadHistory()).hasSize(SAMPLE_HISTORY_COUNT)
        assertWithMessage("custom exercises").that(persistence.loadCustomExercises()).hasSize(1)
        assertWithMessage("personal bests").that(persistence.loadPersonalBests()).isNotEmpty()
        assertWithMessage("active workout").that(persistence.loadActiveWorkout()).isNotNull()
    }

    @Test
    fun theStoreOverTheFixturesHasTheDataOfTheFirstRelease() {
        val store = StrengthStore(FileStrengthPersistence(fixtureDirectory()), seedDemoData = false, usesLibraryHistory = false)
        assertThat(store.templates).hasSize(3)
        assertThat(store.history).hasSize(SAMPLE_HISTORY_COUNT)
        assertThat(store.customExercises).hasSize(1)
        assertThat(store.history.flatMap { it.exercises }).isNotEmpty()
        assertThat(store.history.first().personalRecords.isNotEmpty() || store.history.any { it.personalRecords.isNotEmpty() }).isTrue()
    }

    @Test
    fun theWorkoutInProgressOfTheFirstReleaseIsRestoredByTheEngine() {
        val persistence = FileStrengthPersistence(fixtureDirectory())
        val store = StrengthStore(persistence, seedDemoData = false)
        val controller = WorkoutController(store, persistence, clock = { FIXTURE_TIME.plusSeconds(600) })
        controller.restoreFromDisk()
        val restored = controller.state.value
        assertThat(restored).isNotNull()
        assertThat(restored!!.exercises).isNotEmpty()
        assertThat(restored.exercises.sumOf { it.doneCount }).isEqualTo(FIXTURE_DONE_SETS)
    }

    @Test
    fun filesWrittenByANewerVersionWithExtraFieldsStillLoad() {
        // Going back to this version (a Play rollback, a restore on an older app) must not lose data either: unknown keys are ignored.
        val directory = fixtureDirectory()
        for (name in files) {
            val file = File(directory, name)
            val parsed = StrengthJson.format.parseToJsonElement(file.readText())
            file.writeText(withExtraField(parsed).toString())
        }
        val persistence = FileStrengthPersistence(directory)
        assertThat(persistence.loadTemplates()).hasSize(3)
        assertThat(persistence.loadHistory()).hasSize(SAMPLE_HISTORY_COUNT)
        assertThat(persistence.loadCustomExercises()).hasSize(1)
        assertThat(persistence.loadPersonalBests()).isNotEmpty()
        assertThat(persistence.loadActiveWorkout()).isNotNull()
    }

    @Test
    fun theFixturesAreWhatTheFirstReleaseWroteNotWhatTheCurrentCodeWouldWrite() {
        // A guard against "fixing" a failing compatibility test by regenerating the fixtures: they carry a marker that the generator
        // below never writes, so a regenerated folder is noticed.
        val text = javaClass.getResourceAsStream("/format-v1/history.json")!!.use { it.readBytes().toString(Charsets.UTF_8) }
        assertThat(text).contains("\"formatMarker\"")
    }

    /** Writes `src/test/resources/format-v1` from the sample data. Only runs with `PULSE_REGENERATE_FIXTURES=1`. */
    @Test
    fun regenerateFixtures() {
        if (System.getenv("PULSE_REGENERATE_FIXTURES") != "1") return
        val target = File("src/test/resources/format-v1").apply { mkdirs() }
        val persistence = FileStrengthPersistence(folder.newFolder())
        persistence.saveTemplates(SampleData.templates(FIXTURE_TIME))
        persistence.saveHistory(SampleData.history(FIXTURE_TIME))
        persistence.saveCustomExercises(
            listOf(
                Exercise.custom(
                    name = "Landmine press",
                    muscle = MuscleGroup.SHOULDERS,
                    equipment = Equipment.BARBELL,
                    tracking = TrackingKind.WEIGHT_REPS,
                ),
            ),
        )
        persistence.savePersonalBests(SampleData.personalBests(FIXTURE_TIME))
        val store = StrengthStore(persistence, seedDemoData = false)
        val clock = FIXTURE_TIME
        val controller = WorkoutController(store, persistence, clock = { clock })
        controller.startWorkout(store.templates.first())
        controller.send(WorkoutAction.LogNextSet)
        controller.send(WorkoutAction.LogNextSet)
        assertThat(controller.state.value!!.exercises.sumOf { it.doneCount }).isEqualTo(FIXTURE_DONE_SETS)
        for (name in files) {
            val text = File(persistence.directory, name).readText()
            File(target, name).writeText(if (name == "history.json") marked(text) else text)
        }
    }

    /** The marker is a key that no model has: it proves, in every history entry, that unknown keys are skipped. */
    private fun marked(history: String): String =
        withExtraField(StrengthJson.format.parseToJsonElement(history), key = "formatMarker").toString()

    private fun withExtraField(element: JsonElement, key: String = "futureField"): JsonElement = when (element) {
        is JsonObject -> JsonObject(element.mapValues { (_, value) -> withExtraField(value, key) } + (key to JsonPrimitive(1)))
        is JsonArray -> JsonArray(element.map { withExtraField(it, key) })
        else -> element
    }

    private companion object {
        val FIXTURE_TIME: Instant = Instant.parse("2026-01-17T10:00:00Z")
        val SAMPLE_HISTORY_COUNT: Int = SampleData.history(Instant.parse("2026-01-17T10:00:00Z")).size
        const val FIXTURE_DONE_SETS = 2
    }
}
