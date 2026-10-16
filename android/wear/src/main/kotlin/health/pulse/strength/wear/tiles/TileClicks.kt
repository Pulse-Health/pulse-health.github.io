package health.pulse.strength.wear.tiles

/**
 * Identity of the clickables that ask the tile service to do something (a `LoadAction`). A clickable id is `<action>#<generation>`,
 * where the generation is new for every layout the service builds.
 *
 * The renderer reports the id of the last clicked element with the next tile request. If a later request (the periodic refresh, an
 * update pushed by the phone) repeated that id, a command such as "+15 s" would run again without a tap. [firstTime] lets each
 * id through once, and a new layout carries a new generation, so every real tap on a fresh layout counts.
 */
internal object TileClicks {
    private const val SEPARATOR = '#'
    private const val REMEMBERED = 32

    private val handled = LinkedHashSet<String>()

    fun newGeneration(): String = System.nanoTime().toString(36)

    fun clickableId(action: String, generation: String): String = "$action$SEPARATOR$generation"

    fun actionOf(clickableId: String): String = clickableId.substringBefore(SEPARATOR)

    /** True for the first report of [clickableId]; false for an empty id and for a repeat. */
    @Synchronized
    fun firstTime(clickableId: String): Boolean {
        if (clickableId.isEmpty() || !handled.add(clickableId)) return false
        if (handled.size > REMEMBERED) {
            val oldest = handled.iterator()
            oldest.next()
            oldest.remove()
        }
        return true
    }

    /** Test hook. */
    @Synchronized
    fun clear() {
        handled.clear()
    }
}
