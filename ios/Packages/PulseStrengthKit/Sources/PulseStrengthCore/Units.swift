import Foundation

// MARK: - Weight unit

/// The unit weights are shown and typed in.
///
/// Storage never changes: every weight of the feature is kept in kilograms (`LoggedSet.weightKg`, `PlannedSet.weightKg`, ...). The
/// unit is a display and entry concern only, converted at the edge with `fromKg(_:)` and `toKg(_:)`.
public enum WeightUnit: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case kg
    case lb

    public var id: String { rawValue }

    /// Pounds in one kilogram (1 lb is exactly 0.45359237 kg).
    public static let poundsPerKilogram = 2.2046226218

    /// The text after a number: "kg" or "lb".
    public var symbol: String { rawValue }

    /// The unit a person with `locale` expects: pounds where the measurement system is the US one (en_US, en_LR and their equivalents)
    /// and in Liberia, Myanmar and the US by region (my_MM, whose system some platforms report as the UK one); kilograms everywhere
    /// else. A measurement system that the identifier names itself (`-u-ms-metric`) wins over all of this.
    public static func defaultFor(locale: Locale) -> WeightUnit {
        if let chosen = Locale.Components(identifier: locale.identifier).measurementSystem {
            return chosen == .us ? .lb : .kg
        }
        if locale.measurementSystem == .us { return .lb }
        return poundsRegions.contains(locale.region?.identifier ?? "") ? .lb : .kg
    }

    private static let poundsRegions: Set<String> = ["US", "LR", "MM"]

    /// `kg` kilograms in this unit, unrounded.
    public func fromKg(_ kg: Double) -> Double {
        self == .kg ? kg : kg * Self.poundsPerKilogram
    }

    /// `value` of this unit in kilograms, unrounded.
    public func toKg(_ value: Double) -> Double {
        self == .kg ? value : value / Self.poundsPerKilogram
    }

    /// The weight `kg` as shown in this unit: kilograms to 0.01, pounds to 0.1 (ties away from zero). A non-finite weight gives 0.
    ///
    /// Rounding to 0.1 lb is what makes a weight typed in pounds come back unchanged: the reducer stores kilograms to 0.01 kg
    /// (at most 0.011 lb off), so 135 lb is stored as 61.23 kg and shown as 135 lb again.
    public func displayValue(kg: Double) -> Double {
        guard kg.isFinite else { return 0 }
        let scale = fractionScale
        let rounded = (fromKg(kg) * scale).rounded(.toNearestOrAwayFromZero) / scale
        return rounded == 0 ? 0 : rounded
    }

    /// Decimals shown for a weight in this unit.
    var fractionDigits: Int { self == .kg ? 2 : 1 }

    private var fractionScale: Double { self == .kg ? 100 : 10 }
}

// MARK: - Display format

/// How weights and numbers are written for the user: the unit and the locale whose separators are used.
///
/// The Core builds every weight text through a format, so the same state reads "82.5 kg" for one user and "181,9 lb" for another.
public struct DisplayFormat: Equatable, Sendable {
    public var unit: WeightUnit
    public var locale: Locale

    public init(unit: WeightUnit, locale: Locale) {
        self.unit = unit
        self.locale = locale
    }

    /// Kilograms and the en_US separators ("82.5"): what the Core produced before units existed, and the default of every API that
    /// takes a locale, so a caller that does not care gets reproducible text.
    public static let metric = DisplayFormat(unit: .kg, locale: Locale(identifier: "en_US"))

    /// `unit` with the separators of the device (`Locale.current`).
    public static func device(unit: WeightUnit) -> DisplayFormat {
        DisplayFormat(unit: unit, locale: .current)
    }

    /// The formatter of this format.
    public var formatter: WeightFormatter { WeightFormatter(self) }
}

// MARK: - Formatter

/// Writes and reads weights for one `DisplayFormat`.
///
/// Everything is formatted by hand (no `NumberFormatter`), so a given locale produces the same text on Linux and on Apple platforms.
/// The digits are always 0-9; the decimal and the grouping separator come from the locale. Weights are not grouped ("1250.5");
/// volumes are, from four digits on ("1,980"). Every function takes KILOGRAMS unless its name says otherwise.
public struct WeightFormatter: Equatable, Sendable {
    public let unit: WeightUnit
    public let locale: Locale
    private let decimalSeparator: String
    private let groupingSeparator: String

    /// The "minus" of a signed amount (U+2212), not a hyphen.
    static let minus = "\u{2212}"

    public init(unit: WeightUnit, locale: Locale) {
        self.unit = unit
        self.locale = locale
        self.decimalSeparator = locale.decimalSeparator ?? "."
        self.groupingSeparator = locale.groupingSeparator ?? ","
    }

    public init(_ format: DisplayFormat) {
        self.init(unit: format.unit, locale: format.locale)
    }

    /// The format this formatter was made for.
    public var format: DisplayFormat { DisplayFormat(unit: unit, locale: locale) }

    // MARK: Writing

    /// `kg` in the display unit, rounded for display (see `WeightUnit.displayValue(kg:)`).
    public func displayValue(kg: Double) -> Double {
        unit.displayValue(kg: kg)
    }

    /// `kg` as a number without unit: "82.5" or "82,5" (kilograms to 0.01, pounds to 0.1, trailing zeros dropped); "0" for a
    /// non-finite weight.
    public func text(kg: Double) -> String {
        number(unit.fromKg(kg))
    }

    /// `kg` with the unit symbol: "82.5 kg", "135 lb".
    public func textWithUnit(kg: Double) -> String {
        String(format: "%@ %@", text(kg: kg), unit.symbol)
    }

    /// A number that is already in the display unit (a plate, a step) written the way weights are: "2.5", "1,25".
    public func number(_ value: Double) -> String {
        NumberText.decimal(value, fractionDigits: unit.fractionDigits, separator: decimalSeparator)
    }

    /// A weight total in the display unit as a whole number grouped from four digits: "1,980" (en_US), "1.980" (de_DE).
    /// Used for volumes and estimated one-rep maxes.
    public func volume(kg: Double) -> String {
        NumberText.grouped(unit.fromKg(kg), separator: groupingSeparator)
    }

    /// `volume(kg:)` with the unit symbol: "1,980 kg".
    public func volumeWithUnit(kg: Double) -> String {
        String(format: "%@ %@", volume(kg: kg), unit.symbol)
    }

    /// An added or assisted load: "+10", "\u{2212}20" (U+2212 as the minus), and "BW" (bodyweight) when it shows as zero.
    public func signedText(kg: Double) -> String {
        let shown = displayValue(kg: kg)
        if shown == 0 { return "BW" }
        return (shown > 0 ? "+" : Self.minus) + number(abs(shown))
    }

    /// `kg` as it is read aloud: "82.5 kilograms", "1 kilogram", "135 pounds".
    public func accessibilityText(kg: Double) -> String {
        let value = text(kg: kg)
        let isOne = value == "1"
        switch unit {
        case .kg: return String(format: isOne ? "%@ kilogram" : "%@ kilograms", value)
        case .lb: return String(format: isOne ? "%@ pound" : "%@ pounds", value)
        }
    }

    // MARK: Reading

    /// The weight in typed text as KILOGRAMS, or nil when the text is not a weight.
    ///
    /// * Both "." and "," are accepted as the decimal mark whatever the locale: "82.5" and "82,5" are the same weight. The separators
    ///   of `locale` itself count too (the Arabic "\u{066B}" and "\u{066C}"), so the text `text(kg:)` writes in `locale` always reads back.
    /// * Grouping is understood: "1,250.5", "1.250,5", "1 250" and, when it is the locale's own grouping separator and three digits
    ///   follow, a single "1,250" (en_US) or "1.250" (de_DE) is 1250, not 1.25.
    /// * The unit symbol of `unit` may follow ("82.5 kg", "135lb", "135 lbs", any case). Any other letters give nil.
    /// * A leading "+" is ignored. A minus ("-" or U+2212) gives nil unless `allowsNegative` (assisted loads).
    /// * The value is clamped to `WorkoutReducer.maximumWeightKg` in magnitude. Empty text, NaN, "inf" and exponents give nil.
    ///
    /// The result is the exact conversion; the reducer rounds it to 0.01 kg when it stores it.
    public static func parse(_ text: String, unit: WeightUnit, locale: Locale, allowsNegative: Bool = false) -> Double? {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var isNegative = false
        if let sign = rest.first, sign == "-" || sign == "+" || String(sign) == minus {
            isNegative = sign != "+"
            rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for suffix in unitSuffixes(unit) where rest.hasSuffix(suffix) {
            rest = String(rest.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        guard !rest.isEmpty, !isNegative || allowsNegative else { return nil }
        guard let magnitude = number(in: Array(rest), locale: locale) else { return nil }
        let kg = unit.toKg(magnitude)
        guard !kg.isNaN else { return nil }
        let clamped = min(kg, WorkoutReducer.maximumWeightKg)
        return isNegative && clamped != 0 ? -clamped : clamped
    }

    private static func unitSuffixes(_ unit: WeightUnit) -> [String] {
        switch unit {
        case .kg: return ["kgs", "kg"]
        case .lb: return ["lbs", "lb"]
        }
    }

    /// The value of a number written with digits, an optional decimal mark and optional grouping; nil for anything else.
    private static func number(in characters: [Character], locale: Locale) -> Double? {
        let localeMarks = marksOf(locale)
        let isMark = { (character: Character) in character == "." || character == "," || localeMarks.contains(character) }
        guard characters.allSatisfy({ isDigit($0) || isMark($0) || isGrouping($0) }) else { return nil }
        let marks = characters.indices.filter { isMark(characters[$0]) }
        let decimalIndex = decimalMarkIndex(characters, marks: marks, locale: locale)
        let head = decimalIndex.map { Array(characters[..<$0]) } ?? characters
        let fraction = decimalIndex.map { Array(characters[($0 + 1)...]) } ?? []
        guard fraction.allSatisfy(isDigit), let integerDigits = ungrouped(head) else { return nil }
        guard !(integerDigits.isEmpty && fraction.isEmpty) else { return nil }
        let text = (integerDigits.isEmpty ? "0" : integerDigits) + (fraction.isEmpty ? "" : "." + String(fraction))
        guard let value = Double(text), !value.isNaN else { return nil }
        return value
    }

    /// The position of the decimal mark, nil when the number has none (every "." or "," is then a grouping separator).
    private static func decimalMarkIndex(_ characters: [Character], marks: [Int], locale: Locale) -> Int? {
        guard let last = marks.last else { return nil }
        let kinds = Set(marks.map { characters[$0] })
        // Two kinds ("1,250.5"): the last one is the decimal mark. One kind twice or more ("1.250.500"): all grouping.
        if kinds.count == 1, marks.count > 1 { return nil }
        guard kinds.count == 1 else { return last }
        // A single mark followed by exactly three digits after one to three leading digits ("1,250") is grouping when the locale
        // groups with that character; every other single mark is the decimal mark ("82.5", "0,125").
        let after = characters.count - last - 1
        let before = Array(characters[..<last])
        let isLeadingGroup = (1...3).contains(before.count) && before.allSatisfy(isDigit) && before.first != "0"
        let mark = String(characters[last])
        if after == 3, isLeadingGroup, mark == locale.groupingSeparator, mark != locale.decimalSeparator { return nil }
        return last
    }

    /// The digits of an integer part whose groups are separated by one kind of separator ("1,250,000", "1 250"); nil when the
    /// groups are not one to three digits followed by groups of exactly three. No separator at all is fine, and so is no digit.
    private static func ungrouped(_ head: [Character]) -> String? {
        let groups = head.split(omittingEmptySubsequences: false) { !isDigit($0) }.map { String($0) }
        let separators = head.filter { !isDigit($0) }
        guard separators.count == groups.count - 1, Set(separators).count <= 1 else { return nil }
        if groups.count == 1 { return groups[0] }
        guard (1...3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        return groups.joined()
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    /// The one-character decimal and grouping separators of `locale` that are neither digits nor spaces (which `isGrouping` covers).
    private static func marksOf(_ locale: Locale) -> Set<Character> {
        let separators = [locale.decimalSeparator, locale.groupingSeparator].compactMap { $0 }
        return Set(separators.filter { $0.count == 1 }.map { Character($0) }.filter { !isDigit($0) && !isGrouping($0) })
    }

    /// Spaces (also the no-break ones that fr and sv group with) and the apostrophes of de_CH.
    private static func isGrouping(_ character: Character) -> Bool {
        character.isWhitespace || character == "\u{2019}" || character == "'"
    }
}
