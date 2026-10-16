package health.pulse.strength.ui.active

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutController

/** The active-workout screen (OWNER: active-workout agent; placeholder until the screen is ported). */
@Composable
fun ActiveWorkoutScreen(
    controller: WorkoutController,
    store: StrengthStore,
    onMinimise: () -> Unit,
    onFinished: (CompletedWorkout?) -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier.fillMaxSize()) { Text("Active workout") }
}
