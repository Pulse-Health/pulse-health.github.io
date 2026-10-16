package health.pulse.strength.core

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import org.junit.Test

// Port of MetricsTests.swift.

class MetricsTests {

    // region Estimated1RM

    @Test
    fun testEpleyBenchExamples() {
        assertThat(Estimated1RM.epley(85.0, 5)).isWithin(1e-6).of(99.1666667)
        assertThat(Estimated1RM.epley(85.0, 6)).isWithin(1e-9).of(102.0)
        assertThat(Estimated1RM.epley(82.5, 6)).isWithin(1e-9).of(99.0)
        assertThat(Estimated1RM.epley(80.0, 6)).isWithin(1e-9).of(96.0)
    }

    @Test
    fun testEpleyMatchesTheFormula() {
        assertThat(Estimated1RM.epley(100.0, 1)).isWithin(1e-9).of(100 * (1 + 1.0 / 30))
        assertThat(Estimated1RM.epley(60.0, 30)).isWithin(1e-9).of(120.0)
        assertThat(Estimated1RM.epley(20.0, 15)).isWithin(1e-9).of(30.0)
        assertThat(Estimated1RM.epley(0.5, 3)).isWithin(1e-9).of(0.55)
    }

    @Test
    fun testEpleyIsZeroForZeroOrNegativeInput() {
        assertThat(Estimated1RM.epley(0.0, 5)).isEqualTo(0.0)
        assertThat(Estimated1RM.epley(-10.0, 5)).isEqualTo(0.0)
        assertThat(Estimated1RM.epley(85.0, 0)).isEqualTo(0.0)
        assertThat(Estimated1RM.epley(85.0, -3)).isEqualTo(0.0)
        assertThat(Estimated1RM.epley(0.0, 0)).isEqualTo(0.0)
        assertThat(Estimated1RM.epley(-85.0, -5)).isEqualTo(0.0)
        assertThat(Estimated1RM.epley(-0.0, 5)).isEqualTo(0.0)
    }

    @Test
    fun testEpleyIsZeroForNonFiniteWeight() {
        assertThat(Estimated1RM.epley(Double.NaN, 5)).isEqualTo(0.0)
        assertThat(Estimated1RM.epley(Double.POSITIVE_INFINITY, 5)).isEqualTo(0.0)
        assertThat(Estimated1RM.epley(Double.NEGATIVE_INFINITY, 5)).isEqualTo(0.0)
    }

    @Test
    fun testEpleyGrowsWithWeightAndReps() {
        val rng = MetricsFuzzRNG(7L)
        repeat(200) {
            val kg = (1 + rng.nextBelow(4000)).toDouble() / 8
            val reps = 1 + rng.nextBelow(40)
            val value = Estimated1RM.epley(kg, reps)
            assertThat(value).isGreaterThan(kg)
            assertThat(Estimated1RM.epley(kg, reps + 1)).isGreaterThan(value)
            assertThat(Estimated1RM.epley(kg + 0.5, reps)).isGreaterThan(value)
        }
    }

    // endregion

    // region PlateCalculator

    @Test
    fun testAvailablePlates() {
        assertThat(PlateCalculator.availablePlates).isEqualTo(listOf(25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25))
    }

    @Test
    fun testPlanFor82Point5OnTwentyKiloBar() {
        val plan = PlateCalculator.plan(82.5, 20.0)
        assertThat(plan).isEqualTo(PlatePlan(perSide = listOf(25.0, 5.0, 1.25), leftoverKg = 0.0))
    }

    @Test
    fun testPlanFor100OnTwentyKiloBar() {
        val plan = PlateCalculator.plan(100.0, 20.0)
        assertThat(plan).isEqualTo(PlatePlan(perSide = listOf(25.0, 15.0), leftoverKg = 0.0))
    }

    @Test
    fun testPlanForEmptyBar() {
        val plan = PlateCalculator.plan(20.0, 20.0)
        assertThat(plan).isEqualTo(PlatePlan(perSide = emptyList(), leftoverKg = 0.0))
    }

    @Test
    fun testPlanBelowTheBarIsNil() {
        assertThat(PlateCalculator.plan(19.0, 20.0)).isNull()
        assertThat(PlateCalculator.plan(0.0, 20.0)).isNull()
        assertThat(PlateCalculator.plan(-5.0, 20.0)).isNull()
        assertThat(PlateCalculator.plan(9.99, 10.0)).isNull()
        assertThat(PlateCalculator.plan(19.99, 20.0)).isNull()
    }

    @Test
    fun testPlanWithLeftover() {
        val plan = PlateCalculator.plan(21.0, 20.0)
        assertThat(plan).isEqualTo(PlatePlan(perSide = emptyList(), leftoverKg = 0.5))
        assertThat(PlateCalculator.plan(23.0, 20.0)).isEqualTo(PlatePlan(perSide = listOf(1.25), leftoverKg = 0.25))
        assertThat(PlateCalculator.plan(87.0, 20.0)).isEqualTo(PlatePlan(perSide = listOf(25.0, 5.0, 2.5), leftoverKg = 1.0))
        assertThat(PlateCalculator.plan(20.1, 20.0)).isEqualTo(PlatePlan(perSide = emptyList(), leftoverKg = 0.05))
        assertThat(PlateCalculator.plan(20.06, 20.0)).isEqualTo(PlatePlan(perSide = emptyList(), leftoverKg = 0.03))
    }

    @Test
    fun testSmallestPlatesGiveTwoAndAHalfKiloSteps() {
        assertThat(PlateCalculator.plan(22.5, 20.0)).isEqualTo(PlatePlan(perSide = listOf(1.25), leftoverKg = 0.0))
        assertThat(PlateCalculator.plan(25.0, 20.0)).isEqualTo(PlatePlan(perSide = listOf(2.5), leftoverKg = 0.0))
        assertThat(PlateCalculator.plan(27.5, 20.0)).isEqualTo(PlatePlan(perSide = listOf(2.5, 1.25), leftoverKg = 0.0))
        assertThat(PlateCalculator.plan(30.0, 20.0)).isEqualTo(PlatePlan(perSide = listOf(5.0), leftoverKg = 0.0))
        assertThat(PlateCalculator.plan(32.5, 20.0)).isEqualTo(PlatePlan(perSide = listOf(5.0, 1.25), leftoverKg = 0.0))
    }

    @Test
    fun testPlanIsGreedyAndRepeatsPlates() {
        assertThat(PlateCalculator.plan(140.0, 20.0)).isEqualTo(PlatePlan(perSide = listOf(25.0, 25.0, 10.0), leftoverKg = 0.0))
        assertThat(PlateCalculator.plan(220.0, 20.0)).isEqualTo(PlatePlan(perSide = listOf(25.0, 25.0, 25.0, 25.0), leftoverKg = 0.0))
        assertThat(PlateCalculator.plan(120.0, 20.0)).isEqualTo(PlatePlan(perSide = listOf(25.0, 25.0), leftoverKg = 0.0))
        assertThat(PlateCalculator.plan(60.0, 20.0)).isEqualTo(PlatePlan(perSide = listOf(20.0), leftoverKg = 0.0))
        assertThat(PlateCalculator.plan(200.0, 20.0)).isEqualTo(PlatePlan(perSide = listOf(25.0, 25.0, 25.0, 15.0), leftoverKg = 0.0))
    }

    @Test
    fun testPlanWithTenKiloBar() {
        assertThat(PlateCalculator.plan(25.0, 10.0)).isEqualTo(PlatePlan(perSide = listOf(5.0, 2.5), leftoverKg = 0.0))
        assertThat(PlateCalculator.plan(30.0, 10.0)).isEqualTo(PlatePlan(perSide = listOf(10.0), leftoverKg = 0.0))
        assertThat(PlateCalculator.plan(10.0, 10.0)).isEqualTo(PlatePlan(perSide = emptyList(), leftoverKg = 0.0))
        val skull = ExerciseLibrary.exercise("skull")
        assertThat(PlateCalculator.plan(30.0, skull?.barKg ?: 0.0)).isEqualTo(PlatePlan(perSide = listOf(10.0), leftoverKg = 0.0))
    }

    @Test
    fun testPlanToleratesFloatingPointNoise() {
        // 1e-9 kg below an exact multiple must still give the exact plate, with no negative leftover.
        val nearlyExact = PlateCalculator.plan(22.5 - 1e-9, 20.0)
        assertThat(nearlyExact?.perSide).isEqualTo(listOf(1.25))
        assertThat(nearlyExact?.leftoverKg).isEqualTo(0.0)
        assertThat(isPositiveSign(nearlyExact!!.leftoverKg)).isTrue()
        // Slightly below the bar is the bar.
        val belowBar = PlateCalculator.plan(19.999, 20.0)
        assertThat(belowBar).isEqualTo(PlatePlan(perSide = emptyList(), leftoverKg = 0.0))
        assertThat(isPositiveSign(belowBar!!.leftoverKg)).isTrue()
        // Slightly above is still the bar with a leftover below the smallest plate.
        assertThat(PlateCalculator.plan(82.5 + 1e-9, 20.0)?.perSide).isEqualTo(listOf(25.0, 5.0, 1.25))
        assertThat(PlateCalculator.plan(0.1 + 0.2 + 19.7, 20.0)?.perSide).isEqualTo(emptyList<Double>())
    }

    /** Swift `x.sign == .plus` (a negative zero has the sign `.minus`). */
    private fun isPositiveSign(x: Double): Boolean = Math.copySign(1.0, x) > 0

    @Test
    fun testPlanRejectsInvalidInput() {
        assertThat(PlateCalculator.plan(Double.NaN, 20.0)).isNull()
        assertThat(PlateCalculator.plan(Double.POSITIVE_INFINITY, 20.0)).isNull()
        assertThat(PlateCalculator.plan(100.0, Double.NaN)).isNull()
        assertThat(PlateCalculator.plan(100.0, -20.0)).isNull()
        assertWithMessage("absurd totals must not allocate millions of plates").that(PlateCalculator.plan(1e12, 20.0)).isNull()
        assertThat(PlateCalculator.plan(1_000.0, 20.0)).isNotNull()
    }

    @Test
    fun testPlanWithoutBar() {
        assertThat(PlateCalculator.plan(50.0, 0.0)).isEqualTo(PlatePlan(perSide = listOf(25.0), leftoverKg = 0.0))
        assertThat(PlateCalculator.plan(0.0, 0.0)).isEqualTo(PlatePlan(perSide = emptyList(), leftoverKg = 0.0))
    }

    @Test
    fun testPlanInvariantsOnRandomWeights() {
        val rng = MetricsFuzzRNG(42L)
        repeat(500) {
            val bar: Double = if (rng.nextBelow(2) == 0) 20.0 else 10.0
            val total = bar + rng.nextBelow(1200).toDouble() / 4        // up to 300 kg above the bar in 0.25 kg steps
            val plan = PlateCalculator.plan(total, bar)
            if (plan == null) {
                throw AssertionError("no plan for $total / $bar")
            }
            val perSide = (total - bar) / 2
            assertWithMessage("$total / $bar").that(plan.perSide.fold(0.0) { acc, plate -> acc + plate } + plan.leftoverKg).isWithin(0.0051).of(perSide)
            assertWithMessage("heaviest plate first for $total").that(plan.perSide).isEqualTo(plan.perSide.sortedDescending())
            assertThat(plan.perSide.all { PlateCalculator.availablePlates.contains(it) }).isTrue()
            assertThat(plan.leftoverKg).isAtLeast(0.0)
            assertThat(plan.leftoverKg).isLessThan(1.25 + 0.0051)
            if ((total - bar) % 2.5 == 0.0) {
                assertWithMessage("multiples of 2.5 kg are always loadable: $total / $bar").that(plan.leftoverKg).isEqualTo(0.0)
            }
        }
    }

    @Test
    fun testPlatePlanIsEquatable() {
        val plan = PlatePlan(perSide = listOf(25.0, 5.0), leftoverKg = 0.0)
        assertThat(plan).isEqualTo(PlatePlan(perSide = listOf(25.0, 5.0), leftoverKg = 0.0))
        assertThat(plan).isNotEqualTo(PlatePlan(perSide = listOf(25.0, 5.0), leftoverKg = 0.25))
        assertThat(plan).isNotEqualTo(PlatePlan(perSide = listOf(25.0), leftoverKg = 0.0))
        val changed = plan.copy(perSide = listOf(20.0), leftoverKg = 1.0)
        assertThat(changed.perSide).isEqualTo(listOf(20.0))
        assertThat(changed.leftoverKg).isEqualTo(1.0)
    }

    // endregion

    // region NumberText.kg

    @Test
    fun testKgBasics() {
        assertThat(NumberText.kg(82.5)).isEqualTo("82.5")
        assertThat(NumberText.kg(80.0)).isEqualTo("80")
        assertThat(NumberText.kg(0.0)).isEqualTo("0")
        assertThat(NumberText.kg(100.0)).isEqualTo("100")
        assertWithMessage("kilograms are not grouped").that(NumberText.kg(1000.0)).isEqualTo("1000")
        assertThat(NumberText.kg(62.5)).isEqualTo("62.5")
        assertThat(NumberText.kg(12.3)).isEqualTo("12.3")
        assertThat(NumberText.kg(12.34)).isEqualTo("12.34")
        assertThat(NumberText.kg(0.1)).isEqualTo("0.1")
        assertThat(NumberText.kg(0.05)).isEqualTo("0.05")
        assertThat(NumberText.kg(0.01)).isEqualTo("0.01")
    }

    @Test
    fun testKgRoundsToTwoDecimals() {
        assertThat(NumberText.kg(82.50001)).isEqualTo("82.5")
        assertThat(NumberText.kg(82.5000001)).isEqualTo("82.5")
        assertThat(NumberText.kg(82.4999999)).isEqualTo("82.5")
        assertThat(NumberText.kg(0.004)).isEqualTo("0")
        assertThat(NumberText.kg(0.006)).isEqualTo("0.01")
        assertThat(NumberText.kg(99.1666666)).isEqualTo("99.17")
        assertThat(NumberText.kg(7.0049)).isEqualTo("7")
        assertThat(NumberText.kg(27.499999)).isEqualTo("27.5")
        assertThat(NumberText.kg(0.994)).isEqualTo("0.99")
        assertThat(NumberText.kg(1234567.891)).isEqualTo("1234567.89")
    }

    @Test
    fun testKgMatchesThePrototypeRounding() {
        // Expected values were produced by the prototype's `String(Math.round(n * 100) / 100)`.
        val cases: List<Pair<Double, String>> = listOf(
            82.5 to "82.5", 80.0 to "80", 82.50001 to "82.5", 82.5000001 to "82.5", 0.004 to "0", 0.006 to "0.01",
            0.1 to "0.1", 0.05 to "0.05", 0.01 to "0.01", 12.34 to "12.34", 12.3 to "12.3", 1.005 to "1",
            1.255 to "1.25", 99.1666666 to "99.17", 102.0 to "102", 2.675 to "2.68", 0.285 to "0.28",
            1234567.891 to "1234567.89", 100.0 to "100", 1000.0 to "1000", 0.995 to "1", 0.994 to "0.99",
            7.0049 to "7", 62.5 to "62.5", 27.499999 to "27.5", java.lang.Double.MIN_VALUE to "0",   // Swift `Double.leastNonzeroMagnitude`
        )
        for ((value, expected) in cases) {
            assertWithMessage("kg($value)").that(NumberText.kg(value)).isEqualTo(expected)
        }
    }

    @Test
    fun testKgNegativeValues() {
        assertThat(NumberText.kg(-5.0)).isEqualTo("-5")
        assertThat(NumberText.kg(-82.5)).isEqualTo("-82.5")
        assertThat(NumberText.kg(-12.34)).isEqualTo("-12.34")
        assertThat(NumberText.kg(-0.006)).isEqualTo("-0.01")
        assertThat(NumberText.kg(-0.05)).isEqualTo("-0.05")
        assertThat(NumberText.kg(-82.5000001)).isEqualTo("-82.5")
    }

    @Test
    fun testKgNeverPrintsNegativeZero() {
        assertThat(NumberText.kg(-0.004)).isEqualTo("0")
        assertThat(NumberText.kg(-0.0)).isEqualTo("0")
        assertThat(NumberText.kg(-1e-300)).isEqualTo("0")
    }

    @Test
    fun testKgOfNonFiniteAndHugeValues() {
        assertThat(NumberText.kg(Double.NaN)).isEqualTo("0")
        assertThat(NumberText.kg(Double.POSITIVE_INFINITY)).isEqualTo("0")
        assertThat(NumberText.kg(Double.NEGATIVE_INFINITY)).isEqualTo("0")
        assertThat(NumberText.kg(1e30)).isEqualTo("90000000000000")
        assertThat(NumberText.kg(-1e30)).isEqualTo("-90000000000000")
    }

    @Test
    fun testKgOutputIsAlwaysCanonicalOnRandomValues() {
        val rng = MetricsFuzzRNG(99L)
        repeat(2000) {
            val value = (rng.nextBelow(4_000_001).toDouble() - 2_000_000) / 1000   // -2000.000 ... 2000.000
            val text = NumberText.kg(value)
            assertWithMessage(text).that(text.contains(",")).isFalse()
            assertThat(text).isNotEqualTo("-0")
            if (text.contains(".")) {
                assertWithMessage("trailing zero in $text").that(text.endsWith("0")).isFalse()
                assertWithMessage(text).that(text.split(".")[1].length).isAtMost(2)
            }
            val parsed = text.toDoubleOrNull()
            if (parsed == null) {
                throw AssertionError("not a number: $text")
            }
            assertWithMessage("kg($value) = $text").that(parsed).isWithin(0.005 + 1e-9).of(value)
        }
    }

    // endregion

    // region NumberText.thousands

    @Test
    fun testThousandsGrouping() {
        assertThat(NumberText.thousands(0.0)).isEqualTo("0")
        assertThat(NumberText.thousands(7.0)).isEqualTo("7")
        assertThat(NumberText.thousands(999.0)).isEqualTo("999")
        assertThat(NumberText.thousands(1000.0)).isEqualTo("1,000")
        assertThat(NumberText.thousands(12345.0)).isEqualTo("12,345")
        assertThat(NumberText.thousands(123456.0)).isEqualTo("123,456")
        assertThat(NumberText.thousands(1234567.0)).isEqualTo("1,234,567")
        assertThat(NumberText.thousands(1980.4)).isEqualTo("1,980")
    }

    @Test
    fun testThousandsRoundingEdges() {
        assertThat(NumberText.thousands(1979.5)).isEqualTo("1,980")
        assertThat(NumberText.thousands(1979.4999)).isEqualTo("1,979")
        assertThat(NumberText.thousands(12345.5)).isEqualTo("12,346")
        assertThat(NumberText.thousands(999.5)).isEqualTo("1,000")
        assertThat(NumberText.thousands(99999.5)).isEqualTo("100,000")
        assertThat(NumberText.thousands(1999999.5)).isEqualTo("2,000,000")
        assertThat(NumberText.thousands(0.4)).isEqualTo("0")
        assertThat(NumberText.thousands(0.5)).isEqualTo("1")
        assertThat(NumberText.thousands(1234.5678)).isEqualTo("1,235")
    }

    @Test
    fun testThousandsNegativeValues() {
        assertThat(NumberText.thousands(-1.0)).isEqualTo("-1")
        assertThat(NumberText.thousands(-999.0)).isEqualTo("-999")
        assertThat(NumberText.thousands(-1000.0)).isEqualTo("-1,000")
        assertThat(NumberText.thousands(-1234567.0)).isEqualTo("-1,234,567")
        assertThat(NumberText.thousands(-1979.5)).isEqualTo("-1,980")
        assertThat(NumberText.thousands(-1980.4)).isEqualTo("-1,980")
        assertThat(NumberText.thousands(-0.4)).isEqualTo("0")
        assertThat(NumberText.thousands(-0.0)).isEqualTo("0")
    }

    @Test
    fun testThousandsOfNonFiniteAndHugeValues() {
        assertThat(NumberText.thousands(Double.NaN)).isEqualTo("0")
        assertThat(NumberText.thousands(Double.POSITIVE_INFINITY)).isEqualTo("0")
        assertThat(NumberText.thousands(Double.NEGATIVE_INFINITY)).isEqualTo("0")
        assertThat(NumberText.thousands(1e30)).isEqualTo("9,000,000,000,000,000")
        assertThat(NumberText.thousands(-1e30)).isEqualTo("-9,000,000,000,000,000")
    }

    @Test
    fun testThousandsRoundTripsOnRandomValues() {
        val rng = MetricsFuzzRNG(1234L)
        repeat(2000) {
            val value = (rng.nextBelow(40_000_001).toDouble() - 20_000_000) / 8     // eighths, so ties occur
            val text = NumberText.thousands(value)
            val digits = text.replace(",", "")
            val parsed = digits.toLongOrNull()
            if (parsed == null) {
                throw AssertionError("not an integer: $text")
            }
            assertWithMessage("thousands($value) = $text").that(parsed.toDouble()).isEqualTo(value.roundedAwayFromZero() + 0.0)
            val groups = text.replace("-", "").split(",")
            assertWithMessage(text).that(groups.drop(1).all { it.length == 3 }).isTrue()
            assertWithMessage(text).that(groups[0].length in 1..3).isTrue()
            assertThat(text).isNotEqualTo("-0")
        }
    }

    // endregion

    // region NumberText.clock

    @Test
    fun testClockUnderOneHour() {
        assertThat(NumberText.clock(0)).isEqualTo("0:00")
        assertThat(NumberText.clock(5)).isEqualTo("0:05")
        assertThat(NumberText.clock(59)).isEqualTo("0:59")
        assertThat(NumberText.clock(60)).isEqualTo("1:00")
        assertThat(NumberText.clock(72)).isEqualTo("1:12")
        assertThat(NumberText.clock(599)).isEqualTo("9:59")
        assertThat(NumberText.clock(600)).isEqualTo("10:00")
        assertThat(NumberText.clock(1458)).isEqualTo("24:18")
        assertThat(NumberText.clock(3599)).isEqualTo("59:59")
    }

    @Test
    fun testClockOverOneHour() {
        assertThat(NumberText.clock(3600)).isEqualTo("1:00:00")
        assertThat(NumberText.clock(3601)).isEqualTo("1:00:01")
        assertThat(NumberText.clock(3723)).isEqualTo("1:02:03")
        assertThat(NumberText.clock(7325)).isEqualTo("2:02:05")
        assertThat(NumberText.clock(36000)).isEqualTo("10:00:00")
        assertThat(NumberText.clock(86399)).isEqualTo("23:59:59")
        assertThat(NumberText.clock(90061)).isEqualTo("25:01:01")
    }

    @Test
    fun testClockClampsNegativeInput() {
        assertThat(NumberText.clock(-1)).isEqualTo("0:00")
        assertThat(NumberText.clock(-3723)).isEqualTo("0:00")
        assertThat(NumberText.clock(Int.MIN_VALUE)).isEqualTo("0:00")
        assertThat(NumberText.clock(Int.MAX_VALUE).isEmpty()).isFalse()
    }

    // endregion

    // region NumberText.rest

    @Test
    fun testRestOffAndTimes() {
        assertThat(NumberText.rest(0)).isEqualTo("Off")
        assertThat(NumberText.rest(5)).isEqualTo("0:05")
        assertThat(NumberText.rest(30)).isEqualTo("0:30")
        assertThat(NumberText.rest(45)).isEqualTo("0:45")
        assertThat(NumberText.rest(60)).isEqualTo("1:00")
        assertThat(NumberText.rest(75)).isEqualTo("1:15")
        assertThat(NumberText.rest(90)).isEqualTo("1:30")
        assertThat(NumberText.rest(120)).isEqualTo("2:00")
        assertThat(NumberText.rest(150)).isEqualTo("2:30")
        assertThat(NumberText.rest(180)).isEqualTo("3:00")
    }

    @Test
    fun testRestEdgeCases() {
        assertThat(NumberText.rest(-1)).isEqualTo("Off")
        assertThat(NumberText.rest(Int.MIN_VALUE)).isEqualTo("Off")
        assertThat(NumberText.rest(3599)).isEqualTo("59:59")
        assertWithMessage("minutes are not wrapped into hours").that(NumberText.rest(3600)).isEqualTo("60:00")
        assertThat(NumberText.rest(3723)).isEqualTo("62:03")
    }

    @Test
    fun testRestAgreesWithClockBelowOneHour() {
        for (seconds in 1 until 3600) {
            assertThat(NumberText.rest(seconds)).isEqualTo(NumberText.clock(seconds))
        }
    }

    @Test
    fun testEveryLibraryRestHasAReadableText() {
        for (exercise in ExerciseLibrary.builtIn) {
            val text = NumberText.rest(exercise.defaults.restSeconds)
            assertWithMessage(exercise.id).that(text).isNotEqualTo("Off")
            assertWithMessage(exercise.id).that(text.contains(":")).isTrue()
        }
        assertThat(NumberText.rest(ExerciseLibrary.exercise("bench")?.defaults?.restSeconds ?: -1)).isEqualTo("2:30")
    }

    // endregion

    // region Kotlin-only additions (no Swift test)

    /**
     * Pins the generator to the Swift algorithm (output `state >> 11`); the expected numbers were computed independently with
     * explicit 64-bit wrap-around.
     */
    @Test
    fun testKotlinOnlyFuzzRNGMatchesTheSwiftAlgorithm() {
        val rng = MetricsFuzzRNG(7L)
        assertThat(List(5) { rng.next() }).isEqualTo(
            listOf(4442461162303423L, 8607815882110213L, 8165709068218067L, 2456682174089337L, 2399332919137367L),
        )
    }

    // endregion

    /** Seeded linear congruential generator, so the fuzz tests are deterministic (same constants and output shift as Swift). */
    private class MetricsFuzzRNG(seed: Long) {
        private var state: Long = seed

        fun next(): Long {
            state = state * 6_364_136_223_846_793_005L + 1_442_695_040_888_963_407L
            return state ushr 11
        }

        /** A value in 0..<bound. */
        fun nextBelow(bound: Int): Int = (next() % bound.toLong()).toInt()
    }
}
