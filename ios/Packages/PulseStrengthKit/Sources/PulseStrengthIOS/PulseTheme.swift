#if os(iOS)
import SwiftUI
import UIKit
import PulseStrengthCore

// MARK: - Dynamic colours

extension Color {
    /// A colour that follows the interface style. `light` is the value from the design canvas;
    /// `dark` is the matching iOS dark-mode value.
    public init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.init(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let hex = isDark ? dark : light
            let alpha = isDark ? darkAlpha : lightAlpha
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: CGFloat(alpha)
            )
        })
    }
}

/// Design tokens of the Pulse iOS look (see the "Pulse Gym & Strength" canvas and the
/// "Pulse App Screens" Fitness tab): SF type, grouped grey ground, white 20 pt cards,
/// green Fitness accent, blue Finish pill.
public enum PulseTheme {
    // Surfaces
    public static let ground = Color(light: 0xF2F2F7, dark: 0x000000)
    public static let card = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// Row background inside a card (pending set).
    public static let rowFill = Color(light: 0xF7F7FA, dark: 0x2C2C2E)
    /// Cells, small buttons and inputs inside a card.
    public static let cellFill = Color(light: 0xF2F2F7, dark: 0x2C2C2E)
    /// A pending-set cell sitting on a tinted (done) row.
    public static let cellOnTint = Color(light: 0xFFFFFF, dark: 0x3A3A3C)
    /// Background of an exercise media tile (the design's #F4F4F7 behind the demo frames and the placeholder glyph).
    public static let mediaTile = Color(light: 0xF4F4F7, dark: 0x2C2C2E)
    public static let chipFill = Color(light: 0x767680, dark: 0x767680, lightAlpha: 0.12, darkAlpha: 0.24)
    public static let separator = Color(light: 0x3C3C43, dark: 0x545458, lightAlpha: 0.18, darkAlpha: 0.65)

    // Text
    public static let ink = Color(light: 0x000000, dark: 0xFFFFFF)
    public static let inkSecondary = Color(light: 0x6B6B70, dark: 0x98989D)
    public static let inkTertiary = Color(light: 0x8E8E93, dark: 0x636366)

    // Accents
    public static let green = Color(light: 0x1B8448, dark: 0x30D158)
    /// Green text on grey fills (higher contrast than `green`).
    public static let greenText = Color(light: 0x146638, dark: 0x30D158)
    public static let greenTint = Color(light: 0x1B8448, dark: 0x30D158, lightAlpha: 0.10, darkAlpha: 0.18)
    /// The lighter green wash behind the coach tip (the design's rgba(27,132,72,0.08)).
    public static let coachTipFill = Color(light: 0x1B8448, dark: 0x30D158, lightAlpha: 0.08, darkAlpha: 0.18)
    /// Text / icon colour on a `green` fill.
    public static let onGreen = Color(light: 0xFFFFFF, dark: 0x000000)
    public static let blue = Color(light: 0x0066D6, dark: 0x0A84FF)
    public static let blueText = Color(light: 0x0057B8, dark: 0x64D2FF)
    public static let blueTint = Color(light: 0x007AFF, dark: 0x0A84FF, lightAlpha: 0.15, darkAlpha: 0.28)
    /// The superset pill's wash (the design's rgba(0,122,255,0.12)); `blueTint` is the stronger picker-chip value.
    public static let supersetFill = Color(light: 0x007AFF, dark: 0x0A84FF, lightAlpha: 0.12, darkAlpha: 0.28)
    public static let destructive = Color(light: 0xD70015, dark: 0xFF453A)
    public static let heart = Color(light: 0xFF3B30, dark: 0xFF453A)

    // Data marks
    public static let progress = Color(light: 0x2EC76B, dark: 0x30D158)
    public static let progressTrack = Color(light: 0xE5E5EA, dark: 0x3A3A3C)
    public static let progressTrackCurrent = Color(light: 0xC7C7CC, dark: 0x636366)
    public static let recoveryGood = Color(light: 0x34C759, dark: 0x30D158)
    public static let recoveryFair = Color(light: 0xFFCC00, dark: 0xFFD60A)
    public static let recoveryLow = Color(light: 0xFF3B30, dark: 0xFF453A)
    public static let prFill = Color(light: 0xFFCC00, dark: 0xFFD60A, lightAlpha: 0.24, darkAlpha: 0.24)
    public static let prText = Color(light: 0x7A5200, dark: 0xFFD60A)
    public static let doneRowFill = Color(light: 0x34C759, dark: 0x30D158, lightAlpha: 0.10, darkAlpha: 0.18)
    public static let nextRowRing = Color(light: 0x1B8448, dark: 0x30D158, lightAlpha: 0.55, darkAlpha: 0.7)
    public static let toastFill = Color(light: 0x1C1C1E, dark: 0x3A3A3C)
    public static let toastAction = Color(light: 0x7BE495, dark: 0x7BE495)

    // Metrics
    public static let cardRadius: CGFloat = 20
    public static let listRadius: CGFloat = 12
    public static let rowRadius: CGFloat = 10
    public static let sheetRadius: CGFloat = 26
    public static let screenInset: CGFloat = 16

    public static func recoveryColor(_ level: ActiveWorkoutPresentation.RecoveryLevel) -> Color {
        switch level {
        case .good: return recoveryGood
        case .fair: return recoveryFair
        case .low: return recoveryLow
        }
    }
}

// MARK: - Typography

public enum PulseFont {
    public static let largeTitle = Font.system(size: 34, weight: .bold)
    public static let title = Font.system(size: 22, weight: .bold)
    public static let headline = Font.system(size: 17, weight: .semibold)
    public static let body = Font.system(size: 17)
    public static let subhead = Font.system(size: 15)
    public static let footnote = Font.system(size: 13)
    public static let caption = Font.system(size: 12)
    public static let caption2 = Font.system(size: 11)

    /// Rounded numerals (SF Pro Rounded), the look of every figure in the design.
    public static func number(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .rounded)
    }
}

public extension View {
    /// Rounded, monospaced-digit figure text.
    func pulseNumber(_ size: CGFloat, _ weight: Font.Weight = .bold) -> some View {
        self.font(PulseFont.number(size, weight)).monospacedDigit()
    }

    /// White card with the design's soft shadow.
    func pulseCard(radius: CGFloat = PulseTheme.cardRadius, shadow: Bool = true) -> some View {
        self
            .background(PulseTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color.black.opacity(shadow ? 0.07 : 0), radius: 5, x: 0, y: 4)
    }
}

// MARK: - Set type colours

public extension SetType {
    var badgeBackground: Color {
        switch self {
        case .normal: return PulseTheme.cellFill
        case .warmup: return Color(light: 0xFF9500, dark: 0xFF9F0A, lightAlpha: 0.16, darkAlpha: 0.24)
        case .drop: return Color(light: 0x9B3FC9, dark: 0xBF5AF2, lightAlpha: 0.14, darkAlpha: 0.24)
        case .failure: return Color(light: 0xFF3B30, dark: 0xFF453A, lightAlpha: 0.14, darkAlpha: 0.24)
        }
    }

    var badgeForeground: Color {
        switch self {
        case .normal: return PulseTheme.ink
        case .warmup: return Color(light: 0x9A4A00, dark: 0xFF9F0A)
        case .drop: return Color(light: 0x7A2FA3, dark: 0xBF5AF2)
        case .failure: return Color(light: 0xB3261E, dark: 0xFF453A)
        }
    }
}

// MARK: - Button styles

/// Full-width green call to action (52 pt, radius 14).
public struct PulsePrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PulseFont.headline)
            .foregroundStyle(PulseTheme.onGreen)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(PulseTheme.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Grey tinted button with green text ("Add Set", stepper buttons).
public struct PulseTintButtonStyle: ButtonStyle {
    public var radius: CGFloat
    public init(radius: CGFloat = PulseTheme.rowRadius) { self.radius = radius }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(PulseTheme.greenText)
            .frame(minHeight: 44)
            .background(PulseTheme.cellFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The blue "Finish" pill.
public struct PulsePillButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(PulseTheme.blue, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Plain button with a pressed-state fade (rows, cells).
public struct PulsePlainButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Controls

/// Filter chip (picker, create form): blue tint when selected.
public struct PulseChip: View {
    public var title: String
    public var isSelected: Bool
    public var action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? PulseTheme.blueText : PulseTheme.ink.opacity(0.75))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(isSelected ? PulseTheme.blueTint : PulseTheme.chipFill, in: Capsule())
        }
        .buttonStyle(PulsePlainButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// iOS-style segmented control (RIR selector, tracking kind).
public struct PulseSegmented<Value: Hashable>: View {
    public var options: [(value: Value, title: String)]
    @Binding public var selection: Value

    public init(options: [(value: Value, title: String)], selection: Binding<Value>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(PulseFont.number(15, isSelected ? .bold : .medium))
                        .foregroundStyle(PulseTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        // An unselected segment only paints a clear fill, which has no hit area: without this
                        // shape a tap beside the digit would not reach the button.
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isSelected ? PulseTheme.card : Color.clear)
                                .shadow(color: Color.black.opacity(isSelected ? 0.12 : 0), radius: 4, x: 0, y: 3)
                        )
                }
                .buttonStyle(PulsePlainButtonStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(PulseTheme.chipFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
#endif
