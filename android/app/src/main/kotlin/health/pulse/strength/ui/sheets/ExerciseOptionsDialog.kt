package health.pulse.strength.ui.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowDownward
import androidx.compose.material.icons.rounded.ArrowUpward
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.Link
import androidx.compose.material.icons.rounded.LinkOff
import androidx.compose.material.icons.rounded.SwapHoriz
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.NumberText
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.core.WorkoutState
import health.pulse.strength.ui.components.rememberPulseHaptics
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight
import java.util.UUID

/**
 * The options of one workout exercise as an action list in a bottom sheet (the iOS "Exercise options" dialog): Form & instructions,
 * Rest timer, Replace exercise, Superset with next / Remove from superset, Move up, Move down and Remove exercise (destructive).
 * The title is the exercise name.
 *
 * "Superset", "Move up / down" and "Remove exercise" are applied to the controller here; the three follow-up presentations
 * (information, rest timer, replace picker) are reported through the callbacks. Every action closes the dialog. The dialog closes
 * itself when the exercise is not in the workout (any more).
 */
@Composable
fun ExerciseOptionsDialog(
    controller: WorkoutController,
    exerciseID: UUID,
    onShowInfo: (Exercise) -> Unit,
    onShowRestSettings: (UUID) -> Unit,
    onReplace: (UUID) -> Unit,
    onDismiss: () -> Unit,
) {
    val state by controller.state.collectAsState()
    val live = remember(state, exerciseID) { ExerciseOptionsContext.of(state, exerciseID) }
    // What the dialog showed last, so it does not go blank while it slides away after "Remove exercise".
    var last by remember { mutableStateOf<ExerciseOptionsContext?>(null) }
    LaunchedEffect(live) { if (live != null) last = live }
    val context = live ?: last
    LaunchedEffect(context == null) { if (context == null) onDismiss() }
    if (context != null) {
        PulseSheet(onDismiss = onDismiss) { dismiss ->
            ExerciseOptionsContent(
                context = context,
                onAction = { action ->
                    when (action) {
                        ExerciseOption.INFO -> onShowInfo(context.exercise)
                        ExerciseOption.REST -> onShowRestSettings(context.id)
                        ExerciseOption.REPLACE -> onReplace(context.id)
                        ExerciseOption.SUPERSET -> controller.send(WorkoutAction.ToggleSuperset(context.id))
                        ExerciseOption.MOVE_UP -> controller.send(WorkoutAction.MoveExerciseBy(context.id, -1))
                        ExerciseOption.MOVE_DOWN -> controller.send(WorkoutAction.MoveExerciseBy(context.id, 1))
                        ExerciseOption.REMOVE -> controller.send(WorkoutAction.RemoveExercise(context.id))
                    }
                    dismiss()
                },
            )
        }
    }
}

/** The actions of the dialog. */
internal enum class ExerciseOption { INFO, REST, REPLACE, SUPERSET, MOVE_UP, MOVE_DOWN, REMOVE }

/** Everything the dialog needs about one workout exercise. */
internal data class ExerciseOptionsContext(
    val id: UUID,
    val exercise: Exercise,
    /** "Off" or "2:30". */
    val restText: String,
    val isInSuperset: Boolean,
    /** The superset item exists for exercises in a group and for every exercise that has a next one. */
    val showsSuperset: Boolean,
    val canMoveUp: Boolean,
    val canMoveDown: Boolean,
) {
    companion object {
        fun of(state: WorkoutState?, exerciseID: UUID): ExerciseOptionsContext? {
            val index = state?.exerciseIndex(exerciseID) ?: return null
            val entry = state.exercises[index]
            val isLast = index >= state.exercises.size - 1
            return ExerciseOptionsContext(
                id = entry.id,
                exercise = entry.exercise,
                restText = NumberText.rest(entry.restSeconds),
                isInSuperset = entry.supersetGroup != null,
                showsSuperset = entry.supersetGroup != null || !isLast,
                canMoveUp = index > 0,
                canMoveDown = !isLast,
            )
        }
    }
}

/** Everything inside the options sheet's window. [onAction] reports the tapped action. */
@Composable
internal fun ExerciseOptionsContent(
    context: ExerciseOptionsContext,
    onAction: (ExerciseOption) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = PulseTheme.colors
    val haptics = rememberPulseHaptics()
    val shape = RoundedCornerShape(12.dp)
    Column(modifier.fillMaxWidth()) {
        Text(
            context.exercise.name,
            style = PulseFont.headline,
            color = colors.ink,
            textAlign = TextAlign.Center,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 12.dp)
                .semantics { heading() },
        )
        Column(
            Modifier
                .weight(1f, fill = false)
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
        ) {
            val items = remember(context) { optionItems(context) }
            Column(Modifier.fillMaxWidth().clip(shape).background(colors.card, shape)) {
                for ((index, item) in items.withIndex()) {
                    OptionRow(
                        icon = item.icon,
                        label = item.label,
                        tint = if (item.destructive) colors.destructive else colors.green,
                        textColor = if (item.destructive) colors.destructive else colors.ink,
                        showsDivider = index > 0,
                    ) {
                        if (item.option == ExerciseOption.REMOVE) haptics.warning()
                        onAction(item.option)
                    }
                }
            }
        }
    }
}

private class OptionItem(val option: ExerciseOption, val icon: ImageVector, val label: String, val destructive: Boolean = false)

/** The actions that apply to this exercise, in the order of the dialog. */
private fun optionItems(context: ExerciseOptionsContext): List<OptionItem> = buildList {
    add(OptionItem(ExerciseOption.INFO, Icons.Rounded.Info, "Form & instructions"))
    add(OptionItem(ExerciseOption.REST, Icons.Rounded.Timer, "Rest timer · " + context.restText))
    add(OptionItem(ExerciseOption.REPLACE, Icons.Rounded.SwapHoriz, "Replace exercise"))
    if (context.showsSuperset) {
        if (context.isInSuperset) {
            add(OptionItem(ExerciseOption.SUPERSET, Icons.Rounded.LinkOff, "Remove from superset"))
        } else {
            add(OptionItem(ExerciseOption.SUPERSET, Icons.Rounded.Link, "Superset with next"))
        }
    }
    if (context.canMoveUp) add(OptionItem(ExerciseOption.MOVE_UP, Icons.Rounded.ArrowUpward, "Move up"))
    if (context.canMoveDown) add(OptionItem(ExerciseOption.MOVE_DOWN, Icons.Rounded.ArrowDownward, "Move down"))
    add(OptionItem(ExerciseOption.REMOVE, Icons.Rounded.Delete, "Remove exercise", destructive = true))
}

@Composable
private fun OptionRow(icon: ImageVector, label: String, tint: Color, textColor: Color, showsDivider: Boolean, onClick: () -> Unit) {
    val separator = PulseTheme.colors.separator
    Row(
        Modifier
            .fillMaxWidth()
            .pulseMinHeight(56.dp)
            .then(
                if (showsDivider) {
                    Modifier.drawBehind { drawRect(separator, size = Size(size.width, 0.5.dp.toPx())) }
                } else {
                    Modifier
                },
            )
            .pulseClickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(24.dp.scaledWithFont()))
        Text(label, style = PulseFont.body, color = textColor, modifier = Modifier.weight(1f))
    }
}
