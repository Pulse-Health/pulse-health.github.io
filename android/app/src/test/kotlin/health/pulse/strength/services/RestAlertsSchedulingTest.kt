package health.pulse.strength.services

import android.app.AlarmManager
import android.app.Application
import android.app.NotificationManager
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.ExerciseLibrary
import health.pulse.strength.core.FileStrengthPersistence
import health.pulse.strength.core.StrengthStore
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutController
import java.time.Instant
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager

/**
 * Which alarms a rest gets on each Android version (see the class comment of [RestAlerts]): an exact `PendingIntent` alarm before
 * Android 12, the "approaching" inexact alarm on 12-13 and the in-process listener alarm from 14 on, and how an alarm that fires
 * early is set again. Runs the real [RestAlerts] with a controllable clock.
 */
@RunWith(RobolectricTestRunner::class)
class RestAlertsSchedulingTest {
    private lateinit var app: Application
    private lateinit var alarmManager: AlarmManager
    private lateinit var notifications: NotificationManager

    private val start: Instant = Instant.parse("2026-03-02T17:00:00Z")
    private var wall: Instant = start
    private var elapsed = 5_000_000L

    private lateinit var controller: WorkoutController
    private lateinit var alerts: RestAlerts

    @Before
    fun setUp() {
        app = ApplicationProvider.getApplicationContext()
        shadowOf(app).grantPermissions(android.Manifest.permission.POST_NOTIFICATIONS)
        alarmManager = app.getSystemService(AlarmManager::class.java)
        notifications = app.getSystemService(NotificationManager::class.java)
        ShadowAlarmManager.reset()
        val persistence = FileStrengthPersistence.temporary()
        val store = StrengthStore(persistence, seedDemoData = false, usesLibraryHistory = false)
        controller = WorkoutController(store, persistence, clock = { wall })
        alerts = RestAlerts(app, controller, AppForegroundTracker(), PulseSettings(app), { elapsed }, { wall })
    }

    /** Logs the first set of a bench workout: a rest of [REST_SECONDS] starts at [wall] and the alerts are synced like the app does. */
    private fun startRest() {
        controller.startWorkout(null, "Push day")
        controller.send(WorkoutAction.AddExercises(listOf(ExerciseLibrary.exercise("bench")!!)))
        val entry = controller.state.value!!.exercises[0]
        controller.send(WorkoutAction.LogSet(entry.id, entry.sets[0].id))
        assertThat(controller.state.value!!.rest!!.totalSeconds).isEqualTo(REST_SECONDS)
        alerts.sync(controller.state.value)
    }

    private val scheduled get() = shadowOf(alarmManager).scheduledAlarms

    private fun advance(seconds: Double) {
        wall = wall.plusMillis((seconds * 1000).toLong())
        elapsed += (seconds * 1000).toLong()
    }

    private fun leadSeconds(alarm: ShadowAlarmManager.ScheduledAlarm) = (alarm.triggerAtMs - elapsed) / 1000.0

    @Test
    @Config(sdk = [29])
    fun beforeAndroid12AnExactPendingIntentAlarmIsUsed() {
        startRest()
        assertThat(scheduled).hasSize(1)
        val alarm = scheduled[0]
        assertThat(alarm.operation).isNotNull()
        assertThat(alarm.windowLengthMs).isEqualTo(ShadowAlarmManager.WINDOW_EXACT)
        assertThat(alarm.isAllowWhileIdle).isTrue()
        assertThat(leadSeconds(alarm)).isWithin(0.01).of(REST_SECONDS.toDouble())
    }

    @Test
    @Config(sdk = [33])
    fun onAndroid12And13TheApproachingAlarmEndsItsWindowAtTheEndOfTheRest() {
        startRest()
        // No listener alarm (it throws a SecurityException before Android 14) and no exact alarm (needs a permission the app lacks).
        assertThat(scheduled).hasSize(1)
        val alarm = scheduled[0]
        assertThat(alarm.operation).isNotNull()
        assertThat(alarm.onAlarmListener).isNull()
        assertThat(alarm.windowLengthMs).isEqualTo(ShadowAlarmManager.WINDOW_HEURISTIC)
        assertThat(alarm.isAllowWhileIdle).isTrue()
        // The system may deliver an inexact alarm up to 0.75 times its distance late: set at 1/1.75 of the rest, the latest delivery
        // is the end of the rest.
        val lead = leadSeconds(alarm)
        assertThat(lead).isWithin(0.01).of(REST_SECONDS / 1.75)
        assertThat(lead + 0.75 * lead).isWithin(0.01).of(REST_SECONDS.toDouble())
    }

    @Test
    @Config(sdk = [33])
    fun withTheExactAlarmPermissionOnAndroid13TheAlarmIsExact() {
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        startRest()
        assertThat(scheduled).hasSize(1)
        assertThat(scheduled[0].windowLengthMs).isEqualTo(ShadowAlarmManager.WINDOW_EXACT)
        assertThat(leadSeconds(scheduled[0])).isWithin(0.01).of(REST_SECONDS.toDouble())
    }

    @Test
    @Config(sdk = [34])
    fun fromAndroid14AnExactListenerAlarmComesFirstAndTheApproachingAlarmBacksItUp() {
        startRest()
        assertThat(scheduled).hasSize(2)
        val listener = scheduled.single { it.onAlarmListener != null }
        val backup = scheduled.single { it.operation != null }
        assertThat(listener.windowLengthMs).isEqualTo(ShadowAlarmManager.WINDOW_EXACT)
        assertThat(leadSeconds(listener)).isWithin(0.01).of(REST_SECONDS.toDouble())
        assertThat(backup.windowLengthMs).isEqualTo(ShadowAlarmManager.WINDOW_HEURISTIC)
        assertThat(leadSeconds(backup)).isWithin(0.01).of(REST_SECONDS / 1.75)
    }

    @Test
    @Config(sdk = [35])
    fun androidFifteenSchedulesTheSameAsFourteen() {
        startRest()
        assertThat(scheduled.map { it.onAlarmListener != null }).containsExactly(true, false)
    }

    @Test
    @Config(sdk = [33])
    fun anApproachingAlarmThatFiresEarlyIsSetAgainForWhatIsLeftAndTheLastOneAlerts() {
        startRest()
        val endsAt = controller.state.value!!.rest!!.endsAt.toEpochMilli()

        // The phone was awake anyway, so the system delivered the alarm at its trigger time: far before the end of the rest.
        advance(REST_SECONDS / 1.75)
        alerts.onAlarm(endsAt)
        assertThat(shadowOf(notifications).getNotification(WorkoutNotifications.REST_ALERT_ID)).isNull()
        assertThat(scheduled).hasSize(1)
        val remaining = REST_SECONDS - REST_SECONDS / 1.75
        assertThat(leadSeconds(scheduled[0])).isWithin(0.05).of(remaining / 1.75)

        // Closer than ten seconds Android does not fuzz an alarm any more, so the last one is set for the end itself.
        advance(remaining / 1.75)
        alerts.onAlarm(endsAt)
        advance(remaining - remaining / 1.75 - 8.0)
        alerts.onAlarm(endsAt)
        assertThat(scheduled).hasSize(1)
        assertThat(leadSeconds(scheduled[0])).isWithin(0.05).of(8.0)

        advance(8.1)
        alerts.onAlarm(endsAt)
        assertThat(shadowOf(notifications).getNotification(WorkoutNotifications.REST_ALERT_ID)).isNotNull()
    }

    @Test
    @Config(sdk = [33])
    fun theAlarmOfARestThatChangedIsIgnoredAndNothingStaysScheduledAfterTheRestEnds() {
        startRest()
        val staleEndsAt = controller.state.value!!.rest!!.endsAt.toEpochMilli()
        controller.send(WorkoutAction.AdjustRest(15))
        alerts.sync(controller.state.value)
        assertThat(scheduled).hasSize(1)
        assertThat(leadSeconds(scheduled[0])).isWithin(0.05).of((REST_SECONDS + 15) / 1.75)

        // An alarm of the old end time arrives: the rest is longer now, so it is not over.
        advance(REST_SECONDS.toDouble() + 1)
        alerts.onAlarm(staleEndsAt)
        assertThat(shadowOf(notifications).getNotification(WorkoutNotifications.REST_ALERT_ID)).isNull()

        controller.send(WorkoutAction.SkipRest)
        alerts.sync(controller.state.value)
        assertThat(scheduled).isEmpty()
    }

    @Test
    @Config(sdk = [33])
    fun theReceiverPassesTheAlarmToTheRunningApp() {
        val application = app as health.pulse.strength.PulseStrengthApplication
        val live = application.environment.controller
        live.startWorkout(null, "Push day")
        live.send(WorkoutAction.AddExercises(listOf(ExerciseLibrary.exercise("bench")!!)))
        val entry = live.state.value!!.exercises[0]
        live.send(WorkoutAction.LogSet(entry.id, entry.sets[0].id))
        val endsAt = live.state.value!!.rest!!.endsAt.toEpochMilli()
        // The receiver is what the system starts for the alarm; with the rest still running it must not alert yet, and must survive.
        RestAlarmReceiver().onReceive(app, Intent(RestAlarmReceiver.ACTION_REST_END).putExtra(RestAlarmReceiver.EXTRA_ENDS_AT, endsAt))
        assertThat(shadowOf(notifications).getNotification(WorkoutNotifications.REST_ALERT_ID)).isNull()
        RestAlarmReceiver().onReceive(app, Intent("another.action"))
    }

    private companion object {
        /** The default rest of the bench press in the library. */
        const val REST_SECONDS = 150
    }
}
