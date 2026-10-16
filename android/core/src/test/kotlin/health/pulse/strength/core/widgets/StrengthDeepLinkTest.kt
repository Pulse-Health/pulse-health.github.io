package health.pulse.strength.core.widgets

import health.pulse.strength.core.StrengthConfig
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class StrengthDeepLinkTest {
    @Test
    fun everyLinkRoundTrips() {
        val links = listOf(
            StrengthDeepLink.Workout,
            StrengthDeepLink.StartNext,
            StrengthDeepLink.Hub,
            StrengthDeepLink.Plates,
            StrengthDeepLink.Weight,
            StrengthDeepLink.Start(UUID.randomUUID()),
            StrengthDeepLink.StartEmpty("Mobility · Hips & T-spine"),
            StrengthDeepLink.Exercise("bench"),
            StrengthDeepLink.Exercise("custom exercise/1"),
        )
        for (link in links) assertEquals(link, StrengthDeepLink.parse(link.url), link.toString())
    }

    @Test
    fun theExistingWorkoutUrlStillParses() {
        assertEquals(StrengthDeepLink.Workout, StrengthDeepLink.parse(StrengthConfig.workoutUrl))
        assertEquals(StrengthDeepLink.Workout, StrengthDeepLink.parse("PULSE-STRENGTH://Workout"))
    }

    @Test
    fun foreignSchemesAndGarbageAreRejected() {
        assertNull(StrengthDeepLink.parse(null))
        assertNull(StrengthDeepLink.parse(""))
        assertNull(StrengthDeepLink.parse("https://example.com/workout"))
        assertNull(StrengthDeepLink.parse("pulse-strength://unknown"))
        assertNull(StrengthDeepLink.parse("pulse-strength://start?template=nope"))
        assertNull(StrengthDeepLink.parse("pulse-strength://start"))
        assertNull(StrengthDeepLink.parse("pulse-strength://exercise"))
        assertNull(StrengthDeepLink.parse("pulse-strength://exercise/"))
        assertNull(StrengthDeepLink.parse("pulse strength://workout"))
    }

    @Test
    fun anEmptyNameFallsBackToTheDefaultWorkoutName() {
        assertEquals(
            StrengthDeepLink.StartEmpty(StrengthConfig.defaultWorkoutName),
            StrengthDeepLink.parse("pulse-strength://start-empty?name=%20"),
        )
        assertEquals(
            StrengthDeepLink.StartEmpty(StrengthConfig.defaultWorkoutName),
            StrengthDeepLink.parse("pulse-strength://start-empty"),
        )
    }

    @Test
    fun theTemplateIdIsReadCaseInsensitively() {
        val id = UUID.randomUUID()
        assertEquals(StrengthDeepLink.Start(id), StrengthDeepLink.parse("pulse-strength://start?template=${id.toString().uppercase()}"))
    }
}
