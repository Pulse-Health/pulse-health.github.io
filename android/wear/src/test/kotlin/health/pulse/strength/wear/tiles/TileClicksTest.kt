package health.pulse.strength.wear.tiles

import com.google.common.truth.Truth.assertThat
import org.junit.After
import org.junit.Before
import org.junit.Test

class TileClicksTest {
    @Before
    fun setUp() = TileClicks.clear()

    @After
    fun tearDown() = TileClicks.clear()

    @Test
    fun aClickableIdIsTheActionAndTheGeneration() {
        val id = TileClicks.clickableId("log", "abc")

        assertThat(id).isEqualTo("log#abc")
        assertThat(TileClicks.actionOf(id)).isEqualTo("log")
        assertThat(TileClicks.actionOf("open")).isEqualTo("open")
    }

    @Test
    fun everyIdGetsThroughOnlyOnce() {
        assertThat(TileClicks.firstTime("log#1")).isTrue()
        assertThat(TileClicks.firstTime("log#1")).isFalse()
        assertThat(TileClicks.firstTime("log#2")).isTrue()
    }

    @Test
    fun noClickAtAllNeverRunsAnything() {
        assertThat(TileClicks.firstTime("")).isFalse()
    }

    @Test
    fun theMemoryIsBoundedSoAVeryOldIdMayRunAgain() {
        assertThat(TileClicks.firstTime("old#0")).isTrue()
        repeat(40) { TileClicks.firstTime("new#$it") }

        assertThat(TileClicks.firstTime("old#0")).isTrue()
        assertThat(TileClicks.firstTime("new#39")).isFalse()
    }

    @Test
    fun generationsDiffer() {
        assertThat(TileClicks.newGeneration()).isNotEqualTo(TileClicks.newGeneration())
    }
}
