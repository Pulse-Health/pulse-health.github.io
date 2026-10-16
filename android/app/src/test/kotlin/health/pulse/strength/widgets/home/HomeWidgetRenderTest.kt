package health.pulse.strength.widgets.home

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Every widget composed by Glance, translated to `RemoteViews` and inflated, at the sizes a launcher gives it, with the preview snapshot
 * and with no history, in light and dark. The PNGs land in `app/build/screens/widgets/` (CI uploads them with the other screens).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "xxhdpi")
class HomeWidgetRenderTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private suspend fun renderAll(night: Boolean) {
        RuntimeEnvironment.setQualifiers(if (night) "+night" else "+notnight")
        val mode = if (night) "dark" else "light"
        val wallpaper = if (night) 0xFF101215.toInt() else 0xFFE9E9EE.toInt()
        for (case in WidgetCases.all) {
            for (size in case.sizes) {
                for ((label, snapshot) in listOf("preview" to HomeFixtures.preview, "empty" to HomeFixtures.empty)) {
                    val rendered = GlanceHarness.inflate(context, size, snapshot, case.dynamic, case.content)
                    assertThat(rendered.viewCount).isGreaterThan(1)
                    assertThat(rendered.texts).isNotEmpty()
                    assertThat(rendered.clickable).isAtLeast(1)
                    rendered.savePng("${case.name}-${size.width.value.toInt()}x${size.height.value.toInt()}-$label-$mode", wallpaper)
                }
            }
        }
    }

    @Test
    fun everyWidgetRendersInLightMode() = runTest { renderAll(night = false) }

    @Test
    fun everyWidgetRendersInDarkMode() = runTest { renderAll(night = true) }
}
