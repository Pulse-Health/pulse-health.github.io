package health.pulse.strength.core.widgets

import health.pulse.strength.core.NumberText
import health.pulse.strength.core.roundedAwayFromZero
import health.pulse.strength.core.splitOnFoundationWhitespace
import health.pulse.strength.core.trimmedFoundation
import java.text.BreakIterator
import java.util.Locale

/** Small text and rounding rules shared by the snapshot analytics (widgets/SPEC.md section 2). */
internal object WidgetText {
    /** The dot between the two parts of a template name ("Upper A · Push"): U+00B7 MIDDLE DOT. */
    private const val nameSeparator = '·'

    /**
     * Initials of a workout name: split on whitespace, drop the tokens that have no letter or digit (like the dot), take the first
     * character of the first two tokens, or the first two characters of a single token; "WO" without a token. Upper case.
     * "Upper A · Push" gives "UA".
     */
    fun initials(name: String): String {
        val tokens = name.splitOnFoundationWhitespace().filter { token -> token.codePoints().anyMatch(::isLetterOrNumber) }
        return when (tokens.size) {
            0 -> "WO"
            1 -> firstCharacters(tokens[0], 2).uppercase()
            else -> (firstCharacters(tokens[0], 1) + firstCharacters(tokens[1], 1)).uppercase()
        }
    }

    /** True for a letter (the Unicode Alphabetic property) or a number of any kind. */
    private fun isLetterOrNumber(codePoint: Int): Boolean {
        if (Character.isAlphabetic(codePoint)) return true
        val type = Character.getType(codePoint)
        return type == Character.DECIMAL_DIGIT_NUMBER.toInt() ||
            type == Character.LETTER_NUMBER.toInt() ||
            type == Character.OTHER_NUMBER.toInt()
    }

    /** The first [count] user-perceived characters of [text]. */
    private fun firstCharacters(text: String, count: Int): String {
        val iterator = BreakIterator.getCharacterInstance(Locale.ROOT)
        iterator.setText(text)
        var end = iterator.first()
        repeat(count) {
            val next = iterator.next()
            if (next == BreakIterator.DONE) return text
            end = next
        }
        return text.substring(0, end)
    }

    /**
     * The text after the last dot of a name, trimmed: "Push" for "Upper A · Push". null without a dot, and when nothing but
     * whitespace follows it (the name is then its own label).
     */
    fun textAfterLastDot(name: String): String? {
        val dot = name.lastIndexOf(nameSeparator)
        if (dot < 0) return null
        return name.substring(dot + 1).trimmedFoundation().ifEmpty { null }
    }

    /** "Push day" for "Upper A · Push", else the name. */
    fun splitLabel(name: String): String = textAfterLastDot(name)?.let { "$it day" } ?: name

    /** "Push" for "Upper A · Push", else the name (the row labels of the training block). */
    fun rowLabel(name: String): String = textAfterLastDot(name) ?: name

    /** The name up to its first " ·": "Lower A" for "Lower A · Quads", else the whole name. */
    fun shortName(name: String): String {
        val separator = name.indexOf(" $nameSeparator")
        if (separator < 0) return name
        return name.substring(0, separator).trimmedFoundation().ifEmpty { name }
    }

    /** [value] rounded to 0.1 (halves away from zero). */
    fun tenth(value: Double): Double = (value * 10).roundedAwayFromZero() / 10

    /** [value] rounded to 0.01 (halves away from zero). */
    fun hundredth(value: Double): Double = (value * 100).roundedAwayFromZero() / 100

    /** The plates of one side as "20 + 10 + 2.5". */
    fun platesText(perSide: List<Double>): String = perSide.joinToString(" + ") { NumberText.kg(it) }
}
