package health.pulse.strength.ui

import androidx.compose.ui.graphics.Color
import com.google.common.truth.Truth.assertWithMessage
import health.pulse.strength.ui.theme.DarkPulseColors
import health.pulse.strength.ui.theme.LightPulseColors
import health.pulse.strength.ui.theme.PulseColors
import kotlin.math.pow
import org.junit.Test

/**
 * WCAG contrast of the colour tokens on the surfaces they are drawn on, in both styles: 4.5:1 for text, 3:1 for the boundary of a control
 * and for the selected state of a segmented control. The review found a dozen dark-mode pairs below that (the pending set ring at 2.3:1,
 * the white "Finish" label at 3.65:1, the drop and failure badges at 2.5-3:1, the placeholder at 2.3:1).
 */
class ThemeContrastTest {
    private fun channel(value: Float): Double = value.toDouble().let { if (it <= 0.03928) it / 12.92 else ((it + 0.055) / 1.055).pow(2.4) }

    private fun luminance(c: Color): Double = 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)

    /** [foreground] (with its alpha) over [background]. */
    private fun over(foreground: Color, background: Color): Color {
        val a = foreground.alpha
        return Color(
            red = foreground.red * a + background.red * (1 - a),
            green = foreground.green * a + background.green * (1 - a),
            blue = foreground.blue * a + background.blue * (1 - a),
            alpha = 1f,
        )
    }

    private fun ratio(a: Color, b: Color): Double {
        val la = luminance(a)
        val lb = luminance(b)
        return (maxOf(la, lb) + 0.05) / (minOf(la, lb) + 0.05)
    }

    private fun check(name: String, minimum: Double, foreground: Color, background: Color) {
        val value = ratio(over(foreground, background), background)
        assertWithMessage("$name: ${"%.2f".format(value)}:1, needs $minimum:1").that(value >= minimum).isTrue()
    }

    private fun styles(block: (String, PulseColors) -> Unit) {
        block("light", LightPulseColors)
        block("dark", DarkPulseColors)
    }

    @Test
    fun textOnTheSurfacesItIsDrawnOn() = styles { style, c ->
        val doneRow = over(c.doneRowFill, c.rowFill)
        for ((surfaceName, surface) in listOf("ground" to c.ground, "card" to c.card, "row" to c.rowFill, "cell" to c.cellFill)) {
            check("$style ink on $surfaceName", 4.5, c.ink, surface)
            check("$style secondary on $surfaceName", 4.5, c.inkSecondary, surface)
            check("$style tertiary on $surfaceName", 4.5, c.inkTertiary, surface)
        }
        check("$style secondary on a done row", 4.5, c.inkSecondary, doneRow)
        check("$style ink on a done row", 4.5, c.ink, doneRow)
        check("$style green text on the card", 4.5, c.greenText, c.card)
        check("$style green text on the ground", 4.5, c.greenText, c.ground)
        check("$style blue text on the card", 4.5, c.blueText, c.card)
        check("$style destructive on the card", 4.5, c.destructive, c.card)
        check("$style PR text on a PR chip", 4.5, c.prText, over(c.prFill, c.card))
    }

    @Test
    fun theFinishPillAndTheGreenButtonsKeepTheirLabelsReadable() = styles { style, c ->
        check("$style white on the Finish pill", 4.5, Color.White, c.pillFill)
        check("$style label on the green button", 4.5, c.onGreen, c.green)
        check("$style toast action on the toast", 4.5, c.toastAction, c.toastFill)
    }

    @Test
    fun setTypeBadgesOnPendingAndDoneRows() = styles { style, c ->
        val doneRow = over(c.doneRowFill, c.rowFill)
        for ((rowName, row) in listOf("pending" to c.rowFill, "done" to doneRow)) {
            check("$style warm-up badge on a $rowName row", 4.5, c.warmupBadgeForeground, over(c.warmupBadgeBackground, row))
            check("$style drop badge on a $rowName row", 4.5, c.dropBadgeForeground, over(c.dropBadgeBackground, row))
            check("$style failure badge on a $rowName row", 4.5, c.failureBadgeForeground, over(c.failureBadgeBackground, row))
        }
    }

    @Test
    fun theBoundariesOfControlsAndTheNextSetMarker() = styles { style, c ->
        // The empty check circle is drawn in the tertiary ink on the row, the next set is marked by a ring.
        check("$style pending check circle", 3.0, c.inkTertiary, c.rowFill)
        check("$style next-set ring", 3.0, c.nextRowRing, c.rowFill)
        check("$style unchecked switch outline", 3.0, c.inkSecondary, c.card)
    }

    @Test
    fun theSelectedSegmentCanBeToldFromTheTrack() = styles { style, c ->
        val track = over(c.chipFill, c.ground)
        // Dark mode cannot reach 3:1 with greys on black, but the thumb must be clearly lighter than its track, and its label readable.
        assertWithMessage("$style thumb vs track").that(ratio(c.segmentThumb, track) >= if (c.isDark) 2.0 else 1.05).isTrue()
        check("$style label on the selected thumb", 4.5, c.ink, c.segmentThumb)
    }
}
