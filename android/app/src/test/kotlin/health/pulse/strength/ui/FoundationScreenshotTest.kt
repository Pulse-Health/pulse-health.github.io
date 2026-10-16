package health.pulse.strength.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.background
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.dp
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.ui.ScreenshotSupport.snapshot
import health.pulse.strength.ui.components.ExerciseMediaView
import health.pulse.strength.ui.theme.PulseChip
import health.pulse.strength.ui.theme.PulseFont
import health.pulse.strength.ui.theme.PulsePillButton
import health.pulse.strength.ui.theme.PulsePrimaryButton
import health.pulse.strength.ui.theme.PulseSegmented
import health.pulse.strength.ui.theme.PulseTheme
import health.pulse.strength.ui.theme.PulseTintButton
import health.pulse.strength.ui.theme.pulseCard
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Renders the shared design primitives so the theme can be checked by eye in light and dark. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class FoundationScreenshotTest {
    @get:Rule val rule = createComposeRule()

    @Composable
    private fun Gallery() {
        val colors = PulseTheme.colors
        Column(Modifier.fillMaxWidth().background(colors.ground).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Foundation", style = PulseFont.largeTitle, color = colors.ink)
            Column(Modifier.fillMaxWidth().pulseCard().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Card title", style = PulseFont.headline, color = colors.ink)
                Text("Secondary text 82.5 kg × 6", style = PulseFont.subhead, color = colors.inkSecondary)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PulseChip("Chest", isSelected = true, onClick = {})
                    PulseChip("Back", isSelected = false, onClick = {})
                    PulseChip("Legs", isSelected = false, onClick = {})
                }
                PulseSegmented(
                    options = listOf<Pair<Int?, String>>(null to "–", 0 to "0", 1 to "1", 2 to "2", 3 to "3", 4 to "4+"),
                    selection = 2,
                    onSelect = {},
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PulseTintButton("Add Set", onClick = {}, modifier = Modifier.weight(1f))
                    PulsePillButton("Finish", onClick = {})
                }
                PulsePrimaryButton("Start workout", onClick = {})
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                for (key in listOf("bench", "squat", null)) {
                    Box(Modifier.size(80.dp)) { ExerciseMediaView(mediaKey = key, modifier = Modifier.size(80.dp), animated = false) }
                }
            }
            Box(Modifier.height(4.dp))
        }
    }

    @Test
    fun light() {
        val file = rule.snapshot("foundation-light") { Gallery() }
        assertThat(file.length()).isGreaterThan(1000)
    }

    @Test
    fun mediaKeysAllHaveFrames() {
        // Every built-in media key ships both frames in assets (a missing file would show the placeholder).
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
        for (key in ExerciseLibrary.mediaKeys) {
            val frames = health.pulse.strength.ui.components.ExerciseMediaStore.frames(context, key)
            assertThat(frames.first).isNotNull()
            assertThat(frames.second).isNotNull()
        }
    }
}
