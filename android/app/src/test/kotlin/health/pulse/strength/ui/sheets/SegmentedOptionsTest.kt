package health.pulse.strength.ui.sheets

import android.graphics.Bitmap
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.ui.theme.LightPulseColors
import health.pulse.strength.ui.theme.PulseTheme
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The segmented control (RIR and Track): the selected segment must be told from the track by its looks, in both themes. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SegmentedOptionsTest {
    @get:Rule val rule = createComposeRule()

    private val options = listOf(SegmentOption(0, "0", "Zero"), SegmentOption(1, "1", "One"), SegmentOption(2, "2", "Two"))
    private val density = 3f // xxhdpi

    /** The pixels of the control on the sheet ground, and where the three segments are (px). */
    private class Shot(val pixels: Bitmap, val selected: Rect, val other: Rect) {
        fun pixel(x: Float, y: Float) = pixels.getPixel(x.toInt(), y.toInt())
    }

    private fun shoot(dark: Boolean): Shot {
        rule.setContent {
            PulseTestTheme(dark = dark) {
                Box(Modifier.fillMaxWidth().background(PulseTheme.colors.ground).padding(16.dp)) {
                    SegmentedOptions(options, selection = 1, onSelect = {}, groupLabel = "Group")
                }
            }
        }
        rule.waitForIdle()
        rule.onNodeWithContentDescription("One").assert(SemanticsMatcher.expectValue(SemanticsProperties.Selected, true))
        val bounds = { name: String -> rule.onNodeWithContentDescription(name).fetchSemanticsNode().boundsInRoot }
        return Shot(rule.onRoot().captureToImage().asAndroidBitmap(), bounds("One"), bounds("Zero"))
    }

    /** The colour of the track, away from the selected segment and its shadow: the left end of the first (unselected) segment. */
    private fun Shot.track() = pixel(other.left + 6 * density, other.center.y)

    /** The colour inside the selected segment, next to its left edge and clear of its label. */
    private fun Shot.thumb() = pixel(selected.left + 6 * density, selected.center.y)

    /** The colour on the left edge of the selected segment, where a ring would be. */
    private fun Shot.rim() = pixel(selected.left + 1f, selected.center.y)

    private fun luminance(argb: Int): Double {
        fun channel(value: Int): Double {
            val s = value / 255.0
            return if (s <= 0.04045) s / 12.92 else ((s + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * channel((argb shr 16) and 0xFF) + 0.7152 * channel((argb shr 8) and 0xFF) + 0.0722 * channel(argb and 0xFF)
    }

    /** The WCAG contrast ratio of two opaque colours. */
    private fun contrast(a: Int, b: Int): Double = (max(luminance(a), luminance(b)) + 0.05) / (min(luminance(a), luminance(b)) + 0.05)

    @Test
    fun inDarkModeTheSelectedSegmentIsRingedInAColourThatContrastsWithTheTrack() {
        val shot = shoot(dark = true)
        // Non-text contrast (WCAG 1.4.11): at least 3:1 between the marker of the selection and what is next to it.
        assertThat(contrast(shot.rim(), shot.track())).isAtLeast(3.0)
        // The thumb itself is a step lighter than the track, not the same colour.
        assertThat(contrast(shot.thumb(), shot.track())).isAtLeast(1.3)
    }

    @Test
    fun inLightModeTheThumbStaysTheWhiteCardWithoutARing() {
        val shot = shoot(dark = false)
        assertThat(shot.thumb()).isEqualTo(LightPulseColors.card.toArgb())
        assertThat(shot.rim()).isEqualTo(shot.thumb())
    }
}
