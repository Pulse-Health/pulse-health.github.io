package health.pulse.strength.ui.sheets

import androidx.compose.runtime.Composable
import health.pulse.strength.core.Exercise
import health.pulse.strength.core.WorkoutController
import java.util.UUID

/**
 * Options of one workout exercise: form & instructions, rest timer, replace, superset, move up/down, remove (OWNER: sheets agent;
 * placeholder until ported). Shows its own dialog / bottom sheet.
 */
@Composable
fun ExerciseOptionsDialog(
    controller: WorkoutController,
    exerciseID: UUID,
    onShowInfo: (Exercise) -> Unit,
    onShowRestSettings: (UUID) -> Unit,
    onReplace: (UUID) -> Unit,
    onDismiss: () -> Unit,
) {}
