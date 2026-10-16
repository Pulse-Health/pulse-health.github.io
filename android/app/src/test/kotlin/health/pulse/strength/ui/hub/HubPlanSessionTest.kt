package health.pulse.strength.ui.hub

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.WorkoutTemplate
import health.pulse.strength.live.PlannedSessions
import health.pulse.strength.ui.hub.HubTestSupport.fixLocale
import health.pulse.strength.ui.hub.HubTestSupport.setPulseContent
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The day and time arithmetic of "Plan a session", with no screen. */
class HubPlanTimesTest {
    private val berlin = ZoneId.of("Europe/Berlin")
    private val utc = ZoneId.of("UTC")

    @Test
    fun theSuggestedStartIsTheNextFullHourAtLeastHalfAnHourAway() {
        assertThat(HubPlanTimes.suggestedStart(Instant.parse("2026-01-17T10:07:00Z"), utc)).isEqualTo(Instant.parse("2026-01-17T11:00:00Z"))
        assertThat(HubPlanTimes.suggestedStart(Instant.parse("2026-01-17T10:29:59Z"), utc)).isEqualTo(Instant.parse("2026-01-17T11:00:00Z"))
        // Exactly half an hour away is far enough.
        assertThat(HubPlanTimes.suggestedStart(Instant.parse("2026-01-17T10:30:00Z"), utc)).isEqualTo(Instant.parse("2026-01-17T11:00:00Z"))
        assertThat(HubPlanTimes.suggestedStart(Instant.parse("2026-01-17T10:30:01Z"), utc)).isEqualTo(Instant.parse("2026-01-17T12:00:00Z"))
        assertThat(HubPlanTimes.suggestedStart(Instant.parse("2026-01-17T23:45:00Z"), utc)).isEqualTo(Instant.parse("2026-01-18T01:00:00Z"))
    }

    @Test
    fun theSuggestedStartIsAFullHourOnTheLocalClockEvenInAHalfHourZone() {
        val india = ZoneId.of("Asia/Kolkata")
        // 10:07 UTC is 15:37 in India; half an hour later is 16:07, so the next full local hour is 17:00 = 11:30 UTC.
        assertThat(HubPlanTimes.suggestedStart(Instant.parse("2026-01-17T10:07:00Z"), india)).isEqualTo(Instant.parse("2026-01-17T11:30:00Z"))
    }

    @Test
    fun movingTheDayKeepsTheTimeOfDayOnTheLocalClock() {
        val start = Instant.parse("2026-10-24T16:00:00Z") // 18:00 in Berlin (summer time)
        val moved = HubPlanTimes.withDate(start, LocalDate.of(2026, 10, 26), berlin) // the clocks went back on 25 October
        assertThat(moved).isEqualTo(Instant.parse("2026-10-26T17:00:00Z")) // 18:00 in Berlin (winter time)
    }

    @Test
    fun movingTheTimeKeepsTheLocalDay() {
        val start = Instant.parse("2026-01-17T23:30:00Z") // 00:30 on 18 January in Berlin
        assertThat(HubPlanTimes.withTime(start, LocalTime.of(7, 15), berlin)).isEqualTo(Instant.parse("2026-01-18T06:15:00Z"))
    }

    @Test
    fun aTimeInTheGapOfTheClockChangeMovesForward() {
        val start = Instant.parse("2026-03-28T12:00:00Z")
        // 02:30 does not exist on 29 March 2026 in Berlin: the clocks jump from 02:00 to 03:00.
        val moved = HubPlanTimes.withDate(HubPlanTimes.withTime(start, LocalTime.of(2, 30), berlin), LocalDate.of(2026, 3, 29), berlin)
        assertThat(moved.atZone(berlin).toLocalTime()).isEqualTo(LocalTime.of(3, 30))
    }

    @Test
    fun theDayIsTodayTomorrowOrAnother() {
        val now = Instant.parse("2026-01-17T23:30:00Z") // 00:30 on 18 January in Berlin
        assertThat(HubPlanTimes.dayOf(Instant.parse("2026-01-18T05:00:00Z"), now, berlin)).isEqualTo(PlanDay.TODAY)
        assertThat(HubPlanTimes.dayOf(Instant.parse("2026-01-19T05:00:00Z"), now, berlin)).isEqualTo(PlanDay.TOMORROW)
        assertThat(HubPlanTimes.dayOf(Instant.parse("2026-01-21T05:00:00Z"), now, berlin)).isEqualTo(PlanDay.OTHER)
    }
}

/** The "Plan a session" sheet, its button on the template screen and the planner behind it. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class HubPlanSessionTest {
    @get:Rule val rule = createAndroidComposeRule<ComponentActivity>()

    private class FakePlanner(var plan: PlannedStart? = null, override var notificationsOn: Boolean = true) : SessionPlanner {
        val scheduled = mutableListOf<Pair<UUID, Instant>>()
        var cancelled = 0

        override fun current() = plan

        override fun schedule(templateID: UUID, startsAt: Instant) {
            scheduled += templateID to startsAt
        }

        override fun cancel() {
            cancelled += 1
            plan = null
        }
    }

    private val env = HubTestSupport.environment()
    private val template: WorkoutTemplate = env.store.templates.first()

    @Before fun setUp() = fixLocale()

    private fun showSheet(planner: SessionPlanner, onDismiss: () -> Unit = {}) {
        rule.setPulseContent {
            HubPlanSessionSheet(template = template, planner = planner, templateName = { id -> env.store.templates.firstOrNull { it.id == id }?.name }, onDismiss = onDismiss)
        }
        rule.waitForIdle()
    }

    @Test
    fun theSheetSuggestsTheNextFullHourToday() {
        showSheet(FakePlanner())
        rule.onNodeWithText("Plan a session").assertExists()
        rule.onNodeWithText(template.name).assertExists()
        rule.onNodeWithText("Today").assertExists()
        // Now is 10:00 UTC in these tests: the suggestion is 11:00.
        rule.onNodeWithText("11:00", substring = true).assertExists()
        rule.onNodeWithText("Plan Session").assertIsEnabled()
    }

    @Test
    fun planSessionSchedulesTheTemplateAtTheShownTime() {
        val planner = FakePlanner()
        var dismissed = 0
        showSheet(planner, onDismiss = { dismissed += 1 })
        rule.onNodeWithText("Plan Session").performClick()
        rule.waitForIdle()
        assertThat(planner.scheduled).containsExactly(template.id to Instant.parse("2026-01-17T11:00:00Z"))
        rule.waitUntil(2_000) { dismissed == 1 }
    }

    @Test
    fun tomorrowMovesTheDayAndKeepsTheTime() {
        val planner = FakePlanner()
        showSheet(planner)
        rule.onNodeWithText("Tomorrow").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("Plan Session").performClick()
        rule.waitForIdle()
        assertThat(planner.scheduled).containsExactly(template.id to Instant.parse("2026-01-18T11:00:00Z"))
    }

    @Test
    fun aPlanThatIsWaitingCanBeCancelled() {
        val other = env.store.templates.last()
        val planner = FakePlanner(plan = PlannedStart(other.id, Instant.parse("2026-01-17T18:00:00Z")))
        var dismissed = 0
        showSheet(planner, onDismiss = { dismissed += 1 })
        rule.onNodeWithText("Planned: ${other.name}, Today", substring = true).assertExists()
        rule.onNodeWithText("Cancel the planned session").performClick()
        rule.waitForIdle()
        assertThat(planner.cancelled).isEqualTo(1)
        assertThat(planner.scheduled).isEmpty()
        rule.waitUntil(2_000) { dismissed == 1 }
    }

    @Test
    fun withoutAPlanThereIsNothingToCancel() {
        showSheet(FakePlanner())
        rule.onNodeWithText("Cancel the planned session").assertDoesNotExist()
    }

    @Test
    fun switchedOffNotificationsAreSaid() {
        showSheet(FakePlanner(notificationsOn = false))
        rule.onNodeWithText("Notifications are off", substring = true).assertExists()
    }

    @Test
    fun theContentDisablesPlanForAStartThatHasPassed() {
        rule.setPulseContent {
            HubPlanSessionContent(
                templateName = "Push Day", day = PlanDay.TODAY, dayText = "Today", timeText = "9:00 AM", canPlan = false, notificationsOn = true,
                existing = null, onClose = {}, onSelectDay = {}, onPickTime = {}, onPlan = {}, onCancelPlan = {},
            )
        }
        rule.onNodeWithText("Plan Session").assertIsNotEnabled()
    }

    @Test
    fun anotherDayShowsItsDateInTheThirdSegment() {
        rule.setPulseContent {
            HubPlanSessionContent(
                templateName = "Push Day", day = PlanDay.OTHER, dayText = "Wed, Jan 21", timeText = "9:00 AM", canPlan = true, notificationsOn = true,
                existing = null, onClose = {}, onSelectDay = {}, onPickTime = {}, onPlan = {}, onCancelPlan = {},
            )
        }
        rule.onNodeWithText("Wed, Jan 21").assertExists()
        rule.onNodeWithContentDescription("Start time, 9:00 AM. Change").assertExists()
    }

    @Test
    fun theAndroidPlannerSchedulesAndCancelsThroughPlannedSessions() {
        val context = ApplicationProvider.getApplicationContext<android.app.Application>()
        PlannedSessions.cancel(context)
        val planner = AndroidSessionPlanner(context)
        assertThat(planner.current()).isNull()

        val startsAt = Instant.now().plusSeconds(3 * 3600).let { Instant.ofEpochSecond(it.epochSecond) }
        planner.schedule(template.id, startsAt)
        val plan = planner.current()
        assertThat(plan?.templateID).isEqualTo(template.id)
        assertThat(plan?.startsAt).isEqualTo(startsAt)

        planner.cancel()
        assertThat(planner.current()).isNull()
    }
}
