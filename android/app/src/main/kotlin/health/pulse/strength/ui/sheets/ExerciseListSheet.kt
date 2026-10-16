package health.pulse.strength.ui.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.DragHandle
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.core.WorkoutExercise
import health.pulse.strength.ui.PickerMode
import health.pulse.strength.ui.components.ExerciseMediaView
import health.pulse.strength.ui.components.rememberPulseHaptics
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulsePrimaryButton
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight
import java.util.UUID
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.isActive

/**
 * "Exercises": the workout's exercises as reorderable rows, each with its form thumbnail, name, "3 of 5 sets" progress, superset
 * label and an options button. Shows its own modal bottom sheet.
 *
 * Reordering: drag a row by its handle; for screen readers every row also offers "Move up" / "Move down" actions, and the options
 * have Move up / Move down. Tapping a row shows that exercise and closes the sheet; "Add Exercise" opens the picker. The sheet
 * owns the sheets it opens (picker, form information, rest timer) and the options dialog.
 */
@Composable
fun ExerciseListSheet(controller: WorkoutController, store: StrengthStore, onDismiss: () -> Unit) {
    var reordering by remember { mutableStateOf(false) }
    // The navigation state lives out here, in the screen's composition, not in the sheet's window: that is what survives a rotation.
    val nav = rememberListNavState()
    PulseSheet(onDismiss = onDismiss, fullHeight = true, gesturesEnabled = !reordering) { dismiss ->
        ExerciseListSheetContent(
            controller = controller,
            store = store,
            onDone = dismiss,
            onReorderingChange = { reordering = it },
            nav = nav,
        )
    }
}

/**
 * What the list has open on top of itself: the options of a workout exercise (its id) and a nested sheet, as "add",
 * "replace:<workout exercise id>", "info:<exercise id>" or "rest:<workout exercise id>".
 */
@Stable
internal class ListNavState(optionsID: String? = null, nestedKey: String? = null) {
    var optionsID by mutableStateOf(optionsID)
    var nestedKey by mutableStateOf(nestedKey)

    companion object {
        val Saver = listSaver<ListNavState, String?>(
            save = { listOf(it.optionsID, it.nestedKey) },
            restore = { ListNavState(it[0], it[1]) },
        )
    }
}

@Composable
internal fun rememberListNavState(): ListNavState = rememberSaveable(saver = ListNavState.Saver) { ListNavState() }

/** One row of the list, derived from a workout exercise. */
internal class ExerciseListRow(
    val id: UUID,
    /** Position in the workout. */
    val index: Int,
    val exercise: Exercise,
    /** "Superset A · 3 of 5 sets · Chest · Now" */
    val subtitle: String,
)

internal fun exerciseListRows(exercises: List<WorkoutExercise>, currentIndex: Int): List<ExerciseListRow> =
    exercises.mapIndexed { index, entry ->
        var subtitle = ""
        entry.supersetGroup?.let { subtitle += "Superset $it · " }
        subtitle += "${entry.doneCount} of ${entry.sets.size} sets · ${entry.exercise.muscle.title}"
        if (index == currentIndex) subtitle += " · Now"
        ExerciseListRow(entry.id, index, entry.exercise, subtitle)
    }

/** Everything inside the exercise list sheet's window (and the sheets it opens). [onDone] closes the sheet. */
@Composable
internal fun ExerciseListSheetContent(
    controller: WorkoutController,
    store: StrengthStore,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
    onReorderingChange: (Boolean) -> Unit = {},
    nav: ListNavState = rememberListNavState(),
) {
    val state by controller.state.collectAsState()
    val haptics = rememberPulseHaptics()
    val rows = remember(state) { exerciseListRows(state?.exercises.orEmpty(), state?.clampedIndex ?: 0) }
    val rowsByID = remember(rows) { rows.associateBy { it.id } }

    var optionsID by nav::optionsID
    var nestedKey by nav::nestedKey

    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val reorder = remember(listState) { ReorderState<UUID>(listState, scope, onSwap = { haptics.light() }) }
    val displayed = reorder.order?.mapNotNull { rowsByID[it] } ?: rows
    val currentOnMove by rememberUpdatedState<(Int, Int) -> Unit> { from, to ->
        controller.send(WorkoutAction.MoveExercise(from, to))
    }

    // The sheet must not treat the drag as a swipe to dismiss it.
    LaunchedEffect(reorder.draggedKey) { onReorderingChange(reorder.draggedKey != null) }
    val maxEdge = with(LocalDensity.current) { 56.dp.toPx() }
    val maxSpeed = with(LocalDensity.current) { AutoScrollSpeed.toPx() }
    // While the finger is near an edge of the list the list scrolls on its own, by speed x time since the last frame (the same on
    // a 60 and a 120 Hz screen); otherwise this does nothing (and costs no frames).
    LaunchedEffect(reorder, maxEdge, maxSpeed) {
        snapshotFlow { reorder.autoScrollSpeed(maxEdge, maxSpeed) }.collectLatest { first ->
            var speed = first
            var last = withFrameNanos { it }
            while (speed != 0f && isActive) {
                val now = withFrameNanos { it }
                reorder.scrollBySteps(edgeScrollDistance(speed, now - last))
                last = now
                speed = reorder.autoScrollSpeed(maxEdge, maxSpeed)
            }
        }
    }

    Column(modifier.fillMaxSize()) {
        SheetTitleBar(title = "Exercises", trailing = SheetBarButton("Done", onClick = onDone))
        Text(
            "${rows.size} " + (if (rows.size == 1) "exercise" else "exercises") +
                " · Drag the handle to reorder. Superset exercises alternate their sets.",
            style = PulseFont.footnote,
            color = PulseTheme.colors.inkSecondary,
            modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 10.dp),
        )
        LazyColumn(
            state = listState,
            modifier = Modifier.weight(1f).fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 16.dp),
        ) {
            items(displayed, key = { it.id }) { row ->
                val isDragged = reorder.draggedKey == row.id
                ExerciseListRowView(
                    row = row,
                    count = rows.size,
                    isDragged = isDragged,
                    dragOffset = if (isDragged) reorder.dragOffset else 0f,
                    onOpen = {
                        controller.send(WorkoutAction.GoTo(row.index))
                        onDone()
                    },
                    onOptions = { optionsID = row.id.toString() },
                    onMoveBy = { delta ->
                        haptics.light()
                        controller.send(WorkoutAction.MoveExerciseBy(row.id, delta))
                    },
                    drag = RowDrag(
                        onStart = { fingerFromCentre ->
                            haptics.selection()
                            reorder.start(row.id, displayed.map { it.id }, fingerFromCentre)
                        },
                        onDrag = { reorder.drag(it) },
                        onEnd = { reorder.end(currentOnMove) },
                        onCancel = { reorder.cancel() },
                    ),
                    modifier = if (isDragged) Modifier else Modifier.animateItem(),
                )
            }
        }
        PulsePrimaryButton(
            onClick = { nestedKey = "add" },
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 8.dp),
        ) {
            Icon(Icons.Rounded.Add, contentDescription = null, tint = PulseTheme.colors.onGreen, modifier = Modifier.size(20.dp.scaledWithFont()))
            Spacer(Modifier.width(8.dp))
            Text("Add Exercise", style = PulseFont.headline, color = PulseTheme.colors.onGreen)
        }
    }

    optionsID?.let { id ->
        ExerciseOptionsDialog(
            controller = controller,
            exerciseID = UUID.fromString(id),
            onShowInfo = { exercise -> nestedKey = "info:${exercise.id}" },
            onShowRestSettings = { exerciseID -> nestedKey = "rest:$exerciseID" },
            onReplace = { exerciseID -> nestedKey = "replace:$exerciseID" },
            onDismiss = { optionsID = null },
        )
    }

    val key = nestedKey
    when {
        key == null -> Unit
        key == "add" -> ExercisePickerSheet(store, controller, PickerMode.Add) { nestedKey = null }
        key.startsWith("replace:") ->
            ExercisePickerSheet(store, controller, PickerMode.Replace(UUID.fromString(key.removePrefix("replace:")))) { nestedKey = null }
        key.startsWith("rest:") ->
            RestSettingsSheet(controller, UUID.fromString(key.removePrefix("rest:"))) { nestedKey = null }
        key.startsWith("info:") -> {
            val exerciseID = key.removePrefix("info:")
            val exercise = state?.exercises?.firstOrNull { it.exercise.id == exerciseID }?.exercise ?: store.exercise(exerciseID)
            if (exercise != null) FormInfoHost(exercise, store) { nestedKey = null } else nestedKey = null
        }
    }
}

/** How fast the list scrolls by itself with the finger at its edge: what 18 dp per frame is on a 60 Hz screen. */
private val AutoScrollSpeed = 1080.dp

/**
 * What the drag handle of a row reports: the finger went down [onStart] px below the vertical centre of the handle (which is
 * the centre of the row), and moves [onDrag] px vertically.
 */
private class RowDrag(val onStart: (Float) -> Unit, val onDrag: (Float) -> Unit, val onEnd: () -> Unit, val onCancel: () -> Unit)

/**
 * One row: thumbnail, name with "Superset A · 3 of 5 sets · Chest · Now", the options button and the drag handle. The whole
 * left part opens the exercise; screen readers get "Move up" / "Move down" actions on it.
 */
@Composable
private fun ExerciseListRowView(
    row: ExerciseListRow,
    count: Int,
    isDragged: Boolean,
    dragOffset: Float,
    onOpen: () -> Unit,
    onOptions: () -> Unit,
    onMoveBy: (Int) -> Unit,
    drag: RowDrag,
    modifier: Modifier = Modifier,
) {
    val colors = PulseTheme.colors
    val larger = isLargerFontScale()
    // The handle's gesture lives as long as the row: it must always call the latest callbacks (the order has changed since).
    val currentDrag by rememberUpdatedState(drag)
    // The vertical padding is part of the item, so neighbours swap by whole item sizes while dragging.
    Box(
        modifier
            .fillMaxWidth()
            .padding(vertical = 3.dp)
            .zIndex(if (isDragged) 1f else 0f)
            .graphicsLayer {
                translationY = dragOffset
                shadowElevation = if (isDragged) 12.dp.toPx() else 0f
                shape = RoundedCornerShape(12.dp)
                clip = false
                scaleX = if (isDragged) 1.02f else 1f
                scaleY = if (isDragged) 1.02f else 1f
            },
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .background(colors.card, RoundedCornerShape(12.dp))
                .padding(start = 10.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                Modifier
                    .weight(1f)
                    .pulseMinHeight(64.dp)
                    .semantics {
                        val actions = mutableListOf<CustomAccessibilityAction>()
                        if (row.index > 0) actions.add(CustomAccessibilityAction("Move up") { onMoveBy(-1); true })
                        if (row.index < count - 1) actions.add(CustomAccessibilityAction("Move down") { onMoveBy(1); true })
                        customActions = actions
                    }
                    .pulseClickable(onClickLabel = "Show this exercise in the workout", role = Role.Button, onClick = onOpen),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ExerciseMediaView(row.exercise.mediaKey, Modifier.size(44.dp), cornerRadius = 10.dp, animated = false)
                Column(Modifier.weight(1f).padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        row.exercise.name,
                        style = PulseFont.text(15.sp, FontWeight.SemiBold),
                        color = colors.ink,
                        maxLines = if (larger) 2 else 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        row.subtitle,
                        style = PulseFont.text(12.sp),
                        color = colors.inkSecondary,
                        maxLines = if (larger) 3 else 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            Box(
                Modifier
                    .size(48.dp)
                    .semantics { contentDescription = "Options for ${row.exercise.name}" }
                    .pulseClickable(role = Role.Button, onClick = onOptions),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.MoreVert, contentDescription = null, tint = colors.green, modifier = Modifier.size(24.dp))
            }
            // The handle only works with a finger; screen reader users reorder with the row's actions instead.
            Box(
                Modifier
                    .size(width = 44.dp, height = 48.dp)
                    .clearAndSetSemantics { testTag = "reorder-handle-${row.index}" }
                    .pointerInput(row.id) {
                        detectDragGestures(
                            onDragStart = { down -> currentDrag.onStart(down.y - size.height / 2f) },
                            onDrag = { change, amount ->
                                change.consume()
                                currentDrag.onDrag(amount.y)
                            },
                            onDragEnd = { currentDrag.onEnd() },
                            onDragCancel = { currentDrag.onCancel() },
                        )
                    },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.DragHandle, contentDescription = null, tint = colors.inkTertiary, modifier = Modifier.size(24.dp))
            }
        }
    }
}
