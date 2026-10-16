package health.pulse.strength.widgets.extras

import com.google.common.truth.Truth.assertThat
import health.pulse.strength.core.MuscleGroup
import health.pulse.strength.core.widgets.BodyMap
import health.pulse.strength.core.widgets.MuscleLevel
import health.pulse.strength.widgets.WidgetFixtures
import org.junit.Test

/** The geometry behind the body map (WI-01) and the loaded bar (WI-05). */
class ExtrasShapesTest {
    private val preview = WidgetFixtures.preview

    private fun BodyRegion.overlaps(other: BodyRegion): Boolean =
        x < other.x + other.width && other.x < x + width && y < other.y + other.height && other.y < y + height

    @Test
    fun bothSilhouettesFitTheDrawingSpace() {
        for (region in BodyMapShapes.regions) {
            assertThat(region.x).isAtLeast(0f)
            assertThat(region.y).isAtLeast(0f)
            assertThat(region.x + region.width).isAtMost(BodyMapShapes.WIDTH)
            assertThat(region.y + region.height).isAtMost(BodyMapShapes.HEIGHT)
            assertThat(region.radius).isAtMost(minOf(region.width, region.height) / 2f)
        }
    }

    @Test
    fun noTwoRegionsOfAFigureOverlap() {
        for (figure in BodyFigure.entries) {
            val regions = BodyMapShapes.regions.filter { it.figure == figure }
            for (first in regions.indices) {
                for (second in first + 1 until regions.size) {
                    assertThat(regions[first].overlaps(regions[second])).isFalse()
                }
            }
        }
    }

    @Test
    fun theTwoFiguresDoNotTouchEachOther() {
        val front = BodyMapShapes.regions.filter { it.figure == BodyFigure.FRONT }
        val back = BodyMapShapes.regions.filter { it.figure == BodyFigure.BACK }
        assertThat(front.maxOf { it.x + it.width }).isLessThan(back.minOf { it.x })
    }

    @Test
    fun everyMuscleGroupCanBeSeenAndEachFigureHasAHead() {
        val drawn = BodyMapShapes.regions.mapNotNull { it.muscle }.toSet()
        assertThat(drawn).containsExactlyElementsIn(MuscleGroup.entries)
        for (figure in BodyFigure.entries) {
            assertThat(BodyMapShapes.regions.count { it.figure == figure && it.muscle == null }).isEqualTo(1)
        }
    }

    @Test
    fun theShadedGroupsAreChestOnTheFrontAndBackOnTheBack() {
        fun figuresOf(muscle: MuscleGroup) = BodyMapShapes.regions.filter { it.muscle == muscle }.map { it.figure }.toSet()
        assertThat(figuresOf(MuscleGroup.CHEST)).containsExactly(BodyFigure.FRONT)
        assertThat(figuresOf(MuscleGroup.BACK)).containsExactly(BodyFigure.BACK)
        for (muscle in listOf(MuscleGroup.SHOULDERS, MuscleGroup.ARMS, MuscleGroup.LEGS, MuscleGroup.CORE)) {
            assertThat(figuresOf(muscle)).containsExactly(BodyFigure.FRONT, BodyFigure.BACK)
        }
    }

    @Test
    fun levelsComeFromTheSnapshotAndMissingGroupsAreUntouched() {
        val levels = BodyMapShapes.levels(preview.bodyMap)
        assertThat(levels[MuscleGroup.CHEST]).isEqualTo(3)
        assertThat(levels[MuscleGroup.BACK]).isEqualTo(2)
        assertThat(levels[MuscleGroup.LEGS]).isEqualTo(0)
        val partial = BodyMap(levels = listOf(MuscleLevel(MuscleGroup.ARMS, 2)))
        assertThat(BodyMapShapes.levels(partial).getValue(MuscleGroup.CHEST)).isEqualTo(0)
        assertThat(BodyMapShapes.levels(partial).keys).containsExactlyElementsIn(MuscleGroup.entries)
    }

    @Test
    fun levelsAreClampedToTheDrawnSteps() {
        val wild = BodyMap(levels = listOf(MuscleLevel(MuscleGroup.CHEST, 9), MuscleLevel(MuscleGroup.BACK, -4)))
        assertThat(BodyMapShapes.levels(wild).getValue(MuscleGroup.CHEST)).isEqualTo(3)
        assertThat(BodyMapShapes.levels(wild).getValue(MuscleGroup.BACK)).isEqualTo(0)
    }

    @Test
    fun eachRegionIsDrawnIntoExactlyOneLevelMask() {
        val masks = (0..BodyMapShapes.MAX_LEVEL).map { BodyMapShapes.regionsAt(preview.bodyMap, it) }
        assertThat(masks.sumOf { it.size }).isEqualTo(BodyMapShapes.regions.size)
        assertThat(masks.flatten()).containsNoDuplicates()
    }

    @Test
    fun theMasksOfThePreviewHoldTheGroupsOfTheirLevel() {
        val bodyMap = preview.bodyMap
        assertThat(BodyMapShapes.regionsAt(bodyMap, 3).map { it.muscle }).containsExactly(MuscleGroup.CHEST)
        assertThat(BodyMapShapes.regionsAt(bodyMap, 2).mapNotNull { it.muscle }.toSet())
            .containsExactly(MuscleGroup.BACK, MuscleGroup.SHOULDERS)
        assertThat(BodyMapShapes.regionsAt(bodyMap, 1).mapNotNull { it.muscle }.toSet()).containsExactly(MuscleGroup.ARMS)
        // Level 0: the heads, the untouched legs and the untouched core.
        val untouched = BodyMapShapes.regionsAt(bodyMap, 0)
        assertThat(untouched.count { it.muscle == null }).isEqualTo(2)
        assertThat(untouched.mapNotNull { it.muscle }.toSet()).containsExactly(MuscleGroup.LEGS, MuscleGroup.CORE)
    }

    @Test
    fun aFreshInstallDrawsEverythingUntouched() {
        val fresh = WidgetFixtures.empty().bodyMap
        assertThat(BodyMapShapes.regionsAt(fresh, 0)).hasSize(BodyMapShapes.regions.size)
        for (level in 1..BodyMapShapes.MAX_LEVEL) assertThat(BodyMapShapes.regionsAt(fresh, level)).isEmpty()
    }

    // Barbell

    @Test
    fun plateColoursFollowTheCompetitionCodeAndRepeatForSmallPlates() {
        assertThat(Barbell.plateColor(25.0)).isEqualTo(PlateColor.RED)
        assertThat(Barbell.plateColor(20.0)).isEqualTo(PlateColor.BLUE)
        assertThat(Barbell.plateColor(15.0)).isEqualTo(PlateColor.YELLOW)
        assertThat(Barbell.plateColor(10.0)).isEqualTo(PlateColor.GREEN)
        assertThat(Barbell.plateColor(5.0)).isEqualTo(PlateColor.WHITE)
        assertThat(Barbell.plateColor(2.5)).isEqualTo(PlateColor.RED)
        assertThat(Barbell.plateColor(2.0)).isEqualTo(PlateColor.BLUE)
        assertThat(Barbell.plateColor(1.5)).isEqualTo(PlateColor.YELLOW)
        assertThat(Barbell.plateColor(1.25)).isEqualTo(PlateColor.GREEN)
        assertThat(Barbell.plateColor(0.5)).isEqualTo(PlateColor.WHITE)
    }

    @Test
    fun theBarbellLaysThePlatesOutLeftToRightWithTheSleeveAfterThem() {
        val layout = Barbell.layout(preview.loadedBar!!.platesPerSide)
        assertThat(layout.plates.map { it.weightKg }).containsExactly(20.0, 10.0, 2.5).inOrder()
        assertThat(layout.plates.map { it.color }).containsExactly(PlateColor.BLUE, PlateColor.GREEN, PlateColor.RED).inOrder()
        // Each plate starts after the one before it, and the sleeve end starts after the last plate.
        layout.plates.zipWithNext { first, second -> assertThat(second.x).isGreaterThan(first.x + first.width) }
        assertThat(layout.plates.first().x).isGreaterThan(Barbell.SHAFT_WIDTH)
        assertThat(layout.sleeveStart).isGreaterThan(layout.plates.last().x + layout.plates.last().width)
        assertThat(layout.width).isWithin(0.001f).of(layout.sleeveStart + Barbell.SLEEVE_WIDTH)
    }

    @Test
    fun heavierPlatesAreTallerAndThickerAndNeverExceedTheDrawing() {
        val layout = Barbell.layout(listOf(25.0, 20.0, 10.0, 5.0, 2.5, 1.25))
        layout.plates.zipWithNext { heavier, lighter ->
            assertThat(heavier.heightFraction).isAtLeast(lighter.heightFraction)
            assertThat(heavier.width).isAtLeast(lighter.width)
        }
        for (plate in layout.plates) {
            assertThat(plate.heightFraction).isAtMost(1f)
            assertThat(plate.heightFraction * Barbell.PLATE_HEIGHT).isAtMost(Barbell.HEIGHT)
        }
    }

    @Test
    fun aBarWithoutPlatesIsJustTheShaftAndTheSleeve() {
        val layout = Barbell.layout(emptyList())
        assertThat(layout.plates).isEmpty()
        assertThat(layout.width).isEqualTo(Barbell.SHAFT_WIDTH + 3f + Barbell.SLEEVE_WIDTH)
    }
}
