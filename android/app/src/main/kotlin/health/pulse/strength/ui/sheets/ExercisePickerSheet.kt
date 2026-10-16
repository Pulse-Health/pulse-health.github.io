package health.pulse.strength.ui.sheets

import androidx.compose.runtime.Composable
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.ui.PickerMode

/** Add / replace exercise picker (OWNER: sheets agent; placeholder until ported). Shows its own modal bottom sheet; dismisses itself. */
@Composable
fun ExercisePickerSheet(store: StrengthStore, controller: WorkoutController, mode: PickerMode, onDismiss: () -> Unit) {}
