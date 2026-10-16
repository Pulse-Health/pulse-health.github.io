package health.pulse.strength.core

import health.pulse.strength.core.widgets.WidgetJson
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.preview
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertNotNull

/** The widget data contract (widgets/tools/schema.py) as seen from Kotlin. */
class WidgetSnapshotContractTest {
    @Test
    fun previewDecodesAndHasEveryHomeScreenSection() {
        val preview = WidgetSnapshot.preview
        assertEquals(WidgetSnapshot.CURRENT_SCHEMA_VERSION, preview.schemaVersion)
        assertEquals(7, preview.week.days.size)
        assertEquals(3, preview.week.completed)
        assertEquals(4, preview.week.goal)
        assertEquals("Upper A · Push", preview.nextUp?.name)
        assertEquals(6, preview.nextUp?.exercises?.size)
        assertEquals(3, preview.templates.size)
        assertEquals(MuscleGroup.entries.size, preview.freshness.size)
        assertEquals(MuscleGroup.entries.size, preview.weeklySets.muscles.size)
        assertEquals(31, preview.month.days.size)
        assertEquals(12, preview.year.monthlyTonnes.size)
        assertNull(preview.active)
    }

    @Test
    fun previewRoundTripsThroughTheJsonConfiguration() {
        val preview = WidgetSnapshot.preview
        val again = WidgetJson.decodeSnapshot(WidgetJson.encodeSnapshot(preview))
        assertEquals(preview, again)
    }

    @Test
    fun aNewerSchemaOrGarbageReadsAsNull() {
        val newer = WidgetJson.encodeSnapshot(WidgetSnapshot.preview.copy(schemaVersion = WidgetSnapshot.CURRENT_SCHEMA_VERSION + 1))
        assertNull(WidgetJson.decodeSnapshotOrNull(newer))
        assertNull(WidgetJson.decodeSnapshotOrNull("{not json"))
        assertNull(WidgetJson.decodeSnapshotOrNull(null))
        assertNotNull(WidgetJson.decodeSnapshotOrNull(WidgetJson.encodeSnapshot(WidgetSnapshot.preview)))
    }
}
