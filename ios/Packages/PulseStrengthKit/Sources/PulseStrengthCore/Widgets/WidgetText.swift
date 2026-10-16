import Foundation

/// Small text and rounding rules shared by the snapshot analytics (widgets/SPEC.md section 2).
enum WidgetText {
    /// The dot between the two parts of a template name ("Upper A · Push"): U+00B7 MIDDLE DOT.
    private static let nameSeparator: Character = "\u{00B7}"

    /// Initials of a workout name: split on whitespace, drop the tokens that have no letter or digit (like the dot), take the first
    /// character of the first two tokens, or the first two characters of a single token; "WO" without a token. Upper case.
    /// "Upper A · Push" gives "UA".
    static func initials(of name: String) -> String {
        let tokens = name.split(whereSeparator: { $0.isWhitespace }).filter { token in
            token.contains { $0.isLetter || $0.isNumber }
        }
        switch tokens.count {
        case 0: return "WO"
        case 1: return String(tokens[0].prefix(2)).uppercased()
        default: return (String(tokens[0].prefix(1)) + String(tokens[1].prefix(1))).uppercased()
        }
    }

    /// The text after the last dot of a name, trimmed: "Push" for "Upper A · Push". nil without a dot, and when nothing but
    /// whitespace follows it (the name is then its own label).
    static func textAfterLastDot(_ name: String) -> String? {
        guard let dot = name.lastIndex(of: nameSeparator) else { return nil }
        let text = name[name.index(after: dot)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// "Push day" for "Upper A · Push", else the name.
    static func splitLabel(of name: String) -> String {
        textAfterLastDot(name).map { $0 + " day" } ?? name
    }

    /// "Push" for "Upper A · Push", else the name (the row labels of the training block).
    static func rowLabel(of name: String) -> String {
        textAfterLastDot(name) ?? name
    }

    /// The name up to its first " ·": "Lower A" for "Lower A · Quads", else the whole name.
    static func shortName(of name: String) -> String {
        guard let range = name.range(of: " " + String(nameSeparator)) else { return name }
        let text = name[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? name : text
    }

    /// `value` rounded to 0.1 (halves away from zero).
    static func tenth(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// `value` rounded to 0.01 (halves away from zero).
    static func hundredth(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    /// The plates of one side as "20 + 10 + 2.5".
    static func platesText(_ perSide: [Double]) -> String {
        perSide.map { NumberText.kg($0) }.joined(separator: " + ")
    }
}
