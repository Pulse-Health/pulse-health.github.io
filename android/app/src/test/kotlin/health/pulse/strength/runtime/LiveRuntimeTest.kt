package health.pulse.strength.runtime

import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.PulseStrengthApplication
import health.pulse.strength.core.ActionOrigin
import health.pulse.strength.core.FileStrengthPersistence
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.core.StrengthConfig
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutController
import health.pulse.strength.core.WorkoutSideEffect
import health.pulse.strength.core.WorkoutState
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.core.widgets.WidgetContext
import health.pulse.strength.core.widgets.WidgetSnapshotBuilder
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * The runtime of the running app against a store with the demo data and a workout controller on a clock the test moves: the commands
 * change the workout and the snapshot follows, a change anywhere else (store, goal, clock, heart rate) is picked up, and the surfaces
 * are refreshed once per burst of changes. The coroutines run on a test dispatcher, so time is virtual.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LiveRuntimeTest {
    private lateinit var app: PulseStrengthApplication
    private lateinit var store: StrengthStore
    private lateinit var controller: WorkoutController
    private var time: Instant = Instant.parse("2026-10-16T09:41:00Z")
    private val goal = MutableStateFlow(WidgetContext.defaultWeeklyGoal)

    /** Every action the controller applied, with its origin. */
    private val applied = mutableListOf<Pair<WorkoutAction, ActionOrigin>>()
    private val refreshes = mutableListOf<Instant>()
    private val runtimes = mutableListOf<LiveRuntime>()

    @Before
    fun setUp() {
        app = ApplicationProvider.getApplicationContext<Application>() as PulseStrengthApplication
        val persistence = FileStrengthPersistence.temporary()
        store = StrengthStore(persistence, seedDemoData = true, now = time)
        controller = WorkoutController(store, persistence, clock = { time })
        controller.addEffect(
            object : WorkoutSideEffect {
                override fun workoutChanged(old: WorkoutState, new: WorkoutState, action: WorkoutAction, origin: ActionOrigin) {
                    applied += action to origin
                }
            },
        )
    }

    @After
    fun tearDown() {
        runtimes.forEach { it.close() }
        StrengthRuntime.installForTest(PreviewRuntime())
    }

    private fun TestScope.runtime(
        zone: () -> ZoneId = { ZoneOffset.UTC },
        main: CoroutineDispatcher = UnconfinedTestDispatcher(testScheduler),
        refresh: suspend (Context) -> Unit = { refreshes += time },
    ): LiveRuntime {
        val compute = UnconfinedTestDispatcher(testScheduler)
        return LiveRuntime(app, store, controller, goal, clock = { time }, zone = zone, compute = compute, main = main, refreshSurfaces = refresh)
            .also { runtimes += it }
    }

    private fun actions(): List<WorkoutAction> = applied.map { it.first }

    // region The first snapshot

    @Test
    fun theFirstSnapshotIsBuiltFromTheStoreTheGoalAndTheClock() = runTest {
        val runtime = runtime()
        val expected = WidgetSnapshotBuilder.make(store.data.value, WidgetContext(weeklyGoal = 4, zone = ZoneOffset.UTC), time)
        assertThat(runtime.snapshots.current()).isEqualTo(expected)
        assertThat(runtime.snapshots.current().nextUp?.name).isEqualTo("Upper A · Push")
        assertThat(runtime.snapshots.current().active).isNull()
    }

    @Test
    fun aWorkoutThatIsRunningAtStartIsInTheFirstSnapshot() = runTest {
        controller.startWorkout(null, "Restored")
        val runtime = runtime()
        assertThat(runtime.snapshots.current().active?.workoutName).isEqualTo("Restored")
    }

    // endregion

    // region Starting

    @Test
    fun startNextStartsTheNextTemplateAndTheSnapshotShowsItWhenTheCommandReturns() = runTest {
        val runtime = runtime()
        val next = runtime.snapshots.current().nextUp!!
        runtime.commands.startNext()
        val state = controller.state.value!!
        assertThat(state.name).isEqualTo(next.name)
        assertThat(state.templateID.toString()).isEqualTo(next.templateID)
        val active = runtime.snapshots.current().active!!
        assertThat(active.workoutID).isEqualTo(state.id)
        assertThat(active.phase).isEqualTo(SnapshotPhase.LOGGING)
    }

    @Test
    fun startNextWithoutTemplatesStartsAnEmptyWorkout() = runTest {
        val emptyStore = StrengthStore(null)
        val emptyController = WorkoutController(emptyStore, null, clock = { time })
        val runtime = LiveRuntime(
            app, emptyStore, emptyController, goal, clock = { time }, zone = { ZoneOffset.UTC },
            compute = UnconfinedTestDispatcher(testScheduler), main = UnconfinedTestDispatcher(testScheduler), refreshSurfaces = {},
        ).also { runtimes += it }
        runtime.commands.startNext()
        assertThat(emptyController.state.value?.name).isEqualTo(StrengthConfig.defaultWorkoutName)
        assertThat(runtime.snapshots.current().active?.workoutName).isEqualTo(StrengthConfig.defaultWorkoutName)
    }

    @Test
    fun startNextWhileAWorkoutRunsChangesNothing() = runTest {
        val runtime = runtime()
        runtime.commands.startEmpty("Mine")
        runtime.commands.startNext()
        assertThat(controller.state.value?.name).isEqualTo("Mine")
    }

    @Test
    fun startTemplateStartsThatTemplateAndIgnoresUnknownAndDamagedIds() = runTest {
        val runtime = runtime()
        runtime.commands.startTemplate("not an id")
        runtime.commands.startTemplate(UUID.randomUUID().toString())
        assertThat(controller.state.value).isNull()

        val chosen = store.templates[1]
        runtime.commands.startTemplate(chosen.id.toString())
        assertThat(controller.state.value?.name).isEqualTo(chosen.name)
        assertThat(runtime.snapshots.current().active?.workoutName).isEqualTo(chosen.name)

        runtime.commands.startTemplate(store.templates[2].id.toString())
        assertThat(controller.state.value?.name).isEqualTo(chosen.name)
    }

    @Test
    fun startEmptyNamesTheWorkoutAndFallsBackToTheDefaultName() = runTest {
        val runtime = runtime()
        runtime.commands.startEmpty("Mobility")
        assertThat(controller.state.value?.name).isEqualTo("Mobility")
        assertThat(runtime.snapshots.current().active?.workoutName).isEqualTo("Mobility")
        controller.discard()
        runtime.commands.startEmpty("   ")
        assertThat(controller.state.value?.name).isEqualTo(StrengthConfig.defaultWorkoutName)
    }

    // endregion

    // region The workout buttons

    @Test
    fun logNextSetLogsTheSetAndTheSnapshotRests() = runTest {
        val runtime = runtime()
        runtime.commands.startNext()
        runtime.commands.logNextSet()
        assertThat(controller.state.value!!.exercises.sumOf { entry -> entry.sets.count { it.isDone } }).isEqualTo(1)
        val active = runtime.snapshots.current().active!!
        assertThat(active.loggedSets).isEqualTo(1)
        assertThat(active.phase).isEqualTo(SnapshotPhase.RESTING)
        assertThat(active.restEndsAt).isNotNull()
    }

    @Test
    fun theButtonsSendTheActionsOfTheNotificationButtonsWithTheirLimits() = runTest {
        val runtime = runtime()
        runtime.commands.startNext()
        runtime.commands.logNextSet()
        runtime.commands.adjustRest(15)
        runtime.commands.adjustRest(500)
        runtime.commands.adjustRest(-500)
        runtime.commands.skipRest()
        runtime.commands.nudge(1, 0)
        runtime.commands.nudge(9, -9)
        runtime.commands.pause()
        runtime.commands.resume()
        assertThat(applied).containsExactly(
            WorkoutAction.LogNextSet to ActionOrigin.LIVE_ACTIVITY,
            WorkoutAction.AdjustRest(15) to ActionOrigin.LIVE_ACTIVITY,
            WorkoutAction.AdjustRest(60) to ActionOrigin.LIVE_ACTIVITY,
            WorkoutAction.AdjustRest(-60) to ActionOrigin.LIVE_ACTIVITY,
            WorkoutAction.SkipRest to ActionOrigin.LIVE_ACTIVITY,
            WorkoutAction.NudgeNextSet(1, 0) to ActionOrigin.LIVE_ACTIVITY,
            WorkoutAction.NudgeNextSet(1, -1) to ActionOrigin.LIVE_ACTIVITY,
            WorkoutAction.Pause to ActionOrigin.LIVE_ACTIVITY,
            WorkoutAction.Resume to ActionOrigin.LIVE_ACTIVITY,
        ).inOrder()
    }

    @Test
    fun pauseAndResumeAreInTheSnapshot() = runTest {
        val runtime = runtime()
        runtime.commands.startNext()
        runtime.commands.pause()
        assertThat(runtime.snapshots.current().active?.isPaused).isTrue()
        runtime.commands.resume()
        assertThat(runtime.snapshots.current().active?.isPaused).isFalse()
    }

    @Test
    fun logSetLogsTheSetOfThoseIdsAndIgnoresDamagedOnes() = runTest {
        val runtime = runtime()
        runtime.commands.startNext()
        val target = runtime.snapshots.current().active!!
        runtime.commands.logSet("not an id", target.targetSetID.toString())
        runtime.commands.logSet(target.targetExerciseID.toString(), "")
        assertThat(applied).isEmpty()

        runtime.commands.logSet(target.targetExerciseID.toString(), target.targetSetID.toString())
        assertThat(applied).containsExactly(WorkoutAction.LogSet(target.targetExerciseID!!, target.targetSetID!!) to ActionOrigin.LIVE_ACTIVITY)
        assertThat(runtime.snapshots.current().active?.loggedSets).isEqualTo(1)
    }

    @Test
    fun applyCoachTipSetsTheWeightOfTheSetItNames() = runTest {
        val runtime = runtime()
        runtime.commands.startNext()
        runtime.commands.logNextSet()
        val target = runtime.snapshots.current().active!!
        val setId = target.targetSetID!!
        val before = applied.size

        runtime.commands.applyCoachTip(setId.toString(), 0.0)
        runtime.commands.applyCoachTip(setId.toString(), Double.NaN)
        runtime.commands.applyCoachTip(setId.toString(), -5.0)
        runtime.commands.applyCoachTip(UUID.randomUUID().toString(), 90.0)
        runtime.commands.applyCoachTip("nope", 90.0)
        assertThat(applied.size).isEqualTo(before)

        runtime.commands.applyCoachTip(setId.toString(), 92.5)
        assertThat(applied.last()).isEqualTo(WorkoutAction.SetWeight(target.targetExerciseID!!, setId, 92.5) to ActionOrigin.LIVE_ACTIVITY)
        val set = controller.state.value!!.exercises.flatMap { it.sets }.first { it.id == setId }
        assertThat(set.weightKg).isEqualTo(92.5)
    }

    // endregion

    // region primaryAction

    @Test
    fun primaryActionStartsLogsAndSkipsAccordingToTheWorkout() = runTest {
        val runtime = runtime()
        runtime.commands.primaryAction()
        assertThat(controller.state.value).isNotNull()
        runtime.commands.primaryAction()
        runtime.commands.primaryAction()
        runtime.commands.primaryAction()
        assertThat(actions()).containsExactly(WorkoutAction.LogNextSet, WorkoutAction.SkipRest, WorkoutAction.LogNextSet).inOrder()
    }

    @Test
    fun primaryActionKnowsThatARestIsOverBeforeTheSnapshotSaysSo() = runTest {
        val runtime = runtime()
        runtime.commands.startNext()
        runtime.commands.logNextSet()
        val rest = runtime.snapshots.current().active!!.restTotalSeconds
        time = time.plusSeconds(rest + 1L)
        assertThat(runtime.snapshots.current().active?.phase).isEqualTo(SnapshotPhase.RESTING)

        runtime.commands.primaryAction()
        assertThat(actions()).containsExactly(WorkoutAction.LogNextSet, WorkoutAction.LogNextSet).inOrder()
    }

    // endregion

    // region Finishing

    @Test
    fun finishRecordsTheWorkoutAndTheSnapshotFollows() = runTest {
        val runtime = runtime()
        val completedBefore = runtime.snapshots.current().week.completed
        val historyBefore = store.history.size
        runtime.commands.startNext()
        runtime.commands.logNextSet()
        val name = controller.state.value!!.name

        runtime.commands.finish()
        assertThat(controller.state.value).isNull()
        assertThat(store.history.size).isEqualTo(historyBefore + 1)
        val snapshot = runtime.snapshots.current()
        assertThat(snapshot.active).isNull()
        assertThat(snapshot.lastSession?.name).isEqualTo(name)
        assertThat(snapshot.week.completed).isEqualTo(completedBefore + 1)
    }

    @Test
    fun finishWithoutALoggedSetRecordsNothing() = runTest {
        val runtime = runtime()
        val historyBefore = store.history.size
        runtime.commands.startNext()
        runtime.commands.finish()
        assertThat(controller.state.value).isNull()
        assertThat(store.history.size).isEqualTo(historyBefore)
        assertThat(runtime.snapshots.current().active).isNull()
    }

    @Test
    fun theCommandsChangeTheWorkoutOnTheMainDispatcher() = runTest {
        var dispatched = 0
        val main = object : CoroutineDispatcher() {
            override fun dispatch(context: CoroutineContext, block: Runnable) {
                dispatched++
                block.run()
            }
        }
        val runtime = runtime(main = main)
        runtime.commands.startNext()
        assertThat(dispatched).isEqualTo(1)
        runtime.commands.logNextSet()
        assertThat(dispatched).isEqualTo(2)
    }

    // endregion

    // region What changes the snapshot

    @Test
    fun theSnapshotFollowsTheStore() = runTest {
        val runtime = runtime()
        store.saveTemplate(WorkoutTemplate(name = "Mobility", entries = emptyList()))
        assertThat(runtime.snapshots.current().templates.map { it.name }).contains("Mobility")
    }

    @Test
    fun theSnapshotFollowsTheWeeklyGoalWithinOneAndSeven() = runTest {
        val runtime = runtime()
        goal.value = 6
        assertThat(runtime.snapshots.current().week.goal).isEqualTo(6)
        goal.value = 12
        assertThat(runtime.snapshots.current().week.goal).isEqualTo(7)
        goal.value = 0
        assertThat(runtime.snapshots.current().week.goal).isEqualTo(1)
    }

    @Test
    fun heartRateReadingsReachTheSnapshotAtMostEveryTenSeconds() = runTest {
        val runtime = runtime()
        runtime.commands.startNext()
        fun heartRate(): Int? = runtime.snapshots.current().active?.heartRate

        controller.send(WorkoutAction.UpdateHeartRate(120))
        assertThat(heartRate()).isEqualTo(120)
        time = time.plusSeconds(3)
        controller.send(WorkoutAction.UpdateHeartRate(130))
        assertThat(heartRate()).isEqualTo(120)
        time = time.plusSeconds(8)
        controller.send(WorkoutAction.UpdateHeartRate(140))
        assertThat(heartRate()).isEqualTo(140)

        // A change that is not a reading brings the latest reading with it.
        time = time.plusSeconds(1)
        controller.send(WorkoutAction.UpdateHeartRate(150))
        assertThat(heartRate()).isEqualTo(140)
        runtime.commands.logNextSet()
        assertThat(heartRate()).isEqualTo(150)
    }

    @Test
    fun whenARestEndsThePhaseTurnsToRestOverWithoutAnyOtherChange() = runTest {
        val runtime = runtime()
        runtime.commands.startNext()
        runtime.commands.logNextSet()
        val rest = runtime.snapshots.current().active!!.restTotalSeconds
        assertThat(runtime.snapshots.current().active?.phase).isEqualTo(SnapshotPhase.RESTING)

        time = time.plusSeconds(rest + 1L)
        advanceTimeBy(rest * 1_000L - 1)
        runCurrent()
        assertThat(runtime.snapshots.current().active?.phase).isEqualTo(SnapshotPhase.RESTING)

        advanceTimeBy(200)
        runCurrent()
        assertThat(runtime.snapshots.current().active?.phase).isEqualTo(SnapshotPhase.REST_OVER)
    }

    @Test
    fun aPausedRestDoesNotEnd() = runTest {
        val runtime = runtime()
        runtime.commands.startNext()
        runtime.commands.logNextSet()
        runtime.commands.pause()
        val rest = runtime.snapshots.current().active!!.restTotalSeconds

        time = time.plusSeconds(rest + 1L)
        advanceTimeBy((rest + 1) * 1_000L)
        runCurrent()
        assertThat(runtime.snapshots.current().active?.phase).isEqualTo(SnapshotPhase.RESTING)
    }

    @Test
    fun theDateTheTimeAndTheTimeZoneBeingSetRebuildTheSnapshot() = runTest {
        var zone: ZoneId = ZoneOffset.UTC
        val runtime = runtime(zone = { zone })
        fun todayIndex(): Int = runtime.snapshots.current().week.days.indexOfFirst { it.isToday }
        assertThat(todayIndex()).isEqualTo(4)

        time = Instant.parse("2026-10-17T00:05:00Z")
        app.sendBroadcast(Intent(Intent.ACTION_DATE_CHANGED))
        shadowOf(Looper.getMainLooper()).idle()
        assertThat(runtime.snapshots.current().generatedAt).isEqualTo(time)
        assertThat(todayIndex()).isEqualTo(5)

        zone = ZoneId.of("Pacific/Auckland")
        app.sendBroadcast(Intent(Intent.ACTION_TIMEZONE_CHANGED))
        shadowOf(Looper.getMainLooper()).idle()
        assertThat(runtime.snapshots.current().timeZoneID).isEqualTo("Pacific/Auckland")

        time = time.plusSeconds(3_600)
        app.sendBroadcast(Intent(Intent.ACTION_TIME_CHANGED))
        shadowOf(Looper.getMainLooper()).idle()
        assertThat(runtime.snapshots.current().generatedAt).isEqualTo(time)
    }

    // endregion

    // region Closing

    /** The receivers of the runtimes in the application's registrations, newest last. */
    private fun runtimeReceivers() = shadowOf(app).registeredReceivers
        .map { it.broadcastReceiver }
        .filter { it.javaClass.name.startsWith("health.pulse.strength.runtime.LiveRuntime") }

    @Test
    fun aRuntimeThatWasClosedStopsFollowingAndUnregistersItsReceiverAtOnce() = runTest {
        val runtime = runtime()
        val registered = runtimeReceivers().size
        runtime.close()
        assertThat(runtimeReceivers()).hasSize(registered - 1)

        goal.value = 7
        time = Instant.parse("2026-10-17T00:05:00Z")
        app.sendBroadcast(Intent(Intent.ACTION_DATE_CHANGED))
        shadowOf(Looper.getMainLooper()).idle()
        assertThat(runtime.snapshots.current().week.goal).isEqualTo(4)
        assertThat(runtime.snapshots.current().generatedAt).isNotEqualTo(time)
    }

    @Test
    fun closingTwiceIsFine() = runTest {
        val runtime = runtime()
        runtime.close()
        runtime.close()
    }

    @Test
    fun closingARuntimeWhoseReceiverIsAlreadyGoneIsFine() = runTest {
        val runtime = runtime()
        // What a context that was torn down meanwhile has done to the registration.
        app.unregisterReceiver(runtimeReceivers().last())
        runtime.close()
    }

    // endregion

    // region rebuild

    @Test
    fun rebuildPublishesTheSnapshotOfTheCurrentTimeWithoutRefreshingTheSurfacesItself() = runTest {
        val runtime = runtime()
        time = Instant.parse("2026-10-17T00:05:00Z")
        runtime.rebuild()
        assertThat(runtime.snapshots.current().generatedAt).isEqualTo(time)
        assertThat(refreshes).isEmpty()
    }

    @Test
    fun aRebuildThatShowsNothingNewDoesNotRefreshTheSurfacesLater() = runTest {
        val runtime = runtime()
        time = time.plusSeconds(300)
        runtime.rebuild()
        advanceTimeBy(1_001)
        assertThat(runtime.snapshots.current().generatedAt).isEqualTo(time)
        assertThat(refreshes).isEmpty()
    }

    @Test
    fun aRebuildOnAnotherDayRefreshesTheSurfacesLater() = runTest {
        val runtime = runtime()
        time = Instant.parse("2026-10-17T00:05:00Z")
        runtime.rebuild()
        advanceTimeBy(999)
        assertThat(refreshes).isEmpty()
        advanceTimeBy(2)
        assertThat(refreshes).hasSize(1)
    }

    @Test
    fun theFacadeRebuildsTheInstalledRuntime() = runTest {
        val runtime = runtime()
        StrengthRuntime.installForTest(runtime)
        time = time.plusSeconds(600)
        StrengthRuntime.rebuild()
        assertThat(StrengthRuntime.snapshots.current().generatedAt).isEqualTo(time)
    }

    @Test
    fun aRuntimeWithoutAClockHasNothingToRebuild() = runTest {
        StrengthRuntime.installForTest(PreviewRuntime())
        val before = StrengthRuntime.snapshots.current()
        StrengthRuntime.rebuild()
        assertThat(StrengthRuntime.snapshots.current()).isSameInstanceAs(before)
    }

    // endregion

    // region Refreshing the surfaces

    @Test
    fun theSurfacesAreNotRefreshedForTheSnapshotOfTheStart() = runTest {
        runtime()
        advanceTimeBy(60_000)
        assertThat(refreshes).isEmpty()
    }

    @Test
    fun aBurstOfChangesRefreshesTheSurfacesOnceAfterTheDelay() = runTest {
        val runtime = runtime()
        runtime.commands.startNext()
        runtime.commands.logNextSet()
        runtime.commands.adjustRest(15)
        advanceTimeBy(999)
        assertThat(refreshes).isEmpty()
        advanceTimeBy(2)
        assertThat(refreshes).hasSize(1)

        runtime.commands.skipRest()
        advanceTimeBy(999)
        assertThat(refreshes).hasSize(1)
        advanceTimeBy(2)
        assertThat(refreshes).hasSize(2)
    }

    @Test
    fun aChangeThatIsUndoneBeforeTheDelayRefreshesNothing() = runTest {
        val runtime = runtime()
        goal.value = 6
        goal.value = WidgetContext.defaultWeeklyGoal
        advanceTimeBy(60_000)
        assertThat(runtime.snapshots.current().week.goal).isEqualTo(WidgetContext.defaultWeeklyGoal)
        assertThat(refreshes).isEmpty()
    }

    @Test
    fun aChangeThatShowsNothingNewPublishesAndRefreshesNothing() = runTest {
        val runtime = runtime()
        runtime.commands.startNext()
        advanceTimeBy(1_001)
        val published = runtime.snapshots.current()
        refreshes.clear()

        // The note is part of the workout (its revision grows) but not of anything a surface shows.
        val exercise = controller.state.value!!.exercises.first()
        controller.send(WorkoutAction.SetNote(exercise.id, "Slow eccentric"))
        advanceTimeBy(1_001)
        assertThat(controller.state.value!!.revision).isGreaterThan(published.active!!.revision)
        assertThat(runtime.snapshots.current()).isSameInstanceAs(published)
        assertThat(refreshes).isEmpty()
    }

    @Test
    fun aSurfaceThatFailsToRefreshDoesNotStopTheNextRefresh() = runTest {
        var attempts = 0
        val runtime = runtime(refresh = {
            attempts++
            if (attempts == 1) throw IllegalStateException("the widget host is gone")
        })
        runtime.commands.startNext()
        advanceTimeBy(1_001)
        assertThat(attempts).isEqualTo(1)

        runtime.commands.logNextSet()
        advanceTimeBy(1_001)
        assertThat(attempts).isEqualTo(2)
    }

    @Test
    fun aRefreshThatFailedIsTriedAgainWithTheNextPublicationEvenForTheSameContent() = runTest {
        var attempts = 0
        val runtime = runtime(refresh = {
            attempts++
            if (attempts == 1) throw IllegalStateException("the widget host is gone")
        })
        runtime.commands.startNext()
        advanceTimeBy(1_001)
        assertThat(attempts).isEqualTo(1)

        time = time.plusSeconds(60)
        runtime.rebuild()
        advanceTimeBy(1_001)
        assertThat(attempts).isEqualTo(2)

        time = time.plusSeconds(60)
        runtime.rebuild()
        advanceTimeBy(1_001)
        assertThat(attempts).isEqualTo(2)
    }

    // endregion

    // region Failures

    @Test
    fun aSnapshotThatCannotBeBuiltLeavesTheLastOneAndTheNextChangeRecovers() = runTest {
        var broken = false
        val runtime = runtime(zone = { if (broken) throw IllegalStateException("no zone") else ZoneOffset.UTC })
        broken = true
        goal.value = 6
        assertThat(runtime.snapshots.current().week.goal).isEqualTo(4)

        broken = false
        goal.value = 5
        assertThat(runtime.snapshots.current().week.goal).isEqualTo(5)
    }

    // endregion

    // region The running app

    @Test
    fun theFactoryBuildsALiveRuntimeAroundTheEnvironmentOfTheApplication() {
        val runtime = RuntimeFactory.create(app)
        assertThat(runtime).isInstanceOf(LiveRuntime::class.java)
        runtimes += runtime as LiveRuntime

        runBlocking { runtime.commands.startEmpty("Push day") }
        assertThat(app.environment.controller.state.value?.name).isEqualTo("Push day")
        assertThat(runtime.snapshots.current().active?.workoutName).isEqualTo("Push day")

        val settings = checkNotNull(app.environment.services).settings
        settings.setWeeklyGoal(6)
        val snapshot = runBlocking { withTimeout(10_000) { runtime.snapshots.snapshot.first { it.week.goal == 6 } } }
        assertThat(snapshot.active?.workoutName).isEqualTo("Push day")
    }

    // endregion
}
