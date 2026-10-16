package health.pulse.strength.wear

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import com.google.android.gms.wearable.MessageEvent
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.WearProtocol
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.core.widgets.WidgetJson
import health.pulse.strength.runtime.PreviewRuntime
import health.pulse.strength.runtime.StrengthRuntime
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

/**
 * The commands of the watch app: the wire format is the one `WearCommandCodecTest` of the wear module produces, a command runs through
 * `StrengthRuntime.commands`, and every surface is refreshed afterwards. Also the manifest entry and the capability the watch looks for.
 */
@RunWith(RobolectricTestRunner::class)
class PhoneWearListenerServiceTest {
    private val app = ApplicationProvider.getApplicationContext<Application>()
    private val runtime = PreviewRuntime()
    private var refreshes = 0

    @Before
    fun setUp() {
        StrengthRuntime.installForTest(runtime)
    }

    private suspend fun handle(text: String): Boolean =
        WearCommandHandler.handle(app, text.toByteArray(Charsets.UTF_8)) { refreshes++ }

    // region Wire format

    @Test
    fun theTextsTheWatchSendsDecodeToTheirCommands() {
        assertThat(WearCommandHandler.decode("""{"name":"logNextSet","args":{}}""".toByteArray())).isEqualTo(WidgetCommand.of(WidgetCommands.LOG_NEXT_SET))
        assertThat(WearCommandHandler.decode("""{"name":"adjustRest","args":{"seconds":"-15"}}""".toByteArray()))
            .isEqualTo(WidgetCommand.of(WidgetCommands.ADJUST_REST, WidgetCommands.ARG_SECONDS to "-15"))
        assertThat(WearCommandHandler.decode("""{"name":"nudge","args":{"weightSteps":"1","repsSteps":"-1"}}""".toByteArray()))
            .isEqualTo(WidgetCommand.of(WidgetCommands.NUDGE, WidgetCommands.ARG_WEIGHT_STEPS to "1", WidgetCommands.ARG_REPS_STEPS to "-1"))
    }

    @Test
    fun aCommandWithoutArgsOrWithUnknownFieldsStillDecodes() {
        assertThat(WearCommandHandler.decode("""{"name":"skipRest"}""".toByteArray())).isEqualTo(WidgetCommand.of(WidgetCommands.SKIP_REST))
        assertThat(WearCommandHandler.decode("""{"name":"pause","args":{},"future":1}""".toByteArray())).isEqualTo(WidgetCommand.of(WidgetCommands.PAUSE))
    }

    @Test
    fun whatIsNotACommandDoesNotDecode() {
        assertThat(WearCommandHandler.decode("{not json".toByteArray())).isNull()
        assertThat(WearCommandHandler.decode(ByteArray(0))).isNull()
        assertThat(WearCommandHandler.decode("""{"args":{}}""".toByteArray())).isNull()
        assertThat(WearCommandHandler.decode("[1,2]".toByteArray())).isNull()
    }

    @Test
    fun theEncodedFormOfACommandDecodesBack() {
        val command = WidgetCommand.of(WidgetCommands.ADJUST_REST, WidgetCommands.ARG_SECONDS to "15")

        val payload = WidgetJson.json.encodeToString(WidgetCommand.serializer(), command).toByteArray(Charsets.UTF_8)

        assertThat(WearCommandHandler.decode(payload)).isEqualTo(command)
    }

    // endregion

    // region Running a command

    @Test
    fun aCommandRunsThroughTheRuntimeAndThenEverySurfaceIsRefreshed() = runTest {
        val ran = handle("""{"name":"logNextSet","args":{}}""")

        assertThat(ran).isTrue()
        assertThat(runtime.received).containsExactly("logNextSet")
        assertThat(refreshes).isEqualTo(1)
    }

    @Test
    fun theArgumentsReachTheEngine() = runTest {
        handle("""{"name":"adjustRest","args":{"seconds":"15"}}""")
        handle("""{"name":"nudge","args":{"weightSteps":"-1","repsSteps":"0"}}""")
        handle("""{"name":"startTemplate","args":{"templateId":"abc"}}""")

        assertThat(runtime.received).containsExactly("adjustRest:15", "nudge:-1:0", "startTemplate:abc").inOrder()
    }

    @Test
    fun everyCommandOfTheWatchIsUnderstood() = runTest {
        listOf("startNext", "logNextSet", "skipRest", "pause", "resume", "finish").forEach { handle("""{"name":"$it","args":{}}""") }

        assertThat(runtime.received).containsExactly("startNext", "logNextSet", "skipRest", "pause", "resume", "finish").inOrder()
    }

    @Test
    fun anUnknownCommandIsIgnoredByTheEngineButStillRefreshes() = runTest {
        val ran = handle("""{"name":"selfDestruct","args":{}}""")

        assertThat(ran).isTrue()
        assertThat(runtime.received).isEmpty()
    }

    @Test
    fun garbageRunsNothingAndRefreshesNothing() = runTest {
        val ran = handle("{not json")

        assertThat(ran).isFalse()
        assertThat(runtime.received).isEmpty()
        assertThat(refreshes).isEqualTo(0)
    }

    // endregion

    // region Service and manifest

    private class Message(private val path: String, private val data: ByteArray) : MessageEvent {
        override fun getRequestId(): Int = 0
        override fun getPath(): String = path
        override fun getSourceNodeId(): String = "watch"
        override fun getData(): ByteArray = data
    }

    @Test
    fun aMessageAtAnotherPathIsIgnored() {
        val service = Robolectric.setupService(PhoneWearListenerService::class.java)

        service.onMessageReceived(Message("/pulse/other", """{"name":"logNextSet","args":{}}""".toByteArray()))

        assertThat(runtime.received).isEmpty()
    }

    @Test
    fun theServiceHearsMessagesAtTheCommandPathFromAnyNode() {
        val intent = Intent("com.google.android.gms.wearable.MESSAGE_RECEIVED").setData(Uri.parse("wear://some-watch" + WearProtocol.COMMAND_PATH))

        val matches = app.packageManager.queryIntentServices(intent, 0)

        assertThat(matches.map { it.serviceInfo.name }).containsExactly(PhoneWearListenerService::class.java.name)
        assertThat(matches.single().serviceInfo.exported).isTrue()
    }

    @Test
    fun theServiceDoesNotHearOtherPaths() {
        val intent = Intent("com.google.android.gms.wearable.MESSAGE_RECEIVED").setData(Uri.parse("wear://some-watch/other"))

        assertThat(app.packageManager.queryIntentServices(intent, 0)).isEmpty()
    }

    @Test
    fun thePhoneAdvertisesTheCapabilityTheWatchLooksFor() {
        val capabilities = app.resources.getStringArray(health.pulse.strength.R.array.android_wear_capabilities)

        assertThat(capabilities.toList()).containsExactly(WearProtocol.PHONE_CAPABILITY)
    }

    // endregion
}
