package health.pulse.strength.widgets.extras

import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import health.pulse.strength.core.widgets.BodyMap
import health.pulse.strength.core.widgets.TimelineKind
import health.pulse.strength.widgets.common.ChartBitmaps
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Rasterises the shapes and spans of the extras widgets into the white-on-transparent masks that the widgets tint with a colour provider
 * (see [ChartBitmaps]). One mask per colour keeps every colour a day/night pair instead of baking it into the pixels.
 */
internal object ExtrasCharts {
    private const val YEAR_STUB = 0.06f

    /** Both silhouettes for one heat [level], [widthPx] wide; null when no muscle group sits at that level. */
    fun bodyMask(bodyMap: BodyMap, level: Int, widthPx: Int): Bitmap? {
        val regions = BodyMapShapes.regionsAt(bodyMap, level)
        if (regions.isEmpty()) return null
        val scale = widthPx / BodyMapShapes.WIDTH
        return ChartBitmaps.mask(widthPx, (BodyMapShapes.HEIGHT * scale).roundToInt()) { canvas, paint ->
            paint.style = Paint.Style.FILL
            for (region in regions) {
                val rect = RectF(region.x * scale, region.y * scale, (region.x + region.width) * scale, (region.y + region.height) * scale)
                canvas.drawRoundRect(rect, region.radius * scale, region.radius * scale, paint)
            }
        }
    }

    private fun barbellBitmap(layout: BarbellLayout, scale: Float, draw: (android.graphics.Canvas, Paint) -> Unit): Bitmap =
        ChartBitmaps.mask(ceil(layout.width * scale).toInt(), ceil(Barbell.HEIGHT * scale).toInt()) { canvas, paint ->
            paint.style = Paint.Style.FILL
            draw(canvas, paint)
        }

    /** The bar itself, the shaft and the sleeve end, at [scale] pixels per drawing unit. */
    fun barbellIron(layout: BarbellLayout, scale: Float): Bitmap = barbellBitmap(layout, scale) { canvas, paint ->
        val top = (Barbell.HEIGHT - Barbell.BAR_THICKNESS) / 2f * scale
        val bottom = top + Barbell.BAR_THICKNESS * scale
        canvas.drawRoundRect(RectF(0f, top, Barbell.SHAFT_WIDTH * scale, bottom), 2f * scale, 2f * scale, paint)
        val sleeveEnd = layout.sleeveStart + Barbell.SLEEVE_WIDTH
        canvas.drawRoundRect(RectF(layout.sleeveStart * scale, top, sleeveEnd * scale, bottom), 2f * scale, 2f * scale, paint)
    }

    /** The plates of one [color], or null when the bar carries none of that colour. */
    fun barbellPlates(layout: BarbellLayout, color: PlateColor, scale: Float): Bitmap? {
        val plates = layout.plates.filter { it.color == color }
        if (plates.isEmpty()) return null
        return barbellBitmap(layout, scale) { canvas, paint ->
            for (plate in plates) {
                val height = Barbell.PLATE_HEIGHT * plate.heightFraction
                val top = (Barbell.HEIGHT - height) / 2f
                val rect = RectF(plate.x * scale, top * scale, (plate.x + plate.width) * scale, (top + height) * scale)
                canvas.drawRoundRect(rect, 2.5f * scale, 2.5f * scale, paint)
            }
        }
    }

    /**
     * One mask per timeline kind in [kinds]: the [spans] of that kind as full-height stripes, with the outer corners of the whole bar
     * rounded by [radiusPx]. The stripes tile the bar, so the masks put together are one rounded bar.
     */
    fun timelineMasks(
        kinds: List<TimelineKind>,
        spans: List<ExtrasText.BarSpan>,
        widthPx: Int,
        heightPx: Int,
        radiusPx: Float,
    ): Map<TimelineKind, Bitmap> {
        val outline = ChartBitmaps.mask(widthPx, heightPx) { canvas, paint ->
            paint.style = Paint.Style.FILL
            canvas.drawRoundRect(RectF(0f, 0f, widthPx.toFloat(), heightPx.toFloat()), radiusPx, radiusPx, paint)
        }
        val keepInside = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN) }
        return kinds.associateWith { kind ->
            ChartBitmaps.mask(widthPx, heightPx) { canvas, paint ->
                paint.style = Paint.Style.FILL
                for (span in spans) if (span.kind == kind) canvas.drawRect(span.start.toFloat(), 0f, span.end.toFloat(), heightPx.toFloat(), paint)
                canvas.drawBitmap(outline, 0f, 0f, keepInside)
            }
        }
    }

    /** The monthly bars of the current month ([current] true) or of all the others; an empty month is a short stub so twelve slots show. */
    fun yearMask(bars: List<ExtrasText.YearBar>, current: Boolean, widthPx: Int, heightPx: Int): Bitmap {
        val gap = max(1f, widthPx * 0.03f)
        val barWidth = (widthPx - gap * (bars.size - 1)) / bars.size
        return ChartBitmaps.mask(widthPx, heightPx) { canvas, paint ->
            paint.style = Paint.Style.FILL
            bars.forEachIndexed { index, bar ->
                if (bar.isCurrent != current) return@forEachIndexed
                val left = index * (barWidth + gap)
                val top = heightPx - heightPx * max(bar.fraction, YEAR_STUB)
                canvas.drawRoundRect(RectF(left, top, left + barWidth, heightPx.toFloat()), min(barWidth / 2f, 3f), min(barWidth / 2f, 3f), paint)
            }
        }
    }
}
