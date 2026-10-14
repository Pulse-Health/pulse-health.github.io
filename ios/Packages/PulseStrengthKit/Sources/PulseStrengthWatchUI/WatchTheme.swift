#if os(watchOS)
import SwiftUI
import WatchKit
import PulseStrengthCore

// MARK: - Colour helper

extension Color {
    /// An sRGB colour from 0xRRGGBB.
    init(watchHex hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Tokens

/// Design tokens of the Apple Watch app. The Watch is always dark; the values equal the dark values of `PulseTheme`
/// (ground black, green 30D158, yellow FFD60A, red FF453A) and the grays of `Watch.dc.html`.
public enum WatchTheme {
    /// Screen background.
    public static let ground = Color(watchHex: 0x000000)
    /// Round control background (steppers, -15 / +15).
    public static let fill = Color(watchHex: 0x2C2C2E)
    /// Raised control background.
    public static let fillRaised = Color(watchHex: 0x3A3A3C)
    /// Primary accent: exercise name, Log set, rest ring, skip.
    public static let green = Color(watchHex: 0x30D158)
    /// Unfilled part of the rest ring (green at 22 %).
    public static let greenTrack = Color(watchHex: 0x30D158, opacity: 0.22)
    /// Elapsed workout time.
    public static let yellow = Color(watchHex: 0xFFD60A)
    /// Heart.
    public static let red = Color(watchHex: 0xFF453A)
    /// Primary text.
    public static let ink = Color.white
    /// Secondary text and units.
    public static let inkSecondary = Color(watchHex: 0x98989D)
    /// Next-set text on the rest screen.
    public static let inkSoft = Color(watchHex: 0xEBEBF5)
    /// Text on green.
    public static let onGreen = Color.black
}

/// Typography: rounded, tabular numerals for every number; the system font for words.
public enum WatchFont {
    public static func number(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    public static func text(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: weight, design: .default)
    }
}

/// The colours of a screen, dimmed in the Always-On state (`isLuminanceReduced`): no bright fills, softer text.
struct WatchPalette {
    let reduced: Bool

    init(reduced: Bool) {
        self.reduced = reduced
    }

    var primary: Color { reduced ? WatchTheme.ink.opacity(0.78) : WatchTheme.ink }
    var secondary: Color { reduced ? WatchTheme.inkSecondary.opacity(0.78) : WatchTheme.inkSecondary }
    var soft: Color { reduced ? WatchTheme.inkSoft.opacity(0.7) : WatchTheme.inkSoft }
    var accent: Color { reduced ? WatchTheme.green.opacity(0.75) : WatchTheme.green }
    var accentTrack: Color { reduced ? WatchTheme.green.opacity(0.14) : WatchTheme.greenTrack }
    var time: Color { reduced ? WatchTheme.yellow.opacity(0.75) : WatchTheme.yellow }
    var heart: Color { reduced ? WatchTheme.red.opacity(0.75) : WatchTheme.red }
    var controlFill: Color { reduced ? WatchTheme.fill.opacity(0.5) : WatchTheme.fill }
    var onAccent: Color { WatchTheme.onGreen }
}

// MARK: - Button styles

/// A round control (stepper, -15 / +15, skip).
struct WatchCircleButtonStyle: ButtonStyle {
    let fill: Color
    let diameter: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(fill))
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

/// A full-width pill (Log set, Done, Check again). `outline` is clear when the pill is filled.
struct WatchCapsuleButtonStyle: ButtonStyle {
    let fill: Color
    let outline: Color
    let outlineWidth: CGFloat
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(outline, lineWidth: outlineWidth))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

// MARK: - Haptics

/// Wrist haptics (`WKInterfaceDevice`). Main-actor only, like the views that call it.
@MainActor
enum WatchHaptics {
    /// A light tick for stepper and rest buttons.
    static func click() {
        WKInterfaceDevice.current().play(.click)
    }

    /// A set was logged.
    static func success() {
        WKInterfaceDevice.current().play(.success)
    }

    /// The rest timer ended.
    static func notification() {
        WKInterfaceDevice.current().play(.notification)
    }
}

// MARK: - Formatting and snapshot maths

/// Pure helpers shared by the screens; everything is derived from a `WorkoutSnapshot` and a date.
enum WatchFormat {

    /// Elapsed active seconds: frozen while paused, otherwise `date - activeStart`.
    static func elapsedSeconds(_ snapshot: WorkoutSnapshot, at date: Date) -> Int {
        if snapshot.isPaused { return max(0, snapshot.elapsedWhenPaused) }
        return max(0, Int(date.timeIntervalSince(snapshot.activeStart).rounded(.down)))
    }

    /// Remaining rest in seconds (frozen while paused); nil when no rest exists.
    static func restRemaining(_ snapshot: WorkoutSnapshot, at date: Date) -> TimeInterval? {
        if let frozen = snapshot.restFrozenRemaining { return Double(max(0, frozen)) }
        guard let endsAt = snapshot.restEndsAt else { return nil }
        return max(0, endsAt.timeIntervalSince(date))
    }

    /// Whole seconds shown on the countdown: the remaining time rounded up (a tiny tolerance ignores floating-point noise).
    static func wholeSeconds(_ remaining: TimeInterval) -> Int {
        let rounded = (max(0, remaining) - 1e-6).rounded(.up)
        return Int(max(0, min(rounded, 1_000_000)))
    }

    /// The share of the rest ring that is still filled: remaining / total, 1 once the rest is over, 0 without a rest.
    static func restFraction(_ snapshot: WorkoutSnapshot, remaining: TimeInterval?) -> Double {
        guard let remaining else { return 0 }
        if remaining <= 0 { return 1 }
        let total = max(1, Double(snapshot.restTotalSeconds))
        return min(1, max(0, remaining / total))
    }

    /// "24:18" normally; whole minutes ("24 min", "1 h 05 min") in the Always-On state, where seconds cannot be kept current.
    static func clockText(_ seconds: Int, coarse: Bool) -> String {
        if !coarse { return NumberText.clock(seconds: seconds) }
        let minutes = max(0, seconds) / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            let padding = rest < 10 ? "0" : ""
            return "\(hours) h \(padding)\(rest) min"
        }
        return "\(minutes) min"
    }

    /// The rest countdown: "1:12", or whole minutes (rounded up) in the Always-On state.
    static func countdownText(_ seconds: Int, coarse: Bool) -> String {
        if !coarse { return NumberText.clock(seconds: seconds) }
        let minutes = (max(0, seconds) + 59) / 60
        return "\(minutes) min"
    }

    /// What a set asks for, as the phone writes it: "82.5 kg × 6", "8 reps" or "45 s".
    static func workText(_ snapshot: WorkoutSnapshot) -> String {
        switch snapshot.tracking {
        case .weightReps: return snapshot.weightText + " kg × " + snapshot.repsText
        case .repsOnly: return snapshot.repsText + " reps"
        case .duration: return snapshot.repsText + " s"
        }
    }

    /// Appends `unit` unless the text already carries it or is the "–" placeholder.
    static func withUnit(_ text: String, _ unit: String) -> String {
        if text == "–" || text.isEmpty || text.contains(unit) { return text }
        return text + " " + unit
    }

    /// A duration for VoiceOver: "24 minutes 18 seconds".
    static func spoken(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 hour" : "\(hours) hours") }
        if minutes > 0 { parts.append(minutes == 1 ? "1 minute" : "\(minutes) minutes") }
        if secs > 0 || parts.isEmpty { parts.append(secs == 1 ? "1 second" : "\(secs) seconds") }
        return parts.joined(separator: " ")
    }
}
#endif
