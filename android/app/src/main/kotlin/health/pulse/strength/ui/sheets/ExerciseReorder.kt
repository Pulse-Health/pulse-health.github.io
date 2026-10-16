package health.pulse.strength.ui.sheets

import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlin.math.abs
import kotlin.math.min
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Drag-to-reorder for a [LazyListState] list whose items have stable keys of type [K].
 *
 * While a row is dragged the list shows [order] (the keys in their preview order) and the dragged row follows the finger with
 * [dragOffset]; nothing is committed to the model until the finger is lifted ([end] reports the final move once). Neighbours swap
 * places when the dragged row's centre passes their centre, and the list scrolls by itself near its edges ([autoScrollStep]).
 */
@Stable
internal class ReorderState<K : Any>(
    private val listState: LazyListState,
    private val scope: CoroutineScope,
    /** Called when the dragged row swaps places with a neighbour (a light haptic). */
    private val onSwap: () -> Unit = {},
) {
    /** The keys in their preview order while a row is dragged; null otherwise. */
    var order by mutableStateOf<List<K>?>(null)
        private set

    /** The key of the dragged row; stays set while the row settles into its place after the finger was lifted. */
    var draggedKey by mutableStateOf<K?>(null)
        private set

    /** Distance in px the dragged row is displaced from its layout position (follows the finger). */
    var dragOffset by mutableFloatStateOf(0f)
        private set

    private var fingerDown = false
    private var startIndex = -1

    val isDragging: Boolean get() = fingerDown

    /** Starts dragging [key]; [keys] is the current order of the list. Ignored while another row is still settling. */
    fun start(key: K, keys: List<K>) {
        if (draggedKey != null) return
        startIndex = keys.indexOf(key)
        if (startIndex < 0) return
        fingerDown = true
        order = keys
        draggedKey = key
        dragOffset = 0f
    }

    /** Moves the dragged row by [delta] px and swaps it with the neighbour whose centre it has passed. */
    fun drag(delta: Float) {
        val key = draggedKey ?: return
        if (!fingerDown) return
        dragOffset += delta
        val current = order ?: return
        val index = current.indexOf(key)
        val items = listState.layoutInfo.visibleItemsInfo
        val me = items.firstOrNull { it.key == key } ?: return
        // The layout has not caught up with the last swap yet (one swap per frame): its offsets are stale, wait for the next frame.
        if (me.index != index) return
        val centre = me.offset + me.size / 2f + dragOffset
        val next = if (index < current.lastIndex) items.firstOrNull { it.key == current[index + 1] } else null
        val previous = if (index > 0) items.firstOrNull { it.key == current[index - 1] } else null
        if (next != null && centre > next.offset + next.size / 2f) {
            order = current.toMutableList().also { it.add(index + 1, it.removeAt(index)) }
            // The row now sits where its neighbour was: keep it under the finger.
            dragOffset -= next.size
            onSwap()
        } else if (previous != null && centre < previous.offset + previous.size / 2f) {
            order = current.toMutableList().also { it.add(index - 1, it.removeAt(index)) }
            dragOffset += previous.size
            onSwap()
        }
    }

    /**
     * How far the list should scroll this frame (px, negative = up) because the dragged row is near an edge of the list; 0 when it
     * is not. [edge] is the width of the hot zone in px.
     */
    fun autoScrollStep(edge: Float, maxStep: Float): Float {
        val key = draggedKey ?: return 0f
        if (!fingerDown) return 0f
        val layout = listState.layoutInfo
        val me = layout.visibleItemsInfo.firstOrNull { it.key == key } ?: return 0f
        val top = me.offset + dragOffset
        val bottom = top + me.size
        return when {
            top < layout.viewportStartOffset + edge && listState.canScrollBackward ->
                -maxStep * min(1f, (layout.viewportStartOffset + edge - top) / edge)
            bottom > layout.viewportEndOffset - edge && listState.canScrollForward ->
                maxStep * min(1f, (bottom - (layout.viewportEndOffset - edge)) / edge)
            else -> 0f
        }
    }

    /** Scrolls the list by [step] px and keeps the dragged row under the finger. */
    suspend fun scrollBySteps(step: Float) {
        if (abs(step) < 0.5f) return
        val consumed = listState.scrollBy(step)
        dragOffset += consumed
    }

    /** The finger was lifted: reports the move (original index, final index) once and settles the row into its place. */
    fun end(onMove: (from: Int, to: Int) -> Unit) {
        val key = draggedKey ?: return
        if (!fingerDown) return
        fingerDown = false
        val to = order?.indexOf(key) ?: -1
        if (to >= 0 && to != startIndex) onMove(startIndex, to)
        scope.launch {
            animate(dragOffset, 0f, animationSpec = tween(durationMillis = 150)) { value, _ -> dragOffset = value }
            order = null
            draggedKey = null
        }
    }

    /** The gesture was cancelled: the row goes back to where it started. */
    fun cancel() {
        if (!fingerDown) return
        fingerDown = false
        order = null
        scope.launch {
            animate(dragOffset, 0f, animationSpec = tween(durationMillis = 150)) { value, _ -> dragOffset = value }
            draggedKey = null
        }
    }
}
