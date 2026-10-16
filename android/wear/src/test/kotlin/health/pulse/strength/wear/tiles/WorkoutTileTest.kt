package health.pulse.strength.wear.tiles

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.widgets.WidgetCommand
import health.pulse.strength.core.widgets.WidgetCommands
import health.pulse.strength.core.widgets.WidgetJson
import health.pulse.strength.wear.WearFixtures
import health.pulse.strength.wear.WearFixtures.now
import health.pulse.strength.wear.data.FakePhoneLink
import health.pulse.strength.wear.data.WearCommands
import health.pulse.strength.wear.data.WearRuntime
import health.pulse.strength.wear.data.WearView
import health.pulse.strength.wear.sync.SnapshotIngest
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** WA-04 Log set (double tap) and WA-05 Rest: the one tile that follows the running workout. */
@RunWith(RobolectricTestRunner::class)
class WorkoutTileTest {
    private val context = ApplicationProvider.getApplicationContext<Application>()
    private val ui = tileUi(context)
    private val tile = WorkoutTile()
    private val link = FakePhoneLink()

    @Before
    fun setUp() {
        TileClicks.clear()
        SnapshotIngest.resetForTest()
        WearRuntime.installForTest(null, link)
    }

    @After
    fun tearDown() {
        WearRuntime.resetForTest()
        SnapshotIngest.resetForTest()
        TileClicks.clear()
    }

    private fun plan(view: WearView) = tile.plan(ui, view, now)

    private fun single(view: WearView): LayoutInspector {
        val plan = plan(view)
        assertThat(plan.timeline.timelineEntries).hasSize(1)
        return plan.entries().single().second.inspect()
    }

    private fun logging() = WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout()))

    private fun resting() = WearFixtures.view(WearFixtures.withWorkout(WearFixtures.resting(seconds = 84, total = 120)))

    // region Logging

    @Test
    fun loggingShowsTheSetTheExerciseAndWhatToLift() {
        val inspected = single(logging())

        assertThat(inspected.textValues).containsAtLeast("Set 3 of 4", "Bench Press", "80 kg × 6", "Log set")
    }

    @Test
    fun theLogSetChipIsTheFirstClickableSoTheDoubleTapGestureTriggersIt() {
        val clicks = single(logging()).clicks

        assertThat(clicks).hasSize(1)
        assertThat(clicks.first().kind).isEqualTo(LayoutInspector.Kind.LOAD)
        assertThat(TileClicks.actionOf(clicks.first().id)).isEqualTo(WorkoutTile.ACTION_LOG)
    }

    @Test
    fun theLogSetChipIsDescribedWithTheSetItLogs() {
        assertThat(single(logging()).descriptions).contains("Log set. Bench Press, Set 3 of 4, 80 kg × 6")
    }

    @Test
    fun theLogSetChipCarriesTheTappingHandGlyph() {
        assertThat(single(logging()).images).contains(TileIcons.HAND)
    }

    @Test
    fun repsOnlyAndTimedExercisesReadAsRepsAndSeconds() {
        val reps = WearFixtures.workout(tracking = health.pulse.strength.core.TrackingKind.REPS_ONLY, showsWeight = false)
        val timed = WearFixtures.workout(tracking = health.pulse.strength.core.TrackingKind.DURATION, showsWeight = false)

        assertThat(single(WearFixtures.view(WearFixtures.withWorkout(reps))).textValues).contains("6 reps")
        assertThat(single(WearFixtures.view(WearFixtures.withWorkout(timed))).textValues).contains("6 s")
    }

    @Test
    fun aVeryLongExerciseNameStaysInTheLayout() {
        val name = "Single-Arm Cable Crossover with Rotational Finish"
        val snapshot = WearFixtures.withWorkout(WearFixtures.workout(exerciseName = name))

        assertThat(single(WearFixtures.view(snapshot)).textValues).contains(name)
    }

    @Test
    fun aLoggingTileIsRefreshedEveryHalfHour() {
        val plan = plan(logging())

        assertThat(plan.freshnessMillis).isEqualTo(30 * 60 * 1000L)
    }

    // endregion

    // region Resting

    @Test
    fun restingHasTwoLayoutsTheCountdownUntilTheEndAndThenTheLogSetPage() {
        val entries = plan(resting()).entries()

        assertThat(entries).hasSize(2)
        val (countdownValidity, countdown) = entries[0]
        val (afterValidity, after) = entries[1]
        assertThat(countdownValidity!!.endMillis).isEqualTo(now.plusSeconds(84).toEpochMilli())
        assertThat(afterValidity).isNull()
        assertThat(countdown.inspect().textValues).contains("Skip")
        assertThat(after.inspect().textValues).containsAtLeast("Rest over", "Log set")
    }

    @Test
    fun theRestCountdownIsDrawnByTheRendererWithAStaticFallback() {
        val countdown = plan(resting()).entries()[0].second.inspect()

        val clock = countdown.texts.single { it.isDynamic }
        assertThat(clock.value).isEqualTo("1:24")
    }

    @Test
    fun restingNamesTheNextSetAndOffersSkipBeforeAddFifteenSeconds() {
        val countdown = plan(resting()).entries()[0].second.inspect()

        assertThat(countdown.textValues).containsAtLeast("Next · 80 kg × 6", "Skip", "+15 s")
        // Skip is first: a double tap skips the rest, the same meaning primaryAction has everywhere.
        assertThat(countdown.clicks.map { TileClicks.actionOf(it.id) }).containsExactly(WorkoutTile.ACTION_SKIP_REST, WorkoutTile.ACTION_ADD_REST).inOrder()
        assertThat(countdown.descriptions).containsAtLeast("Skip rest", "Add 15 seconds to the rest")
    }

    @Test
    fun theRestOverPageIsTheLogSetPageWithTheLogChipFirst() {
        val after = plan(resting()).entries()[1].second.inspect()

        assertThat(TileClicks.actionOf(after.clicks.first().id)).isEqualTo(WorkoutTile.ACTION_LOG)
    }

    @Test
    fun aTileWithALiveCountdownIsRefreshedEveryMinute() {
        assertThat(plan(resting()).freshnessMillis).isEqualTo(60 * 1000L)
    }

    @Test
    fun aRestThatAlreadyEndedShowsTheLogSetPageAlone() {
        val ended = WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout(phase = SnapshotPhase.RESTING, restEndsAt = now.minusSeconds(5))))

        val inspected = single(ended)

        assertThat(inspected.textValues).containsAtLeast("Rest over", "Log set")
    }

    // endregion

    // region Other states

    @Test
    fun pausedOffersResume() {
        val paused = WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout(isPaused = true, elapsedWhenPaused = 1480)))

        val inspected = single(paused)

        assertThat(inspected.textValues).containsAtLeast("Paused", "24:40 elapsed", "Resume")
        assertThat(TileClicks.actionOf(inspected.clicks.single().id)).isEqualTo(WorkoutTile.ACTION_RESUME)
    }

    @Test
    fun afterTheLastSetTheTileOpensTheAppToFinish() {
        val complete = WearFixtures.view(WearFixtures.withWorkout(WearFixtures.workout(phase = SnapshotPhase.COMPLETE, loggedSets = 20)))

        val inspected = single(complete)

        assertThat(inspected.textValues).containsAtLeast("All sets logged", "20 sets logged", "Open")
        assertThat(inspected.clicks.single().kind).isEqualTo(LayoutInspector.Kind.LAUNCH)
    }

    @Test
    fun withNoWorkoutTheTileOffersTheNextOneAndBeforeTheSyncItWaits() {
        assertThat(single(WearFixtures.view()).textValues).contains("Start")
        assertThat(single(WearFixtures.view(isPlaceholder = true)).textValues).contains("Waiting for your phone")
    }

    // endregion

    // region Clicks

    @Test
    fun eachClickableMapsToItsCommand() {
        assertThat(WorkoutTile.commandFor(WorkoutTile.ACTION_LOG)).isEqualTo(WearCommands.logNextSet())
        assertThat(WorkoutTile.commandFor(WorkoutTile.ACTION_SKIP_REST)).isEqualTo(WearCommands.skipRest())
        assertThat(WorkoutTile.commandFor(WorkoutTile.ACTION_ADD_REST)).isEqualTo(WearCommands.adjustRest(15))
        assertThat(WorkoutTile.commandFor(WorkoutTile.ACTION_RESUME)).isEqualTo(WearCommands.resume())
        assertThat(WorkoutTile.commandFor("open")).isNull()
        assertThat(WorkoutTile.commandFor("")).isNull()
    }

    private fun sentCommands(): List<WidgetCommand> =
        link.sent.map { (_, payload) -> WidgetJson.json.decodeFromString(WidgetCommand.serializer(), String(payload, Charsets.UTF_8)) }

    @Test
    fun aTapOnLogSetSendsOneLogNextSetToThePhone() = runTest {
        val service = org.robolectric.Robolectric.setupService(WorkoutTile::class.java)
        val clicked = TileClicks.clickableId(WorkoutTile.ACTION_LOG, "gen1")

        val tileForTheTap = service.respond(deviceParameters(), clicked)

        assertThat(sentCommands()).containsExactly(WidgetCommand.of(WidgetCommands.LOG_NEXT_SET))
        assertThat(tileForTheTap.timelineEntries()).isNotEmpty()
    }

    @Test
    fun theSameTapReportedAgainByALaterRequestDoesNotRunTheCommandAgain() = runTest {
        val service = org.robolectric.Robolectric.setupService(WorkoutTile::class.java)
        val clicked = TileClicks.clickableId(WorkoutTile.ACTION_ADD_REST, "gen1")

        service.respond(deviceParameters(), clicked)
        service.respond(deviceParameters(), clicked)

        assertThat(sentCommands()).containsExactly(WearCommands.adjustRest(15))
    }

    @Test
    fun aRequestWithoutAClickSendsNothing() = runTest {
        val service = org.robolectric.Robolectric.setupService(WorkoutTile::class.java)

        service.respond(deviceParameters(), "")

        assertThat(link.sent).isEmpty()
    }

    @Test
    fun aNewLayoutCarriesNewClickableIdsSoTheNextTapCounts() = runTest {
        val service = org.robolectric.Robolectric.setupService(WorkoutTile::class.java)

        val first = tile.plan(tileUi(context), logging(), now).entries().single().second.inspect().clicks.single().id
        val second = tile.plan(tileUi(context), logging(), now).entries().single().second.inspect().clicks.single().id
        service.respond(deviceParameters(), first)
        service.respond(deviceParameters(), second)

        assertThat(first).isNotEqualTo(second)
        assertThat(sentCommands()).hasSize(2)
    }

    // endregion
}
