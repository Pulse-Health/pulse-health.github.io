package health.pulse.strength.widgets.home

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class WeeklyGoalModelTest {
    @Test
    fun theRingFillsTowardTheGoalAndNeverBeyondIt() {
        assertThat(WeeklyGoalModel.progress(3, 4)).isEqualTo(0.75f)
        assertThat(WeeklyGoalModel.progress(0, 4)).isEqualTo(0f)
        assertThat(WeeklyGoalModel.progress(5, 4)).isEqualTo(1f)
        assertThat(WeeklyGoalModel.progress(1, 0)).isEqualTo(0f)
    }

    @Test
    fun theHeadlineCountsDownThenCelebrates() {
        assertThat(WeeklyGoalModel.headline(3, 4)).isEqualTo("1 to go")
        assertThat(WeeklyGoalModel.headline(0, 4)).isEqualTo("4 to go")
        assertThat(WeeklyGoalModel.headline(4, 4)).isEqualTo("Goal reached")
        assertThat(WeeklyGoalModel.headline(6, 4)).isEqualTo("Goal reached")
    }

    @Test
    fun theSublineIsTheStreakOrTheWeek() {
        assertThat(WeeklyGoalModel.subline(6)).isEqualTo("6 week streak")
        assertThat(WeeklyGoalModel.subline(0)).isEqualTo("This week")
    }

    @Test
    fun theDescriptionNamesTheStreakOnlyWhenThereIsOneAndTheDaysTrained() {
        val week = HomeFixtures.preview.week
        assertThat(WeeklyGoalModel.description(week))
            .isEqualTo("3 of 4 workouts this week, 6 week streak. Workouts on Monday, Tuesday and Wednesday.")
        assertThat(WeeklyGoalModel.description(week.copy(streakWeeks = 0)))
            .isEqualTo("3 of 4 workouts this week. Workouts on Monday, Tuesday and Wednesday.")
        assertThat(WeeklyGoalModel.description(HomeFixtures.empty.week)).isEqualTo("0 of 4 workouts this week.")
    }
}
