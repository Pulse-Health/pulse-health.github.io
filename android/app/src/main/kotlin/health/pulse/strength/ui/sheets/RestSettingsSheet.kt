package health.pulse.strength.ui.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import health.pulse.strength.core.NumberText
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.core.WorkoutSettings
import health.pulse.strength.ui.components.rememberPulseHaptics
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.pulseClickable
import health.pulse.strength.ui.theme.pulseMinHeight
import java.util.UUID

/**
 * Rest timer settings. Shows its own modal bottom sheet.
 *
 * Title bar ("Rest Timer" + Done), the line "Rest after each set · <exercise>", ten presets (Off, 0:30, 0:45, 1:00, 1:30, 2:00,
 * 2:30, 3:00, 4:00, 5:00; the chosen one is green) that set the exercise's rest, and the two workout-wide switches "Start after
 * logging a set" and "Alert when rest is over".
 */
@Composable
fun RestSettingsSheet(controller: WorkoutController, exerciseID: UUID, onDismiss: () -> Unit) {
    PulseSheet(onDismiss = onDismiss) { dismiss ->
        RestSettingsSheetContent(controller = controller, exerciseID = exerciseID, onDone = dismiss)
    }
}

/** The rest presets in seconds (0 turns the timer off for the exercise). */
internal val RestPresets: List<Int> = listOf(0, 30, 45, 60, 90, 120, 150, 180, 240, 300)

/** Everything inside the rest settings sheet's window. [onDone] closes the sheet. */
@Composable
internal fun RestSettingsSheetContent(
    controller: WorkoutController,
    exerciseID: UUID,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by controller.state.collectAsState()
    // The exercise being configured; the current exercise when the id is no longer in the workout.
    val entry = state?.let { s -> s.exercises.firstOrNull { it.id == exerciseID } ?: s.currentExercise }
    val settings = state?.settings ?: WorkoutSettings()
    val haptics = rememberPulseHaptics()

    Column(modifier.fillMaxWidth()) {
        SheetTitleBar(title = "Rest Timer", trailing = SheetBarButton("Done", onClick = onDone))
        Column(
            Modifier
                .weight(1f, fill = false)
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (entry != null) {
                SheetSectionLabel("Rest after each set · ${entry.exercise.name}")
                RestPresetGrid(selectedSeconds = entry.restSeconds) { seconds ->
                    haptics.selection()
                    controller.send(WorkoutAction.SetRest(entry.id, seconds))
                }
            }
            RestToggleCard(
                autoStart = settings.autoStartRest,
                alertWhenOver = settings.alertWhenRestEnds,
                onAutoStart = { controller.send(WorkoutAction.SetAutoStartRest(it)) },
                onAlertWhenOver = { controller.send(WorkoutAction.SetAlertWhenRestEnds(it)) },
            )
        }
    }
}

/** "Rest timer off", "30 seconds", "1 minute 30 seconds", "5 minutes". */
internal fun spokenRest(seconds: Int): String {
    if (seconds <= 0) return "Rest timer off"
    val minutes = seconds / 60
    val rest = seconds % 60
    val parts = mutableListOf<String>()
    if (minutes > 0) parts.add("$minutes " + if (minutes == 1) "minute" else "minutes")
    if (rest > 0) parts.add("$rest " + if (rest == 1) "second" else "seconds")
    return parts.joinToString(" ")
}

/** The ten presets: two rows of five; at the largest font sizes five rows of two, so a button is wide enough for its time. */
@Composable
private fun RestPresetGrid(selectedSeconds: Int, onSelect: (Int) -> Unit) {
    val columns = if (isAccessibilityFontScale()) 2 else 5
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (row in RestPresets.chunked(columns)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (seconds in row) {
                    RestPresetButton(seconds, isSelected = seconds == selectedSeconds, onClick = { onSelect(seconds) }, Modifier.weight(1f))
                }
            }
        }
    }
}

/** One of the ten presets: 48 dp tall, white, or solid green when it is the exercise's rest. */
@Composable
private fun RestPresetButton(seconds: Int, isSelected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = PulseTheme.colors
    Box(
        modifier
            .pulseMinHeight(48.dp)
            .background(if (isSelected) colors.green else colors.card, RoundedCornerShape(12.dp))
            .semantics {
                contentDescription = spokenRest(seconds)
                selected = isSelected
            }
            .pulseClickable(role = Role.RadioButton, onClick = onClick)
            .padding(horizontal = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            NumberText.rest(seconds),
            style = PulseFont.number(17.sp, FontWeight.SemiBold),
            color = if (isSelected) colors.onGreen else colors.ink,
            maxLines = 1,
            softWrap = false,
            overflow = TextOverflow.Clip,
            textAlign = TextAlign.Center,
            autoSize = TextAutoSize.StepBased(minFontSize = 11.sp, maxFontSize = 17.sp),
        )
    }
}

/** The two workout-wide switches in one card. */
@Composable
private fun RestToggleCard(
    autoStart: Boolean,
    alertWhenOver: Boolean,
    onAutoStart: (Boolean) -> Unit,
    onAlertWhenOver: (Boolean) -> Unit,
) {
    val colors = PulseTheme.colors
    val shape = RoundedCornerShape(12.dp)
    Column(Modifier.fillMaxWidth().clip(shape).background(colors.card, shape)) {
        RestToggleRow("Start after logging a set", "Shorter after warm-up sets", autoStart, onAutoStart)
        RestToggleRow("Alert when rest is over", "Haptic, sound and Lock Screen update", alertWhenOver, onAlertWhenOver, showsDivider = true)
    }
}

/** A 56 dp row: title and explanation on the left, the green switch on the right; the whole row toggles. */
@Composable
private fun RestToggleRow(
    title: String,
    subtitle: String,
    isOn: Boolean,
    onChange: (Boolean) -> Unit,
    showsDivider: Boolean = false,
) {
    val colors = PulseTheme.colors
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
            .toggleable(value = isOn, role = Role.Switch, onValueChange = onChange)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = PulseFont.body, color = colors.ink)
            Text(subtitle, style = PulseFont.text(12.sp), color = colors.inkSecondary)
        }
        Switch(
            checked = isOn,
            onCheckedChange = null,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = colors.recoveryGood,
                checkedBorderColor = Color.Transparent,
                uncheckedThumbColor = Color.White,
                uncheckedTrackColor = colors.progressTrackCurrent,
                uncheckedBorderColor = Color.Transparent,
            ),
        )
    }
}
