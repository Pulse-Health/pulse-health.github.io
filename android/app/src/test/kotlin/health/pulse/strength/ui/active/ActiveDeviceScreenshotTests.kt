package health.pulse.strength.ui.active

import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** The active-workout states on a 360 x 640 dp small phone. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h640dp-xhdpi")
class ActiveSmallPhoneScreenshotTest : ActiveScreenshotScenarios("small")

/** The active-workout states on a phone held sideways (891 x 411 dp). */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
class ActiveLandscapeScreenshotTest : ActiveScreenshotScenarios("landscape", topDp = 24, bottomDp = 0, leftDp = 48)

/** The active-workout states on a phone held sideways that is too narrow for the dock beside the card (640 x 360 dp, bar on the right). */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w640dp-h360dp-land-xxhdpi")
class ActiveShortLandscapeScreenshotTest : ActiveScreenshotScenarios("landscape-short", topDp = 24, bottomDp = 0, rightDp = 48)

/** The active-workout states in a 600 x 480 dp window (a split screen on a large screen). */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w600dp-h480dp-xhdpi")
class ActiveSplitWindowScreenshotTest : ActiveScreenshotScenarios("split", topDp = 24, bottomDp = 24)

/** The active-workout states on an 800 x 1280 dp tablet. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w800dp-h1280dp-xhdpi")
class ActiveTabletScreenshotTest : ActiveScreenshotScenarios("tablet")

/** The active-workout states with the system font size at 200 %. */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2.0f)
class ActiveFontScale2ScreenshotTest : ActiveScreenshotScenarios("font2")

/** A small phone with the system font size at 200 % (the hardest case). */
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
class ActiveSmallFontScale2ScreenshotTest : ActiveScreenshotScenarios("small-font2")
