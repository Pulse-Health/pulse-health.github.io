package health.pulse.strength.wear.tiles

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import androidx.core.graphics.createBitmap
import java.io.ByteArrayOutputStream
import kotlin.math.max

/**
 * The trend line of the lift tile, drawn as a small PNG and shipped as an inline tile image resource. A tile cannot draw polylines
 * (ProtoLayout has boxes, arcs and images), and a PNG keeps the canvas look: a rounded green line through the sessions with the
 * personal record as a larger gold dot. A few hundred bytes of PNG per tile, regenerated only when the lift's points change.
 */
internal object Sparkline {
    /** A position inside the image, in pixels. */
    data class Point(val x: Float, val y: Float)

    /**
     * Where each of [values] sits in a [width] x [height] box with [inset] free on every side: evenly spaced from left to right, the
     * highest value at the top and the lowest at the bottom. One value or a flat series sits at half height.
     */
    fun points(values: List<Double>, width: Float, height: Float, inset: Float): List<Point> {
        if (values.isEmpty()) return emptyList()
        val low = values.min()
        val high = values.max()
        val usableWidth = max(width - 2 * inset, 0f)
        val usableHeight = max(height - 2 * inset, 0f)
        return values.mapIndexed { index, value ->
            val x = if (values.size == 1) width / 2f else inset + usableWidth * index / (values.size - 1)
            val share = if (high == low) 0.5f else ((value - low) / (high - low)).toFloat()
            Point(x, inset + usableHeight * (1f - share))
        }
    }

    /** The PNG of the line through [values], the record at [recordIndex] in gold; [density] scales the stroke and the dots. */
    fun png(values: List<Double>, recordIndex: Int?, widthPx: Int, heightPx: Int, density: Float): ByteArray {
        val bitmap = createBitmap(max(widthPx, 1), max(heightPx, 1))
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        val recordRadius = RECORD_RADIUS_DP * density
        val points = points(values, bitmap.width.toFloat(), bitmap.height.toFloat(), recordRadius + 1f)

        if (points.size > 1) {
            val path = Path()
            points.forEachIndexed { index, point -> if (index == 0) path.moveTo(point.x, point.y) else path.lineTo(point.x, point.y) }
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = STROKE_DP * density
            paint.color = TileColors.GREEN
            canvas.drawPath(path, paint)
        }
        paint.style = Paint.Style.FILL
        points.forEachIndexed { index, point ->
            val isRecord = index == recordIndex
            paint.color = if (isRecord) TileColors.GOLD else TileColors.GREEN
            canvas.drawCircle(point.x, point.y, if (isRecord) recordRadius else DOT_RADIUS_DP * density, paint)
        }

        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, PNG_QUALITY, out)
        bitmap.recycle()
        return out.toByteArray()
    }

    private const val STROKE_DP = 2.5f
    private const val DOT_RADIUS_DP = 2.5f
    private const val RECORD_RADIUS_DP = 4.5f
    private const val PNG_QUALITY = 100
}
