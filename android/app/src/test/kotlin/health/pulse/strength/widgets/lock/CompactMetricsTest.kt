package health.pulse.strength.widgets.lock

import androidx.compose.ui.unit.dp
import com.google.common.truth.Truth.assertThat
import org.junit.Test

/** The padding and type sizes a 3x1 widget gets for the height a launcher offers (counted for text at its default size). */
class CompactMetricsTest {
    @Test
    fun aTallRowGetsTheLargestSetWithAllThreeLines() {
        val metrics = CompactMetrics.forHeight(80.dp)
        assertThat(metrics.padding).isEqualTo(10.dp)
        assertThat(metrics.showsEyebrow).isTrue()
        assertThat(metrics.showsDetail).isTrue()
    }

    @Test
    fun aShorterRowGetsSmallerTypeAndLessPaddingBeforeAnythingIsDropped() {
        val sizes = listOf(80.dp, 70.dp, 64.dp).map { CompactMetrics.forHeight(it) }
        assertThat(sizes.map { it.padding.value }).containsExactly(10f, 8f, 7f).inOrder()
        assertThat(sizes.map { it.title.value }).containsExactly(16f, 15f, 14f).inOrder()
        assertThat(sizes.all { it.showsEyebrow && it.showsDetail }).isTrue()
    }

    @Test
    fun aRowTooShortForThreeLinesDropsTheEyebrowFirst() {
        val metrics = CompactMetrics.forHeight(50.dp)
        assertThat(metrics.showsEyebrow).isFalse()
        assertThat(metrics.showsDetail).isTrue()
    }

    @Test
    fun theSmallestRowALauncherOffersStillHoldsTheHeadlineAndTheDetail() {
        val metrics = CompactMetrics.forHeight(40.dp)
        assertThat(metrics.padding).isEqualTo(4.dp)
        assertThat(metrics.showsEyebrow).isFalse()
        assertThat(metrics.showsDetail).isTrue()
    }

    @Test
    fun largeTextInAShortRowKeepsOnlyTheHeadline() {
        // 40 dp of height at a font scale of 1.3 counts as 31 dp of default-size text: room for the headline alone.
        val metrics = CompactMetrics.forHeight(31.dp)
        assertThat(metrics.showsEyebrow).isFalse()
        assertThat(metrics.showsDetail).isFalse()
        assertThat(CompactMetrics.forHeight(5.dp).showsDetail).isFalse()
    }
}
