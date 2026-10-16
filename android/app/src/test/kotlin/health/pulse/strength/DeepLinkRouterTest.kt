package health.pulse.strength

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.widgets.StrengthDeepLink
import health.pulse.strength.runtime.PreviewRuntime
import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.junit.Test

class DeepLinkRouterTest {
    private val runtime = PreviewRuntime()

    private fun router(environment: StrengthAppEnvironment) = DeepLinkRouter(environment) { runtime.commands }

    @Test
    fun theWorkoutLinkShowsTheRunningWorkout() = runTest {
        val environment = StrengthAppEnvironment.preview(withActiveWorkout = true)
        router(environment).open(StrengthDeepLink.Workout)
        assertThat(environment.hostRequests.current.value).isEqualTo(HostRequest.OpenWorkout)
    }

    @Test
    fun theWorkoutLinkWithoutAWorkoutShowsTheHub() = runTest {
        val environment = StrengthAppEnvironment.preview()
        router(environment).open(StrengthDeepLink.Workout)
        assertThat(environment.hostRequests.current.value).isEqualTo(HostRequest.OpenHub)
    }

    @Test
    fun theStartLinksRunTheSameCommandsAsTheWidgetButtons() = runTest {
        val environment = StrengthAppEnvironment.preview()
        val template = UUID.randomUUID()
        router(environment).open(StrengthDeepLink.StartNext)
        router(environment).open(StrengthDeepLink.Start(template))
        router(environment).open(StrengthDeepLink.StartEmpty("Mobility"))
        assertThat(runtime.received).containsExactly("startNext", "startTemplate:$template", "startEmpty:Mobility").inOrder()
    }

    @Test
    fun anExerciseLinkOpensThatExercise() = runTest {
        val environment = StrengthAppEnvironment.preview()
        router(environment).open(StrengthDeepLink.Exercise("bench"))
        assertThat(environment.hostRequests.current.value).isEqualTo(HostRequest.OpenExercise("bench"))
    }

    @Test
    fun theHubAndWeightLinksOpenTheHub() = runTest {
        val environment = StrengthAppEnvironment.preview(withActiveWorkout = true)
        router(environment).open(StrengthDeepLink.Hub)
        assertThat(environment.hostRequests.current.value).isEqualTo(HostRequest.OpenHub)
        environment.hostRequests.consume(HostRequest.OpenHub)
        router(environment).open(StrengthDeepLink.Weight)
        assertThat(environment.hostRequests.current.value).isEqualTo(HostRequest.OpenHub)
    }

    @Test
    fun aRequestIsKeptUntilItIsConsumedAndANewerOneSurvivesAStaleConsume() {
        val requests = HostRequests()
        requests.post(HostRequest.OpenHub)
        assertThat(requests.current.value).isEqualTo(HostRequest.OpenHub)
        requests.post(HostRequest.OpenExercise("squat"))
        requests.consume(HostRequest.OpenHub)
        assertThat(requests.current.value).isEqualTo(HostRequest.OpenExercise("squat"))
        requests.consume(HostRequest.OpenExercise("squat"))
        assertThat(requests.current.value).isNull()
    }
}
