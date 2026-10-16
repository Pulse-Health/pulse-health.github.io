package health.pulse.strength.ui.sheets

import androidx.compose.runtime.Composable
import health.pulse.strength.core.SetRef
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.ui.KeypadField

/** The weight / reps keypad (OWNER: sheets agent; placeholder until ported). Shows its own modal bottom sheet. */
@Composable
fun KeypadSheet(controller: WorkoutController, ref: SetRef, initialField: KeypadField, onDismiss: () -> Unit) {}
