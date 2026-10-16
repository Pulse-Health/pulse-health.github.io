package health.pulse.strength.ui.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Cancel
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.Equipment
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.ui.PickerMode
import health.pulse.strength.ui.components.ExerciseMediaView
import health.pulse.strength.ui.components.rememberPulseHaptics
import health.pulse.strength.ui.theme.PulseChip
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight

/**
 * "Add Exercise" / "Replace Exercise": search field, muscle and equipment filter chips, the filtered library with selection
 * circles (several in add mode, exactly one in replace mode), a "Create ..." row that opens [CreateExerciseSheet] and the bottom
 * action ("Select exercises", "Add 3 exercises", "Replace with <name>"). Shows its own modal bottom sheet.
 *
 * Confirming sends `AddExercises` / `ReplaceExercise` to the controller and closes the sheet.
 */
@Composable
fun ExercisePickerSheet(store: StrengthStore, controller: WorkoutController, mode: PickerMode, onDismiss: () -> Unit) {
    // The form state lives out here, in the screen's composition, not in the sheet's window: that is what survives a rotation.
    val form = rememberPickerFormState()
    PulseSheet(onDismiss = onDismiss, fullHeight = true) { dismiss ->
        ExercisePickerSheetContent(store = store, controller = controller, mode = mode, onClose = dismiss, form = form)
    }
}

/** The picker's inputs: search text, filters, the selected exercise ids (in selection order) and what is open. */
@Stable
internal class PickerFormState(
    query: String = "",
    muscle: MuscleGroup? = null,
    equipment: Equipment? = null,
    selection: List<String> = emptyList(),
    showsCreateSheet: Boolean = false,
    didSubmit: Boolean = false,
) {
    var query by mutableStateOf(query)
    var muscle by mutableStateOf(muscle)
    var equipment by mutableStateOf(equipment)
    var selection by mutableStateOf(selection)
    var showsCreateSheet by mutableStateOf(showsCreateSheet)

    /** Set by the first tap on the bottom action, so a second tap while the sheet slides away adds nothing again. */
    var didSubmit by mutableStateOf(didSubmit)

    companion object {
        val Saver = listSaver<PickerFormState, Any?>(
            save = {
                listOf(it.query, it.muscle?.name, it.equipment?.name, ArrayList(it.selection), it.showsCreateSheet, it.didSubmit)
            },
            restore = {
                @Suppress("UNCHECKED_CAST")
                PickerFormState(
                    it[0] as String, (it[1] as String?)?.let(MuscleGroup::valueOf), (it[2] as String?)?.let(Equipment::valueOf),
                    it[3] as List<String>, it[4] as Boolean, it[5] as Boolean,
                )
            },
        )
    }
}

@Composable
internal fun rememberPickerFormState(): PickerFormState = rememberSaveable(saver = PickerFormState.Saver) { PickerFormState() }

/** The equipment chips of the design (no "Other"). */
private val EquipmentChoices: List<Equipment> =
    listOf(Equipment.BARBELL, Equipment.DUMBBELL, Equipment.CABLE, Equipment.MACHINE, Equipment.BODYWEIGHT)

/** One library row of the picker. */
internal class ExercisePickerRow(
    val exercise: Exercise,
    /** "Chest · Barbell", plus " · Already in workout" for an exercise that cannot be added twice. */
    val subtitle: String,
    val isSelected: Boolean,
    /** Add mode only: the exercise is already part of the workout (row dimmed and not selectable). */
    val isUsed: Boolean,
)

/** Everything inside the picker sheet's window. [onClose] closes the sheet (Cancel, and after the action was applied). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ExercisePickerSheetContent(
    store: StrengthStore,
    controller: WorkoutController,
    mode: PickerMode,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
    form: PickerFormState = rememberPickerFormState(),
) {
    val data by store.data.collectAsState()
    val workout by controller.state.collectAsState()
    val haptics = rememberPulseHaptics()
    val focusManager = LocalFocusManager.current

    var query by form::query
    var muscle by form::muscle
    var equipment by form::equipment
    var selection by form::selection
    var showsCreateSheet by form::showsCreateSheet
    var didSubmit by form::didSubmit

    val library = remember(data) { store.exercises }
    val matches = remember(library, query, muscle, equipment) { ExerciseLibrary.filter(library, query, muscle, equipment) }
    val inWorkout = remember(workout, mode) {
        if (mode is PickerMode.Add) workout?.exercises?.mapTo(HashSet()) { it.exercise.id } ?: emptySet<String>() else emptySet()
    }
    val rows = remember(matches, inWorkout, selection) {
        matches.map { exercise ->
            val used = exercise.id in inWorkout
            ExercisePickerRow(
                exercise = exercise,
                subtitle = exercise.muscle.title + " · " + exercise.equipment.title + if (used) " · Already in workout" else "",
                isSelected = exercise.id in selection,
                isUsed = used,
            )
        }
    }
    val trimmedQuery = query.trim()
    val createTitle = if (trimmedQuery.isEmpty()) "Create custom exercise" else "Create “$trimmedQuery”"

    fun chosenExercises(): List<Exercise> = selection.mapNotNull { store.exercise(it) }

    val actionTitle = when {
        selection.isEmpty() -> "Select exercises"
        mode is PickerMode.Add -> "Add ${selection.size} " + if (selection.size == 1) "exercise" else "exercises"
        else -> "Replace with " + (chosenExercises().firstOrNull()?.name ?: "exercise")
    }

    fun toggle(row: ExercisePickerRow) {
        if (row.isUsed) return
        haptics.light()
        val id = row.exercise.id
        selection = when (mode) {
            is PickerMode.Replace -> listOf(id)
            PickerMode.Add -> if (id in selection) selection - id else selection + id
        }
    }

    /** A custom exercise came back from the create form: save it to the library, select it and clear the search. */
    fun handleCreated(exercise: Exercise) {
        store.addCustomExercise(exercise)
        selection = when (mode) {
            is PickerMode.Replace -> listOf(exercise.id)
            PickerMode.Add -> if (exercise.id in selection) selection else selection + exercise.id
        }
        query = ""
    }

    fun confirm() {
        if (didSubmit) return
        val chosen = chosenExercises()
        if (chosen.isEmpty()) return
        didSubmit = true
        when (mode) {
            PickerMode.Add -> controller.send(WorkoutAction.AddExercises(chosen))
            is PickerMode.Replace -> controller.send(WorkoutAction.ReplaceExercise(mode.exerciseID, chosen.first()))
        }
        haptics.success()
        onClose()
    }

    val listState = rememberLazyListState()
    LaunchedEffect(listState.isScrollInProgress) { if (listState.isScrollInProgress) focusManager.clearFocus() }

    val filters: @Composable () -> Unit = {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                PulseChip("All", isSelected = muscle == null, onClick = { muscle = null })
                for (group in MuscleGroup.entries) PulseChip(group.title, isSelected = muscle == group, onClick = { muscle = group })
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                PulseChip("Any", isSelected = equipment == null, onClick = { equipment = null })
                for (item in EquipmentChoices) PulseChip(item.title, isSelected = equipment == item, onClick = { equipment = item })
            }
        }
    }
    val countLabel: @Composable () -> Unit = {
        Text(
            "${rows.size} " + if (rows.size == 1) "exercise" else "exercises",
            style = PulseFont.text(12.sp),
            color = PulseTheme.colors.inkSecondary,
            modifier = Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 6.dp),
        )
    }

    Box(modifier.fillMaxSize()) {
        // Tall windows keep the search field and the filters in view; on a short one (small phone, landscape, large font) they
        // scroll away with the list, which then gets the room. The decision uses the screen, not the space left above the keyboard:
        // opening the keyboard must not rearrange the screen under the finger that just tapped the search field.
        val density = LocalDensity.current
        val windowHeight = with(density) { LocalWindowInfo.current.containerSize.height.toDp() }
        val pinHeader = windowHeight / density.fontScale >= 700.dp
        Column(Modifier.fillMaxSize()) {
            SheetTitleBar(
                title = if (mode is PickerMode.Add) "Add Exercise" else "Replace Exercise",
                leading = SheetBarButton("Cancel", semibold = false, onClick = onClose),
            )
            if (pinHeader) {
                SearchField(query, { query = it }, { focusManager.clearFocus() }, Modifier.padding(horizontal = 16.dp))
                Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 10.dp)) {
                    filters()
                    countLabel()
                }
            }
            LazyColumn(
                state = listState,
                modifier = Modifier.weight(1f).fillMaxWidth(),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 8.dp),
            ) {
                if (!pinHeader) {
                    item(key = "search") { SearchField(query, { query = it }, { focusManager.clearFocus() }) }
                    item(key = "filters") { Box(Modifier.padding(top = 10.dp)) { filters() } }
                    item(key = "count") { countLabel() }
                }
                item(key = "create") {
                    CreateRow(
                        title = createTitle,
                        shape = if (rows.isEmpty()) RoundedCornerShape(12.dp) else RoundedCornerShape(topStart = 12.dp, topEnd = 12.dp),
                        onClick = {
                            focusManager.clearFocus()
                            showsCreateSheet = true
                        },
                    )
                }
                items(rows, key = { it.exercise.id }) { row ->
                    val isLast = row === rows.last()
                    ExerciseRow(
                        row = row,
                        mode = mode,
                        shape = if (isLast) RoundedCornerShape(bottomStart = 12.dp, bottomEnd = 12.dp) else RoundedCornerShape(0.dp),
                        onClick = { toggle(row) },
                    )
                }
                if (rows.isEmpty()) {
                    item(key = "empty") {
                        Text(
                            "No exercise matches. Create it as a custom exercise.",
                            style = PulseFont.subhead,
                            color = PulseTheme.colors.inkSecondary,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 28.dp),
                        )
                    }
                }
            }
            ActionBar(title = actionTitle, enabled = selection.isNotEmpty() && !didSubmit, active = selection.isNotEmpty(), onClick = ::confirm)
        }
    }

    if (showsCreateSheet) {
        CreateExerciseSheet(
            initialName = trimmedQuery,
            onCreate = ::handleCreated,
            onDismiss = { showsCreateSheet = false },
        )
    }
}

// region Pieces

/** The search input: a grey 10 dp rounded field with a magnifier and a clear button. */
@Composable
private fun SearchField(query: String, onChange: (String) -> Unit, onSearch: () -> Unit, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .background(colors.chipFill, RoundedCornerShape(10.dp))
            .padding(start = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.Search, contentDescription = null, tint = colors.inkSecondary, modifier = Modifier.size(20.dp.scaledWithFont()))
        Spacer(Modifier.width(8.dp))
        BasicTextField(
            value = query,
            onValueChange = onChange,
            singleLine = true,
            textStyle = PulseFont.body.copy(color = colors.ink),
            cursorBrush = SolidColor(colors.green),
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                autoCorrectEnabled = false,
                imeAction = ImeAction.Search,
            ),
            keyboardActions = KeyboardActions(onSearch = { onSearch() }),
            modifier = Modifier
                .weight(1f)
                .padding(vertical = 8.dp)
                .semantics { contentDescription = "Search exercises" },
            decorationBox = { inner ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (query.isEmpty()) Text("Search", style = PulseFont.body, color = colors.inkSecondary)
                    inner()
                }
            },
        )
        if (query.isNotEmpty()) {
            Box(
                Modifier
                    .size(width = 48.dp, height = 48.dp)
                    .semantics { contentDescription = "Clear search" }
                    .pulseClickable(role = Role.Button, onClick = { onChange("") }),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.Cancel, contentDescription = null, tint = colors.inkSecondary, modifier = Modifier.size(20.dp))
            }
        } else {
            Spacer(Modifier.width(12.dp))
        }
    }
}

/** The green "Create ..." row at the top of the list. */
@Composable
private fun CreateRow(title: String, shape: Shape, onClick: () -> Unit) {
    val colors = PulseTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .background(colors.card, shape)
            .pulseMinHeight(56.dp)
            .pulseClickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(24.dp.scaledWithFont()).background(colors.green, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Rounded.Add, contentDescription = null, tint = colors.onGreen, modifier = Modifier.size(16.dp))
        }
        Text(
            title,
            style = PulseFont.headline,
            color = colors.greenText,
            maxLines = if (isLargerFontScale()) 4 else 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
    }
}

/** One library row: selection circle, name and "Chest · Barbell", and the form thumbnail. */
@Composable
private fun ExerciseRow(row: ExercisePickerRow, mode: PickerMode, shape: Shape, onClick: () -> Unit) {
    val colors = PulseTheme.colors
    val isAdd = mode is PickerMode.Add
    val lines = if (isLargerFontScale()) 3 else 1
    Row(
        Modifier
            .fillMaxWidth()
            .background(colors.card, shape)
            .drawBehind { drawRect(colors.separator, size = Size(size.width, 0.5.dp.toPx())) }
            .pulseMinHeight(64.dp)
            .alpha(if (row.isUsed) 0.45f else 1f)
            .semantics {
                if (isAdd) toggleableState = ToggleableState(row.isSelected) else selected = row.isSelected
            }
            .pulseClickable(enabled = !row.isUsed, role = if (isAdd) Role.Checkbox else Role.RadioButton, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SelectionMark(row.isSelected)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(row.exercise.name, style = PulseFont.body, color = colors.ink, maxLines = lines, overflow = TextOverflow.Ellipsis)
            Text(row.subtitle, style = PulseFont.text(12.sp), color = colors.inkSecondary, maxLines = lines, overflow = TextOverflow.Ellipsis)
        }
        ExerciseMediaView(row.exercise.mediaKey, Modifier.size(44.dp), cornerRadius = 10.dp, animated = false)
    }
}

/** A 24 dp circle: grey ring when not selected, green with a check when selected. */
@Composable
private fun SelectionMark(isSelected: Boolean) {
    val colors = PulseTheme.colors
    Box(
        Modifier
            .size(24.dp.scaledWithFont())
            .then(
                if (isSelected) {
                    Modifier.background(colors.green, CircleShape)
                } else {
                    Modifier.border(2.dp, colors.inkTertiary, CircleShape)
                },
            ),
        contentAlignment = Alignment.Center,
    ) {
        if (isSelected) Icon(Icons.Rounded.Check, contentDescription = null, tint = colors.onGreen, modifier = Modifier.size(16.dp))
    }
}

/** The bottom action: solid green once something is selected, grey before. */
@Composable
private fun ActionBar(title: String, enabled: Boolean, active: Boolean, onClick: () -> Unit) {
    val colors = PulseTheme.colors
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 8.dp)
            .pulseMinHeight(52.dp)
            .background(if (active) colors.green else colors.progressTrack, RoundedCornerShape(14.dp))
            .pulseClickable(enabled = enabled, role = Role.Button, pressedAlpha = 0.8f, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            style = PulseFont.headline,
            color = if (active) colors.onGreen else colors.inkSecondary,
            textAlign = TextAlign.Center,
            maxLines = if (isLargerFontScale()) 3 else 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

// endregion
