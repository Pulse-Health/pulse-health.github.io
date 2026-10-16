package health.pulse.strength.services

import android.app.Application
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** The weekly goal in the device settings: what the week ring, the streak and the training block of the widgets count against. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PulseSettingsGoalTest {
    private val context: Context = ApplicationProvider.getApplicationContext<Application>()

    @Test
    fun theGoalIsFourUntilTheUserChoosesAnother() {
        assertThat(PulseSettings(context).weeklyGoal.value).isEqualTo(4)
    }

    @Test
    fun aGoalIsKeptBetweenOneAndSevenAndPublished() {
        val settings = PulseSettings(context)
        settings.setWeeklyGoal(6)
        assertThat(settings.weeklyGoal.value).isEqualTo(6)
        settings.setWeeklyGoal(0)
        assertThat(settings.weeklyGoal.value).isEqualTo(1)
        settings.setWeeklyGoal(12)
        assertThat(settings.weeklyGoal.value).isEqualTo(7)
        settings.setWeeklyGoal(Int.MIN_VALUE)
        assertThat(settings.weeklyGoal.value).isEqualTo(1)
    }

    @Test
    fun theGoalSurvivesARestart() {
        PulseSettings(context).setWeeklyGoal(5)
        assertThat(PulseSettings(context).weeklyGoal.value).isEqualTo(5)
    }

    @Test
    fun aDamagedStoredGoalIsBroughtIntoRange() {
        context.getSharedPreferences(PulseSettings.NAME, Context.MODE_PRIVATE).edit().putInt("weekly_goal", 99).commit()
        assertThat(PulseSettings(context).weeklyGoal.value).isEqualTo(7)
    }
}
