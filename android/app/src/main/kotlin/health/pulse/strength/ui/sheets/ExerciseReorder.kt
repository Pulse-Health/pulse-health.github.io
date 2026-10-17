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

/** The share of the viewport height that one hot zone (at the top and at the bottom) may take at most. */
internal const val AutoScrollZoneShare = 0.25f

/** A frame longer than this (a hitch) scrolls as far as this long frame would: the list must not jump. */
internal const val AutoScrollMaxFrameNanos = 50_000_000L

/**
 * How fast (px per second, negative = up) the list scrolls because the finger at [finger] (px in the list's coordinates) is near
 * an edge of the viewport [viewportStart] to [viewportEnd]; 0 when it is not, or when the list cannot scroll that way. The hot
 * zone is [maxEdge] wide but at most [AutoScrollZoneShare] of the viewport, so a short viewport keeps a dead band in the middle;
 * the speed grows linearly from 0 at the inner border of the zone to [maxSpeed] at the viewport's edge (and beyond it).
 */
internal fun edgeScrollSpeed(
    finger: Float,
    viewportStart: Float,
    viewportEnd: Float,
    maxEdge: Float,
    maxSpeed: Float,
    canScrollBackward: Boolean,
    canScrollForward: Boolean,
): Float {
    val edge = min(maxEdge, (viewportEnd - viewportStart) * AutoScrollZoneShare)
    if (edge <= 0f) return 0f
    return when {
        finger < viewportStart + edge && canScrollBackward -> -maxSpeed * min(1f, (viewportStart + edge - finger) / edge)
        finger > viewportEnd - edge && canScrollForward -> maxSpeed * min(1f, (finger - (viewportEnd - edge)) / edge)
        else -> 0f
    }
}

/** The distance (px) to scroll in a frame of [frameNanos] at [speed] px per second: the same per second at any refresh rate. */
internal fun edgeScrollDistance(speed: Float, frameNanos: Long): Float =
    speed * frameNanos.coerceIn(0L, AutoScrollMaxFrameNanos) / 1_000_000_000f

/**
 * Drag-to-reorder for a [LazyListState] list whose items have stable keys of type [K].
 *
 * While a row is dragged the list shows [order] (the keys in their preview order) and the dragged row follows the finger with
 * [dragOffset]; nothing is committed to the model until the finger is lifted ([end] reports the final move once). Neighbours swap
 * places when the dragged row's centre passes their centre, and the list scrolls by itself while the finger is near an edge of
 * the list ([autoScrollSpeed]).
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

    /** Where the finger holds the dragged row, in px below (positive) or above its vertical centre; it stays the same all drag. */
    private var fingerFromCentre = 0f

    /** False until the first [drag] after [start], which carries what the touch slop left over (see [drag]). */
    private var hasMoved = false

    /** The part of a scroll step (px) that was too small to move the list; it is added to the next step. */
    private var carry = 0f

    val isDragging: Boolean get() = fingerDown

    /**
     * Starts dragging [key]; [keys] is the current order of the list. The finger is [fingerFromCentre] px below the row's centre
     * (negative: above) where it is now. Ignored while another row is still settling.
     */
    fun start(key: K, keys: List<K>, fingerFromCentre: Float = 0f) {
        if (draggedKey != null) return
        startIndex = keys.indexOf(key)
        if (startIndex < 0) return
        fingerDown = true
        order = keys
        draggedKey = key
        dragOffset = 0f
        this.fingerFromCentre = fingerFromCentre
        hasMoved = false
        carry = 0f
    }

    /** Moves the dragged row by [delta] px and swaps it with the neighbour whose centre it has passed. */
    fun drag(delta: Float) {
        val key = draggedKey ?: return
        if (!fingerDown) return
        // The gesture reports the finger's place once the touch slop is crossed, and then the movement beyond the slop as the
        // first [delta]: the row moves by it, the finger does not (it is already there).
        if (!hasMoved) {
            fingerFromCentre -= delta
            hasMoved = true
        }
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
            reorder(current.toMutableList().also { it.add(index + 1, it.removeAt(index)) })
            // The row now sits where its neighbour was: keep it under the finger.
            dragOffset -= next.size
            onSwap()
        } else if (previous != null && centre < previous.offset + previous.size / 2f) {
            reorder(current.toMutableList().also { it.add(index - 1, it.removeAt(index)) })
            dragOffset += previous.size
            onSwap()
        }
    }

    /**
     * Shows [newOrder]. A LazyColumn keeps the item that was first in view first in view when items change places, which would
     * scroll the list by a row whenever that item is the dragged one or the one it swaps with; here the list stays where it is.
     */
    private fun reorder(newOrder: List<K>) {
        val firstIndex = listState.firstVisibleItemIndex
        val firstOffset = listState.firstVisibleItemScrollOffset
        order = newOrder
        listState.requestScrollToItem(firstIndex, firstOffset)
    }

    /**
     * How fast the list should scroll now (px per second, negative = up) because the finger is near an edge of the list; 0 when
     * it is not. [maxEdge] is the widest hot zone in px (see [edgeScrollSpeed]), [maxSpeed] the speed at the edge in px per second.
     */
    fun autoScrollSpeed(maxEdge: Float, maxSpeed: Float): Float {
        val key = draggedKey ?: return 0f
        if (!fingerDown) return 0f
        val layout = listState.layoutInfo
        val me = layout.visibleItemsInfo.firstOrNull { it.key == key } ?: return 0f
        // The layout has not caught up with the last swap yet (see [drag]): its offsets are one row off, wait for the next frame.
        if (me.index != order?.indexOf(key)) return 0f
        val finger = me.offset + me.size / 2f + dragOffset + fingerFromCentre
        return edgeScrollSpeed(
            finger = finger,
            viewportStart = layout.viewportStartOffset.toFloat(),
            viewportEnd = layout.viewportEndOffset.toFloat(),
            maxEdge = maxEdge,
            maxSpeed = maxSpeed,
            canScrollBackward = listState.canScrollBackward,
            canScrollForward = listState.canScrollForward,
        )
    }

    /** Scrolls the list by [step] px and keeps the dragged row under the finger. */
    suspend fun scrollBySteps(step: Float) {
        carry += step
        if (abs(carry) < 0.5f) return
        val consumed = listState.scrollBy(carry)
        carry = 0f
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
