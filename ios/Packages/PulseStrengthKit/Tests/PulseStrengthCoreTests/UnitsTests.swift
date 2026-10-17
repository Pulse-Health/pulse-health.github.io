import Foundation
import XCTest
@testable import PulseStrengthCore

// Weight units, rounding, the formatter and the parser. Every locale is explicit: nothing here depends on the machine's region.

private let enUS = Locale(identifier: "en_US")
private let enGB = Locale(identifier: "en_GB")
private let deDE = Locale(identifier: "de_DE")
private let frFR = Locale(identifier: "fr_FR")

private func kgFormatter(_ locale: Locale = enUS) -> WeightFormatter { WeightFormatter(unit: .kg, locale: locale) }
private func lbFormatter(_ locale: Locale = enUS) -> WeightFormatter { WeightFormatter(unit: .lb, locale: locale) }

// MARK: - Unit

final class WeightUnitTests: XCTestCase {
    func testSymbolsRawValuesAndCases() {
        XCTAssertEqual(WeightUnit.allCases, [.kg, .lb])
        XCTAssertEqual(WeightUnit.kg.symbol, "kg")
        XCTAssertEqual(WeightUnit.lb.symbol, "lb")
        XCTAssertEqual(WeightUnit.kg.rawValue, "kg")
        XCTAssertEqual(WeightUnit.lb.id, "lb")
        XCTAssertEqual(WeightUnit.poundsPerKilogram, 2.2046226218)
    }

    func testKilogramsAreTheIdentity() {
        for value in [0, 0.01, 82.5, 1_000_000, -5] as [Double] {
            XCTAssertEqual(WeightUnit.kg.fromKg(value), value)
            XCTAssertEqual(WeightUnit.kg.toKg(value), value)
        }
    }

    func testConversionTable() {
        XCTAssertEqual(WeightUnit.lb.fromKg(0), 0)
        XCTAssertEqual(WeightUnit.lb.fromKg(1), 2.2046226218, accuracy: 1e-12)
        XCTAssertEqual(WeightUnit.lb.fromKg(100), 220.46226218, accuracy: 1e-9)
        XCTAssertEqual(WeightUnit.lb.toKg(1), 0.4535923700, accuracy: 1e-9, "one pound is 0.45359237 kg")
        XCTAssertEqual(WeightUnit.lb.toKg(135), 61.2349699514, accuracy: 1e-9)
        XCTAssertEqual(WeightUnit.lb.toKg(225), 102.0582832523, accuracy: 1e-9)
        for kg in [0.25, 1, 20, 61.23, 100, 227.5, 999_999] as [Double] {
            XCTAssertEqual(WeightUnit.lb.toKg(WeightUnit.lb.fromKg(kg)), kg, accuracy: kg * 1e-12)
        }
    }

    func testDisplayRoundingTable() {
        let rows: [(unit: WeightUnit, kg: Double, shown: Double)] = [
            (.kg, 82.5, 82.5), (.kg, 82.504, 82.5), (.kg, 82.506, 82.51), (.kg, 0.005, 0.01), (.kg, -0.005, -0.01),
            (.kg, 0.004, 0), (.kg, -0.004, 0), (.kg, 0, 0), (.kg, 1_000_000, 1_000_000),
            (.lb, 61.23, 135), (.lb, 102.06, 225), (.lb, 100, 220.5), (.lb, 60, 132.3), (.lb, 82.5, 181.9), (.lb, 0.5, 1.1),
            (.lb, 0.01, 0), (.lb, 0.02, 0), (.lb, 0.03, 0.1), (.lb, 0, 0), (.lb, -0.02, 0),
        ]
        for row in rows {
            XCTAssertEqual(row.unit.displayValue(kg: row.kg), row.shown, accuracy: 1e-9, "\(row.kg) kg in \(row.unit)")
        }
    }

    func testDisplayValueNeverReturnsNegativeZeroOrNonFiniteNumbers() {
        XCTAssertEqual(WeightUnit.kg.displayValue(kg: -0.001).sign, .plus)
        XCTAssertEqual(WeightUnit.lb.displayValue(kg: -0.001).sign, .plus)
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(WeightUnit.kg.displayValue(kg: value), 0)
            XCTAssertEqual(WeightUnit.lb.displayValue(kg: value), 0)
        }
        XCTAssertTrue(WeightUnit.lb.displayValue(kg: 1e300).isFinite)
    }

    func testAWeightTypedInPoundsComesBackUnchangedAfterStorage() {
        // Every tenth of a pound up to 1,000 lb: typed -> kilograms -> stored to 0.01 kg (as the reducer does) -> shown.
        for tenths in 0...10_000 {
            let typed = Double(tenths) / 10
            let stored = WorkoutReducer.roundedWeight(WeightUnit.lb.toKg(typed))
            XCTAssertEqual(WeightUnit.lb.displayValue(kg: stored ?? -1), typed, accuracy: 1e-9, "\(typed) lb")
        }
    }

    func testAWeightTypedInKilogramsComesBackUnchangedAfterStorage() {
        for hundredths in 0...100_000 {
            let typed = Double(hundredths) / 100
            let stored = WorkoutReducer.roundedWeight(typed)
            XCTAssertEqual(WeightUnit.kg.displayValue(kg: stored ?? -1), typed, accuracy: 1e-9, "\(typed) kg")
        }
    }

    func testTheCommonBarbellLoadsInPoundsRoundTrip() {
        for pounds in [45.0, 95, 135, 185, 225, 275, 315, 365, 405, 495] {
            let stored = WorkoutReducer.roundedWeight(WeightUnit.lb.toKg(pounds)) ?? -1
            XCTAssertEqual(lbFormatter().text(kg: stored), NumberText.kg(pounds), "\(pounds) lb")
        }
    }
}

// MARK: - Default unit by locale

final class WeightUnitDefaultTests: XCTestCase {
    func testPoundsWhereThePoundIsAtHome() {
        for identifier in ["en_US", "en_LR", "my_MM", "es_US", "en-US"] {
            XCTAssertEqual(WeightUnit.defaultFor(locale: Locale(identifier: identifier)), .lb, identifier)
        }
    }

    func testKilogramsEverywhereElse() {
        for identifier in ["de_DE", "fr_FR", "en_GB", "en_CA", "en_AU", "ja_JP", "pt_BR", "sv_SE", "hi_IN", "de_CH"] {
            XCTAssertEqual(WeightUnit.defaultFor(locale: Locale(identifier: identifier)), .kg, identifier)
        }
    }

    func testAMeasurementSystemThatTheIdentifierNamesWins() {
        XCTAssertEqual(WeightUnit.defaultFor(locale: Locale(identifier: "en-US-u-ms-metric")), .kg)
        XCTAssertEqual(WeightUnit.defaultFor(locale: Locale(identifier: "de-DE-u-ms-ussystem")), .lb)
    }
}

// MARK: - Display format

final class DisplayFormatTests: XCTestCase {
    func testMetricIsKilogramsWithEnglishSeparators() {
        XCTAssertEqual(DisplayFormat.metric.unit, .kg)
        XCTAssertEqual(DisplayFormat.metric.locale.identifier, "en_US")
        XCTAssertEqual(DisplayFormat.metric.formatter.text(kg: 1234.5), "1234.5")
    }

    func testDeviceUsesTheCurrentLocaleWithTheGivenUnit() {
        let format = DisplayFormat.device(unit: .lb)
        XCTAssertEqual(format.unit, .lb)
        XCTAssertEqual(format.locale, Locale.current)
    }

    func testAFormatAndItsFormatterAreEquatableAndRoundTrip() {
        let format = DisplayFormat(unit: .lb, locale: deDE)
        XCTAssertEqual(format, DisplayFormat(unit: .lb, locale: deDE))
        XCTAssertNotEqual(format, DisplayFormat(unit: .kg, locale: deDE))
        XCTAssertNotEqual(format, DisplayFormat(unit: .lb, locale: enUS))
        XCTAssertEqual(format.formatter.format, format)
        XCTAssertEqual(WeightFormatter(format), WeightFormatter(unit: .lb, locale: deDE))
    }
}

// MARK: - Formatter output

final class WeightFormatterTests: XCTestCase {
    func testKilogramsInEnglish() {
        let f = kgFormatter()
        XCTAssertEqual(f.text(kg: 82.5), "82.5")
        XCTAssertEqual(f.text(kg: 80), "80")
        XCTAssertEqual(f.text(kg: 0), "0")
        XCTAssertEqual(f.text(kg: 0.05), "0.05")
        XCTAssertEqual(f.text(kg: 1.25), "1.25")
        XCTAssertEqual(f.text(kg: 82.504), "82.5")
        XCTAssertEqual(f.text(kg: 0.125), "0.13", "ties round away from zero")
        XCTAssertEqual(f.text(kg: 1234.5), "1234.5", "a weight is not grouped")
        XCTAssertEqual(f.text(kg: -2.5), "-2.5")
        XCTAssertEqual(f.text(kg: -0.001), "0")
        XCTAssertEqual(f.text(kg: .nan), "0")
        XCTAssertEqual(f.text(kg: .infinity), "0")
        XCTAssertEqual(f.textWithUnit(kg: 82.5), "82.5 kg")
        XCTAssertEqual(f.textWithUnit(kg: 80), "80 kg")
    }

    func testPoundsInEnglish() {
        let f = lbFormatter()
        XCTAssertEqual(f.text(kg: 61.23), "135")
        XCTAssertEqual(f.text(kg: 102.06), "225")
        XCTAssertEqual(f.text(kg: 100), "220.5")
        XCTAssertEqual(f.text(kg: 82.5), "181.9")
        XCTAssertEqual(f.text(kg: 0.5), "1.1")
        XCTAssertEqual(f.text(kg: 0), "0")
        XCTAssertEqual(f.textWithUnit(kg: 61.23), "135 lb")
        XCTAssertEqual(f.textWithUnit(kg: 100), "220.5 lb")
    }

    func testDecimalMarkAndGroupingByLocale() {
        XCTAssertEqual(kgFormatter(deDE).text(kg: 82.5), "82,5")
        XCTAssertEqual(kgFormatter(deDE).textWithUnit(kg: 82.5), "82,5 kg")
        XCTAssertEqual(lbFormatter(deDE).textWithUnit(kg: 100), "220,5 lb")
        XCTAssertEqual(kgFormatter(deDE).volume(kg: 1980.4), "1.980")
        XCTAssertEqual(kgFormatter(deDE).volume(kg: 1_234_567), "1.234.567")

        XCTAssertEqual(kgFormatter(enGB).text(kg: 82.5), "82.5")
        XCTAssertEqual(kgFormatter(enGB).volume(kg: 1980.4), "1,980")
        XCTAssertEqual(kgFormatter(enUS).volume(kg: 1_234_567), "1,234,567")

        // French groups with a (narrow no-break) space: whichever the platform's data says, it is the locale's own separator.
        let separator = frFR.groupingSeparator ?? ""
        XCTAssertFalse(separator.isEmpty)
        XCTAssertEqual(kgFormatter(frFR).text(kg: 82.5), "82,5")
        XCTAssertEqual(kgFormatter(frFR).volume(kg: 1980), "1" + separator + "980")
        XCTAssertEqual(kgFormatter(frFR).volumeWithUnit(kg: 1_234_567), "1" + separator + "234" + separator + "567 kg")
    }

    func testVolumeIsAGroupedWholeNumberInTheDisplayUnit() {
        XCTAssertEqual(kgFormatter().volume(kg: 0), "0")
        XCTAssertEqual(kgFormatter().volume(kg: 999.4), "999")
        XCTAssertEqual(kgFormatter().volume(kg: 999.5), "1,000")
        XCTAssertEqual(kgFormatter().volume(kg: 1979.5), "1,980")
        XCTAssertEqual(kgFormatter().volume(kg: -0.4), "0")
        XCTAssertEqual(kgFormatter().volume(kg: .nan), "0")
        XCTAssertEqual(lbFormatter().volume(kg: 1980), "4,365", "1,980 kg are 4,365.15 lb")
        XCTAssertEqual(lbFormatter().volumeWithUnit(kg: 1980), "4,365 lb")
        XCTAssertEqual(kgFormatter().volumeWithUnit(kg: 1980), "1,980 kg")
        XCTAssertEqual(lbFormatter(deDE).volume(kg: 1980), "4.365")
    }

    func testSignedTextForAddedAndAssistedLoads() {
        XCTAssertEqual(kgFormatter().signedText(kg: 10), "+10")
        XCTAssertEqual(kgFormatter().signedText(kg: 2.5), "+2.5")
        XCTAssertEqual(kgFormatter().signedText(kg: -20), "\u{2212}20")
        XCTAssertEqual(kgFormatter().signedText(kg: 0), "BW")
        XCTAssertEqual(kgFormatter().signedText(kg: 0.004), "BW")
        XCTAssertEqual(kgFormatter().signedText(kg: -0.004), "BW")
        XCTAssertEqual(kgFormatter(deDE).signedText(kg: -2.5), "\u{2212}2,5")
        XCTAssertEqual(lbFormatter().signedText(kg: 10), "+22")
        XCTAssertEqual(lbFormatter().signedText(kg: -9.07), "\u{2212}20")
        XCTAssertEqual(lbFormatter().signedText(kg: 0.01), "BW")
        XCTAssertTrue(kgFormatter().signedText(kg: -20).unicodeScalars.first == "\u{2212}")
        XCTAssertEqual(kgFormatter().signedText(kg: .nan), "BW")
    }

    func testAccessibilityText() {
        XCTAssertEqual(kgFormatter().accessibilityText(kg: 82.5), "82.5 kilograms")
        XCTAssertEqual(kgFormatter().accessibilityText(kg: 1), "1 kilogram")
        XCTAssertEqual(kgFormatter().accessibilityText(kg: 0), "0 kilograms")
        XCTAssertEqual(kgFormatter(deDE).accessibilityText(kg: 82.5), "82,5 kilograms")
        XCTAssertEqual(lbFormatter().accessibilityText(kg: 61.23), "135 pounds")
        XCTAssertEqual(lbFormatter().accessibilityText(kg: 0.4536), "1 pound")
        XCTAssertEqual(lbFormatter().accessibilityText(kg: 0), "0 pounds")
    }

    func testNumberWritesAValueThatIsAlreadyInTheDisplayUnit() {
        XCTAssertEqual(kgFormatter().number(1.25), "1.25")
        XCTAssertEqual(kgFormatter().number(25), "25")
        XCTAssertEqual(lbFormatter().number(2.5), "2.5")
        XCTAssertEqual(lbFormatter().number(45), "45")
        XCTAssertEqual(lbFormatter().number(2.25), "2.3", "a pound value shows one decimal")
        XCTAssertEqual(kgFormatter(deDE).number(1.25), "1,25")
    }

    func testDisplayValueOfTheFormatterIsTheUnitsRounding() {
        XCTAssertEqual(lbFormatter().displayValue(kg: 61.23), 135, accuracy: 1e-9)
        XCTAssertEqual(kgFormatter().displayValue(kg: 82.504), 82.5, accuracy: 1e-9)
    }

    func testTheEnglishKilogramFormatterIsTheLegacyNumberText() {
        let values: [Double] = [0, 0.004, 0.005, 0.125, 1, 2.5, 82.5, 100.01, 1234.5, 99_999.99, -3.25, -0.004, .nan, .infinity, 1e300]
        for value in values {
            XCTAssertEqual(kgFormatter().text(kg: value), NumberText.kg(value), "\(value)")
            XCTAssertEqual(kgFormatter().volume(kg: value), NumberText.thousands(value), "\(value)")
        }
    }

    func testNumberTextStaysLocaleIndependent() {
        // The legacy helpers write "." and "," whatever the locale of the device or of any formatter.
        XCTAssertEqual(NumberText.kg(82.5), "82.5")
        XCTAssertEqual(NumberText.kg(1234.5), "1234.5")
        XCTAssertEqual(NumberText.thousands(1_234_567), "1,234,567")
        XCTAssertEqual(NumberText.clock(seconds: 3723), "1:02:03")
        XCTAssertEqual(NumberText.rest(seconds: 150), "2:30")
        XCTAssertEqual(NumberText.rest(seconds: 0), "Off")
        XCTAssertEqual(kgFormatter(deDE).text(kg: 82.5), "82,5", "a formatter does use its locale")
        XCTAssertEqual(NumberText.kg(82.5), "82.5", "a German formatter changes nothing about NumberText")
    }

    func testNumberTextHasNoOpinionOfTheLocaleOfTheDevice() throws {
        // The legacy helpers must not read Locale.current. A source scan is the only check that also holds on a machine in an English
        // locale, where a regression would give the same text.
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PulseStrengthCore")
        let metrics = try String(contentsOf: sources.appendingPathComponent("Metrics.swift"), encoding: .utf8)
        XCTAssertFalse(metrics.contains("Locale.current"))
        XCTAssertFalse(metrics.contains("NumberFormatter"))
        XCTAssertFalse(metrics.contains("String(format: \"%f"), "no C-locale-dependent formatting either")
    }
}

// MARK: - Parsing

final class WeightParseTests: XCTestCase {
    private func parse(_ text: String, _ unit: WeightUnit = .kg, _ locale: Locale = enUS, negative: Bool = false) -> Double? {
        WeightFormatter.parse(text, unit: unit, locale: locale, allowsNegative: negative)
    }

    func testBothDecimalMarksAreAcceptedWhateverTheLocale() {
        for locale in [enUS, deDE, frFR, enGB] {
            XCTAssertEqual(parse("82.5", .kg, locale), 82.5, "\(locale.identifier)")
            XCTAssertEqual(parse("82,5", .kg, locale), 82.5, "\(locale.identifier)")
            XCTAssertEqual(parse("0.25", .kg, locale), 0.25)
            XCTAssertEqual(parse("0,25", .kg, locale), 0.25)
            XCTAssertEqual(parse("80", .kg, locale), 80)
            XCTAssertEqual(parse("0", .kg, locale), 0)
        }
    }

    func testTheUnitSymbolMayFollowTheNumber() {
        XCTAssertEqual(parse("82.5 kg"), 82.5)
        XCTAssertEqual(parse(" 82.5 kg "), 82.5)
        XCTAssertEqual(parse("82,5kg", .kg, deDE), 82.5)
        XCTAssertEqual(parse("82.5KG"), 82.5)
        XCTAssertEqual(parse("80 kgs"), 80)
        XCTAssertEqual(parse("\t80\u{00A0}kg\n"), 80)
        XCTAssertEqual(try XCTUnwrap(parse("135 lb", .lb)), 61.2349699514, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(parse("135lb", .lb)), 61.2349699514, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(parse("135 LBS", .lb)), 61.2349699514, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(parse("135", .lb)), 61.2349699514, accuracy: 1e-9, "the result is kilograms")
        XCTAssertEqual(try XCTUnwrap(parse("225.5", .lb)), WeightUnit.lb.toKg(225.5), accuracy: 1e-12)
    }

    func testTheOtherUnitsSymbolIsNotAWeightInThisUnit() {
        XCTAssertNil(parse("82.5 lb", .kg))
        XCTAssertNil(parse("135 kg", .lb))
        XCTAssertNil(parse("82.5 stone", .kg))
        XCTAssertNil(parse("82.5 kgx", .kg))
    }

    func testGroupingIsUnderstood() {
        XCTAssertEqual(parse("1,250.5"), 1250.5)
        XCTAssertEqual(parse("1.250,5"), 1250.5)
        XCTAssertEqual(try XCTUnwrap(parse("1,250,000", .lb)), WeightUnit.lb.toKg(1_250_000), accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(parse("1.250.000", .lb, deDE)), WeightUnit.lb.toKg(1_250_000), accuracy: 1e-6)
        XCTAssertEqual(parse("1,000,000"), 1_000_000)
        XCTAssertEqual(parse("1 250"), 1250)
        XCTAssertEqual(parse("1 250,5", .kg, frFR), 1250.5)
        XCTAssertEqual(parse("1\u{202F}250", .kg, frFR), 1250)
        XCTAssertEqual(parse("1\u{2019}250", .kg, Locale(identifier: "de_CH")), 1250)
        XCTAssertEqual(parse("12 345.5"), 12_345.5)
    }

    func testASingleSeparatorFollowedByThreeDigitsIsGroupingOnlyInTheLocalesOwnGroupingCharacter() {
        XCTAssertEqual(parse("1,250", .kg, enUS), 1250, "en_US groups with a comma")
        XCTAssertEqual(parse("1.250", .kg, enUS), 1.25, "and writes decimals with a point")
        XCTAssertEqual(parse("1.250", .kg, deDE), 1250, "de_DE groups with a point")
        XCTAssertEqual(parse("1,250", .kg, deDE), 1.25)
        XCTAssertEqual(parse("12,500", .kg, enUS), 12_500)
        XCTAssertEqual(parse("0,125", .kg, enUS), 0.125, "a leading zero is never a group")
        XCTAssertEqual(parse("0.125", .kg, deDE), 0.125)
        XCTAssertEqual(parse("1,25", .kg, enUS), 1.25, "two digits after the mark are decimals")
        XCTAssertEqual(parse("82,5", .kg, enUS), 82.5)
        XCTAssertEqual(parse("1234,567", .kg, enUS), 1234.567, "four digits before the mark are not a group")
    }

    func testTheLocalesOwnSeparatorsAreAccepted() {
        let arabic = Locale(identifier: "ar_SA")
        XCTAssertEqual(parse("82\u{066B}5", .kg, arabic), 82.5, "the Arabic decimal separator")
        XCTAssertEqual(parse("1\u{066C}250\u{066B}5", .kg, arabic), 1250.5, "and the Arabic grouping separator")
        XCTAssertEqual(parse("1\u{066C}250", .kg, arabic), 1250, "a single group of three digits is grouping")
        XCTAssertEqual(parse("82.5", .kg, arabic), 82.5, "the ASCII marks still work")
        XCTAssertNil(parse("82\u{066B}5", .kg, enUS), "another locale's separator is not a mark")
    }

    func testWhatTheFormatterWritesReadsBackInEveryLocale() {
        let kilograms: [Double] = [0, 0.25, 2.5, 82.5, 100, 1250.5, 12_345.67]
        for identifier in Locale.availableIdentifiers {
            let locale = Locale(identifier: identifier)
            for unit in WeightUnit.allCases {
                let formatter = WeightFormatter(unit: unit, locale: locale)
                for kg in kilograms {
                    let written = formatter.text(kg: kg)
                    let expected = unit.toKg(unit.displayValue(kg: kg))
                    XCTAssertEqual(WeightFormatter.parse(written, unit: unit, locale: locale) ?? .nan, expected, accuracy: 1e-9, "\(identifier) \(unit) \(written)")
                    let withUnit = formatter.textWithUnit(kg: kg)
                    XCTAssertNotNil(WeightFormatter.parse(withUnit, unit: unit, locale: locale), "\(identifier) \(withUnit)")
                }
                let volume = formatter.volume(kg: 1980)
                let expectedVolume = unit.toKg(unit.fromKg(1980).rounded())
                XCTAssertEqual(WeightFormatter.parse(volume, unit: unit, locale: locale) ?? .nan, expectedVolume, accuracy: 1e-9, "\(identifier) \(volume)")
            }
        }
    }

    func testIncompleteNumbersThatAPersonTypesAreAccepted() {
        XCTAssertEqual(parse(".5"), 0.5)
        XCTAssertEqual(parse(",5"), 0.5)
        XCTAssertEqual(parse("82."), 82)
        XCTAssertEqual(parse("82,"), 82)
        XCTAssertEqual(parse("+10"), 10)
    }

    func testGarbageIsRejected() {
        let garbage = [
            "", " ", "\n", "abc", "kg", "lb", ".", ",", ",.", "82.5.5", "82,5,5", "1.2.3", "8 2.5", "1,2,3.4", "1,25,000", "1 2 3",
            "1e5", "1E3", "0x50", "inf", "-inf", "nan", "NaN", "infinity", "--5", "5-", "5 5", "82.5kg5", "٣", "８２", "82.5 %",
            "1,2.5", "1.250,500.5", "1  250", "12,34,567",
        ]
        for text in garbage {
            XCTAssertNil(parse(text), "\"\(text)\"")
            XCTAssertNil(parse(text, .lb, deDE), "\"\(text)\" in pounds")
        }
    }

    func testNegativeValuesAreRejectedUnlessTheCallerAllowsThem() {
        XCTAssertNil(parse("-5"))
        XCTAssertNil(parse("\u{2212}5"))
        XCTAssertNil(parse("-0.5 kg"))
        XCTAssertNil(parse("-5", .lb))
        XCTAssertEqual(parse("-5", .kg, enUS, negative: true), -5)
        XCTAssertEqual(parse("\u{2212}5", .kg, enUS, negative: true), -5)
        XCTAssertEqual(parse("- 5,5 kg", .kg, deDE, negative: true), -5.5)
        XCTAssertEqual(try XCTUnwrap(parse("-10 lb", .lb, enUS, negative: true)), -4.5359237, accuracy: 1e-9)
        XCTAssertEqual(parse("-0", .kg, enUS, negative: true), 0)
        XCTAssertEqual(parse("-0", .kg, enUS, negative: true)?.sign, .plus, "no negative zero")
        XCTAssertEqual(parse("5", .kg, enUS, negative: true), 5)
        XCTAssertNil(parse("-", .kg, enUS, negative: true))
    }

    func testHugeValuesClampToTheMaximumWeight() {
        let maximum = WorkoutReducer.maximumWeightKg
        XCTAssertEqual(parse("1000000"), maximum)
        XCTAssertEqual(parse("1000001"), maximum)
        XCTAssertEqual(parse("99999999999999999999"), maximum)
        XCTAssertEqual(parse(String(repeating: "9", count: 400)), maximum, "a number beyond Double clamps too")
        XCTAssertEqual(parse("99999999 lb", .lb), maximum)
        XCTAssertEqual(parse("999999 kg"), 999_999)
        XCTAssertEqual(parse("-99999999999", .kg, enUS, negative: true), -maximum)
    }

    func testTheTypedPoundsComeBackAsTheSameDisplayedWeightAfterTheReducerStoredThem() throws {
        for text in ["45", "135", "225", "315", "132.3", "181,9", "0.5", "1000", "99.9"] {
            let kg = try XCTUnwrap(parse(text, .lb), text)
            let stored = try XCTUnwrap(WorkoutReducer.roundedWeight(kg))
            let typed = try XCTUnwrap(Double(text.replacingOccurrences(of: ",", with: ".")))
            XCTAssertEqual(WeightUnit.lb.displayValue(kg: stored), typed, accuracy: 1e-9, text)
        }
    }
}

// MARK: - Exhaustive round trips

final class WeightRoundTripSweepTests: XCTestCase {
    /// Every weight a person can type in pounds (0.1 steps up to 2,000 lb) is stored by the reducer and shown again unchanged.
    func testEveryTenthOfAPoundTypedIsShownUnchangedAfterStorage() throws {
        let formatter = lbFormatter()
        for tenths in 0...20_000 {
            let typed = formatter.number(Double(tenths) / 10)
            let kg = try XCTUnwrap(WeightFormatter.parse(typed, unit: .lb, locale: enUS), typed)
            let stored = try XCTUnwrap(WorkoutReducer.roundedWeight(kg), typed)
            XCTAssertEqual(formatter.text(kg: stored), typed, "\(typed) lb")
        }
    }

    /// What the formatter writes reads back in every unit and locale, grouping-free and with the locale's own decimal mark.
    func testWhatTheFormatterWritesReadsBackInEveryUnitAndLocale() throws {
        let identifiers = ["en_US", "en_GB", "de_DE", "fr_FR", "de_CH", "sv_SE", "ar_EG"]
        for identifier in identifiers {
            let locale = Locale(identifier: identifier)
            for unit in WeightUnit.allCases {
                let formatter = WeightFormatter(unit: unit, locale: locale)
                for hundredths in stride(from: 0, through: 300_000, by: 37) {
                    let text = formatter.text(kg: Double(hundredths) / 100)
                    let kg = try XCTUnwrap(WeightFormatter.parse(text, unit: unit, locale: locale), "\(identifier) \(unit) \(text)")
                    XCTAssertEqual(formatter.text(kg: kg), text, "\(identifier) \(unit)")
                }
            }
        }
    }

    /// Whatever is typed, the parser answers with a weight in range or nil: it never traps.
    func testArbitraryTextNeverGivesAnOutOfRangeWeight() {
        let alphabet = Array("0123456789.,- +\u{2212}kglbs e\u{066B}\u{066C}'\u{2019}\u{202F}x")
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(seed >> 33)
        }
        for _ in 0..<20_000 {
            let text = String((0..<(next() % 13)).map { _ in alphabet[next() % alphabet.count] })
            for unit in WeightUnit.allCases {
                for allowsNegative in [false, true] {
                    guard let kg = WeightFormatter.parse(text, unit: unit, locale: deDE, allowsNegative: allowsNegative) else { continue }
                    XCTAssertTrue(kg.isFinite, text)
                    XCTAssertLessThanOrEqual(abs(kg), WorkoutReducer.maximumWeightKg, text)
                    XCTAssertTrue(allowsNegative || kg >= 0, text)
                }
            }
        }
    }
}
