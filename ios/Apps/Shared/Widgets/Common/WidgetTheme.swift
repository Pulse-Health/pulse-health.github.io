// WidgetTheme.swift
//
// Colours, fonts and small view helpers shared by every widget (Home Screen, Lock Screen, StandBy, Watch, Controls). The hex values are the
// ones of PulseTheme (PulseStrengthIOS); the widget extension does not link that module, so they are repeated here. iOS widgets follow the
// system appearance; the Watch is always dark. Compiled into the iOS widget extension, the watchOS widget extension and the snapshot tests.

#if os(iOS) || os(watchOS)
import SwiftUI
import WidgetKit
#if os(iOS)
import UIKit
#endif

enum WidgetTheme {
    // MARK: Colour construction

    /// sRGB colour from a 0xRRGGBB value.
    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// A colour with a light and a dark value. On the Watch (always dark) it is the dark value.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if os(iOS)
        return Color(UIColor { (traits: UITraitCollection) -> UIColor in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
        #else
        return hex(dark)
        #endif
    }

    // MARK: Surfaces and text

    static let card = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let ground = adaptive(light: 0xF2F2F7, dark: 0x000000)
    static let rowFill = adaptive(light: 0xF7F7FA, dark: 0x2C2C2E)
    static let track = adaptive(light: 0xE5E5EA, dark: 0x3A3A3C)
    static let trackStrong = adaptive(light: 0xC7C7CC, dark: 0x636366)
    static let ink = adaptive(light: 0x000000, dark: 0xFFFFFF)
    static let inkSecondary = adaptive(light: 0x6B6B70, dark: 0x98989D)
    static let inkTertiary = adaptive(light: 0x8E8E93, dark: 0x636366)
    static let separator = adaptive(light: 0xDADADF, dark: 0x38383A)

    // MARK: Accents

    static let green = adaptive(light: 0x1B8448, dark: 0x30D158)
    static let greenText = adaptive(light: 0x146638, dark: 0x30D158)
    static let greenTint = adaptive(light: 0xE4F2EA, dark: 0x16301F)
    static let progress = adaptive(light: 0x2EC76B, dark: 0x30D158)
    /// Text on a `green` fill.
    static let onGreen = adaptive(light: 0xFFFFFF, dark: 0x000000)
    static let blue = adaptive(light: 0x0066D6, dark: 0x0A84FF)
    static let blueText = adaptive(light: 0x0057B8, dark: 0x64D2FF)
    static let heart = adaptive(light: 0xFF3B30, dark: 0xFF453A)

    // MARK: Personal records

    static let goldFill = adaptive(light: 0xFFF6D6, dark: 0x3A2E00)
    static let gold = adaptive(light: 0xFFCC00, dark: 0xFFD60A)
    static let goldText = adaptive(light: 0x7A5200, dark: 0xFFD60A)

    // MARK: Recovery and status

    static let ready = adaptive(light: 0x34C759, dark: 0x30D158)
    static let recovering = adaptive(light: 0xFFCC00, dark: 0xFFD60A)
    static let worked = adaptive(light: 0xFF3B30, dark: 0xFF453A)
    /// Dim colour of an unfilled cell or a missed day.
    static let muted = adaptive(light: 0xF2F2F7, dark: 0x2C2C2E)

    /// The three steps of the month heatmap and the body map (0 is `muted`).
    static func heat(_ level: Int) -> Color {
        switch level {
        case 1: return adaptive(light: 0xB9E7C8, dark: 0x1E5A34)
        case 2: return adaptive(light: 0x5BC783, dark: 0x2F9B55)
        case 3: return adaptive(light: 0x1B8448, dark: 0x30D158)
        default: return muted
        }
    }

    // MARK: Fonts

    /// SF Pro Rounded with fixed-width digits: every figure in the widgets.
    static func number(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight)
    }

    /// Small upper-case label above a value ("NEXT UP").
    static func eyebrow(_ size: CGFloat = 11) -> Font {
        Font.system(size: size, weight: .semibold)
    }

    /// Corner radius of a widget-sized card drawn inside a widget.
    static let cornerRadius: CGFloat = 14
}

// MARK: - View helpers

extension View {
    /// The widget's background (the card colour; the system replaces it in tinted and StandBy modes).
    func widgetCardBackground() -> some View {
        containerBackground(for: .widget) { WidgetTheme.card }
    }

    /// A background that is the given colour (dark cards such as "Beat last time").
    func widgetBackground(_ color: Color) -> some View {
        containerBackground(for: .widget) { color }
    }
}
#endif
