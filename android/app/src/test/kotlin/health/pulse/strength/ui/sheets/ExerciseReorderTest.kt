package health.pulse.strength.ui.sheets

import com.google.common.truth.Truth.assertThat
import org.junit.Test

/** The auto-scroll of the drag-to-reorder list without any UI: where the hot zones are and how far a frame scrolls. */
class ExerciseReorderTest {
    /** The speed for a finger at [finger] in a viewport of [height] px (starting at 0) that can scroll both ways. */
    private fun speed(
        finger: Float,
        height: Float,
        maxEdge: Float = 56f,
        maxSpeed: Float = 1000f,
        back: Boolean = true,
        forward: Boolean = true,
    ) = edgeScrollSpeed(finger, 0f, height, maxEdge, maxSpeed, canScrollBackward = back, canScrollForward = forward)

    @Test
    fun theMiddleOfATallViewportDoesNotScroll() {
        assertThat(speed(finger = 400f, height = 800f)).isEqualTo(0f)
        assertThat(speed(finger = 57f, height = 800f)).isEqualTo(0f)
        assertThat(speed(finger = 743f, height = 800f)).isEqualTo(0f)
    }

    @Test
    fun aTallViewportKeepsTheFullHotZone() {
        // 56 px at the bottom: 744...800.
        assertThat(speed(finger = 745f, height = 800f)).isGreaterThan(0f)
        assertThat(speed(finger = 55f, height = 800f)).isLessThan(0f)
    }

    @Test
    fun aShortViewportScalesTheZoneAndKeepsADeadBand() {
        // 187 px (a landscape list): the zone is a quarter, 46.75 px, not 56. The old rule scrolled whenever the row (70 px) that was
        // dragged one place down reached 131, with the finger in the middle of it at about 105.
        assertThat(speed(finger = 105f, height = 187f)).isEqualTo(0f)
        assertThat(speed(finger = 140f, height = 187f)).isEqualTo(0f)
        assertThat(speed(finger = 141f, height = 187f)).isGreaterThan(0f)
        assertThat(speed(finger = 46f, height = 187f)).isLessThan(0f)
        // Every viewport keeps at least half of its height without a hot zone.
        for (height in listOf(60f, 100f, 187f, 240f, 400f, 800f)) {
            val dead = (0..height.toInt()).count { speed(it.toFloat(), height) == 0f }
            assertThat(dead.toFloat()).isAtLeast(height / 2f)
        }
    }

    @Test
    fun theSpeedGrowsFromTheInnerBorderOfTheZoneToTheEdge() {
        // Bottom zone of a 800 px viewport: 744...800.
        assertThat(speed(finger = 744f, height = 800f)).isEqualTo(0f)
        assertThat(speed(finger = 772f, height = 800f)).isWithin(0.01f).of(500f)
        assertThat(speed(finger = 800f, height = 800f)).isEqualTo(1000f)
        // The finger left the list (over the button below it): the full speed, not more.
        assertThat(speed(finger = 900f, height = 800f)).isEqualTo(1000f)
        // Top zone: up is negative.
        assertThat(speed(finger = 28f, height = 800f)).isWithin(0.01f).of(-500f)
        assertThat(speed(finger = -40f, height = 800f)).isEqualTo(-1000f)
    }

    @Test
    fun aListThatCannotScrollThatWayStaysStill() {
        assertThat(speed(finger = 790f, height = 800f, forward = false)).isEqualTo(0f)
        assertThat(speed(finger = 10f, height = 800f, back = false)).isEqualTo(0f)
        assertThat(speed(finger = 790f, height = 800f, back = false)).isGreaterThan(0f)
    }

    @Test
    fun anEmptyViewportDoesNotDivideByZero() {
        assertThat(speed(finger = 0f, height = 0f)).isEqualTo(0f)
        assertThat(speed(finger = 10f, height = 800f, maxEdge = 0f)).isEqualTo(0f)
    }

    @Test
    fun aViewportThatStartsBelowZeroMeasuresFromItsOwnEdges() {
        // Content padding can move the viewport: 100...900.
        fun at(finger: Float) = edgeScrollSpeed(finger, 100f, 900f, 56f, 1000f, canScrollBackward = true, canScrollForward = true)
        assertThat(at(500f)).isEqualTo(0f)
        assertThat(at(900f)).isEqualTo(1000f)
        assertThat(at(100f)).isEqualTo(-1000f)
    }

    @Test
    fun aSecondOfFramesScrollsTheSameDistanceAtAnyRefreshRate() {
        fun scrolled(frames: Int): Float {
            val frameNanos = 1_000_000_000L / frames
            var total = 0f
            repeat(frames) { total += edgeScrollDistance(1000f, frameNanos) }
            return total
        }
        assertThat(scrolled(60)).isWithin(1f).of(1000f)
        assertThat(scrolled(90)).isWithin(1f).of(1000f)
        assertThat(scrolled(120)).isWithin(1f).of(1000f)
        // A 120 Hz frame moves half of a 60 Hz one.
        assertThat(edgeScrollDistance(1000f, 8_333_333L)).isWithin(0.1f).of(edgeScrollDistance(1000f, 16_666_667L) / 2f)
    }

    @Test
    fun aHitchOrAnOddClockCannotMakeTheListJump() {
        // One frame that took half a second scrolls what 50 ms would.
        assertThat(edgeScrollDistance(1000f, 500_000_000L)).isWithin(0.01f).of(50f)
        assertThat(edgeScrollDistance(-1000f, 500_000_000L)).isWithin(0.01f).of(-50f)
        assertThat(edgeScrollDistance(1000f, -16_000_000L)).isEqualTo(0f)
        assertThat(edgeScrollDistance(0f, 16_000_000L)).isEqualTo(0f)
    }
}
