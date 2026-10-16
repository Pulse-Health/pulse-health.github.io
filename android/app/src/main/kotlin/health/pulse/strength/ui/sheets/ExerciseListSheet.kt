package health.pulse.strength.ui.sheets

import androidx.compose.runtime.Composable
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutController

/** The workout's exercise list with reordering (OWNER: sheets agent; placeholder until ported). Shows its own modal bottom sheet. */
@Composable
fun ExerciseListSheet(controller: WorkoutController, store: StrengthStore, onDismiss: () -> Unit) {}
