package health.pulse.strength.services

import android.Manifest
import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.ActionOrigin
import health.pulse.strength.core.CompletedWorkout
import health.pulse.strength.core.WorkoutAction
import health.pulse.strength.core.WorkoutState
import health.pulse.strength.core.widgets.PRMoment
import health.pulse.strength.live.CardKind
import health.pulse.strength.runtime.PreviewRuntime
import health.pulse.strength.runtime.StrengthRuntime
import health.pulse.strength.ui.hub.HubTestSupport
import java.time.Instant
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** The two live moments that pass through the notification effect: the record flash (LA-01) and the finish summary (LA-05). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WorkoutNotificationEffectTest {
    private lateinit var app: Application
    private lateinit var manager: NotificationManager
    private val start = Instant.parse("2026-01-17T10:00:00Z")
    private var now = start

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

    private val record = { at: Instant ->
        PRMoment(exerciseName = "Bench Press", weightText = "85", repsText = "5", estimated1RM = 99, deltaKg = 4, expiresAt = at.plusSeconds(4))
    }

    private fun title(id: Int): String? = shadowOf(manager).getNotification(id)?.extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()

    private fun text(id: Int): String? = shadowOf(manager).getNotification(id)?.extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()

    private fun subText(id: Int): String? = shadowOf(manager).getNotification(id)?.extras?.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()

    private class Fixture(val effect: WorkoutNotificationEffect, val state: WorkoutState, val completed: CompletedWorkout)

    private fun fixture(moments: (WorkoutState, WorkoutState, Instant) -> PRMoment?, savedToHealth: Boolean = false): Fixture {
        val env = HubTestSupport.environment(withActiveWorkout = true)
        val settings = PulseSettings(app)
        val restAlerts = RestAlerts(app, env.controller, AppForegroundTracker(), settings)
        val effect = WorkoutNotificationEffect(app, restAlerts, clock = { now }, savedToHealth = { savedToHealth }, moments = moments)
        return Fixture(effect, checkNotNull(env.controller.state.value), env.store.history.first())
    }

    @Test
    fun aRecordFlashesOnTheOngoingNotificationAndRunsOut() {
        var fresh: PRMoment? = record(start)
        val f = fixture(moments = { _, _, _ -> fresh })
        f.effect.workoutChanged(f.state, f.state, WorkoutAction.LogNextSet, ActionOrigin.PHONE)
        assertThat(title(WorkoutNotifications.ONGOING_ID)).isEqualTo("New record: Bench Press")

        // Other updates of the same workout (a rest tick, a heart rate) carry the record until it runs out.
        fresh = null
        now = start.plusSeconds(2)
        f.effect.workoutChanged(f.state, f.state, WorkoutAction.LogNextSet, ActionOrigin.PHONE)
        assertThat(title(WorkoutNotifications.ONGOING_ID)).isEqualTo("New record: Bench Press")

        now = start.plusSeconds(5)
        f.effect.workoutChanged(f.state, f.state, WorkoutAction.LogNextSet, ActionOrigin.PHONE)
        assertThat(title(WorkoutNotifications.ONGOING_ID)).doesNotContain("New record")
    }

    @Test
    fun withoutARecordTheNotificationIsTheUsualOne() {
        val f = fixture(moments = { _, _, _ -> null })
        f.effect.workoutChanged(f.state, f.state, WorkoutAction.LogNextSet, ActionOrigin.PHONE)
        assertThat(shadowOf(manager).getNotification(WorkoutNotifications.ONGOING_ID)).isNotNull()
        assertThat(title(WorkoutNotifications.ONGOING_ID)).doesNotContain("New record")
    }

    @Test
    fun aRecordIsForgottenWhenTheWorkoutEnds() {
        val f = fixture(moments = { _, _, at -> record(at) })
        f.effect.workoutChanged(f.state, f.state, WorkoutAction.LogNextSet, ActionOrigin.PHONE)
        f.effect.workoutEnded(f.state, completed = null)
        // The same instant, the next workout: nothing of the earlier record is left.
        val next = fixture(moments = { _, _, _ -> null })
        next.effect.workoutStarted(next.state)
        assertThat(title(WorkoutNotifications.ONGOING_ID)).doesNotContain("New record")
    }

    @Test
    fun aFinishedWorkoutLeavesItsSummary() {
        val f = fixture(moments = { _, _, _ -> null })
        f.effect.workoutStarted(f.state)
        f.effect.workoutEnded(f.state, f.completed)
        assertThat(shadowOf(manager).getNotification(WorkoutNotifications.ONGOING_ID)).isNull()
        assertThat(title(CardKind.FINISH.notificationId)).isEqualTo("${f.completed.name} done")
        assertThat(text(CardKind.FINISH.notificationId)).contains("min")
        assertThat(subText(CardKind.FINISH.notificationId)).isNull()
    }

    @Test
    fun theSummarySaysWhenHealthConnectHasTheWorkout() {
        val f = fixture(moments = { _, _, _ -> null }, savedToHealth = true)
        f.effect.workoutEnded(f.state, f.completed)
        assertThat(subText(CardKind.FINISH.notificationId)).isEqualTo("Saved to Health")
    }

    @Test
    fun aDiscardedWorkoutLeavesNothing() {
        val f = fixture(moments = { _, _, _ -> null })
        f.effect.workoutStarted(f.state)
        f.effect.workoutEnded(f.state, completed = null)
        assertThat(shadowOf(manager).getNotification(WorkoutNotifications.ONGOING_ID)).isNull()
        assertThat(shadowOf(manager).getNotification(CardKind.FINISH.notificationId)).isNull()
    }
}
