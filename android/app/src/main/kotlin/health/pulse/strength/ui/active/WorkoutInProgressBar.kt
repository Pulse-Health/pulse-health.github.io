package health.pulse.strength.ui.active

import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import health.pulse.strength.core.ActiveWorkoutPresentation

/** The floating "workout in progress" bar (OWNER: active-workout agent; placeholder until the component is ported). */
@Composable
fun WorkoutInProgressBar(
    presentation: ActiveWorkoutPresentation,
    onResume: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Text(presentation.header.title, modifier)
}
