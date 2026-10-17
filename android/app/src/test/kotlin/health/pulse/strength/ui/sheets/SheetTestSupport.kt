package health.pulse.strength.ui.sheets

import android.view.View
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
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.core.graphics.Insets
import androidx.core.view.WindowInsetsCompat
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.core.SetRef
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.core.WorkoutExercise
import health.pulse.strength.ui.ScreenshotSupport
import health.pulse.strength.ui.components.LocalPulseClock
import health.pulse.strength.ui.components.PulseClock
import health.pulse.strength.ui.theme.PulseMetrics
import health.pulse.strength.ui.theme.PulseTheme
import org.robolectric.RuntimeEnvironment
import org.robolectric.shadows.ShadowDialog

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

/**
 * Delivers system bar and keyboard insets (dp) to the window of the latest sheet the way the system does it (the keyboard is
 * visible when [ime] is above 0).
 */
fun ComposeTestRule.deliverSheetInsets(status: Int = 0, navigation: Int = 0, ime: Int = 0) {
    val density = RuntimeEnvironment.getApplication().resources.displayMetrics.density
    fun px(dp: Int) = (dp * density).toInt()
    val decor: View = ShadowDialog.getLatestDialog().window!!.decorView
    val insets = WindowInsetsCompat.Builder()
        .setInsets(WindowInsetsCompat.Type.statusBars(), Insets.of(0, px(status), 0, 0))
        .setInsets(WindowInsetsCompat.Type.navigationBars(), Insets.of(0, 0, 0, px(navigation)))
        .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, px(ime)))
        .setVisible(WindowInsetsCompat.Type.ime(), ime > 0)
        .build()
        .toWindowInsets()!!
    runOnUiThread { decor.dispatchApplyWindowInsets(insets) }
    waitForIdle()
}
