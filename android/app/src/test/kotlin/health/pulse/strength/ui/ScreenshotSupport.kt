package health.pulse.strength.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.test.onRoot
import health.pulse.strength.ui.components.LocalPulseClock
import health.pulse.strength.ui.components.PulseClock
import health.pulse.strength.ui.theme.PulseTheme
import java.io.File
import java.io.FileOutputStream
import java.time.Instant

/** Device sizes the screens are checked on (Robolectric qualifier strings). */
enum class TestDevice(val qualifiers: String) {
    PHONE("w411dp-h891dp-xxhdpi"),
    SMALL_PHONE("w360dp-h640dp-xhdpi"),
    PHONE_LANDSCAPE("w891dp-h411dp-land-xxhdpi"),
    TABLET("w800dp-h1280dp-xhdpi"),
}

object ScreenshotSupport {
    /** Where the PNGs go: `app/build/screens/` (the Gradle test task runs in the module directory). */
    val directory: File = File("build/screens").also { it.mkdirs() }

    /** A fixed "now" so countdowns and clocks render the same every time: 2026-01-12 18:30:00 UTC. */
    val fixedNow: Instant = Instant.parse("2026-01-12T18:30:00Z")

    /**
     * Sets [content] inside the Pulse theme with a frozen clock and no animations, and writes the root's pixels to
     * `build/screens/<name>.png`.
     */
    fun ComposeContentTestRule.snapshot(
        name: String,
        dark: Boolean = false,
        now: Instant = fixedNow,
        content: @Composable () -> Unit,
    ): File {
        setContent {
            CompositionLocalProvider(LocalPulseClock provides PulseClock(now = { now }, ticks = false)) {
                PulseTheme(darkTheme = dark, reduceMotion = true) { content() }
            }
        }
        waitForIdle()
        return capture(name)
    }

    /** Writes the current pixels of the root to `build/screens/<name>.png`. */
    fun ComposeContentTestRule.capture(name: String): File {
        val file = File(directory, "$name.png")
        file.parentFile?.mkdirs()
        val bitmap = onRoot().captureToImage().asAndroidBitmap()
        FileOutputStream(file).use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        return file
    }
}
