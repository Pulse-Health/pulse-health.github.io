package health.pulse.strength.ui.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Delete
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.SetRef
import health.pulse.strength.core.SetType
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.core.WorkoutState
import health.pulse.strength.ui.components.rememberPulseHaptics
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.badgeBackground
import health.pulse.strength.ui.theme.badgeForeground
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight

/**
 * Set type, reps in reserve and delete for one set. Shows its own modal bottom sheet.
 *
 * Title bar ("Set 3 · Barbell bench press" + Done), the "Set type" list (Normal, Warm-up, Drop set, To failure, each with its badge
 * colours and a check on the current one), the "Reps in reserve" segmented control (– 0 1 2 3 4+) and the red "Delete Set" button.
 * Every choice is dispatched at once and the sheet stays open; "Delete Set" removes the set (the workout screen offers Undo) and
 * closes the sheet.
 */
@Composable
fun SetDetailSheet(controller: WorkoutController, ref: SetRef, onDismiss: () -> Unit) {
    PulseSheet(onDismiss = onDismiss) { dismiss ->
        SetDetailSheetContent(controller = controller, ref = ref, onDone = dismiss)
    }
}

/** The few values of the set the sheet displays. */
internal data class SetDetailSnapshot(val title: String, val type: SetType, val rir: Int?) {
    companion object {
        fun of(state: WorkoutState?, ref: SetRef): SetDetailSnapshot? {
            val exercise = state?.exercises?.firstOrNull { it.id == ref.exerciseID } ?: return null
            val index = exercise.sets.indexOfFirst { it.id == ref.setID }
            if (index < 0) return null
            val set = exercise.sets[index]
            return SetDetailSnapshot("Set ${index + 1} · ${exercise.exercise.name}", set.type, set.rir)
        }
    }
}

/** Everything inside the set detail sheet's window. [onDone] closes the sheet. */
@Composable
internal fun SetDetailSheetContent(
    controller: WorkoutController,
    ref: SetRef,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by controller.state.collectAsState()
    val live = remember(state, ref) { SetDetailSnapshot.of(state, ref) }
    // What the sheet showed when "Delete Set" was tapped, so it does not go blank while it slides away.
    var frozen by remember { mutableStateOf<SetDetailSnapshot?>(null) }
    val shown = live ?: frozen
    val haptics = rememberPulseHaptics()

    // The set is gone (removed elsewhere): nothing left to edit.
    LaunchedEffect(shown == null) { if (shown == null) onDone() }

    Column(modifier.fillMaxWidth()) {
        SheetTitleBar(title = shown?.title ?: "Set details", trailing = SheetBarButton("Done", onClick = onDone))
        if (shown != null) {
            Column(
                Modifier
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState())
                    .padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                SheetSectionLabel("Set type")
                SetDetailTypeList(selected = shown.type) { type ->
                    haptics.selection()
                    controller.send(WorkoutAction.SetSetType(ref.exerciseID, ref.setID, type))
                }
                SheetSectionLabel("Reps in reserve")
                SegmentedOptions(
                    options = SetDetailRirOptions,
                    selection = shown.rir,
                    onSelect = { value ->
                        haptics.selection()
                        controller.send(WorkoutAction.SetRIR(ref.exerciseID, ref.setID, value))
                    },
                    groupLabel = "Reps in reserve",
                )
                SetDetailDeleteButton(
                    onClick = {
                        // Once only: a second tap while the sheet slides away finds no set and must not repeat the haptic.
                        val current = live
                        if (current != null) {
                            frozen = current
                            haptics.warning()
                            controller.send(WorkoutAction.DeleteSet(ref.exerciseID, ref.setID))
                            onDone()
                        }
                    },
                )
            }
        }
    }
}

/** "– 0 1 2 3 4+": "–" clears the value, "4+" stores 4. */
private val SetDetailRirOptions: List<SegmentOption<Int?>> = listOf(
    SegmentOption(null, "–", "Not recorded"),
    SegmentOption(0, "0", "0 reps in reserve"),
    SegmentOption(1, "1", "1 rep in reserve"),
    SegmentOption(2, "2", "2 reps in reserve"),
    SegmentOption(3, "3", "3 reps in reserve"),
    SegmentOption(4, "4+", "4 or more reps in reserve"),
)

private fun explanation(type: SetType): String = when (type) {
    SetType.NORMAL -> "Counts toward volume"
    SetType.WARMUP -> "Left out of volume and PRs"
    SetType.DROP -> "Lower weight, little rest"
    SetType.FAILURE -> "Until you cannot do another rep"
}

@Composable
private fun SetDetailTypeList(selected: SetType, onPick: (SetType) -> Unit) {
    val shape = RoundedCornerShape(12.dp)
    Column(Modifier.fillMaxWidth().clip(shape).background(PulseTheme.colors.card, shape)) {
        for ((index, type) in SetType.entries.withIndex()) {
            SetDetailTypeRow(type = type, isSelected = type == selected, showsDivider = index > 0, onClick = { onPick(type) })
        }
    }
}

/** One row of the set type list: a 32 dp badge, the name, an explanation and a check on the chosen type. */
@Composable
private fun SetDetailTypeRow(type: SetType, isSelected: Boolean, showsDivider: Boolean, onClick: () -> Unit) {
    val colors = PulseTheme.colors
    val explanation = explanation(type)
    Row(
        Modifier
            .fillMaxWidth()
            .pulseMinHeight(56.dp)
            .then(
                if (showsDivider) {
                    Modifier.drawBehind { drawRect(colors.separator, size = Size(size.width, 0.5.dp.toPx())) }
                } else {
                    Modifier
                },
            )
            .semantics(mergeDescendants = true) {
                contentDescription = "${type.title}, $explanation"
                selected = isSelected
            }
            .pulseClickable(role = Role.RadioButton, onClick = onClick)
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(32.dp.scaledWithFont())
                .background(type.badgeBackground(), RoundedCornerShape(8.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Text(type.badge, style = PulseFont.text(15.sp, FontWeight.Bold), color = type.badgeForeground())
        }
        Column(Modifier.weight(1f).padding(vertical = 8.dp)) {
            Text(type.title, style = PulseFont.body, color = colors.ink)
            Text(explanation, style = PulseFont.text(12.sp), color = colors.inkSecondary)
        }
        Icon(
            Icons.Rounded.Check,
            contentDescription = null,
            tint = colors.green,
            modifier = Modifier.size(20.dp.scaledWithFont()).alpha(if (isSelected) 1f else 0f),
        )
    }
}

@Composable
private fun SetDetailDeleteButton(onClick: () -> Unit) {
    val colors = PulseTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .pulseMinHeight(52.dp)
            .background(colors.card, RoundedCornerShape(12.dp))
            .pulseClickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Rounded.Delete, contentDescription = null, tint = colors.destructive, modifier = Modifier.size(22.dp.scaledWithFont()))
        Spacer(Modifier.width(8.dp))
        Text("Delete Set", style = PulseFont.body, color = colors.destructive)
    }
}
