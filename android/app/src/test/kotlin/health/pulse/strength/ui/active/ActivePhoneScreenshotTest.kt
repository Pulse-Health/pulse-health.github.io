package health.pulse.strength.ui.active

import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The active-workout states on a 411 x 891 dp phone. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ActivePhoneScreenshotTest : ActiveScreenshotScenarios("phone")
