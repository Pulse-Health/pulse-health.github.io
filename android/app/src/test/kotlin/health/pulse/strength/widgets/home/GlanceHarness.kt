package health.pulse.strength.widgets.home

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.RectF
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.glance.GlanceTheme
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.GlanceRemoteViews
import health.pulse.strength.core.widgets.WidgetSnapshot
import health.pulse.strength.widgets.common.PulseColors
import java.io.File
import java.io.FileOutputStream
import kotlin.math.roundToInt

/**
 * Runs a widget the way the launcher does: Glance composes it for a widget size, translates it to `RemoteViews`, and the views are
 * inflated here. What a test sees (texts, content descriptions, click listeners) is what the device would show; the translation also
 * enforces Glance's limits (for example the ten children of a container), which a pure composition test would not.
 */
@OptIn(ExperimentalGlanceRemoteViewsApi::class)
internal object GlanceHarness {
    /** Where the PNGs of the widgets go: next to the app's screen shots, `app/build/screens/widgets/`. */
    val screenDirectory: File = File("build/screens/widgets").also { it.mkdirs() }

    suspend fun inflate(context: Context, size: DpSize, dynamic: Boolean = false, content: @Composable () -> Unit): Rendered {
        val result = GlanceRemoteViews().compose(context, size) {
            if (dynamic) GlanceTheme { content() } else GlanceTheme(colors = PulseColors.colors) { content() }
        }
        return Rendered(result.remoteViews.apply(context, FrameLayout(context)), size)
    }

    suspend fun inflate(context: Context, size: DpSize, snapshot: WidgetSnapshot, dynamic: Boolean = false, content: @Composable (WidgetSnapshot) -> Unit): Rendered =
        inflate(context, size, dynamic) { content(snapshot) }
}

/** The inflated widget and the facts tests ask about it. */
internal class Rendered(val root: View, val size: DpSize) {
    private val all: List<View> = buildList { walk(root) { add(it) } }

    /** Every visible text, in view order. */
    val texts: List<String> = all.filterIsInstance<TextView>().filter { it.visibleInTree() }.map { it.text.toString() }

    /** Every content description of a visible view (images, buttons, the card). */
    val descriptions: List<String> = all.filter { it.visibleInTree() }.mapNotNull { it.contentDescription?.toString() }

    /** How many visible views have a click listener (the card and its buttons). */
    val clickable: Int = all.count { it.visibleInTree() && it.hasOnClickListeners() }

    val images: Int = all.count { it is ImageView && it.visibleInTree() }

    val viewCount: Int = all.size

    fun hasText(text: String): Boolean = texts.contains(text)

    /**
     * Draws the widget at its size over a wallpaper-like background and writes `<name>.png`. The card is clipped to the 22 dp corners the
     * launcher gives it; the rounded corners of the smaller elements are applied by the device through view outlines, which a software
     * canvas does not draw, so they appear square here.
     */
    fun savePng(name: String, wallpaper: Int) {
        val density = root.context.resources.displayMetrics.density
        val width = (size.width.value * density).roundToInt()
        val height = (size.height.value * density).roundToInt()
        val margin = (MARGIN_DP * density).roundToInt()
        root.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
        root.layout(0, 0, width, height)
        val bitmap = Bitmap.createBitmap(width + 2 * margin, height + 2 * margin, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(wallpaper)
        canvas.translate(margin.toFloat(), margin.toFloat())
        val radius = CARD_RADIUS_DP * density
        canvas.clipPath(Path().apply { addRoundRect(RectF(0f, 0f, width.toFloat(), height.toFloat()), radius, radius, Path.Direction.CW) })
        root.draw(canvas)
        FileOutputStream(File(GlanceHarness.screenDirectory, "$name.png")).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    /** `View.isShown` is false for a view that is not attached to a window, which these inflated trees are not; this checks the flags only. */
    private fun View.visibleInTree(): Boolean {
        var current: View? = this
        while (current != null) {
            if (current.visibility != View.VISIBLE) return false
            current = current.parent as? View
        }
        return true
    }

    private fun walk(view: View, visit: (View) -> Unit) {
        visit(view)
        if (view is ViewGroup) for (index in 0 until view.childCount) walk(view.getChildAt(index), visit)
    }

    private companion object {
        const val MARGIN_DP = 12f
        const val CARD_RADIUS_DP = 22f
    }
}
