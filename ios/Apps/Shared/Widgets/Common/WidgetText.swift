// WidgetText.swift
//
// Text helpers: relative days, kilograms, "weight × reps". Locale independent (hand formatted, English), like PulseStrengthCore's NumberText.

#if os(iOS) || os(watchOS)
import Foundation
import PulseStrengthCore

enum WidgetText {
    /// "Never", "Today", "Yesterday", "5 days ago".
    static func daysAgo(_ days: Int?) -> String {
        guard let days else { return "Never" }
        switch days {
        case ...0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }

    /// "5d" ("–" for none).
    static func daysShort(_ days: Int?) -> String {
        guard let days else { return "–" }
        return "\(max(0, days))d"
    }

    /// "85 kg".
    static func kg(_ value: Double) -> String { NumberText.kg(value) + " kg" }

    /// "85 × 5".
    static func weightReps(_ kg: Double, _ reps: Int) -> String { NumberText.kg(kg) + " × " + String(reps) }

    /// "+2.5" / "−3" with a real minus sign, "0" for zero.
    static func signed(_ value: Double) -> String {
        if abs(value) < 0.005 { return "0" }
        return (value > 0 ? "+" : "−") + NumberText.kg(abs(value))
    }

    /// "~55 min".
    static func minutes(_ minutes: Int) -> String { "~\(minutes) min" }

    /// "6 exercises" / "1 exercise".
    static func exercises(_ count: Int) -> String { count == 1 ? "1 exercise" : "\(count) exercises" }

    /// "7:00" style time of day from minutes after midnight.
    static func timeOfDay(minutes: Int) -> String {
        let hour = (minutes / 60) % 24
        let minute = minutes % 60
        return String(hour) + ":" + (minute < 10 ? "0" : "") + String(minute)
    }
}
#endif
