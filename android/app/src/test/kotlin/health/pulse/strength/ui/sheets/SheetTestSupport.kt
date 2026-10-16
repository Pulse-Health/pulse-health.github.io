package health.pulse.strength.ui.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.widthIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.core.SetRef
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.core.WorkoutExercise
import health.pulse.strength.ui.ScreenshotSupport
import health.pulse.strength.ui.components.LocalPulseClock
import health.pulse.strength.ui.components.PulseClock
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulseTheme

/**
 * Draws [content] the way a sheet window shows it (dimmed page behind, rounded surface at the bottom, handle, body with the
 * height rules of the real sheet) so a sheet's content can be photographed without a window.
 */
@Composable
fun SheetFrame(fullHeight: Boolean, content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxSize().background(Color(0xFF8E8E93))) {
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.32f)))
        Column(
            Modifier
                .align(Alignment.BottomCenter)
                .widthIn(max = PulseMetrics.maxContentWidth)
                .fillMaxWidth()
                .clip(SheetShape)
                .background(PulseTheme.colors.ground),
        ) {
            Box(Modifier.align(Alignment.CenterHorizontally)) { SheetHandle() }
            SheetBody(fullHeight = fullHeight) { content() }
        }
    }
}

/** A demo store and workout ("Upper A · Push", nothing logged yet) for the sheet tests. */
class SheetFixture(withActiveWorkout: Boolean = true) {
    val environment: StrengthAppEnvironment = StrengthAppEnvironment.preview(withActiveWorkout)
    val store = environment.store
    val controller: WorkoutController = environment.controller

    val exercises: List<WorkoutExercise> get() = controller.state.value!!.exercises

    /** The set [setIndex] of workout exercise [exerciseIndex]. */
    fun ref(exerciseIndex: Int, setIndex: Int): SetRef {
        val exercise = exercises[exerciseIndex]
        return SetRef(exercise.id, exercise.sets[setIndex].id)
    }

    fun set(exerciseIndex: Int, setIndex: Int) = exercises[exerciseIndex].sets[setIndex]
}

/** Provides the Pulse theme with a frozen clock around [content] (for interaction tests that build their own content). */
@Composable
fun PulseTestTheme(dark: Boolean = false, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalPulseClock provides PulseClock(now = { ScreenshotSupport.fixedNow }, ticks = false)) {
        PulseTheme(darkTheme = dark, reduceMotion = true) { content() }
    }
}
