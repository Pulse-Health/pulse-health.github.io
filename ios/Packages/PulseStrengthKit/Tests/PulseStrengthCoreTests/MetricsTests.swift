import Foundation
import XCTest
@testable import PulseStrengthCore

final class MetricsTests: XCTestCase {

    // MARK: - Estimated1RM

    func testEpleyBenchExamples() {
        XCTAssertEqual(Estimated1RM.epley(weightKg: 85, reps: 5), 99.1666667, accuracy: 1e-6)
        XCTAssertEqual(Estimated1RM.epley(weightKg: 85, reps: 6), 102.0, accuracy: 1e-9)
        XCTAssertEqual(Estimated1RM.epley(weightKg: 82.5, reps: 6), 99.0, accuracy: 1e-9)
        XCTAssertEqual(Estimated1RM.epley(weightKg: 80, reps: 6), 96.0, accuracy: 1e-9)
    }

    func testEpleyMatchesTheFormula() {
        XCTAssertEqual(Estimated1RM.epley(weightKg: 100, reps: 1), 100 * (1 + 1.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(Estimated1RM.epley(weightKg: 60, reps: 30), 120, accuracy: 1e-9)
        XCTAssertEqual(Estimated1RM.epley(weightKg: 20, reps: 15), 30, accuracy: 1e-9)
        XCTAssertEqual(Estimated1RM.epley(weightKg: 0.5, reps: 3), 0.55, accuracy: 1e-9)
    }

    func testEpleyIsZeroForZeroOrNegativeInput() {
        XCTAssertEqual(Estimated1RM.epley(weightKg: 0, reps: 5), 0)
        XCTAssertEqual(Estimated1RM.epley(weightKg: -10, reps: 5), 0)
        XCTAssertEqual(Estimated1RM.epley(weightKg: 85, reps: 0), 0)
        XCTAssertEqual(Estimated1RM.epley(weightKg: 85, reps: -3), 0)
        XCTAssertEqual(Estimated1RM.epley(weightKg: 0, reps: 0), 0)
        XCTAssertEqual(Estimated1RM.epley(weightKg: -85, reps: -5), 0)
        XCTAssertEqual(Estimated1RM.epley(weightKg: -0.0, reps: 5), 0)
    }

    func testEpleyIsZeroForNonFiniteWeight() {
        XCTAssertEqual(Estimated1RM.epley(weightKg: .nan, reps: 5), 0)
        XCTAssertEqual(Estimated1RM.epley(weightKg: .infinity, reps: 5), 0)
        XCTAssertEqual(Estimated1RM.epley(weightKg: -.infinity, reps: 5), 0)
    }

    func testEpleyGrowsWithWeightAndReps() {
        var rng = MetricsFuzzRNG(seed: 7)
        for _ in 0..<200 {
            let kg = Double(1 + rng.next(below: 4000)) / 8
            let reps = 1 + rng.next(below: 40)
            let value = Estimated1RM.epley(weightKg: kg, reps: reps)
            XCTAssertGreaterThan(value, kg)
            XCTAssertGreaterThan(Estimated1RM.epley(weightKg: kg, reps: reps + 1), value)
            XCTAssertGreaterThan(Estimated1RM.epley(weightKg: kg + 0.5, reps: reps), value)
        }
    }

    // MARK: - PlateCalculator

    func testAvailablePlates() {
        XCTAssertEqual(PlateCalculator.availablePlates, [25, 20, 15, 10, 5, 2.5, 1.25])
    }

    func testPlanFor82Point5OnTwentyKiloBar() {
        let plan = PlateCalculator.plan(totalKg: 82.5, barKg: 20)
        XCTAssertEqual(plan, PlatePlan(perSide: [25, 5, 1.25], leftoverKg: 0))
    }

    func testPlanFor100OnTwentyKiloBar() {
        let plan = PlateCalculator.plan(totalKg: 100, barKg: 20)
        XCTAssertEqual(plan, PlatePlan(perSide: [25, 15], leftoverKg: 0))
    }

    func testPlanForEmptyBar() {
        let plan = PlateCalculator.plan(totalKg: 20, barKg: 20)
        XCTAssertEqual(plan, PlatePlan(perSide: [], leftoverKg: 0))
    }

    func testPlanBelowTheBarIsNil() {
        XCTAssertNil(PlateCalculator.plan(totalKg: 19, barKg: 20))
        XCTAssertNil(PlateCalculator.plan(totalKg: 0, barKg: 20))
        XCTAssertNil(PlateCalculator.plan(totalKg: -5, barKg: 20))
        XCTAssertNil(PlateCalculator.plan(totalKg: 9.99, barKg: 10))
        XCTAssertNil(PlateCalculator.plan(totalKg: 19.99, barKg: 20))
    }

    func testPlanWithLeftover() {
        let plan = PlateCalculator.plan(totalKg: 21, barKg: 20)
        XCTAssertEqual(plan, PlatePlan(perSide: [], leftoverKg: 0.5))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 23, barKg: 20), PlatePlan(perSide: [1.25], leftoverKg: 0.25))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 87, barKg: 20), PlatePlan(perSide: [25, 5, 2.5], leftoverKg: 1))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 20.1, barKg: 20), PlatePlan(perSide: [], leftoverKg: 0.05))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 20.06, barKg: 20), PlatePlan(perSide: [], leftoverKg: 0.03))
    }

    func testSmallestPlatesGiveTwoAndAHalfKiloSteps() {
        XCTAssertEqual(PlateCalculator.plan(totalKg: 22.5, barKg: 20), PlatePlan(perSide: [1.25], leftoverKg: 0))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 25, barKg: 20), PlatePlan(perSide: [2.5], leftoverKg: 0))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 27.5, barKg: 20), PlatePlan(perSide: [2.5, 1.25], leftoverKg: 0))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 30, barKg: 20), PlatePlan(perSide: [5], leftoverKg: 0))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 32.5, barKg: 20), PlatePlan(perSide: [5, 1.25], leftoverKg: 0))
    }

    func testPlanIsGreedyAndRepeatsPlates() {
        XCTAssertEqual(PlateCalculator.plan(totalKg: 140, barKg: 20), PlatePlan(perSide: [25, 25, 10], leftoverKg: 0))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 220, barKg: 20), PlatePlan(perSide: [25, 25, 25, 25], leftoverKg: 0))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 120, barKg: 20), PlatePlan(perSide: [25, 25], leftoverKg: 0))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 60, barKg: 20), PlatePlan(perSide: [20], leftoverKg: 0))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 200, barKg: 20), PlatePlan(perSide: [25, 25, 25, 15], leftoverKg: 0))
    }

    func testPlanWithTenKiloBar() {
        XCTAssertEqual(PlateCalculator.plan(totalKg: 25, barKg: 10), PlatePlan(perSide: [5, 2.5], leftoverKg: 0))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 30, barKg: 10), PlatePlan(perSide: [10], leftoverKg: 0))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 10, barKg: 10), PlatePlan(perSide: [], leftoverKg: 0))
        let skull = ExerciseLibrary.exercise(id: "skull")
        XCTAssertEqual(PlateCalculator.plan(totalKg: 30, barKg: skull?.barKg ?? 0), PlatePlan(perSide: [10], leftoverKg: 0))
    }

    func testPlanToleratesFloatingPointNoise() {
        // 1e-9 kg below an exact multiple must still give the exact plate, with no negative leftover.
        let nearlyExact = PlateCalculator.plan(totalKg: 22.5 - 1e-9, barKg: 20)
        XCTAssertEqual(nearlyExact?.perSide, [1.25])
        XCTAssertEqual(nearlyExact?.leftoverKg, 0)
        XCTAssertEqual(nearlyExact?.leftoverKg.sign, .plus)
        // Slightly below the bar is the bar.
        let belowBar = PlateCalculator.plan(totalKg: 19.999, barKg: 20)
        XCTAssertEqual(belowBar, PlatePlan(perSide: [], leftoverKg: 0))
        XCTAssertEqual(belowBar?.leftoverKg.sign, .plus)
        // Slightly above is still the bar with a leftover below the smallest plate.
        XCTAssertEqual(PlateCalculator.plan(totalKg: 82.5 + 1e-9, barKg: 20)?.perSide, [25, 5, 1.25])
        XCTAssertEqual(PlateCalculator.plan(totalKg: 0.1 + 0.2 + 19.7, barKg: 20)?.perSide, [])
    }

    func testPlanRejectsInvalidInput() {
        XCTAssertNil(PlateCalculator.plan(totalKg: .nan, barKg: 20))
        XCTAssertNil(PlateCalculator.plan(totalKg: .infinity, barKg: 20))
        XCTAssertNil(PlateCalculator.plan(totalKg: 100, barKg: .nan))
        XCTAssertNil(PlateCalculator.plan(totalKg: 100, barKg: -20))
        XCTAssertNil(PlateCalculator.plan(totalKg: 1e12, barKg: 20), "absurd totals must not allocate millions of plates")
        XCTAssertNotNil(PlateCalculator.plan(totalKg: 1_000, barKg: 20))
    }

    func testPlanWithoutBar() {
        XCTAssertEqual(PlateCalculator.plan(totalKg: 50, barKg: 0), PlatePlan(perSide: [25], leftoverKg: 0))
        XCTAssertEqual(PlateCalculator.plan(totalKg: 0, barKg: 0), PlatePlan(perSide: [], leftoverKg: 0))
    }

    func testPlanInvariantsOnRandomWeights() {
        var rng = MetricsFuzzRNG(seed: 42)
        for _ in 0..<500 {
            let bar: Double = rng.next(below: 2) == 0 ? 20 : 10
            let total = bar + Double(rng.next(below: 1200)) / 4        // up to 300 kg above the bar in 0.25 kg steps
            guard let plan = PlateCalculator.plan(totalKg: total, barKg: bar) else {
                XCTFail("no plan for \(total) / \(bar)")
                continue
            }
            let perSide = (total - bar) / 2
            XCTAssertEqual(plan.perSide.reduce(0, +) + plan.leftoverKg, perSide, accuracy: 0.0051, "\(total) / \(bar)")
            XCTAssertEqual(plan.perSide, plan.perSide.sorted(by: >), "heaviest plate first for \(total)")
            XCTAssertTrue(plan.perSide.allSatisfy { PlateCalculator.availablePlates.contains($0) })
            XCTAssertGreaterThanOrEqual(plan.leftoverKg, 0)
            XCTAssertLessThan(plan.leftoverKg, 1.25 + 0.0051)
            if (total - bar).truncatingRemainder(dividingBy: 2.5) == 0 {
                XCTAssertEqual(plan.leftoverKg, 0, "multiples of 2.5 kg are always loadable: \(total) / \(bar)")
            }
        }
    }

    func testPlatePlanIsEquatable() {
        let plan = PlatePlan(perSide: [25, 5], leftoverKg: 0)
        XCTAssertEqual(plan, PlatePlan(perSide: [25, 5], leftoverKg: 0))
        XCTAssertNotEqual(plan, PlatePlan(perSide: [25, 5], leftoverKg: 0.25))
        XCTAssertNotEqual(plan, PlatePlan(perSide: [25], leftoverKg: 0))
        var changed = plan
        changed.perSide = [20]
        changed.leftoverKg = 1
        XCTAssertEqual(changed.perSide, [20])
        XCTAssertEqual(changed.leftoverKg, 1)
    }

    // MARK: - NumberText.kg

    func testKgBasics() {
        XCTAssertEqual(NumberText.kg(82.5), "82.5")
        XCTAssertEqual(NumberText.kg(80), "80")
        XCTAssertEqual(NumberText.kg(0), "0")
        XCTAssertEqual(NumberText.kg(100), "100")
        XCTAssertEqual(NumberText.kg(1000), "1000", "kilograms are not grouped")
        XCTAssertEqual(NumberText.kg(62.5), "62.5")
        XCTAssertEqual(NumberText.kg(12.3), "12.3")
        XCTAssertEqual(NumberText.kg(12.34), "12.34")
        XCTAssertEqual(NumberText.kg(0.1), "0.1")
        XCTAssertEqual(NumberText.kg(0.05), "0.05")
        XCTAssertEqual(NumberText.kg(0.01), "0.01")
    }

    func testKgRoundsToTwoDecimals() {
        XCTAssertEqual(NumberText.kg(82.50001), "82.5")
        XCTAssertEqual(NumberText.kg(82.5000001), "82.5")
        XCTAssertEqual(NumberText.kg(82.4999999), "82.5")
        XCTAssertEqual(NumberText.kg(0.004), "0")
        XCTAssertEqual(NumberText.kg(0.006), "0.01")
        XCTAssertEqual(NumberText.kg(99.1666666), "99.17")
        XCTAssertEqual(NumberText.kg(7.0049), "7")
        XCTAssertEqual(NumberText.kg(27.499999), "27.5")
        XCTAssertEqual(NumberText.kg(0.994), "0.99")
        XCTAssertEqual(NumberText.kg(1234567.891), "1234567.89")
    }

    func testKgMatchesThePrototypeRounding() {
        // Expected values were produced by the prototype's `String(Math.round(n * 100) / 100)`.
        let cases: [(Double, String)] = [
            (82.5, "82.5"), (80, "80"), (82.50001, "82.5"), (82.5000001, "82.5"), (0.004, "0"), (0.006, "0.01"),
            (0.1, "0.1"), (0.05, "0.05"), (0.01, "0.01"), (12.34, "12.34"), (12.3, "12.3"), (1.005, "1"),
            (1.255, "1.25"), (99.1666666, "99.17"), (102, "102"), (2.675, "2.68"), (0.285, "0.28"),
            (1234567.891, "1234567.89"), (100, "100"), (1000, "1000"), (0.995, "1"), (0.994, "0.99"),
            (7.0049, "7"), (62.5, "62.5"), (27.499999, "27.5"), (Double.leastNonzeroMagnitude, "0"),
        ]
        for (value, expected) in cases {
            XCTAssertEqual(NumberText.kg(value), expected, "kg(\(value))")
        }
    }

    func testKgNegativeValues() {
        XCTAssertEqual(NumberText.kg(-5), "-5")
        XCTAssertEqual(NumberText.kg(-82.5), "-82.5")
        XCTAssertEqual(NumberText.kg(-12.34), "-12.34")
        XCTAssertEqual(NumberText.kg(-0.006), "-0.01")
        XCTAssertEqual(NumberText.kg(-0.05), "-0.05")
        XCTAssertEqual(NumberText.kg(-82.5000001), "-82.5")
    }

    func testKgNeverPrintsNegativeZero() {
        XCTAssertEqual(NumberText.kg(-0.004), "0")
        XCTAssertEqual(NumberText.kg(-0.0), "0")
        XCTAssertEqual(NumberText.kg(-1e-300), "0")
    }

    func testKgOfNonFiniteAndHugeValues() {
        XCTAssertEqual(NumberText.kg(.nan), "0")
        XCTAssertEqual(NumberText.kg(.infinity), "0")
        XCTAssertEqual(NumberText.kg(-.infinity), "0")
        XCTAssertEqual(NumberText.kg(1e30), "90000000000000")
        XCTAssertEqual(NumberText.kg(-1e30), "-90000000000000")
    }

    func testKgOutputIsAlwaysCanonicalOnRandomValues() {
        var rng = MetricsFuzzRNG(seed: 99)
        for _ in 0..<2000 {
            let value = (Double(rng.next(below: 4_000_001)) - 2_000_000) / 1000   // -2000.000 ... 2000.000
            let text = NumberText.kg(value)
            XCTAssertFalse(text.contains(","), text)
            XCTAssertNotEqual(text, "-0")
            if text.contains(".") {
                XCTAssertFalse(text.hasSuffix("0"), "trailing zero in \(text)")
                XCTAssertLessThanOrEqual(text.split(separator: ".")[1].count, 2, text)
            }
            guard let parsed = Double(text) else {
                XCTFail("not a number: \(text)")
                continue
            }
            XCTAssertEqual(parsed, value, accuracy: 0.005 + 1e-9, "kg(\(value)) = \(text)")
        }
    }

    // MARK: - NumberText.thousands

    func testThousandsGrouping() {
        XCTAssertEqual(NumberText.thousands(0), "0")
        XCTAssertEqual(NumberText.thousands(7), "7")
        XCTAssertEqual(NumberText.thousands(999), "999")
        XCTAssertEqual(NumberText.thousands(1000), "1,000")
        XCTAssertEqual(NumberText.thousands(12345), "12,345")
        XCTAssertEqual(NumberText.thousands(123456), "123,456")
        XCTAssertEqual(NumberText.thousands(1234567), "1,234,567")
        XCTAssertEqual(NumberText.thousands(1980.4), "1,980")
    }

    func testThousandsRoundingEdges() {
        XCTAssertEqual(NumberText.thousands(1979.5), "1,980")
        XCTAssertEqual(NumberText.thousands(1979.4999), "1,979")
        XCTAssertEqual(NumberText.thousands(12345.5), "12,346")
        XCTAssertEqual(NumberText.thousands(999.5), "1,000")
        XCTAssertEqual(NumberText.thousands(99999.5), "100,000")
        XCTAssertEqual(NumberText.thousands(1999999.5), "2,000,000")
        XCTAssertEqual(NumberText.thousands(0.4), "0")
        XCTAssertEqual(NumberText.thousands(0.5), "1")
        XCTAssertEqual(NumberText.thousands(1234.5678), "1,235")
    }

    func testThousandsNegativeValues() {
        XCTAssertEqual(NumberText.thousands(-1), "-1")
        XCTAssertEqual(NumberText.thousands(-999), "-999")
        XCTAssertEqual(NumberText.thousands(-1000), "-1,000")
        XCTAssertEqual(NumberText.thousands(-1234567), "-1,234,567")
        XCTAssertEqual(NumberText.thousands(-1979.5), "-1,980")
        XCTAssertEqual(NumberText.thousands(-1980.4), "-1,980")
        XCTAssertEqual(NumberText.thousands(-0.4), "0")
        XCTAssertEqual(NumberText.thousands(-0.0), "0")
    }

    func testThousandsOfNonFiniteAndHugeValues() {
        XCTAssertEqual(NumberText.thousands(.nan), "0")
        XCTAssertEqual(NumberText.thousands(.infinity), "0")
        XCTAssertEqual(NumberText.thousands(-.infinity), "0")
        XCTAssertEqual(NumberText.thousands(1e30), "9,000,000,000,000,000")
        XCTAssertEqual(NumberText.thousands(-1e30), "-9,000,000,000,000,000")
    }

    func testThousandsRoundTripsOnRandomValues() {
        var rng = MetricsFuzzRNG(seed: 1234)
        for _ in 0..<2000 {
            let value = (Double(rng.next(below: 40_000_001)) - 20_000_000) / 8     // eighths, so ties occur
            let text = NumberText.thousands(value)
            let digits = text.replacingOccurrences(of: ",", with: "")
            guard let parsed = Int(digits) else {
                XCTFail("not an integer: \(text)")
                continue
            }
            XCTAssertEqual(Double(parsed), value.rounded(.toNearestOrAwayFromZero) + 0.0, "thousands(\(value)) = \(text)")
            let groups = text.replacingOccurrences(of: "-", with: "").split(separator: ",", omittingEmptySubsequences: false)
            XCTAssertTrue(groups.dropFirst().allSatisfy { $0.count == 3 }, text)
            XCTAssertTrue((1...3).contains(groups[0].count), text)
            XCTAssertNotEqual(text, "-0")
        }
    }

    // MARK: - NumberText.clock

    func testClockUnderOneHour() {
        XCTAssertEqual(NumberText.clock(seconds: 0), "0:00")
        XCTAssertEqual(NumberText.clock(seconds: 5), "0:05")
        XCTAssertEqual(NumberText.clock(seconds: 59), "0:59")
        XCTAssertEqual(NumberText.clock(seconds: 60), "1:00")
        XCTAssertEqual(NumberText.clock(seconds: 72), "1:12")
        XCTAssertEqual(NumberText.clock(seconds: 599), "9:59")
        XCTAssertEqual(NumberText.clock(seconds: 600), "10:00")
        XCTAssertEqual(NumberText.clock(seconds: 1458), "24:18")
        XCTAssertEqual(NumberText.clock(seconds: 3599), "59:59")
    }

    func testClockOverOneHour() {
        XCTAssertEqual(NumberText.clock(seconds: 3600), "1:00:00")
        XCTAssertEqual(NumberText.clock(seconds: 3601), "1:00:01")
        XCTAssertEqual(NumberText.clock(seconds: 3723), "1:02:03")
        XCTAssertEqual(NumberText.clock(seconds: 7325), "2:02:05")
        XCTAssertEqual(NumberText.clock(seconds: 36000), "10:00:00")
        XCTAssertEqual(NumberText.clock(seconds: 86399), "23:59:59")
        XCTAssertEqual(NumberText.clock(seconds: 90061), "25:01:01")
    }

    func testClockClampsNegativeInput() {
        XCTAssertEqual(NumberText.clock(seconds: -1), "0:00")
        XCTAssertEqual(NumberText.clock(seconds: -3723), "0:00")
        XCTAssertEqual(NumberText.clock(seconds: Int.min), "0:00")
        XCTAssertFalse(NumberText.clock(seconds: Int.max).isEmpty)
    }

    // MARK: - NumberText.rest

    func testRestOffAndTimes() {
        XCTAssertEqual(NumberText.rest(seconds: 0), "Off")
        XCTAssertEqual(NumberText.rest(seconds: 5), "0:05")
        XCTAssertEqual(NumberText.rest(seconds: 30), "0:30")
        XCTAssertEqual(NumberText.rest(seconds: 45), "0:45")
        XCTAssertEqual(NumberText.rest(seconds: 60), "1:00")
        XCTAssertEqual(NumberText.rest(seconds: 75), "1:15")
        XCTAssertEqual(NumberText.rest(seconds: 90), "1:30")
        XCTAssertEqual(NumberText.rest(seconds: 120), "2:00")
        XCTAssertEqual(NumberText.rest(seconds: 150), "2:30")
        XCTAssertEqual(NumberText.rest(seconds: 180), "3:00")
    }

    func testRestEdgeCases() {
        XCTAssertEqual(NumberText.rest(seconds: -1), "Off")
        XCTAssertEqual(NumberText.rest(seconds: Int.min), "Off")
        XCTAssertEqual(NumberText.rest(seconds: 3599), "59:59")
        XCTAssertEqual(NumberText.rest(seconds: 3600), "60:00", "minutes are not wrapped into hours")
        XCTAssertEqual(NumberText.rest(seconds: 3723), "62:03")
    }

    func testRestAgreesWithClockBelowOneHour() {
        for seconds in 1..<3600 {
            XCTAssertEqual(NumberText.rest(seconds: seconds), NumberText.clock(seconds: seconds))
        }
    }

    func testEveryLibraryRestHasAReadableText() {
        for exercise in ExerciseLibrary.builtIn {
            let text = NumberText.rest(seconds: exercise.defaults.restSeconds)
            XCTAssertNotEqual(text, "Off", exercise.id)
            XCTAssertTrue(text.contains(":"), exercise.id)
        }
        XCTAssertEqual(NumberText.rest(seconds: ExerciseLibrary.exercise(id: "bench")?.defaults.restSeconds ?? -1), "2:30")
    }
}

// MARK: - Helpers

/// Seeded linear congruential generator, so the fuzz tests are deterministic.
private struct MetricsFuzzRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 11
    }

    /// A value in 0..<bound.
    mutating func next(below bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }
}
