package health.pulse.strength.live

import android.Manifest
import android.app.AlarmManager
import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.DeepLinks
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.core.widgets.preview
import health.pulse.strength.runtime.PreviewRuntime
import health.pulse.strength.runtime.StrengthRuntime
import health.pulse.strength.surfaces.DayChange
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager

/** LA-06: a planned session arms two alarms, shows a countdown from 30 minutes before, says "Time to train", and ends with a workout. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PlannedSessionsTest {
    private lateinit var app: Application
    private lateinit var manager: NotificationManager
    private val templateId = WidgetSnapshot.preview.nextUp!!.templateID
    private val minute = 60_000L

    @Before
    fun setUp() {
        app = ApplicationProvider.getApplicationContext()
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        manager = app.getSystemService(NotificationManager::class.java)
        StrengthRuntime.installForTest(PreviewRuntime())
    }

    @After
    fun restore() {
        StrengthRuntime.installForTest(PreviewRuntime())
    }

    /** The alarms of the planned session: the midnight alarm that the application keeps for the widgets is not one of them. */
    private fun alarms() = shadowOf(app.getSystemService(AlarmManager::class.java)).scheduledAlarms
        .filter { actionOf(it) != DayChange.ACTION_MIDNIGHT }
    private fun store() = PlannedSessionStore(app.getSharedPreferences("pulse_planned_session", Context.MODE_PRIVATE))
    private fun countdown(): Notification? = shadowOf(manager).getNotification(CardKind.PLANNED.notificationId)
    private fun due(): Notification? = shadowOf(manager).getNotification(CardKind.PLANNED_DUE.notificationId)
    @Suppress("DEPRECATION") // Robolectric offers no other accessor than the field it deprecated
    private fun actionOf(alarm: ShadowAlarmManager.ScheduledAlarm) = shadowOf(alarm.operation).savedIntent.action

    @Test
    fun aSessionHoursAwayArmsTheCountdownAndTheStartAlarmAndShowsNothing() {
        val start = System.currentTimeMillis() + 3 * 60 * minute
        PlannedSessions.schedule(app, templateId, start)
        assertThat(store().read()).isEqualTo(PlannedSession(templateId, start))
        val byAction = alarms().associateBy { actionOf(it) }
        assertThat(byAction.keys).containsExactly(PlannedSessionReceiver.ACTION_COUNTDOWN, PlannedSessionReceiver.ACTION_DUE)
        assertThat(byAction.getValue(PlannedSessionReceiver.ACTION_COUNTDOWN).triggerAtMs).isEqualTo(start - 30 * minute)
        assertThat(byAction.getValue(PlannedSessionReceiver.ACTION_DUE).triggerAtMs).isEqualTo(start)
        // Inexact and allowed in Doze: no exact-alarm permission is needed.
        assertThat(alarms().all { it.isAllowWhileIdle }).isTrue()
        assertThat(countdown()).isNull()
    }

    @Test
    fun aSessionInsideTheLastHalfHourShowsTheCountdownAtOnce() {
        val start = System.currentTimeMillis() + 25 * minute
        PlannedSessions.schedule(app, templateId, start)
        val n = countdown()!!
        assertThat(n.extras.getCharSequence(Notification.EXTRA_TITLE).toString()).isEqualTo("Upper A · Push")
        assertThat(n.extras.getCharSequence(Notification.EXTRA_SUB_TEXT).toString()).startsWith("Planned ")
        assertThat(n.extras.getBoolean(Notification.EXTRA_SHOW_CHRONOMETER)).isTrue()
        assertThat(n.extras.getBoolean(Notification.EXTRA_CHRONOMETER_COUNT_DOWN)).isTrue()
        assertThat(n.`when`).isEqualTo(start)
        assertThat((n.actions ?: emptyArray()).map { it.title.toString() }).containsExactly("Start now", "Snooze 10 min").inOrder()
        assertThat(n.channelId).isEqualTo("workout_summary")
        assertThat(n.flags and Notification.FLAG_ONGOING_EVENT).isEqualTo(0)
        assertThat(n.timeoutAfter).isAtMost(25 * minute)
        assertThat(n.timeoutAfter).isGreaterThan(24 * minute)
        // Only the start alarm is left to arm.
        assertThat(alarms().map { actionOf(it) }).containsExactly(PlannedSessionReceiver.ACTION_DUE)
    }

    @Test
    fun startNowOpensTheTemplateAndSnoozeGoesToTheReceiver() {
        PlannedSessions.schedule(app, templateId, System.currentTimeMillis() + 25 * minute)
        val actions = countdown()!!.actions
        val start = shadowOf(actions[0].actionIntent).savedIntent
        assertThat(start.dataString).isEqualTo(DeepLinks.start(templateId))
        assertThat(start.component?.className).isEqualTo("health.pulse.strength.MainActivity")
        val snooze = shadowOf(actions[1].actionIntent).savedIntent
        assertThat(snooze.component?.className).isEqualTo(PlannedSessionReceiver::class.java.name)
        assertThat(snooze.action).isEqualTo(PlannedSessionReceiver.ACTION_SNOOZE)
        assertThat(snooze.getIntExtra(PlannedSessionReceiver.EXTRA_MINUTES, 0)).isEqualTo(10)
    }

    @Test
    fun snoozingMovesTheStartByTenMinutesAndDropsTheCountdownOutOfTheWindow() {
        val start = System.currentTimeMillis() + 25 * minute
        PlannedSessions.schedule(app, templateId, start)
        PlannedSessionReceiver().onReceive(app, Intent(PlannedSessionReceiver.ACTION_SNOOZE).putExtra(PlannedSessionReceiver.EXTRA_MINUTES, 10))
        assertThat(store().read()!!.startsAtMillis).isEqualTo(start + 10 * minute)
        // 35 minutes away: more than the 30 of the countdown, so the card goes and both alarms are armed.
        assertThat(countdown()).isNull()
        val byAction = alarms().associateBy { actionOf(it) }
        assertThat(byAction.getValue(PlannedSessionReceiver.ACTION_COUNTDOWN).triggerAtMs).isEqualTo(start + 10 * minute - 30 * minute)
        assertThat(byAction.getValue(PlannedSessionReceiver.ACTION_DUE).triggerAtMs).isEqualTo(start + 10 * minute)
    }

    @Test
    fun snoozingAfterTheStartCountsFromNow() {
        val now = System.currentTimeMillis()
        store().write(PlannedSession(templateId, now - 5 * minute))
        PlannedSessions.snooze(app)
        val moved = store().read()!!.startsAtMillis
        assertThat(moved).isAtLeast(now + 10 * minute)
        assertThat(moved).isLessThan(now + 11 * minute)
        assertThat(countdown()).isNotNull()
    }

    @Test
    fun theStartAlarmPostsTimeToTrainOnTheLoudChannel() {
        store().write(PlannedSession(templateId, System.currentTimeMillis() - minute))
        PlannedSessionReceiver().onReceive(app, Intent(PlannedSessionReceiver.ACTION_DUE))
        val n = due()!!
        assertThat(n.extras.getCharSequence(Notification.EXTRA_TITLE).toString()).isEqualTo("Time to train")
        assertThat(n.extras.getCharSequence(Notification.EXTRA_TEXT).toString()).isEqualTo("Upper A · Push")
        assertThat(n.channelId).isEqualTo("workout_reminder")
        assertThat(manager.getNotificationChannel("workout_reminder")!!.importance).isEqualTo(NotificationManager.IMPORTANCE_HIGH)
        assertThat(manager.getNotificationChannel("workout_summary")!!.importance).isEqualTo(NotificationManager.IMPORTANCE_LOW)
        assertThat(n.timeoutAfter).isEqualTo(2 * 60 * minute)
        assertThat((n.actions ?: emptyArray()).map { it.title.toString() }).containsExactly("Start now", "Snooze 10 min").inOrder()
    }

    @Test
    fun aLateCountdownAlarmDoesNotShowACountdownAfterTheStart() {
        store().write(PlannedSession(templateId, System.currentTimeMillis() - minute))
        PlannedSessionReceiver().onReceive(app, Intent(PlannedSessionReceiver.ACTION_COUNTDOWN))
        assertThat(countdown()).isNull()
        // And an alarm that comes too early (a plan that was moved meanwhile) shows no "Time to train".
        store().write(PlannedSession(templateId, System.currentTimeMillis() + 20 * minute))
        PlannedSessionReceiver().onReceive(app, Intent(PlannedSessionReceiver.ACTION_DUE))
        assertThat(due()).isNull()
    }

    @Test
    fun withoutAPlanTheAlarmsDoNothing() {
        PlannedSessionReceiver().onReceive(app, Intent(PlannedSessionReceiver.ACTION_DUE))
        PlannedSessionReceiver().onReceive(app, Intent(PlannedSessionReceiver.ACTION_COUNTDOWN))
        PlannedSessionReceiver().onReceive(app, Intent(PlannedSessionReceiver.ACTION_SNOOZE))
        assertThat(countdown()).isNull()
        assertThat(due()).isNull()
        assertThat(alarms()).isEmpty()
    }

    @Test
    fun cancelRemovesThePlanItsAlarmsAndItsNotifications() {
        PlannedSessions.schedule(app, templateId, System.currentTimeMillis() + 25 * minute)
        assertThat(countdown()).isNotNull()
        PlannedSessions.cancel(app)
        assertThat(store().read()).isNull()
        assertThat(alarms()).isEmpty()
        assertThat(countdown()).isNull()
    }

    @Test
    fun aStartThatIsNotInTheFutureCancelsInsteadOfPlanning() {
        PlannedSessions.schedule(app, templateId, System.currentTimeMillis() + 3 * 60 * minute)
        PlannedSessions.schedule(app, templateId, System.currentTimeMillis() - minute)
        assertThat(store().read()).isNull()
        assertThat(alarms()).isEmpty()
    }

    @Test
    fun aNewPlanReplacesTheOldOne() {
        val first = System.currentTimeMillis() + 3 * 60 * minute
        PlannedSessions.schedule(app, "first", first)
        PlannedSessions.schedule(app, templateId, first + 60 * minute)
        assertThat(store().read()).isEqualTo(PlannedSession(templateId, first + 60 * minute))
        assertThat(alarms()).hasSize(2)
    }

    @Test
    fun theBootReceiverArmsThePlanAgain() {
        val start = System.currentTimeMillis() + 3 * 60 * minute
        store().write(PlannedSession(templateId, start))
        assertThat(alarms()).isEmpty()
        PlannedSessionReceiver().onReceive(app, Intent(Intent.ACTION_BOOT_COMPLETED))
        assertThat(alarms().map { actionOf(it) }).containsExactly(PlannedSessionReceiver.ACTION_COUNTDOWN, PlannedSessionReceiver.ACTION_DUE)
    }

    @Test
    fun aPlanThatIsTwoHoursOldIsForgottenAtBoot() {
        store().write(PlannedSession(templateId, System.currentTimeMillis() - 3 * 60 * minute))
        PlannedSessionReceiver().onReceive(app, Intent(Intent.ACTION_MY_PACKAGE_REPLACED))
        assertThat(store().read()).isNull()
        assertThat(alarms()).isEmpty()
    }
}
