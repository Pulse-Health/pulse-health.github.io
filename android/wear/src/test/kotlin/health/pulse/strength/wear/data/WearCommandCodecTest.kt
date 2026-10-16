package health.pulse.strength.wear.data

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.core.widgets.WidgetJson
import org.junit.Test

/**
 * The wire format of a watch to phone message (`WearProtocol.COMMAND_PATH`): the phone decodes it with exactly the expression used
 * here, and `PhoneWearListenerServiceTest` in the app module decodes the same literal texts.
 */
class WearCommandCodecTest {
    private fun wire(command: WidgetCommand) = String(WearCommandCodec.encode(command), Charsets.UTF_8)

    private fun decodeLikeThePhone(text: String) = WidgetJson.json.decodeFromString(WidgetCommand.serializer(), text)

    @Test
    fun aCommandWithoutArgumentsHasAnEmptyArgumentMap() {
        assertThat(wire(WearCommands.logNextSet())).isEqualTo("""{"name":"logNextSet","args":{}}""")
        assertThat(wire(WearCommands.skipRest())).isEqualTo("""{"name":"skipRest","args":{}}""")
        assertThat(wire(WearCommands.startNext())).isEqualTo("""{"name":"startNext","args":{}}""")
    }

    @Test
    fun argumentsTravelAsTextUnderTheirProtocolNames() {
        assertThat(wire(WearCommands.adjustRest(15))).isEqualTo("""{"name":"adjustRest","args":{"seconds":"15"}}""")
        assertThat(wire(WearCommands.adjustRest(-15))).isEqualTo("""{"name":"adjustRest","args":{"seconds":"-15"}}""")
        assertThat(wire(WearCommands.nudge(1, -1))).isEqualTo("""{"name":"nudge","args":{"weightSteps":"1","repsSteps":"-1"}}""")
    }

    @Test
    fun everyCommandOfTheWatchRoundTripsThroughTheProtocol() {
        val commands = listOf(
            WearCommands.startNext(),
            WearCommands.logNextSet(),
            WearCommands.nudge(-1, 0),
            WearCommands.nudge(0, 1),
            WearCommands.adjustRest(15),
            WearCommands.adjustRest(-15),
            WearCommands.skipRest(),
            WearCommands.pause(),
            WearCommands.resume(),
            WearCommands.finish(),
        )

        commands.forEach { command -> assertThat(decodeLikeThePhone(wire(command))).isEqualTo(command) }
    }

    @Test
    fun theNamesAreTheOnesOfTheCommandVocabulary() {
        assertThat(
            listOf(
                WearCommands.startNext(),
                WearCommands.logNextSet(),
                WearCommands.nudge(1, 1),
                WearCommands.adjustRest(15),
                WearCommands.skipRest(),
                WearCommands.pause(),
                WearCommands.resume(),
                WearCommands.finish(),
            ).map { it.name },
        ).containsExactly(
            WidgetCommands.START_NEXT,
            WidgetCommands.LOG_NEXT_SET,
            WidgetCommands.NUDGE,
            WidgetCommands.ADJUST_REST,
            WidgetCommands.SKIP_REST,
            WidgetCommands.PAUSE,
            WidgetCommands.RESUME,
            WidgetCommands.FINISH,
        ).inOrder()
    }

    @Test
    fun theRestStepIsFifteenSeconds() {
        assertThat(WearCommands.REST_STEP_SECONDS).isEqualTo(15)
    }
}
