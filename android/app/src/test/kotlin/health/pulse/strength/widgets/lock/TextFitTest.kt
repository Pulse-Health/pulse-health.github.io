package health.pulse.strength.widgets.lock

import com.google.common.truth.Truth.assertThat
import org.junit.Test

/** Choosing and cutting text by width, with a meter that gives every character the same width. */
class TextFitTest {
    private val sixPerCharacter = TextMeter { it.length * 6f }

    @Test
    fun theFirstVariantThatFitsIsChosen() {
        val variants = listOf("across 74 sessions", "74 sessions")
        assertThat(TextFit.firstFitting(variants, 120f, sixPerCharacter)).isEqualTo("across 74 sessions")
        assertThat(TextFit.firstFitting(variants, 80f, sixPerCharacter)).isEqualTo("74 sessions")
    }

    @Test
    fun whenNoVariantFitsTheLastIsUsed() {
        assertThat(TextFit.firstFitting(listOf("across 74 sessions", "74 sessions"), 10f, sixPerCharacter)).isEqualTo("74 sessions")
        assertThat(TextFit.firstFitting(listOf("only"), 1f, sixPerCharacter)).isEqualTo("only")
    }

    @Test
    fun aLeadThatFitsIsLeftAlone() {
        assertThat(TextFit.fitLead("Push day", " · last 5 days ago", 200f, sixPerCharacter)).isEqualTo("Push day · last 5 days ago")
    }

    @Test
    fun aLongLeadIsCutWithAnEllipsisAndTheTrailStaysWhole() {
        // Room for 20 characters: the 7 of the trail, the ellipsis, and 12 of the name.
        val text = TextFit.fitLead("Incline Dumbbell Press", " 85 × 5", maxWidth = 120f, meter = sixPerCharacter)
        assertThat(text).isEqualTo("Incline Dumb… 85 × 5")
        assertThat(sixPerCharacter.width(text)).isAtMost(120f)
    }

    @Test
    fun spacesBeforeTheEllipsisAreDropped() {
        assertThat(TextFit.fitLead("Bench Press", " 85 × 5", maxWidth = 80f, meter = sixPerCharacter)).isEqualTo("Bench… 85 × 5")
    }

    @Test
    fun whenNotEvenOneCharacterFitsOnlyTheEllipsisAndTheTrailRemain() {
        assertThat(TextFit.fitLead("Long name", " 85 × 5", maxWidth = 20f, meter = sixPerCharacter)).isEqualTo("… 85 × 5")
    }

    @Test
    fun withoutATrailTheLeadIsCutAtTheWidth() {
        assertThat(TextFit.fitLead("Incline Dumbbell Press", "", maxWidth = 60f, meter = sixPerCharacter)).isEqualTo("Incline D…")
    }

    @Test
    fun aTextIsSetAtTheSizeAtWhichItFillsTheWidthButNeverLargerThanTheCap() {
        // 60 dp wide at 20 sp: in 30 dp it is 10 sp; in 120 dp it would be 40 sp, but the cap holds it at 18 sp.
        assertThat(TextFit.sizeForWidth(60f, 20f, 30f, minSp = 6f, maxSp = 18f)).isWithin(0.001f).of(10f)
        assertThat(TextFit.sizeForWidth(60f, 20f, 120f, minSp = 6f, maxSp = 18f)).isEqualTo(18f)
    }

    @Test
    fun aTextNeverGoesBelowTheMinimumSizeEvenWhenTheCapIsLower() {
        assertThat(TextFit.sizeForWidth(60f, 20f, 6f, minSp = 9f, maxSp = 18f)).isEqualTo(9f)
        assertThat(TextFit.sizeForWidth(60f, 20f, 120f, minSp = 9f, maxSp = 7f)).isEqualTo(9f)
    }

    @Test
    fun aTextWithNoWidthTakesTheLargestSize() {
        assertThat(TextFit.sizeForWidth(0f, 20f, 30f, minSp = 6f, maxSp = 18f)).isEqualTo(18f)
    }

    @Test
    fun theFirstVariantThatWrapsIntoEnoughLinesIsChosen() {
        // 6 per character in 60 dp: ten characters a line.
        val variants = listOf("Log bench, squat or press.", "Log a main lift.", "Log a lift")
        assertThat(TextFit.firstWithin(variants, 60f, 3, sixPerCharacter)).isEqualTo("Log bench, squat or press.")
        assertThat(TextFit.firstWithin(variants, 60f, 2, sixPerCharacter)).isEqualTo("Log a main lift.")
        assertThat(TextFit.firstWithin(variants, 60f, 1, sixPerCharacter)).isEqualTo("Log a lift")
    }

    @Test
    fun whenNoVariantWrapsIntoEnoughLinesTheLastIsUsed() {
        assertThat(TextFit.firstWithin(listOf("one two three four", "five six seven"), 30f, 1, sixPerCharacter)).isEqualTo("five six seven")
    }

    @Test
    fun linesAreCountedByWrappingAtSpaces() {
        // 6 per character: a line of 90 dp holds 15 characters, one of 60 dp holds 10.
        val cue = "Shoulder blades back and down."
        assertThat(TextFit.lineCount(cue, 90f, sixPerCharacter)).isEqualTo(2)
        assertThat(TextFit.lineCount(cue, 60f, sixPerCharacter)).isEqualTo(4)
        assertThat(TextFit.lineCount(cue, 200f, sixPerCharacter)).isEqualTo(1)
        assertThat(TextFit.lineCount("", 90f, sixPerCharacter)).isEqualTo(1)
    }

    @Test
    fun aWordWiderThanTheLineIsBrokenOverSeveralLines() {
        // 11 characters = 66 dp in a 30 dp line: three lines.
        assertThat(TextFit.lineCount("Weightlifts", 30f, sixPerCharacter)).isEqualTo(3)
        assertThat(TextFit.lineCount("a Weightlifts b", 30f, sixPerCharacter)).isEqualTo(5)
        assertThat(TextFit.lineCount("anything", 0f, sixPerCharacter)).isEqualTo(1)
    }

    @Test
    fun aLineIsAboutOneAndAThirdTimesTheTypeSize() {
        assertThat(TextFit.height(10f)).isWithin(0.001f).of(13f)
        assertThat(TextFit.height(10f, 2)).isWithin(0.001f).of(26f)
        assertThat(TextFit.height(15f, 0)).isEqualTo(0f)
    }
}
