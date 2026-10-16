package health.pulse.strength.surfaces

import android.app.AlarmManager
import android.app.Application
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.runtime.PreviewRuntime
import health.pulse.strength.runtime.StrengthRuntime
import java.time.Instant
import java.time.ZoneId
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAlarmManager

/** The widgets draw "today" from the snapshot, so the snapshot is built again at midnight and when the clock or the zone changes. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DayChangeTest {
    private lateinit var app: Application
    private val berlin = ZoneId.of("Europe/Berlin")

    /** The preview runtime that counts how often it was asked to build its snapshot again. */
    private class CountingRuntime : StrengthRuntime.Runtime {
        private val preview = PreviewRuntime()
        @Volatile var rebuilds = 0
        override val snapshots get() = preview.snapshots
        override val commands get() = preview.commands

        override suspend fun rebuild() {
            rebuilds += 1
        }
    }

    @Before
    fun setUp() {
        app = ApplicationProvider.getApplicationContext()
    }

    @After
    fun restore() {
        StrengthRuntime.installForTest(PreviewRuntime())
    }

    @Suppress("DEPRECATION") // Robolectric offers no other accessor than the field it deprecated
    private fun midnightAlarms(): List<ShadowAlarmManager.ScheduledAlarm> =
        shadowOf(app.getSystemService(AlarmManager::class.java)).scheduledAlarms
            .filter { shadowOf(it.operation).savedIntent.action == DayChange.ACTION_MIDNIGHT }

    private fun awaitTrue(milliseconds: Long = 5_000, condition: () -> Boolean) {
        val deadline = System.nanoTime() + milliseconds * 1_000_000
        while (!condition()) {
            check(System.nanoTime() < deadline) { "The condition did not become true in $milliseconds ms" }
            Thread.sleep(10)
        }
    }

    @Test
    fun theNextMidnightIsTheStartOfTheNextLocalDay() {
        assertThat(DayChange.nextMidnight(Instant.parse("2026-10-16T09:41:00Z"), berlin)).isEqualTo(Instant.parse("2026-10-16T22:00:00Z"))
        // Just before and exactly at midnight (local): the day after.
        assertThat(DayChange.nextMidnight(Instant.parse("2026-10-16T21:59:59Z"), berlin)).isEqualTo(Instant.parse("2026-10-16T22:00:00Z"))
        assertThat(DayChange.nextMidnight(Instant.parse("2026-10-16T22:00:00Z"), berlin)).isEqualTo(Instant.parse("2026-10-17T22:00:00Z"))
    }

    @Test
    fun aDayWithTheClocksSetBackHasTwentyFiveHours() {
        // 25 October 2026 has 25 hours in Berlin: midnight to midnight is 22:00Z to 23:00Z the next day.
        assertThat(DayChange.nextMidnight(Instant.parse("2026-10-24T22:00:00Z"), berlin)).isEqualTo(Instant.parse("2026-10-25T23:00:00Z"))
        // And 29 March 2026 has 23.
        assertThat(DayChange.nextMidnight(Instant.parse("2026-03-28T23:00:00Z"), berlin)).isEqualTo(Instant.parse("2026-03-29T22:00:00Z"))
    }

    @Test
    fun theAppArmsOneMidnightAlarmWhenItStarts() {
        val alarms = midnightAlarms()
        assertThat(alarms).hasSize(1)
        assertThat(alarms.single().triggerAtMs).isGreaterThan(System.currentTimeMillis())
    }

    @Test
    fun schedulingAgainMovesTheSameAlarmToTheNextMidnightPlusAMargin() {
        DayChange.schedule(app, Instant.parse("2026-10-16T09:41:00Z"), berlin)
        DayChange.schedule(app, Instant.parse("2026-10-17T00:05:00Z").plusSeconds(2 * 3600), berlin)
        val alarm = midnightAlarms().single()
        // 02:05 on 17 October in Berlin: the next midnight is the start of the 18th, 22:00Z on the 17th, and the alarm rings 30 s later.
        assertThat(alarm.triggerAtMs).isEqualTo(Instant.parse("2026-10-17T22:00:30Z").toEpochMilli())
    }

    @Test
    fun aClockOrZoneChangeRebuildsTheSnapshotRefreshesTheSurfacesAndArmsTheNextMidnight() {
        val runtime = CountingRuntime()
        StrengthRuntime.installForTest(runtime)
        val alarmBefore = midnightAlarms().single().triggerAtMs

        for (action in listOf(Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, DayChange.ACTION_MIDNIGHT)) {
            val rebuildsBefore = runtime.rebuilds
            DayChangeReceiver().onReceive(app, Intent(action))
            awaitTrue { runtime.rebuilds == rebuildsBefore + 1 }
        }
        assertThat(midnightAlarms()).hasSize(1)
        assertThat(midnightAlarms().single().triggerAtMs).isAtLeast(alarmBefore)
    }

    @Test
    fun theReceiverListensToTheClockTheZoneTheBootAndTheUpdate() {
        val pm = app.packageManager
        for (action in listOf(Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED)) {
            val receivers = pm.queryBroadcastReceivers(Intent(action).setPackage(app.packageName), 0).map { it.activityInfo.name }
            assertThat(receivers).contains(DayChangeReceiver::class.java.name)
        }
        assertThat(pm.getReceiverInfo(android.content.ComponentName(app, DayChangeReceiver::class.java), 0).exported).isFalse()
    }
}
