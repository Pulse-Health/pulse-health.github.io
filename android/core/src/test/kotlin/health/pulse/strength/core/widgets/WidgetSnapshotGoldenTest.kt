package health.pulse.strength.core.widgets

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.core.StrengthData
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlin.math.abs
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Test

/**
 * The snapshot of the demo data against `widgets/fixtures/golden-sample.json` (widgets/SPEC.md section 2). The file is written by the
 * Swift tests (`WidgetSnapshotGoldenTests`, `UPDATE_GOLDEN=1`) for `StrengthData.demo(now:)` at 2026-10-16T09:41:00Z in UTC with a weekly
 * goal of 4 and no body weight; this test builds the same demo data with the Kotlin sample data and expects the same snapshot. It never
 * writes the file.
 *
 * Both sides are decoded into [WidgetSnapshot] and compared as JSON trees: numbers within 1e-9, ids as UUIDs (Swift writes them upper
 * case), everything else equal. A difference means a rule that is not the same on both platforms; the failure lists every one.
 */
class WidgetSnapshotGoldenTest {
    private val now: Instant = Instant.ofEpochSecond(1_792_143_660) // 2026-10-16T09:41:00Z, a Friday

    private fun demoSnapshot(): WidgetSnapshot =
        WidgetSnapshotBuilder.make(StrengthData.demo(now), WidgetContext(zone = ZoneId.of("UTC")), now)

    /** `widgets/fixtures/golden-sample.json` of the repository the tests run in. */
    private fun goldenFile(): File {
        var directory: File? = File(System.getProperty("user.dir")).absoluteFile
        while (directory != null) {
            val candidate = File(directory, "widgets/fixtures/golden-sample.json")
            if (candidate.isFile) return candidate
            directory = directory.parentFile
        }
        throw AssertionError("widgets/fixtures/golden-sample.json was not found above ${System.getProperty("user.dir")}")
    }

    private fun tree(snapshot: WidgetSnapshot): JsonElement = WidgetJson.json.encodeToJsonElement(WidgetSnapshot.serializer(), snapshot)

    @Test
    fun testTheSnapshotOfTheDemoDataMatchesTheGoldenFile() {
        val golden = WidgetJson.decodeSnapshot(goldenFile().readText())
        val differences = mutableListOf<String>()
        compare("snapshot", tree(golden), tree(demoSnapshot()), differences)
        assertWithMessage("golden (Swift) against built (Kotlin):\n" + differences.joinToString("\n"))
            .that(differences)
            .isEmpty()
    }

    /** `5EED<group>-0000-4000-8000-<index as 12 hex digits>`, the ids the Swift demo data uses. */
    private fun fixedId(group: Int, index: Int): UUID =
        UUID.fromString("5EED%04X-0000-4000-8000-%012X".format(group, index))

    /** The input the Swift golden test describes (`WidgetSnapshotGoldenTests`): the Kotlin demo data has to be exactly this. */
    @Test
    fun testTheKotlinDemoDataIsTheFixtureOfTheSwiftGoldenTest() {
        val data = StrengthData.demo(now)
        assertThat(data.templates.map { it.id }).containsExactly(fixedId(1, 1), fixedId(1, 2), fixedId(1, 3)).inOrder()
        assertThat(data.templates.map { it.name }).containsExactly("Upper A · Push", "Lower A · Quads", "Upper B · Pull").inOrder()
        val entryNumbers = listOf((1..6).toList(), (11..15).toList(), (21..26).toList())
        for ((index, template) in data.templates.withIndex()) {
            assertThat(template.entries.map { it.id }).containsExactlyElementsIn(entryNumbers[index].map { fixedId(2, it) }).inOrder()
        }

        // Newest first: name, days before now, minutes, average heart rate.
        val workouts = listOf(
            listOf("Upper B · Pull", 3, 52, 124), listOf("Upper A · Push", 5, 49, 126), listOf("Lower A · Quads", 7, 61, 118),
            listOf("Upper A · Push", 10, 56, 131), listOf("Upper A · Push", 15, 51, null),
        )
        assertThat(data.history).hasSize(5)
        for ((index, expected) in workouts.withIndex()) {
            val workout = data.history[index]
            assertThat(workout.id).isEqualTo(fixedId(3, index + 1))
            assertThat(workout.name).isEqualTo(expected[0])
            assertThat(workout.finishedAt).isEqualTo(now.minusSeconds((expected[1] as Int) * 86_400L))
            assertThat(workout.durationSeconds).isEqualTo((expected[2] as Int) * 60)
            assertThat(workout.averageHeartRate).isEqualTo(expected[3])
            assertThat(workout.exercises.map { it.id }).containsExactlyElementsIn(workout.exercises.indices.map { fixedId(4, (index + 1) * 100 + it + 1) }).inOrder()
        }
        assertThat(data.history[3].personalRecords.map { it.exerciseID }).containsExactly("bench")
        assertThat(data.customExercises).isEmpty()
    }

    @Test
    fun testTheGoldenFileHoldsNoWallClockValue() {
        val golden = WidgetJson.decodeSnapshot(goldenFile().readText())
        assertThat(golden.generatedAt).isEqualTo(now)
        assertThat(golden.timeZoneID).isEqualTo("UTC")
        assertThat(golden.week.goal).isEqualTo(4)
        assertThat(golden.strengthRatio?.bodyweightKg).isNull()
        assertThat(golden.readiness).isNull()
        assertThat(golden.partners).isEmpty()
        assertThat(golden.active).isNull()
    }

    @Test
    fun testBuildingTwiceGivesTheSameSnapshot() {
        assertThat(demoSnapshot()).isEqualTo(demoSnapshot())
        assertThat(WidgetJson.encodeSnapshot(demoSnapshot())).isEqualTo(WidgetJson.encodeSnapshot(demoSnapshot()))
    }

    @Test
    fun testTheComparisonSeesADifference() {
        val built = demoSnapshot()
        val last = built.lastSession!!
        val changed = built.copy(
            week = built.week.copy(completed = built.week.completed + 1, goal = 5),
            lastSession = last.copy(workoutID = "other", volumeKg = last.volumeKg + 1e-6),
        )
        val differences = mutableListOf<String>()
        compare("snapshot", tree(built), tree(changed), differences)
        assertThat(differences.map { it.substringBefore(":") })
            .containsExactly("snapshot.week.completed", "snapshot.week.goal", "snapshot.lastSession.workoutID", "snapshot.lastSession.volumeKg")
    }

    @Test
    fun testTheComparisonIgnoresTheCaseOfIdsAndTinyNumberErrors() {
        val built = demoSnapshot()
        val last = built.lastSession!!
        val same = built.copy(lastSession = last.copy(workoutID = last.workoutID.uppercase(), volumeKg = last.volumeKg + 1e-12))
        val differences = mutableListOf<String>()
        compare("snapshot", tree(built), tree(same), differences)
        assertThat(differences).isEmpty()
    }

    /** Adds one line to [out] for every place where [actual] is not [expected]. */
    private fun compare(path: String, expected: JsonElement?, actual: JsonElement?, out: MutableList<String>) {
        when {
            expected == null || actual == null -> out.add("$path: golden=${expected ?: "missing"} built=${actual ?: "missing"}")
            expected is JsonObject && actual is JsonObject -> {
                for (key in (expected.keys + actual.keys).sorted()) compare("$path.$key", expected[key], actual[key], out)
            }
            expected is JsonArray && actual is JsonArray -> {
                if (expected.size != actual.size) out.add("$path: golden has ${expected.size} entries, built has ${actual.size}")
                for (index in 0 until minOf(expected.size, actual.size)) compare("$path[$index]", expected[index], actual[index], out)
            }
            expected is JsonPrimitive && actual is JsonPrimitive -> if (!samePrimitive(expected, actual)) {
                out.add("$path: golden=${expected.content} built=${actual.content}")
            }
            else -> out.add("$path: golden=$expected built=$actual")
        }
    }

    private fun samePrimitive(expected: JsonPrimitive, actual: JsonPrimitive): Boolean {
        if (expected.isString != actual.isString) return false
        if (expected.isString) return expected.content == actual.content || sameUuid(expected.content, actual.content)
        val left = expected.content.toDoubleOrNull()
        val right = actual.content.toDoubleOrNull()
        if (left != null && right != null) return abs(left - right) <= 1e-9
        return expected.content == actual.content
    }

    private fun sameUuid(left: String, right: String): Boolean {
        val first = runCatching { UUID.fromString(left) }.getOrNull() ?: return false
        return first == runCatching { UUID.fromString(right) }.getOrNull()
    }
}
