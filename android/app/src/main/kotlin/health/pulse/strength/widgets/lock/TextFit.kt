package health.pulse.strength.widgets.lock

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

    /** The first of [variants] that fits [maxWidth] dp; when none does, the last (by convention the shortest). */
    fun firstFitting(variants: List<String>, maxWidth: Float, meter: TextMeter): String =
        variants.firstOrNull { meter.width(it) <= maxWidth } ?: variants.last()

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
