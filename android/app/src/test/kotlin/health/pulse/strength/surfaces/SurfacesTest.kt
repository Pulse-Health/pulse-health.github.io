package health.pulse.strength.surfaces

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Every surface is refreshed, in order, even when an earlier one fails. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SurfacesTest {
    private val app: Application = ApplicationProvider.getApplicationContext()

    @Test
    fun theWatchIsStillFedWhenAnEarlierSurfaceFails() = runBlocking {
        val ran = mutableListOf<String>()
        Surfaces.refresh(
            app,
            listOf(
                Surfaces.Step("widgets") { ran += "widgets" },
                Surfaces.Step("tiles") { error("a tile failed") },
                Surfaces.Step("watch") { ran += "watch" },
            ),
        )
        assertThat(ran).containsExactly("widgets", "watch").inOrder()
    }

    @Test
    fun aCancelledRefreshStops() {
        val ran = mutableListOf<String>()
        assertThrows(CancellationException::class.java) {
            runBlocking {
                Surfaces.refresh(
                    app,
                    listOf(
                        Surfaces.Step("widgets") { throw CancellationException("cancelled") },
                        Surfaces.Step("watch") { ran += "watch" },
                    ),
                )
            }
        }
        assertThat(ran).isEmpty()
    }

    @Test
    fun everySurfaceOfTheAppIsInTheList() {
        assertThat(Surfaces.steps.map { it.name }).containsExactly(
            "Home Screen widgets", "Lock Screen widgets", "tablet widgets", "extra widgets",
            "Quick Settings tiles", "live notifications", "watch",
        ).inOrder()
    }

    @Test
    fun refreshingTheRealSurfacesDoesNotThrow() = runBlocking {
        Surfaces.refreshAll(app)
    }
}
