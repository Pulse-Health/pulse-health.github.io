package health.pulse.strength.core

// Text helpers that give Kotlin strings the whitespace rules the workout core was written against (Foundation and the Swift standard
// library), so search tokens and trimmed names come out the same on every platform.

/**
 * True for the characters Swift treats as whitespace: `Character.isWhitespace` (the Unicode White_Space property) and
 * `CharacterSet.whitespacesAndNewlines` (general category Z*, U+0009...U+000D and U+0085) are the same set:
 * U+0009...U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000...U+200A, U+2028, U+2029, U+202F, U+205F and U+3000.
 *
 * Kotlin's own `Char.isWhitespace()` is not the same set (it includes U+001C...U+001F and leaves out U+0085), and `\s` in a
 * regular expression matches ASCII whitespace only.
 */
internal fun Char.isFoundationWhitespace(): Boolean = when (code) {
    in 0x0009..0x000D, 0x0020, 0x0085, 0x00A0, 0x1680, in 0x2000..0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000 -> true
    else -> false
}

/** Swift `trimmingCharacters(in: .whitespacesAndNewlines)`. */
internal fun String.trimmedFoundation(): String = trim { it.isFoundationWhitespace() }

/** Swift `split(whereSeparator: { $0.isWhitespace })`: the runs between whitespace characters, without empty parts. */
internal fun String.splitOnFoundationWhitespace(): List<String> {
    val parts = mutableListOf<String>()
    var start = -1
    for ((index, character) in withIndex()) {
        if (character.isFoundationWhitespace()) {
            if (start >= 0) {
                parts.add(substring(start, index))
                start = -1
            }
        } else if (start < 0) {
            start = index
        }
    }
    if (start >= 0) parts.add(substring(start))
    return parts
}
