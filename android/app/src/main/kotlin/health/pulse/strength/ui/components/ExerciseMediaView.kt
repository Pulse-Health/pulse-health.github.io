package health.pulse.strength.ui.components

import android.content.Context
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import health.pulse.strength.ui.theme.LocalReduceMotion
import health.pulse.strength.ui.theme.PulseTheme
import kotlinx.coroutines.delay

/** The two form-demo frames of one exercise ("<mediaKey>-a" and "<mediaKey>-b"). */
class ExerciseMediaFrames(val first: ImageBitmap?, val second: ImageBitmap?) {
    val hasAny: Boolean get() = first != null || second != null
}

/**
 * Loads and caches the loose `.jpg` frames shipped in `assets/ExerciseMedia`. Lookups that fail are remembered too, so a missing
 * frame is not searched for again every second.
 */
object ExerciseMediaStore {
    private const val folder = "ExerciseMedia"
    private val images = object : LruCache<String, ImageBitmap>(24) {}
    private val missing = mutableSetOf<String>()

    fun frames(context: Context, mediaKey: String?): ExerciseMediaFrames {
        if (mediaKey.isNullOrEmpty()) return ExerciseMediaFrames(null, null)
        val a = image(context, "$mediaKey-a")
        val b = image(context, "$mediaKey-b")
        // With a single frame, show it as the (static) first frame.
        if (a == null && b != null) return ExerciseMediaFrames(b, null)
        return ExerciseMediaFrames(a, b)
    }

    @Synchronized
    private fun image(context: Context, name: String): ImageBitmap? {
        images.get(name)?.let { return it }
        if (name in missing) return null
        val loaded = runCatching {
            context.applicationContext.assets.open("$folder/$name.jpg").use { BitmapFactory.decodeStream(it) }?.asImageBitmap()
        }.getOrNull()
        if (loaded != null) images.put(name, loaded) else missing.add(name)
        return loaded
    }
}

/**
 * The form-demo tile: crossfades the two frames of an exercise every 0.9 s (0.35 s fade), cropped to fill and clipped to a rounded
 * rectangle. Fills whatever size it is given. Shows a placeholder dumbbell when the exercise has no media or the image is missing,
 * and a static first frame when animations are off ([LocalReduceMotion]) or [animated] is false.
 */
@Composable
fun ExerciseMediaView(
    mediaKey: String?,
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 12.dp,
    animated: Boolean = true,
) {
    val context = LocalContext.current
    val frames = remember(mediaKey) { ExerciseMediaStore.frames(context, mediaKey) }
    val reduceMotion = LocalReduceMotion.current
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(cornerRadius))
            .background(PulseTheme.colors.mediaTile),
        contentAlignment = Alignment.Center,
    ) {
        val first = frames.first
        val second = frames.second
        if (first != null) {
            if (second != null && animated && !reduceMotion) {
                ExerciseMediaCrossfade(first, second)
            } else {
                ExerciseMediaFill(first)
            }
        } else {
            ExerciseMediaPlaceholder()
        }
    }
}

@Composable
private fun ExerciseMediaFill(image: ImageBitmap, modifier: Modifier = Modifier) {
    Image(
        bitmap = image,
        contentDescription = null,
        contentScale = ContentScale.Crop,
        modifier = modifier.fillMaxSize(),
    )
}

@Composable
private fun ExerciseMediaCrossfade(first: ImageBitmap, second: ImageBitmap) {
    var showSecond by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        while (true) {
            delay(900)
            showSecond = !showSecond
        }
    }
    val secondAlpha by animateFloatAsState(if (showSecond) 1f else 0f, animationSpec = tween(350), label = "mediaFade")
    Box(Modifier.fillMaxSize()) {
        ExerciseMediaFill(first)
        ExerciseMediaFill(second, Modifier.alpha(secondAlpha))
    }
}

/** The design's dumbbell in grey: 36 dp (stroke 1.4) in the 60 dp tile of the exercise card, 22 dp (stroke 1.6) in 44 dp list tiles. */
@Composable
private fun ExerciseMediaPlaceholder() {
    BoxWithConstraints(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val side = minOf(maxWidth, maxHeight)
        val isLargeTile = side >= 56.dp
        DumbbellGlyph(
            size = if (isLargeTile) minOf(side * 0.6f, 44.dp) else maxOf(10.dp, side * 0.5f),
            color = PulseTheme.colors.inkTertiary,
            strokeWidth = if (isLargeTile) 1.4.dp else 1.6.dp,
        )
    }
}

/** A dumbbell drawn as outlines: a bar between two weight stacks. */
@Composable
fun DumbbellGlyph(size: Dp, color: Color, strokeWidth: Dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val stroke = Stroke(width = strokeWidth.toPx(), cap = StrokeCap.Round)
        val w = this.size.width
        val h = this.size.height
        val centerY = h / 2
        // Bar
        drawLine(color, Offset(w * 0.18f, centerY), Offset(w * 0.82f, centerY), strokeWidth = stroke.width, cap = StrokeCap.Round)
        // Inner plates
        val inner = Size(w * 0.10f, h * 0.56f)
        drawRoundRect(color, Offset(w * 0.20f, centerY - inner.height / 2), inner, androidx.compose.ui.geometry.CornerRadius(w * 0.03f), style = stroke)
        drawRoundRect(color, Offset(w * 0.70f, centerY - inner.height / 2), inner, androidx.compose.ui.geometry.CornerRadius(w * 0.03f), style = stroke)
        // Outer plates
        val outer = Size(w * 0.08f, h * 0.38f)
        drawRoundRect(color, Offset(w * 0.08f, centerY - outer.height / 2), outer, androidx.compose.ui.geometry.CornerRadius(w * 0.03f), style = stroke)
        drawRoundRect(color, Offset(w * 0.84f, centerY - outer.height / 2), outer, androidx.compose.ui.geometry.CornerRadius(w * 0.03f), style = stroke)
    }
}
