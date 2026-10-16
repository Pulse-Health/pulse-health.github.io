package health.pulse.strength.widgets.lock

import kotlin.math.ceil

/** Measures the width of a text in dp, as the launcher will draw it. */
internal fun interface TextMeter {
    fun width(text: String): Float
}

/**
 * Choosing and cutting text by its measured width, so that what matters stays visible: the figures after a long exercise name, the days
 * after a long split name, the unit after a number. A plain `maxLines` ellipsis cuts the END of a text, which is exactly where those are.
 */
internal object TextFit {
    /** Glance draws text in a `TextView` that keeps its font padding: a line is about this many times the type size high. */
    const val LINE_FACTOR = 1.3f

    private const val ELLIPSIS = "…"

    /** The height in dp of [lines] lines of [sizeSp] text, for working out how many lines a widget has room for. */
    fun height(sizeSp: Float, lines: Int = 1): Float = sizeSp * LINE_FACTOR * lines

    /**
     * The number of lines [text] takes when wrapped at its spaces into [maxWidth] dp. A single word wider than the line takes as many
     * lines as its width needs, as a `TextView` breaks it.
     */
    fun lineCount(text: String, maxWidth: Float, meter: TextMeter): Int {
        if (maxWidth <= 0f) return 1
        var lines = 1
        var current = ""
        for (word in text.split(' ')) {
            val candidate = if (current.isEmpty()) word else "$current $word"
            when {
                meter.width(candidate) <= maxWidth -> current = candidate
                current.isEmpty() -> {
                    lines += extraLines(meter.width(candidate), maxWidth)
                    current = candidate
                }
                else -> {
                    lines += 1 + extraLines(meter.width(word), maxWidth)
                    current = word
                }
            }
        }
        return lines
    }

    /** The lines a single run of [width] dp takes beyond the first when it is broken at [maxWidth]. */
    private fun extraLines(width: Float, maxWidth: Float): Int = (ceil(width / maxWidth).toInt() - 1).coerceAtLeast(0)

    /** The first of [variants] that fits [maxWidth] dp; when none does, the last (by convention the shortest). */
    fun firstFitting(variants: List<String>, maxWidth: Float, meter: TextMeter): String =
        variants.firstOrNull { meter.width(it) <= maxWidth } ?: variants.last()

    /** The first of [variants] that wraps into at most [lines] lines of [maxWidth] dp; when none does, the last (the shortest). */
    fun firstWithin(variants: List<String>, maxWidth: Float, lines: Int, meter: TextMeter): String =
        variants.firstOrNull { lineCount(it, maxWidth, meter) <= lines } ?: variants.last()

    /** [lead] cut short with an ellipsis until [lead] and [trail] together fit [maxWidth] dp; the [trail] is never cut. */
    fun fitLead(lead: String, trail: String, maxWidth: Float, meter: TextMeter): String {
        if (meter.width(lead + trail) <= maxWidth) return lead + trail
        for (keep in lead.length - 1 downTo 1) {
            val candidate = lead.take(keep).trimEnd() + ELLIPSIS + trail
            if (meter.width(candidate) <= maxWidth) return candidate
        }
        return ELLIPSIS + trail
    }
}
