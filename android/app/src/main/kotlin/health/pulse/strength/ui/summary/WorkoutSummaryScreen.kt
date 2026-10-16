package health.pulse.strength.ui.summary

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import health.pulse.strength.core.CompletedWorkout

/** The workout summary (OWNER: detail+summary agent; placeholder until the screen is ported). */
@Composable
fun WorkoutSummaryScreen(workout: CompletedWorkout, onDone: () -> Unit, modifier: Modifier = Modifier) {
    Text(workout.name, modifier)
}
