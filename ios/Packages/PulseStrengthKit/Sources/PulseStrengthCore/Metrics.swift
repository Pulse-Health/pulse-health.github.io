import Foundation

// MARK: - Estimated one-rep max

/// Estimated one-rep max formulas.
public enum Estimated1RM {
    /// Epley estimate `kg * (1 + reps / 30)`; 0 when the weight or the reps are zero or negative.
    public static func epley(weightKg: Double, reps: Int) -> Double {
        guard weightKg > 0, weightKg.isFinite, reps > 0 else { return 0 }
        return weightKg * (1 + Double(reps) / 30)
    }
}

// MARK: - Plate calculator

/// The plates to load on each side of the bar, heaviest first, and the weight that cannot be matched.
///
/// The values are in `unit`: kilograms for a plan from `plan(totalKg:barKg:)`, the display unit for one from `plan(total:bar:unit:)`.
public struct PlatePlan: Equatable, Sendable {
    /// Plates for one side of the bar, heaviest first, in `unit`.
    public var perSide: [Double]
    /// Weight per side that the available plates cannot make up, in `unit`, rounded to 0.01.
    public var leftover: Double
    /// The unit of `perSide` and `leftover`.
    public var unit: WeightUnit

    /// Creates a plan in `unit` from the plates of one side and the unmatched weight per side.
    public init(perSide: [Double], leftover: Double, unit: WeightUnit) {
        self.perSide = perSide
        self.leftover = leftover
        self.unit = unit
    }

    /// Creates a plan in kilograms from the plates of one side and the unmatched weight per side.
    public init(perSide: [Double], leftoverKg: Double) {
        self.init(perSide: perSide, leftover: leftoverKg, unit: .kg)
    }

    /// `leftover` in kilograms (for a plan in pounds: converted and rounded to 0.01 kg); setting it sets `leftover` in `unit`.
    public var leftoverKg: Double {
        get { unit == .kg ? leftover : (unit.toKg(leftover) * 100).rounded() / 100 }
        set { leftover = unit.fromKg(newValue) }
    }
}

/// Works out which plates to load on a barbell.
public enum PlateCalculator {
    /// The plate sizes in kilograms that are on offer, heaviest first.
    public static let availablePlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    /// The plate sizes in pounds that are on offer, heaviest first.
    public static let availablePlatesLb: [Double] = [45, 35, 25, 10, 5, 2.5]

    /// The plate sizes of `unit`, heaviest first.
    public static func plates(in unit: WeightUnit) -> [Double] {
        unit == .kg ? availablePlates : availablePlatesLb
    }

    /// Heaviest total weight the calculator plans for (in kilograms); anything above is treated as invalid input.
    private static let maximumTotalKg = 100_000.0

    /// Greedy plate plan for one side of the bar, or nil when `totalKg` is below `barKg` (or an input is invalid).
    ///
    /// The leftover is the per-side weight the plates cannot make up (rounded to 0.01 kg), for example 0.5 kg for 21 kg on a 20 kg bar.
    public static func plan(totalKg: Double, barKg: Double) -> PlatePlan? {
        plan(total: totalKg, bar: barKg, unit: .kg)
    }

    /// `plan(totalKg:barKg:)` in the display unit: `total` and `bar` are in `unit` and so is the result (plates of
    /// `plates(in:)`, a leftover rounded to 0.01). Pass the weight as it is shown (`WeightFormatter.displayValue(kg:)`) and the bar of
    /// `Exercise.barWeight(in:)`, so that 135 lb on a 45 lb bar is 45 lb per side and nothing is left over.
    public static func plan(total: Double, bar: Double, unit: WeightUnit) -> PlatePlan? {
        guard total.isFinite, bar.isFinite, bar >= 0, unit.toKg(total) <= maximumTotalKg else { return nil }
        var remaining = (total - bar) / 2
        if remaining < -0.001 { return nil }
        var plates: [Double] = []
        for plate in Self.plates(in: unit) {
            while remaining + 0.0001 >= plate {
                plates.append(plate)
                remaining -= plate
            }
        }
        let leftover = remaining > 0 ? remaining : 0
        return PlatePlan(perSide: plates, leftover: (leftover * 100).rounded() / 100, unit: unit)
    }
}

// MARK: - Number text

/// Locale independent number and time text, formatted by hand so the output is identical on every platform.
public enum NumberText {
    /// Largest magnitude (in the unit being formatted) that is converted to an integer; larger values clamp.
    private static let integerLimit = 9_000_000_000_000_000.0

    /// Kilograms with at most two decimals and no trailing zeros: 82.5 gives "82.5", 80 gives "80", 82.50001 gives "82.5".
    ///
    /// Ties round away from zero, a result of zero never carries a sign, and a non-finite value gives "0".
    public static func kg(_ value: Double) -> String {
        decimal(value, fractionDigits: 2, separator: ".")
    }

    /// A value rounded to a whole number with "," grouping: 1980.4 gives "1,980" and 1979.5 gives "1,980".
    ///
    /// Ties round away from zero, a result of zero never carries a sign, and a non-finite value gives "0".
    public static func thousands(_ value: Double) -> String {
        grouped(value, separator: ",")
    }

    /// An elapsed time as "m:ss", or "h:mm:ss" from one hour on: 72 gives "1:12" and 3723 gives "1:02:03".
    ///
    /// Negative input counts as zero.
    public static func clock(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(hours) + ":" + twoDigits(minutes) + ":" + twoDigits(secs)
        }
        return String(minutes) + ":" + twoDigits(secs)
    }

    /// A rest time as "m:ss" (minutes are not wrapped into hours), or "Off" when there is none: 0 gives "Off" and 150 gives "2:30".
    public static func rest(seconds: Int) -> String {
        if seconds <= 0 { return "Off" }
        return String(seconds / 60) + ":" + twoDigits(seconds % 60)
    }

    /// `value` rounded half away from zero to `fractionDigits` (1 or 2) decimals, trailing zeros dropped, `separator` as the decimal mark.
    /// A result of zero never carries a sign and a non-finite value gives "0".
    static func decimal(_ value: Double, fractionDigits: Int, separator: String) -> String {
        let scale = fractionDigits == 1 ? 10 : 100
        guard let scaled = roundedInteger(value * Double(scale)) else { return "0" }
        if scaled == 0 { return "0" }
        let magnitude = scaled < 0 ? -scaled : scaled
        var text = scaled < 0 ? "-" : ""
        text += String(magnitude / scale)
        var fraction = String(magnitude % scale)
        fraction = String(repeating: "0", count: fractionDigits - fraction.count) + fraction
        while fraction.hasSuffix("0") { fraction.removeLast() }
        if !fraction.isEmpty { text += separator + fraction }
        return text
    }

    /// `value` rounded half away from zero to a whole number with `separator` between the groups of three digits.
    /// A result of zero never carries a sign and a non-finite value gives "0".
    static func grouped(_ value: Double, separator: String) -> String {
        guard let rounded = roundedInteger(value), rounded != 0 else { return "0" }
        let digits = Array(String(rounded < 0 ? -rounded : rounded))
        var text = rounded < 0 ? "-" : ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { text += separator }
            text.append(digit)
        }
        return text
    }

    /// Rounds half away from zero; nil for NaN or infinity, clamped to +/- `integerLimit` beyond that.
    private static func roundedInteger(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        let rounded = value.rounded(.toNearestOrAwayFromZero)
        if rounded >= integerLimit { return Int(integerLimit) }
        if rounded <= -integerLimit { return -Int(integerLimit) }
        return Int(rounded)
    }

    /// Zero-padded two digit text for a value from 0 to 59.
    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0" + String(value) : String(value)
    }
}
