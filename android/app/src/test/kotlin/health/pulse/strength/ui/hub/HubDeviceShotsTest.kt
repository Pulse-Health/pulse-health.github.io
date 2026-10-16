package health.pulse.strength.ui.hub

import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

// One class per window size: each runs the shared scenarios of HubShotsBase (real size) or HubTallShotsBase (a window tall enough to
// hold the whole scrolling page) and writes `app/build/screens/hub-<scenario>-<tag>.png`. The qualifiers mirror TestDevice.

/** 360 × 640 dp: the smallest phone the layout must work on. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h640dp-xhdpi")
class HubShotsSmallPhone : HubShotsBase("small")

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h2000dp-xhdpi")
class HubShotsSmallPhoneTall : HubTallShotsBase("small-tall")

/** A phone on its side: 891 × 411 dp, the home screen in two columns. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w891dp-h411dp-land-xxhdpi")
class HubShotsLandscape : HubShotsBase("landscape")

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w891dp-h1100dp-land-xhdpi")
class HubShotsLandscapeTall : HubTallShotsBase("landscape-tall")

/** A tablet in portrait: 800 × 1280 dp, one centred column. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w800dp-h1280dp-xhdpi")
class HubShotsTablet : HubShotsBase("tablet")

/** A tablet in landscape: 1280 × 800 dp, two columns. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class HubShotsTabletLandscape : HubShotsBase("tablet-land")

/** 200 % font size on a normal phone. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h891dp-xxhdpi", fontScale = 2.0f)
class HubShotsFont200 : HubShotsBase("font200")

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w411dp-h4200dp-xhdpi", fontScale = 2.0f)
class HubShotsFont200Tall : HubTallShotsBase("font200-tall")

/** 200 % font size on the smallest phone: the worst case for clipping. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h640dp-xhdpi", fontScale = 2.0f)
class HubShotsFont200Small : HubShotsBase("font200-small")

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(qualifiers = "w360dp-h5000dp-xhdpi", fontScale = 2.0f)
class HubShotsFont200SmallTall : HubTallShotsBase("font200-small-tall")
