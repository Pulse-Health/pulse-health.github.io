package health.pulse.strength.widgets.extras

import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.widgets.BodyMap
import kotlin.math.sqrt

/**
 * The geometry behind the two drawn widgets, as plain numbers: the body silhouettes of WI-01 and the barbell of WI-05. The widgets only
 * rasterise these shapes into bitmap masks, so which muscle sits where and which plate gets which colour can be unit-tested.
 */

internal enum class BodyFigure { FRONT, BACK }

/** One rounded rectangle of a silhouette in the 150 x 142 drawing space of the canvas; [muscle] is null for the head. */
internal data class BodyRegion(
    val figure: BodyFigure,
    val muscle: MuscleGroup?,
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float,
    val radius: Float,
)

/** Front and back silhouettes after the canvas figures, with every muscle group on both so a gap shows from either side. */
internal object BodyMapShapes {
    const val WIDTH = 150f
    const val HEIGHT = 142f
    const val MAX_LEVEL = 3

    val regions: List<BodyRegion> = silhouette(BodyFigure.FRONT, left = 8f) + silhouette(BodyFigure.BACK, left = 80f)

    private fun silhouette(figure: BodyFigure, left: Float): List<BodyRegion> {
        val front = figure == BodyFigure.FRONT
        fun region(muscle: MuscleGroup?, x: Float, y: Float, width: Float, height: Float, radius: Float) =
            BodyRegion(figure, muscle, left + x, 4f + y, width, height, radius)
        return listOf(
            region(null, 21f, 1f, 18f, 18f, 9f),
            region(if (front) MuscleGroup.CHEST else MuscleGroup.BACK, 12f, 22f, 36f, if (front) 22f else 30f, 8f),
            region(MuscleGroup.CORE, 15f, if (front) 46f else 54f, 30f, if (front) 24f else 16f, 6f),
            region(MuscleGroup.SHOULDERS, 2f, 22f, 9f, 17f, 4.5f),
            region(MuscleGroup.SHOULDERS, 49f, 22f, 9f, 17f, 4.5f),
            region(MuscleGroup.ARMS, 2f, 41f, 9f, 21f, 4.5f),
            region(MuscleGroup.ARMS, 49f, 41f, 9f, 21f, 4.5f),
            region(MuscleGroup.LEGS, 14f, 72f, 14f, 62f, 6f),
            region(MuscleGroup.LEGS, 32f, 72f, 14f, 62f, 6f),
        )
    }

    /** The 0...3 load of every muscle group this week; a group missing from the snapshot counts as untouched. */
    fun levels(bodyMap: BodyMap): Map<MuscleGroup, Int> =
        MuscleGroup.entries.associateWith { muscle ->
            (bodyMap.levels.firstOrNull { it.muscle == muscle }?.level ?: 0).coerceIn(0, MAX_LEVEL)
        }

    /** The regions drawn into the mask of [level]: the muscles at that level, and the head (always level 0). */
    fun regionsAt(bodyMap: BodyMap, level: Int): List<BodyRegion> {
        val levels = levels(bodyMap)
        return regions.filter { region -> (region.muscle?.let { levels.getValue(it) } ?: 0) == level }
    }
}

internal enum class PlateColor { RED, BLUE, YELLOW, GREEN, WHITE }

/** One plate of the barbell drawing: [x] and [width] in dp from the left end of the shaft, [heightFraction] of the tallest plate. */
internal data class PlateShape(val weightKg: Double, val color: PlateColor, val x: Float, val width: Float, val heightFraction: Float)

/** The half barbell, left to right: shaft, the plates in order, sleeve end (starting at [sleeveStart]); [width] dp in all. */
internal data class BarbellLayout(val plates: List<PlateShape>, val sleeveStart: Float, val width: Float)

internal object Barbell {
    const val SHAFT_WIDTH = 22f
    const val SLEEVE_WIDTH = 30f
    const val BAR_THICKNESS = 6f
    const val PLATE_HEIGHT = 52f

    /** The height of the whole drawing: the tallest plate with a little air above and below. */
    const val HEIGHT = 56f
    private const val GAP = 3f

    /** The colour of a plate of [kg]: the international competition colours, which the smaller plates repeat. */
    fun plateColor(kg: Double): PlateColor = when {
        kg >= 25.0 -> PlateColor.RED
        kg >= 20.0 -> PlateColor.BLUE
        kg >= 15.0 -> PlateColor.YELLOW
        kg >= 10.0 -> PlateColor.GREEN
        kg >= 5.0 -> PlateColor.WHITE
        kg >= 2.5 -> PlateColor.RED
        kg >= 2.0 -> PlateColor.BLUE
        kg >= 1.5 -> PlateColor.YELLOW
        kg >= 1.0 -> PlateColor.GREEN
        else -> PlateColor.WHITE
    }

    /** Lays the plates (heaviest first, as the plate calculator returns them) along the bar; heavier plates are taller and thicker. */
    fun layout(platesPerSide: List<Double>): BarbellLayout {
        var x = SHAFT_WIDTH + GAP
        val plates = platesPerSide.map { kg ->
            val reach = sqrt(kg.coerceIn(0.0, 20.0) / 20.0).toFloat()
            val plate = PlateShape(kg, plateColor(kg), x, width = 6f + 4f * reach, heightFraction = 0.4f + 0.6f * reach)
            x += plate.width + GAP
            plate
        }
        return BarbellLayout(plates, sleeveStart = x, width = x + SLEEVE_WIDTH)
    }
}
