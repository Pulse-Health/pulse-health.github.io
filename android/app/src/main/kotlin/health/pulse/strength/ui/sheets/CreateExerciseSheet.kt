package health.pulse.strength.ui.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.Equipment
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.ui.components.rememberPulseHaptics
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight

/**
 * "New Exercise" form (Cancel / Save): name, primary muscle, equipment and what to track. Shows its own modal bottom sheet.
 *
 * Save builds the exercise with `Exercise.custom(...)` (an empty name becomes "Custom exercise"), hands it to [onCreate] and closes
 * the sheet. Persisting the exercise is the caller's job (the picker saves it with `StrengthStore.addCustomExercise`).
 */
@Composable
fun CreateExerciseSheet(initialName: String, onCreate: (Exercise) -> Unit, onDismiss: () -> Unit) {
    // The form state lives out here, in the screen's composition, not in the sheet's window: that is what survives a rotation.
    val form = rememberCreateFormState(initialName)
    PulseSheet(onDismiss = onDismiss, fullHeight = true) { dismiss ->
        CreateExerciseSheetContent(initialName = initialName, onCreate = onCreate, onClose = dismiss, form = form)
    }
}

/** The four inputs of the form and the "already saved" flag. */
@Stable
internal class CreateFormState(
    name: String,
    muscle: MuscleGroup = MuscleGroup.CHEST,
    equipment: Equipment = Equipment.BARBELL,
    tracking: TrackingKind = TrackingKind.WEIGHT_REPS,
    didSubmit: Boolean = false,
) {
    var name by mutableStateOf(name)
    var muscle by mutableStateOf(muscle)
    var equipment by mutableStateOf(equipment)
    var tracking by mutableStateOf(tracking)

    /** Set by the first tap on Save, so a second tap while the sheet slides away creates no second exercise. */
    var didSubmit by mutableStateOf(didSubmit)

    companion object {
        val Saver = listSaver<CreateFormState, Any>(
            save = { listOf(it.name, it.muscle.name, it.equipment.name, it.tracking.name, it.didSubmit) },
            restore = {
                CreateFormState(
                    it[0] as String, MuscleGroup.valueOf(it[1] as String), Equipment.valueOf(it[2] as String),
                    TrackingKind.valueOf(it[3] as String), it[4] as Boolean,
                )
            },
        )
    }
}

@Composable
internal fun rememberCreateFormState(initialName: String): CreateFormState =
    rememberSaveable(saver = CreateFormState.Saver) { CreateFormState(initialName) }

/** Everything inside the create sheet's window. [onClose] closes the sheet (Cancel, and after Save). */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun CreateExerciseSheetContent(
    initialName: String,
    onCreate: (Exercise) -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
    form: CreateFormState = rememberCreateFormState(initialName),
) {
    var name by form::name
    var muscle by form::muscle
    var equipment by form::equipment
    var tracking by form::tracking
    var didSubmit by form::didSubmit
    val focusManager = LocalFocusManager.current
    val haptics = rememberPulseHaptics()

    fun save() {
        if (didSubmit) return
        didSubmit = true
        focusManager.clearFocus()
        val exercise = Exercise.custom(name = name, muscle = muscle, equipment = equipment, tracking = tracking)
        haptics.success()
        onCreate(exercise)
        onClose()
    }

    Column(modifier.fillMaxWidth()) {
        SheetTitleBar(
            title = "New Exercise",
            leading = SheetBarButton("Cancel", semibold = false, onClick = onClose),
            trailing = SheetBarButton("Save", onClick = ::save),
        )
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                SheetSectionLabel("Name")
                NameField(name = name, onChange = { name = it }, onDone = { focusManager.clearFocus() })
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SheetSectionLabel("Primary muscle")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (group in MuscleGroup.entries) FormChip(group.title, muscle == group) { muscle = group }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SheetSectionLabel("Equipment")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (item in Equipment.entries) FormChip(item.title, equipment == item) { equipment = item }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SheetSectionLabel("Track")
                SegmentedOptions(
                    options = TrackingKind.entries.map { SegmentOption(it, it.title) },
                    selection = tracking,
                    onSelect = { tracking = it },
                    groupLabel = "Track",
                    vertical = isAccessibilityFontScale(),
                    textStyle = PulseFont.text(14.sp),
                )
            }
            Text(
                "Custom exercises are saved to your library and can be added to any workout.",
                style = PulseFont.footnote,
                color = PulseTheme.colors.inkSecondary,
                modifier = Modifier.padding(horizontal = 4.dp),
            )
        }
    }
}

/** The name input: 48 dp tall, white, 12 dp radius. */
@Composable
private fun NameField(name: String, onChange: (String) -> Unit, onDone: () -> Unit) {
    val colors = PulseTheme.colors
    Box(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .background(colors.card, RoundedCornerShape(12.dp))
            .padding(horizontal = 16.dp, vertical = 8.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        BasicTextField(
            value = name,
            onValueChange = onChange,
            singleLine = true,
            textStyle = PulseFont.body.copy(color = colors.ink),
            cursorBrush = SolidColor(colors.green),
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { onDone() }),
            modifier = Modifier
                .fillMaxWidth()
                .semantics { contentDescription = "Name" },
            decorationBox = { inner ->
                Box(contentAlignment = Alignment.CenterStart) {
                    if (name.isEmpty()) Text("e.g. Landmine press", style = PulseFont.body, color = colors.inkSecondary)
                    inner()
                }
            },
        )
    }
}

/** A muscle / equipment chip of the form: 40 dp tall with 16 dp side padding, blue tint when selected. */
@Composable
private fun FormChip(title: String, isSelected: Boolean, onClick: () -> Unit) {
    val colors = PulseTheme.colors
    Box(
        Modifier
            .pulseMinHeight(40.dp)
            .background(if (isSelected) colors.blueTint else colors.chipFill, CircleShape)
            .semantics { selected = isSelected }
            .pulseClickable(role = Role.RadioButton, onClick = onClick)
            .padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            style = PulseFont.text(15.sp, if (isSelected) FontWeight.SemiBold else FontWeight.Medium),
            color = if (isSelected) colors.blueText else colors.ink.copy(alpha = 0.75f),
        )
    }
}
