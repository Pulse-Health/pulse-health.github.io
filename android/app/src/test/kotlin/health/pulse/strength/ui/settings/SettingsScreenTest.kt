package health.pulse.strength.ui.settings

import android.app.Application
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.StrengthAppEnvironment
import health.pulse.strength.ui.PrivacyLinks
import health.pulse.strength.ui.theme.DarkPulseColors
import health.pulse.strength.ui.theme.LightPulseColors
import health.pulse.strength.ui.theme.PulseColors
import health.pulse.strength.ui.theme.PulseTheme
import kotlin.math.pow
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.shadows.ShadowToast

private const val TALL_PHONE = "w411dp-h2400dp-xxhdpi"
private const val NARROW_PHONE = "w360dp-h4000dp-xhdpi"

/**
 * The settings screen: how TalkBack meets the Health Connect switch, the About rows at big font sizes, and what the rows that
 * leave the app do when the device has nothing to open them with. The window is tall, so the whole page is composed.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = TALL_PHONE)
class SettingsScreenTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    private val app: Application get() = ApplicationProvider.getApplicationContext()
    private var backCount = 0

    private fun show(dark: Boolean = false) {
        val environment = StrengthAppEnvironment.preview()
        rule.setContent { PulseTheme(darkTheme = dark, reduceMotion = true) { SettingsScreen(environment, onBack = { backCount++ }) } }
        rule.waitForIdle()
    }

    private val healthSwitch get() = rule.onNode(isToggleable())
    private val polite = SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite)

    // region Title and Health Connect switch

    @Test
    fun theScreenTitleIsAHeading() {
        show()
        rule.onNode(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading) and hasText("Settings")).assertExists()
    }

    @Test
    fun theHealthConnectSwitchIsOneNamedToggle() {
        show()
        // One stop for TalkBack: the row, named by its text and described as a switch (the Switch inside draws the state only).
        rule.onAllNodes(isToggleable()).assertCountEquals(1)
        healthSwitch
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch))
            .assert(hasText("Save workouts to Health Connect"))
            .assertIsOff()
    }

    @Test
    fun whyTheSwitchDidNotTurnOnIsAnnouncedPolitely() {
        show()
        // Robolectric has no Health Connect, so turning the switch on fails with a message: it must reach TalkBack.
        rule.onNode(polite).assertExists()
        healthSwitch.performClick()
        rule.waitForIdle()
        rule.onNode(polite and hasText("Health Connect is not available on this device.")).assertIsDisplayed()
        healthSwitch.assertIsOff()
    }

    @Test
    fun theSwitchHasRoomToTheTextBesideIt() {
        show()
        val row = healthSwitch.getUnclippedBoundsInRoot()
        val text = rule.onNodeWithText("Each finished workout", substring = true, useUnmergedTree = true).getUnclippedBoundsInRoot()
        // The Switch is 52 dp wide and the wrapped text must stay 12 dp clear of it.
        assertThat((row.right - text.right).value).isAtLeast(52f + 12f)
    }

    // endregion

    // region Switch colours and footnote

    @Test
    fun theSwitchWhenOffStandsOutFromTheCardInLightMode() = assertOffSwitchContrast(dark = false, LightPulseColors)

    @Test
    fun theSwitchWhenOffStandsOutFromTheCardInDarkMode() = assertOffSwitchContrast(dark = true, DarkPulseColors)

    /** Draws the screen and reads the pixels of the off switch: its thumb and its track outline against the card behind it. */
    private fun assertOffSwitchContrast(dark: Boolean, colors: PulseColors) {
        show(dark)
        val image = healthSwitch.captureToImage().asAndroidBitmap()
        val density = app.resources.displayMetrics.density
        fun pixelAt(fromRight: Float, y: Float): Color =
            Color(image.getPixel(image.width - (fromRight * density).toInt(), (y * density).toInt()))
        val middle = image.height / density / 2
        // The 52 x 32 dp switch ends the row: its off thumb (16 dp) sits 16 dp from the track's left end, the outline is 2 dp wide.
        val thumb = pixelAt(fromRight = 36f, y = middle)
        val outline = pixelAt(fromRight = 51f, y = middle)
        for (pixel in listOf(thumb, outline)) {
            assertThat(pixel.copy(alpha = 1f)).isEqualTo(colors.inkSecondary)
            assertThat(contrast(pixel, colors.card)).isAtLeast(3.0)
        }
    }

    @Test
    fun theFootnoteUsesTheSecondaryInk() {
        show(dark = true)
        val layout = rule.onNodeWithText("Built with Kotlin", substring = true).textLayout()
        assertThat(layout.layoutInput.style.color).isEqualTo(DarkPulseColors.inkSecondary)
    }

    // endregion

    // region About rows at a big font size

    @Test
    @Config(qualifiers = NARROW_PHONE, fontScale = 2.0f)
    fun aboutRowsStackAndKeepWordsWholeAtTwiceTheFontSize() {
        show()
        // One TalkBack stop per row ...
        val row = rule.onNode(hasText("Exercise photos") and hasText("Free Exercise DB (public domain)"))
        row.assertIsDisplayed()
        rule.onNode(hasText("Version")).assertIsDisplayed()
        // ... with the value under the label instead of squeezed beside it ...
        val label = rule.onNodeWithText("Exercise photos", useUnmergedTree = true)
        val value = rule.onNodeWithText("Free Exercise DB (public domain)", useUnmergedTree = true)
        assertThat(value.getUnclippedBoundsInRoot().left).isEqualTo(label.getUnclippedBoundsInRoot().left)
        assertThat(value.getUnclippedBoundsInRoot().top).isAtLeast(label.getUnclippedBoundsInRoot().bottom)
        // ... so no line of it breaks inside a word.
        assertNoLineBreaksInsideAWord(value)
    }

    @Test
    @Config(qualifiers = "w320dp-h4000dp-xhdpi", fontScale = 1.49f)
    fun aboutRowsKeepWordsWholeJustBelowTheBigFontSizes() {
        show()
        rule.onNode(hasText("Exercise photos") and hasText("Free Exercise DB (public domain)")).assertIsDisplayed()
        assertNoLineBreaksInsideAWord(rule.onNodeWithText("Free Exercise DB (public domain)", useUnmergedTree = true))
    }

    @Test
    fun aboutRowsKeepLabelAndValueOnOneLineAtNormalSize() {
        show()
        val label = rule.onNodeWithText("Exercise photos", useUnmergedTree = true).getUnclippedBoundsInRoot()
        val value = rule.onNodeWithText("Free Exercise DB (public domain)", useUnmergedTree = true).getUnclippedBoundsInRoot()
        assertThat(value.top).isEqualTo(label.top)
        assertThat(value.left).isGreaterThan(label.right)
        // The value ends at the card's inner right edge (411 dp window, 16 dp screen inset, 16 dp card padding).
        assertThat(value.right.value).isWithin(1f).of(411f - 32f)
    }

    private fun assertNoLineBreaksInsideAWord(node: SemanticsNodeInteraction) {
        val layout = node.textLayout()
        val text = layout.layoutInput.text.text
        for (line in 0 until layout.lineCount - 1) {
            assertThat(text[layout.getLineEnd(line) - 1].isWhitespace()).isTrue()
        }
    }

    // endregion

    // region Rows that leave the app

    @Test
    fun theContactRowShowsTheAddress() {
        show()
        rule.onNode(hasText("Contact") and hasText(PrivacyLinks.supportEmail)).assertIsDisplayed()
    }

    @Test
    fun contactOpensTheMailApp() {
        shadowOf(app).checkActivities(true)
        installHandler(Intent.ACTION_SENDTO, "mailto")
        show()
        rule.onNode(hasText("Contact")).performClick()
        val started = shadowOf(app).nextStartedActivity
        assertThat(started.action).isEqualTo(Intent.ACTION_SENDTO)
        assertThat(started.data).isEqualTo("mailto:${PrivacyLinks.supportEmail}".toUri())
        assertThat(ShadowToast.getLatestToast()).isNull()
    }

    @Test
    fun contactWithoutAMailAppCopiesTheAddressAndSaysSo() {
        shadowOf(app).checkActivities(true)
        show()
        rule.onNode(hasText("Contact")).performClick()
        assertThat(ShadowToast.getTextOfLatestToast()).isEqualTo("No e-mail app found. The address was copied to the clipboard.")
        assertThat(ShadowToast.getLatestToast().duration).isEqualTo(Toast.LENGTH_LONG)
        assertThat(clipboardText()).isEqualTo(PrivacyLinks.supportEmail)
        assertThat(shadowOf(app).nextStartedActivity).isNull()
    }

    @Test
    fun theLinkRowsWithoutABrowserCopyTheLinkAndSaySo() {
        shadowOf(app).checkActivities(true)
        show()
        rule.onNode(hasText("Privacy policy")).performClick()
        assertThat(ShadowToast.getTextOfLatestToast()).isEqualTo("No web browser found. The link was copied to the clipboard.")
        assertThat(clipboardText()).isEqualTo(PrivacyLinks.policyUrl)
    }

    @Test
    fun theHealthConnectStoreRowPrefersThePlayStoreApp() {
        shadowOf(app).checkActivities(true)
        installHandler(Intent.ACTION_VIEW, "market")
        installHandler(Intent.ACTION_VIEW, "https")
        openHealthConnectStore(app)
        assertThat(shadowOf(app).nextStartedActivity.data).isEqualTo("market://details?id=com.google.android.apps.healthdata".toUri())
    }

    @Test
    fun theHealthConnectStoreRowFallsBackToThePlayStoreWebsite() {
        shadowOf(app).checkActivities(true)
        installHandler(Intent.ACTION_VIEW, "https")
        openHealthConnectStore(app)
        val web = "https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata"
        assertThat(shadowOf(app).nextStartedActivity.data).isEqualTo(web.toUri())
        assertThat(ShadowToast.getLatestToast()).isNull()
    }

    @Test
    fun theHealthConnectStoreRowSaysSoWhenNothingOpensIt() {
        shadowOf(app).checkActivities(true)
        openHealthConnectStore(app)
        assertThat(ShadowToast.getTextOfLatestToast()).isEqualTo("This is not available on this device.")
        assertThat(shadowOf(app).nextStartedActivity).isNull()
    }

    /** An app that opens [action] intents for [scheme] links: what a mail app, the Play Store or a browser registers. */
    private fun installHandler(action: String, scheme: String) {
        val component = ComponentName("com.example.$scheme", "com.example.$scheme.Main")
        val packages = shadowOf(app.packageManager)
        packages.addActivityIfNotPresent(component)
        packages.addIntentFilterForActivity(
            component,
            IntentFilter(action).apply {
                addCategory(Intent.CATEGORY_DEFAULT)
                addDataScheme(scheme)
            },
        )
    }

    private fun clipboardText(): String? {
        val clip = app.getSystemService(ClipboardManager::class.java).primaryClip
        return clip?.getItemAt(0)?.text?.toString()
    }

    // endregion

    private fun SemanticsNodeInteraction.textLayout(): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        rule.runOnIdle { fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action!!.invoke(results) }
        return results.first()
    }

    /** WCAG contrast ratio of two colours (the second behind the first). */
    private fun contrast(first: Color, second: Color): Double {
        fun channel(value: Float) = if (value <= 0.03928f) value / 12.92 else ((value + 0.055) / 1.055).pow(2.4)
        fun luminance(color: Color) = 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
        val (a, b) = luminance(first) to luminance(second)
        return (maxOf(a, b) + 0.05) / (minOf(a, b) + 0.05)
    }
}
