package health.pulse.strength.wear.ongoing

import android.Manifest
import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import androidx.core.app.NotificationCompat
import androidx.test.core.app.ApplicationProvider
import androidx.wear.ongoing.OngoingActivity
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.SnapshotPhase
import health.pulse.strength.wear.WearFixtures
import health.pulse.strength.wear.WearFixtures.now
import health.pulse.strength.wear.WearMainActivity
import health.pulse.strength.wear.model.OngoingModel
import health.pulse.strength.wear.model.OngoingStatus
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

/** WA-02: the Ongoing Activity chip of a running workout, started, updated and removed. */
@RunWith(RobolectricTestRunner::class)
class OngoingWorkoutTest {
    private val app = ApplicationProvider.getApplicationContext<Application>()
    private val manager = app.getSystemService(NotificationManager::class.java)

    @Before
    fun grantNotifications() {
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
    }

    private fun posted(): Notification? = shadowOf(manager).getNotification(OngoingWorkout.NOTIFICATION_ID)

    private fun OngoingStatus.render(): String = OngoingWorkout.status(this).getText(app, now.toEpochMilli()).toString()

    /** What the watch face shows next to the title of the chip it recovers from the posted notification. */
    private fun recoveredStatus(): String =
        checkNotNull(checkNotNull(OngoingActivity.recoverOngoingActivity(app)).status).getText(app, now.toEpochMilli()).toString()

    // region Notification

    @Test
    fun aRunningWorkoutPostsAnOngoingNotificationWithTheWorkoutAndTheSet() {
        OngoingWorkout.sync(app, WearFixtures.workout(), now)

        val notification = posted()!!
        assertThat(notification.extras.getCharSequence(Notification.EXTRA_TITLE).toString()).isEqualTo("Upper A · Push")
        assertThat(notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString()).isEqualTo("Bench Press · Set 3 of 4")
        assertThat(notification.flags and Notification.FLAG_ONGOING_EVENT).isNotEqualTo(0)
        assertThat(notification.category).isEqualTo(NotificationCompat.CATEGORY_WORKOUT)
        assertThat(notification.channelId).isEqualTo(OngoingWorkout.CHANNEL_ID)
    }

    @Test
    fun theChannelIsQuiet() {
        OngoingWorkout.sync(app, WearFixtures.workout(), now)

        val channel = manager.getNotificationChannel(OngoingWorkout.CHANNEL_ID)
        assertThat(channel.importance).isEqualTo(NotificationManager.IMPORTANCE_LOW)
        assertThat(channel.name.toString()).isEqualTo("Running workout")
    }

    @Test
    fun aTapOnTheNotificationOpensTheWatchApp() {
        OngoingWorkout.sync(app, WearFixtures.workout(), now)

        val intent = shadowOf(posted()!!.contentIntent).savedIntent
        assertThat(intent.component?.className).isEqualTo(WearMainActivity::class.java.name)
    }

    @Test
    fun theNotificationCarriesTheOngoingActivityOfTheWatchFace() {
        OngoingWorkout.sync(app, WearFixtures.workout(), now)

        val ongoing = OngoingActivity.recoverOngoingActivity(app)!!
        assertThat(ongoing.title).isEqualTo("Upper A · Push")
        assertThat(ongoing.contentDescription).isEqualTo("Upper A · Push. Workout running")
        assertThat(ongoing.category).isEqualTo(NotificationCompat.CATEGORY_WORKOUT)
        assertThat(recoveredStatus()).contains("25:00")
        assertThat(shadowOf(ongoing.touchIntent).savedIntent.component?.className).isEqualTo(WearMainActivity::class.java.name)
    }

    @Test
    fun anUpdateReplacesTheChipInsteadOfAddingAnother() {
        OngoingWorkout.sync(app, WearFixtures.workout(), now)

        OngoingWorkout.sync(app, WearFixtures.resting(seconds = 84), now)

        assertThat(shadowOf(manager).allNotifications).hasSize(1)
        assertThat(recoveredStatus()).contains("1:24")
    }

    @Test
    fun whenTheWorkoutEndsTheChipGoesAway() {
        OngoingWorkout.sync(app, WearFixtures.workout(), now)

        OngoingWorkout.sync(app, null, now)

        assertThat(posted()).isNull()
        assertThat(shadowOf(manager).allNotifications).isEmpty()
    }

    @Test
    fun withoutAWorkoutNothingIsPosted() {
        OngoingWorkout.sync(app, null, now)

        assertThat(shadowOf(manager).allNotifications).isEmpty()
    }

    @Test
    fun withoutTheNotificationPermissionNoChipIsShownAndAnOldOneIsRemoved() {
        OngoingWorkout.sync(app, WearFixtures.workout(), now)
        shadowOf(app).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)

        OngoingWorkout.sync(app, WearFixtures.workout(), now)

        assertThat(shadowOf(manager).allNotifications).isEmpty()
        assertThat(OngoingWorkout.mayNotify(app)).isFalse()
    }

    // endregion

    // region Status

    @Test
    fun whileLoggingTheChipShowsTheWorkoutClock() {
        val status = OngoingModel.of(WearFixtures.workout(), now).status

        assertThat(status.render()).contains("25:00")
    }

    @Test
    fun whileRestingTheChipShowsTheCountdown() {
        val status = OngoingModel.of(WearFixtures.resting(seconds = 84), now).status

        assertThat(status.render()).contains("Rest")
        assertThat(status.render()).contains("1:24")
    }

    @Test
    fun aPausedWorkoutShowsPausedAndTheFrozenClock() {
        val status = OngoingModel.of(WearFixtures.workout(isPaused = true, elapsedWhenPaused = 1480), now).status

        assertThat(status.render()).contains("Paused")
        assertThat(status.render()).contains("24:40")
    }

    @Test
    fun aPausedRestShowsWhatWasLeft() {
        val paused = WearFixtures.resting().copy(isPaused = true, restFrozenRemaining = 61)

        val text = OngoingModel.of(paused, now).status.render()

        assertThat(text).contains("Paused")
        assertThat(text).contains("1:01")
    }

    @Test
    fun theShortStatesAreWords() {
        assertThat(OngoingModel.of(WearFixtures.workout(phase = SnapshotPhase.REST_OVER), now).status.render()).isEqualTo("Rest over")
        assertThat(OngoingModel.of(WearFixtures.workout(phase = SnapshotPhase.COMPLETE), now).status.render()).isEqualTo("All sets logged")
    }

    // endregion
}
