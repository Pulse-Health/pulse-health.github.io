package health.pulse.strength.widgets.common

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import kotlin.math.max
import kotlin.math.min

/**
 * Charts for Glance. Glance cannot draw shapes, so charts are bitmaps; every bitmap here is a MASK (opaque white where something is
 * drawn) that the widget tints with a day/night `ColorProvider` through [MaskImage]. Stack several masks in a `Box` for several colours
 * (ring track + arc, line + record dot, one mask per heat level). Keep bitmaps small: a widget's bitmaps share the RemoteViews memory
 * limit (about 1.5 screens of pixels).
 */
object ChartBitmaps {
    /** Draws into a transparent ARGB bitmap with an anti-aliased white paint. */
    fun mask(widthPx: Int, heightPx: Int, draw: (canvas: Canvas, paint: Paint) -> Unit): Bitmap {
        val bitmap = Bitmap.createBitmap(max(1, widthPx), max(1, heightPx), Bitmap.Config.ARGB_8888)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = android.graphics.Color.WHITE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        draw(Canvas(bitmap), paint)
        return bitmap
    }

    /** A full ring (the track of a progress ring). */
    fun ringTrack(sizePx: Int, strokePx: Float): Bitmap = mask(sizePx, sizePx) { canvas, paint ->
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = strokePx
        canvas.drawOval(ringRect(sizePx, strokePx), paint)
    }

    /** The arc of a progress ring from the top, clockwise, `progress` in 0..1. */
    fun ringArc(sizePx: Int, strokePx: Float, progress: Float): Bitmap = mask(sizePx, sizePx) { canvas, paint ->
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = strokePx
        val sweep = 360f * min(1f, max(0f, progress))
        if (sweep > 0f) canvas.drawArc(ringRect(sizePx, strokePx), -90f, sweep, false, paint)
    }

    /** A 270 degree gauge track (open at the bottom) for the compact lock-screen style gauges. */
    fun gaugeTrack(sizePx: Int, strokePx: Float): Bitmap = mask(sizePx, sizePx) { canvas, paint ->
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = strokePx
        canvas.drawArc(ringRect(sizePx, strokePx), 135f, 270f, false, paint)
    }

    fun gaugeArc(sizePx: Int, strokePx: Float, progress: Float): Bitmap = mask(sizePx, sizePx) { canvas, paint ->
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = strokePx
        val sweep = 270f * min(1f, max(0f, progress))
        if (sweep > 0f) canvas.drawArc(ringRect(sizePx, strokePx), 135f, sweep, false, paint)
    }

    private fun ringRect(sizePx: Int, strokePx: Float): RectF {
        val half = strokePx / 2f
        return RectF(half, half, sizePx - half, sizePx - half)
    }

    /** The polyline through [values] (a trend line). Points are inset by [insetPx] so line caps and dots are not clipped. */
    fun line(widthPx: Int, heightPx: Int, values: List<Double>, strokePx: Float, insetPx: Float): Bitmap =
        mask(widthPx, heightPx) { canvas, paint ->
            if (values.size < 2) return@mask
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = strokePx
            val points = pointsFor(widthPx, heightPx, values, insetPx)
            val path = android.graphics.Path()
            points.forEachIndexed { index, point -> if (index == 0) path.moveTo(point.first, point.second) else path.lineTo(point.first, point.second) }
            canvas.drawPath(path, paint)
        }

    /** One dot per value, or only the dot at [onlyIndex] when given (the personal-record dot has its own mask and tint). */
    fun dots(widthPx: Int, heightPx: Int, values: List<Double>, radiusPx: Float, insetPx: Float, onlyIndex: Int? = null, skipIndex: Int? = null): Bitmap =
        mask(widthPx, heightPx) { canvas, paint ->
            paint.style = Paint.Style.FILL
            pointsFor(widthPx, heightPx, values, insetPx).forEachIndexed { index, point ->
                val wanted = (onlyIndex == null || onlyIndex == index) && skipIndex != index
                if (wanted) canvas.drawCircle(point.first, point.second, radiusPx, paint)
            }
        }

    private fun pointsFor(widthPx: Int, heightPx: Int, values: List<Double>, insetPx: Float): List<Pair<Float, Float>> {
        if (values.isEmpty()) return emptyList()
        val lowest = values.min()
        val range = max(values.max() - lowest, 1.0)
        val usableW = widthPx - 2 * insetPx
        val usableH = heightPx - 2 * insetPx
        return values.mapIndexed { index, value ->
            val x = if (values.size > 1) insetPx + usableW * index / (values.size - 1) else widthPx / 2f
            val y = insetPx + usableH * (1f - ((value - lowest) / range).toFloat())
            x to y
        }
    }

    /** A horizontal rounded bar filled to [fraction] (a meter's fill); pair it with [barTrack] for the unfilled part. */
    fun barFill(widthPx: Int, heightPx: Int, fraction: Float): Bitmap = mask(widthPx, heightPx) { canvas, paint ->
        paint.style = Paint.Style.FILL
        val width = max(heightPx.toFloat(), widthPx * min(1f, max(0f, fraction)))
        if (fraction > 0f) canvas.drawRoundRect(RectF(0f, 0f, width, heightPx.toFloat()), heightPx / 2f, heightPx / 2f, paint)
    }

    fun barTrack(widthPx: Int, heightPx: Int): Bitmap = mask(widthPx, heightPx) { canvas, paint ->
        paint.style = Paint.Style.FILL
        canvas.drawRoundRect(RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat()), heightPx / 2f, heightPx / 2f, paint)
    }
}
