package health.pulse.strength.ui.sheets

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Backspace
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Remove
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.LoggedSet
import health.pulse.strength.core.NumberText
import health.pulse.strength.core.PlateCalculator
import health.pulse.strength.core.PreviousSet
import health.pulse.strength.core.SetRef
import health.pulse.strength.core.TrackingKind
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.core.WorkoutExercise
import health.pulse.strength.core.WorkoutReducer
import health.pulse.strength.core.WorkoutState
import health.pulse.strength.ui.KeypadField
import health.pulse.strength.ui.components.rememberPulseHaptics
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulsePrimaryButton
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight
import kotlin.math.max
import kotlin.math.min

/**
 * The weight / reps keypad of one set. Shows its own modal bottom sheet, as tall as its content (it scrolls on a short window and
 * switches to two columns in landscape).
 *
 * Layout, top to bottom: title bar ("Set 4 · Barbell bench press" + Done), the two value cards (the edited one highlighted), the
 * -/+ steppers around the "Use last" button, the plate chips (barbell exercises only), the 3 x 4 keypad and the primary button
 * ("Next: Reps" / "Log Set" / "Done").
 *
 * The text buffer lives in the sheet. After every key, stepper tap or "Use last" the parsed value is dispatched
 * (`SetWeight` / `SetReps`), so the workout screen, the notification and the watch always show what is typed. The set is always
 * read live from the controller. A fresh buffer (just opened, just stepped, just switched field) is replaced by the first digit.
 */
@Composable
fun KeypadSheet(controller: WorkoutController, ref: SetRef, initialField: KeypadField, onDismiss: () -> Unit) {
    // The edit state lives out here, in the screen's composition, not in the sheet's window: that is what survives a rotation.
    val edit = rememberKeypadEditState(controller, ref, initialField)
    PulseSheet(onDismiss = onDismiss) { dismiss ->
        KeypadSheetContent(controller = controller, ref = ref, initialField = initialField, onDone = dismiss, edit = edit)
    }
}

/** What the keypad has typed so far: the edited field, its text and whether the next digit replaces the whole text. */
@Stable
internal class KeypadEditState(field: KeypadField, buffer: String, isFresh: Boolean = true) {
    var field by mutableStateOf(field)
    var buffer by mutableStateOf(buffer)
    var isFresh by mutableStateOf(isFresh)

    companion object {
        val Saver = listSaver<KeypadEditState, Any>(
            save = { listOf(it.field.name, it.buffer, it.isFresh) },
            restore = { KeypadEditState(KeypadField.valueOf(it[0] as String), it[1] as String, it[2] as Boolean) },
        )
    }
}

/** The starting state: the requested field (the reps of an exercise without weight) with the set's current value. */
@Composable
internal fun rememberKeypadEditState(controller: WorkoutController, ref: SetRef, initialField: KeypadField): KeypadEditState =
    rememberSaveable(ref, initialField, saver = KeypadEditState.Saver) {
        val first = KeypadTarget.lookup(ref, controller.state.value)
        val field = if (first != null && !first.exercise.exercise.tracksWeight) KeypadField.REPS else initialField
        KeypadEditState(field, KeypadLogic.text(field, first?.set))
    }

/** Everything inside the keypad sheet's window. [onDone] closes the sheet (Done, and after "Log Set" / "Done"). */
@Composable
internal fun KeypadSheetContent(
    controller: WorkoutController,
    ref: SetRef,
    initialField: KeypadField,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
    edit: KeypadEditState = rememberKeypadEditState(controller, ref, initialField),
) {
    val workout by controller.state.collectAsState()
    val target = remember(workout, ref) { KeypadTarget.lookup(ref, workout) }
    val haptics = rememberPulseHaptics()

    // The value being edited, its text and whether the next digit replaces the whole text.
    var field by edit::field
    var buffer by edit::buffer
    var isFresh by edit::isFresh

    // The set was removed elsewhere (the notification, another surface): nothing to edit any more.
    LaunchedEffect(target == null) { if (target == null) onDone() }

    fun commit(forField: KeypadField, text: String) {
        when (forField) {
            KeypadField.WEIGHT ->
                controller.send(WorkoutAction.SetWeight(ref.exerciseID, ref.setID, KeypadLogic.parseNumber(text)))
            KeypadField.REPS ->
                controller.send(WorkoutAction.SetReps(ref.exerciseID, ref.setID, KeypadLogic.reps(text)))
        }
    }

    Column(modifier.fillMaxWidth()) {
        SheetTitleBar(
            title = target?.title ?: "Edit set",
            trailing = SheetBarButton("Done", onClick = onDone),
        )
        if (target != null) {
            val exercise = target.exercise.exercise
            val previous = KeypadLogic.previousSet(exercise, target.index)
            val actions = KeypadActions(
                onSelectField = { which ->
                    if (which != KeypadField.WEIGHT || exercise.tracksWeight) {
                        haptics.selection()
                        field = which
                        buffer = KeypadLogic.text(which, target.set)
                        isFresh = true
                    }
                },
                onKey = { key ->
                    haptics.light()
                    val next = KeypadLogic.applying(key, buffer, isFresh, field)
                    if (next != null) {
                        buffer = next
                        isFresh = false
                        commit(field, next)
                    }
                },
                onStep = { direction ->
                    haptics.light()
                    val next = KeypadLogic.stepped(direction, field, buffer, exercise)
                    buffer = next
                    isFresh = true
                    commit(field, next)
                },
                onUseLast = {
                    if (previous != null) {
                        haptics.light()
                        val next = KeypadLogic.usingLast(field, previous)
                        buffer = next
                        isFresh = true
                        commit(field, next)
                    }
                },
                onPrimary = {
                    if (field == KeypadField.WEIGHT && exercise.tracksWeight) {
                        haptics.selection()
                        field = KeypadField.REPS
                        buffer = target.set.reps.toString()
                        isFresh = true
                    } else {
                        if (target.set.isDone) {
                            haptics.selection()
                        } else {
                            controller.send(WorkoutAction.LogSet(ref.exerciseID, ref.setID))
                            haptics.success()
                        }
                        onDone()
                    }
                },
            )
            KeypadPanel(
                target = target,
                field = field,
                buffer = buffer,
                previous = previous,
                actions = actions,
                modifier = Modifier.weight(1f, fill = false),
            )
        }
    }
}

/** The set being edited, with its exercise and position. */
internal class KeypadTarget(val exercise: WorkoutExercise, val set: LoggedSet, val index: Int) {
    val title: String get() = "Set ${index + 1} · ${exercise.exercise.name}"

    companion object {
        fun lookup(ref: SetRef, state: WorkoutState?): KeypadTarget? {
            val exercise = state?.exercises?.firstOrNull { it.id == ref.exerciseID } ?: return null
            val index = exercise.sets.indexOfFirst { it.id == ref.setID }
            if (index < 0) return null
            return KeypadTarget(exercise, exercise.sets[index], index)
        }
    }
}

/** What the panel can do; every handler dispatches to the controller. */
private class KeypadActions(
    val onSelectField: (KeypadField) -> Unit,
    val onKey: (KeypadKey) -> Unit,
    val onStep: (Int) -> Unit,
    val onUseLast: () -> Unit,
    val onPrimary: () -> Unit,
)

// region Logic

internal sealed interface KeypadKey {
    data class Digit(val digit: String) : KeypadKey
    data object Decimal : KeypadKey
    data object Delete : KeypadKey

    val accessibilityName: String
        get() = when (this) {
            is Digit -> digit
            Decimal -> "Decimal point"
            Delete -> "Delete"
        }

    companion object {
        val rows: List<List<KeypadKey>> = listOf(
            listOf(Digit("1"), Digit("2"), Digit("3")),
            listOf(Digit("4"), Digit("5"), Digit("6")),
            listOf(Digit("7"), Digit("8"), Digit("9")),
            listOf(Decimal, Digit("0"), Delete),
        )
    }
}

internal class KeypadPlateInfo(val plates: List<Double>, val note: String)

/** The keypad's rules, free of any UI (so they can be tested directly). */
internal object KeypadLogic {
    /** The text a field starts with: the set's current value. */
    fun text(field: KeypadField, set: LoggedSet?): String = when {
        set == null -> "0"
        field == KeypadField.WEIGHT -> NumberText.kg(set.weightKg)
        else -> set.reps.toString()
    }

    /**
     * The buffer after a key press, or null when the key is ignored (second decimal point, decimal point on reps, more than 6
     * characters, a third decimal of a weight, reps above 999). The last two keep the card equal to the stored value: the reducer
     * rounds a weight to 0.01 and clamps reps to 0...999.
     */
    fun applying(key: KeypadKey, buffer: String, isFresh: Boolean, field: KeypadField): String? = when (key) {
        KeypadKey.Delete -> if (buffer.length > 1) buffer.dropLast(1) else "0"
        KeypadKey.Decimal -> when {
            field == KeypadField.REPS -> null
            isFresh -> "0."
            buffer.contains('.') -> null
            else -> "$buffer."
        }
        is KeypadKey.Digit -> {
            val next = if (isFresh || buffer == "0") key.digit else buffer + key.digit
            when {
                next.length > 6 -> null
                field == KeypadField.REPS -> if ((next.toIntOrNull() ?: 0) > 999) null else next
                else -> {
                    val dot = next.indexOf('.')
                    if (dot >= 0 && next.length - dot - 1 > 2) null else next
                }
            }
        }
    }

    /** "82.5" gives 82.5, "82." gives 82, "" gives 0, anything else gives 0. Never negative, never NaN. */
    fun parseNumber(text: String): Double {
        var cleaned = text.trim()
        if (cleaned.endsWith(".")) cleaned = cleaned.dropLast(1)
        if (cleaned.isEmpty() || cleaned.any { !it.isDigit() && it != '.' }) return 0.0
        val value = cleaned.toDoubleOrNull() ?: return 0.0
        return if (value.isFinite() && value >= 0) value else 0.0
    }

    /** The reps a buffer stands for: rounded, at most 999. */
    fun reps(text: String): Int = min(999.0, parseNumber(text).roundHalfAwayFromZero()).toInt()

    /** The buffer after a stepper tap: one step of the exercise in [direction] (-1 / +1). */
    fun stepped(direction: Int, field: KeypadField, buffer: String, exercise: Exercise): String {
        val next = when (field) {
            KeypadField.WEIGHT ->
                min(WorkoutReducer.maximumWeightKg, max(0.0, parseNumber(buffer) + direction * exercise.weightStepKg))
            KeypadField.REPS ->
                min(999.0, max(0.0, (parseNumber(buffer) + direction * exercise.repsStep).roundHalfAwayFromZero()))
        }
        return NumberText.kg(next)
    }

    /** The same set of the last session; the last one when this session has more sets. */
    fun previousSet(exercise: Exercise, setIndex: Int): PreviousSet? {
        val list = exercise.previousSets
        if (list.isEmpty()) return null
        return list[min(setIndex, list.size - 1)]
    }

    fun usingLast(field: KeypadField, previous: PreviousSet): String = when (field) {
        KeypadField.WEIGHT -> NumberText.kg(previous.weightKg)
        KeypadField.REPS -> min(999, max(0, previous.reps)).toString()
    }

    fun useLastText(field: KeypadField, exercise: Exercise, previous: PreviousSet?): String {
        if (previous == null) return "No previous session · ±" + stepText(field, exercise)
        return when (field) {
            KeypadField.WEIGHT -> "Use last: ${NumberText.kg(previous.weightKg)} kg"
            KeypadField.REPS -> "Use last: ${previous.reps}" + if (exercise.tracking == TrackingKind.DURATION) " s" else " reps"
        }
    }

    /** The size of one stepper tap for the edited field. */
    fun stepText(field: KeypadField, exercise: Exercise): String = when (field) {
        KeypadField.WEIGHT -> NumberText.kg(exercise.weightStepKg)
        KeypadField.REPS -> exercise.repsStep.toString()
    }

    /** Plates for one side of the bar, and the note shown next to them. */
    fun plateInfo(weightKg: Double, barKg: Double): KeypadPlateInfo {
        // `plan` gives nothing for a total below the bar, and also for one above the heaviest it plans for (100,000 kg), which the
        // keypad can still produce.
        val plan = PlateCalculator.plan(weightKg, barKg)
            ?: return KeypadPlateInfo(emptyList(), if (weightKg < barKg) "Below the bar weight" else "Too many plates to show")
        if (plan.perSide.size > 24) return KeypadPlateInfo(emptyList(), "Too many plates to show")
        var note = ""
        if (plan.perSide.isEmpty()) note = "Bar only"
        if (plan.leftoverKg > 0.01) note = "+ ${NumberText.kg(plan.leftoverKg)} kg left over"
        return KeypadPlateInfo(plan.perSide, note)
    }

    /** "20 kilogram bar. 20 + 10 + 2.5 per side" for a screen reader. */
    fun plateSpeech(info: KeypadPlateInfo, barKg: Double): String {
        val bar = NumberText.kg(barKg) + " kilogram bar. "
        if (info.plates.isEmpty()) return bar + info.note
        val list = info.plates.joinToString(" + ") { NumberText.kg(it) }
        val tail = if (info.note.isEmpty()) "" else ", " + info.note
        return "$bar$list per side$tail"
    }

    fun primaryTitle(field: KeypadField, exercise: Exercise, set: LoggedSet): String {
        if (field == KeypadField.WEIGHT && exercise.tracksWeight) return "Next: Reps"
        return if (set.isDone) "Done" else "Log Set"
    }

    private fun Double.roundHalfAwayFromZero(): Double = if (this < 0) -kotlin.math.floor(-this + 0.5) else kotlin.math.floor(this + 0.5)
}

// endregion

// region Panel

/**
 * Everything under the title bar. It scrolls when the window is shorter than the panel; in landscape (wide and short) the keypad
 * moves next to the other controls so the whole sheet stays in view.
 */
@Composable
private fun KeypadPanel(
    target: KeypadTarget,
    field: KeypadField,
    buffer: String,
    previous: PreviousSet?,
    actions: KeypadActions,
    modifier: Modifier = Modifier,
) {
    val exercise = target.exercise.exercise
    BoxWithConstraints(modifier) {
        val compact = maxWidth >= 520.dp && maxHeight < 440.dp
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (compact) {
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        KeypadValueCards(target, field, buffer, actions)
                        KeypadStepperRow(exercise, field, previous, actions)
                        if (exercise.supportsPlates) KeypadPlateRow(exercise.barKg, target.set.weightKg)
                        KeypadPrimaryButton(KeypadLogic.primaryTitle(field, exercise, target.set), actions.onPrimary)
                    }
                    KeypadGrid(field, actions.onKey, Modifier.weight(1f))
                }
            } else {
                KeypadValueCards(target, field, buffer, actions)
                KeypadStepperRow(exercise, field, previous, actions)
                if (exercise.supportsPlates) KeypadPlateRow(exercise.barKg, target.set.weightKg)
                KeypadGrid(field, actions.onKey)
                KeypadPrimaryButton(KeypadLogic.primaryTitle(field, exercise, target.set), actions.onPrimary)
            }
        }
    }
}

@Composable
private fun KeypadPrimaryButton(title: String, onClick: () -> Unit) {
    PulsePrimaryButton(text = title, onClick = onClick)
}

// endregion

// region Value cards

private fun repsLabel(exercise: Exercise): String = if (exercise.tracking == TrackingKind.DURATION) "SECONDS" else "REPS"

private fun repsNoun(exercise: Exercise): String = if (exercise.tracking == TrackingKind.DURATION) "seconds" else "reps"

/** What a card shows: the live buffer for the edited field, the set's value for the other one. */
private fun cardText(which: KeypadField, field: KeypadField, buffer: String, target: KeypadTarget): String {
    if (which == field) return buffer
    return when (which) {
        KeypadField.WEIGHT -> when (target.exercise.exercise.tracking) {
            TrackingKind.WEIGHT_REPS -> NumberText.kg(target.set.weightKg)
            TrackingKind.REPS_ONLY -> "BW"
            TrackingKind.DURATION -> "–"
        }
        KeypadField.REPS -> target.set.reps.toString()
    }
}

private fun spokenValue(which: KeypadField, text: String, exercise: Exercise): String = when (which) {
    KeypadField.WEIGHT -> when (exercise.tracking) {
        TrackingKind.WEIGHT_REPS -> "$text kilograms"
        TrackingKind.REPS_ONLY -> "Bodyweight"
        TrackingKind.DURATION -> "Not used"
    }
    KeypadField.REPS -> "$text ${repsNoun(exercise)}"
}

@Composable
private fun KeypadValueCards(target: KeypadTarget, field: KeypadField, buffer: String, actions: KeypadActions) {
    val exercise = target.exercise.exercise
    val weightText = cardText(KeypadField.WEIGHT, field, buffer, target)
    val repsText = cardText(KeypadField.REPS, field, buffer, target)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        KeypadValueCard(
            label = "KG",
            text = weightText,
            isSelected = field == KeypadField.WEIGHT,
            isEnabled = exercise.tracksWeight,
            accessibilityName = "Weight",
            spokenValue = spokenValue(KeypadField.WEIGHT, weightText, exercise),
            onClick = { actions.onSelectField(KeypadField.WEIGHT) },
            modifier = Modifier.weight(1f),
        )
        KeypadValueCard(
            label = repsLabel(exercise),
            text = repsText,
            isSelected = field == KeypadField.REPS,
            isEnabled = true,
            accessibilityName = repsNoun(exercise).replaceFirstChar { it.uppercase() },
            spokenValue = spokenValue(KeypadField.REPS, repsText, exercise),
            onClick = { actions.onSelectField(KeypadField.REPS) },
            modifier = Modifier.weight(1f),
        )
    }
}

/** "KG 82.5" / "REPS 6": 14 dp radius, a green 2 dp ring and a green tint while it is the edited value. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun KeypadValueCard(
    label: String,
    text: String,
    isSelected: Boolean,
    isEnabled: Boolean,
    accessibilityName: String,
    spokenValue: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = PulseTheme.colors
    val shape = RoundedCornerShape(14.dp)
    Column(
        modifier
            .alpha(if (isEnabled) 1f else 0.45f)
            .background(if (isSelected) colors.ground else colors.card, shape)
            .then(
                if (isSelected) {
                    Modifier.background(colors.green.copy(alpha = if (colors.isDark) 0.16f else 0.08f), shape)
                } else {
                    Modifier
                },
            )
            .border(2.dp, if (isSelected) colors.green else Color.Transparent, shape)
            .semantics(mergeDescendants = true) {
                contentDescription = accessibilityName
                stateDescription = spokenValue
                selected = isSelected
                // Screen readers say the new value after a key, a stepper tap or "Use last" (the focus stays on the buttons). Only
                // the edited card is live: the other one does not change, and a second live node would be read twice.
                if (isSelected) liveRegion = LiveRegionMode.Polite
            }
            .pulseClickable(enabled = isEnabled, role = Role.RadioButton, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
    ) {
        Text(label, style = PulseFont.text(12.sp), color = colors.inkSecondary, maxLines = 1)
        Text(
            text,
            style = PulseFont.number(32.sp, FontWeight.Bold),
            color = colors.ink,
            maxLines = 1,
            softWrap = false,
            overflow = TextOverflow.Clip,
            autoSize = TextAutoSize.StepBased(minFontSize = 14.sp, maxFontSize = 32.sp),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

// endregion

// region Steppers and "Use last"

@Composable
private fun KeypadStepperRow(exercise: Exercise, field: KeypadField, previous: PreviousSet?, actions: KeypadActions) {
    val noun = if (field == KeypadField.WEIGHT) "weight" else repsNoun(exercise)
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        KeypadStepButton(Icons.Rounded.Remove, "Decrease $noun") { actions.onStep(-1) }
        KeypadUseLastButton(KeypadLogic.useLastText(field, exercise, previous), previous != null, actions.onUseLast, Modifier.weight(1f))
        KeypadStepButton(Icons.Rounded.Add, "Increase $noun") { actions.onStep(1) }
    }
}

@Composable
private fun KeypadStepButton(icon: androidx.compose.ui.graphics.vector.ImageVector, description: String, onClick: () -> Unit) {
    Box(
        Modifier
            .width(64.dp)
            .pulseMinHeight(48.dp)
            .background(PulseTheme.colors.card, RoundedCornerShape(12.dp))
            .semantics { contentDescription = description }
            .pulseClickable(role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = PulseTheme.colors.greenText, modifier = Modifier.size(22.dp.scaledWithFont()))
    }
}

@Composable
private fun KeypadUseLastButton(text: String, enabled: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Box(
        modifier
            .pulseMinHeight(48.dp)
            .background(colors.card, RoundedCornerShape(12.dp))
            .pulseClickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = PulseFont.text(15.sp, FontWeight.SemiBold),
            color = if (enabled) colors.greenText else colors.inkSecondary,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

// endregion

// region Plates

/** The plate colours and sizes of the design (the same in light and dark). */
private object KeypadPlateLook {
    fun diameter(plate: Double): Int = when (plate) {
        25.0 -> 44
        20.0 -> 42
        15.0 -> 38
        10.0 -> 34
        5.0 -> 30
        2.5 -> 26
        else -> 24
    }

    fun fill(plate: Double): Color = when (plate) {
        25.0 -> Color(0xFF3A3A3C)
        20.0 -> Color(0xFF48484A)
        15.0 -> Color(0xFF636366)
        10.0 -> Color(0xFF8E8E93)
        5.0 -> Color(0xFFAEAEB2)
        2.5 -> Color(0xFFC7C7CC)
        else -> Color(0xFFD1D1D6)
    }

    fun foreground(plate: Double): Color = when (plate) {
        25.0, 20.0, 15.0 -> Color.White
        else -> Color.Black
    }
}

/** "20 kg bar · each side" and the plates for one side of the bar. The label column grows with the font size. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun KeypadPlateRow(barKg: Double, weightKg: Double) {
    val colors = PulseTheme.colors
    val info = remember(barKg, weightKg) { KeypadLogic.plateInfo(weightKg, barKg) }
    val speech = remember(info, barKg) { KeypadLogic.plateSpeech(info, barKg) }
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 46.dp)
            .padding(horizontal = 4.dp)
            .clearAndSetSemantics { contentDescription = speech },
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            NumberText.kg(barKg) + " kg bar · each side",
            style = PulseFont.footnote,
            color = colors.inkSecondary,
            modifier = Modifier.width(84.dp.scaledWithFont()),
        )
        FlowRow(
            Modifier.weight(1f),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            itemVerticalAlignment = Alignment.CenterVertically,
        ) {
            for (plate in info.plates) KeypadPlateChip(plate)
            if (info.note.isNotEmpty()) Text(info.note, style = PulseFont.footnote, color = colors.inkSecondary)
        }
    }
}

/** One plate as a coloured disc with its weight; the disc grows with the figure inside it. */
@Composable
private fun KeypadPlateChip(plate: Double) {
    Box(
        Modifier
            .size(KeypadPlateLook.diameter(plate).dp.scaledWithFont())
            .background(KeypadPlateLook.fill(plate), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            NumberText.kg(plate),
            style = PulseFont.number(11.sp, FontWeight.Bold),
            color = KeypadPlateLook.foreground(plate),
            maxLines = 1,
            softWrap = false,
            overflow = TextOverflow.Clip,
            autoSize = TextAutoSize.StepBased(minFontSize = 7.sp, maxFontSize = 11.sp),
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 2.dp),
        )
    }
}

// endregion

// region Keys

@Composable
private fun KeypadGrid(field: KeypadField, onKey: (KeypadKey) -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (row in KeypadKey.rows) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (key in row) {
                    KeypadKeyButton(
                        key = key,
                        enabled = !(key == KeypadKey.Decimal && field == KeypadField.REPS),
                        onPress = { onKey(key) },
                    )
                }
            }
        }
    }
}

@Composable
private fun RowScope.KeypadKeyButton(key: KeypadKey, enabled: Boolean, onPress: () -> Unit) {
    val colors = PulseTheme.colors
    Box(
        Modifier
            .weight(1f)
            .pulseMinHeight(52.dp)
            .alpha(if (enabled) 1f else 0.35f)
            .background(colors.card, RoundedCornerShape(12.dp))
            .semantics { contentDescription = key.accessibilityName }
            .pulseClickable(enabled = enabled, role = Role.Button, onClick = onPress),
        contentAlignment = Alignment.Center,
    ) {
        when (key) {
            is KeypadKey.Digit -> Text(key.digit, style = PulseFont.number(26.sp, FontWeight.Medium), color = colors.ink)
            KeypadKey.Decimal -> Text(".", style = PulseFont.number(26.sp, FontWeight.Medium), color = colors.ink)
            KeypadKey.Delete -> Icon(
                Icons.AutoMirrored.Rounded.Backspace,
                contentDescription = null,
                tint = colors.ink,
                modifier = Modifier.size(24.dp),
            )
        }
    }
}

// endregion
