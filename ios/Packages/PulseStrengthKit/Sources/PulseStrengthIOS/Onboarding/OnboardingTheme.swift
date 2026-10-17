#if os(iOS)
import SwiftUI
import PulseStrengthCore

// The look of the onboarding (design/ has the prototype). Dark only and video-led: the colours are the dark values of PulseTheme as
// fixed colours (the onboarding does not follow the system appearance), plus the glass and on-video values that exist only here.

extension Color {
    /// A fixed sRGB colour from 0xRRGGBB.
    init(onboardingHex hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum OnboardingTheme {
    // Surfaces (PulseTheme, dark)
    static let card = Color(onboardingHex: 0x1C1C1E)
    static let cellFill = Color(onboardingHex: 0x2C2C2E)
    static let chipFill = Color(onboardingHex: 0x767680, opacity: 0.24)
    static let separator = Color(onboardingHex: 0x545458, opacity: 0.65)
    static let progressTrack = Color(onboardingHex: 0x3A3A3C)
    static let toastFill = Color(onboardingHex: 0x3A3A3C)

    // Text
    static let inkSecondary = Color(onboardingHex: 0x98989D)
    static let inkTertiary = Color(onboardingHex: 0x636366)
    /// Secondary and tertiary text on the video or the veil.
    static let onMediaSecondary = Color(onboardingHex: 0xEBEBF5, opacity: 0.74)
    static let onMediaTertiary = Color(onboardingHex: 0xEBEBF5, opacity: 0.56)
    static let placeholder = Color(onboardingHex: 0xEBEBF5, opacity: 0.38)

    // Accents
    static let green = Color(onboardingHex: 0x30D158)
    static let greenTint = Color(onboardingHex: 0x30D158, opacity: 0.18)
    static let onGreen = Color.black
    static let blueText = Color(onboardingHex: 0x64D2FF)
    static let heart = Color(onboardingHex: 0xFF453A)
    static let destructive = Color(onboardingHex: 0xFF453A)
    /// Error text: #FF453A is 4.1:1 on the sheet, this is 4.9:1.
    static let destructiveText = Color(onboardingHex: 0xFF6961)
    static let nextRowRing = Color(onboardingHex: 0x30D158, opacity: 0.7)
    static let selectedFill = Color(onboardingHex: 0x30D158, opacity: 0.16)
    static let selectedSegment = Color(onboardingHex: 0x30D158, opacity: 0.22)

    // Data marks of the previews
    static let recoveryGood = Color(onboardingHex: 0x30D158)
    static let recoveryFair = Color(onboardingHex: 0xFFD60A)
    static let prFill = Color(onboardingHex: 0xFFD60A, opacity: 0.24)
    static let prText = Color(onboardingHex: 0xFFD60A)

    // The brand mark: the app icon's green gradient.
    static let markTop = Color(onboardingHex: 0x25A35B)
    static let markBottom = Color(onboardingHex: 0x16723D)

    // Metrics
    /// Side margin of the hero screens.
    static let heroInset: CGFloat = 24
    /// Height of the top bar (brand / back, progress, pause).
    static let topBarHeight: CGFloat = 52
    /// Phones shorter than this (iPhone SE) drop the previews and the option subtitles.
    static let compactHeight: CGFloat = 760
}

// MARK: - Compact layout

private struct OnboardingCompactKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True on short phones (iPhone SE): the flow view sets it from its height.
    var onboardingIsCompact: Bool {
        get { self[OnboardingCompactKey.self] }
        set { self[OnboardingCompactKey.self] = newValue }
    }
}

// MARK: - Surfaces

/// The glass of the preview cards and the example notification: blurred video behind, a light top edge.
struct OnboardingGlassBackground: View {
    var radius: CGFloat = PulseTheme.cardRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Color(onboardingHex: 0x1C1C1E, opacity: 0.5)))
            .overlay(
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.09), Color.white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.38), radius: 16, x: 0, y: 8)
    }
}

/// The dark grouped surface of the option cards and the row lists.
struct OnboardingPanelBackground: View {
    var radius: CGFloat = PulseTheme.cardRadius
    var fill: Color = OnboardingTheme.card.opacity(0.72)
    var edge: Color = Color.white.opacity(0.12)
    var edgeWidth: CGFloat = 0.5

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(fill)
            .overlay(shape.strokeBorder(edge, lineWidth: edgeWidth))
    }
}

extension View {
    func onboardingGlass(radius: CGFloat = PulseTheme.cardRadius) -> some View {
        self.background(OnboardingGlassBackground(radius: radius))
    }

    func onboardingPanel(radius: CGFloat = PulseTheme.cardRadius) -> some View {
        self.background(OnboardingPanelBackground(radius: radius))
    }
}

// MARK: - Buttons

/// The body of the primary button. A `ButtonStyle` cannot read the environment itself, this view reads whether the button is enabled.
private struct OnboardingPrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let glow: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .pulseFont(17, .semibold, relativeTo: .headline)
            .foregroundStyle(isEnabled ? OnboardingTheme.onGreen : OnboardingTheme.inkTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .pulseScaledFrame(minHeight: 52, relativeTo: PulseDynamicType.controlHeightStyle)
            .background(isEnabled ? OnboardingTheme.green : OnboardingTheme.cellFill, in: shape)
            .overlay(
                shape.strokeBorder(Color.white.opacity(isEnabled ? 0.30 : 0), lineWidth: 0.5)
            )
            .shadow(color: OnboardingTheme.green.opacity(isEnabled && glow ? 0.35 : 0), radius: 16, x: 0, y: 10)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

/// Full-width green call to action (52 pt, radius 14). Grey while disabled.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    var glow = false

    func makeBody(configuration: Configuration) -> some View {
        OnboardingPrimaryButtonBody(configuration: configuration, glow: glow)
    }
}

/// "Continue with Apple": white with black text, like Apple's own button.
struct OnboardingAppleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pulseFont(17, .semibold, relativeTo: .headline)
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .pulseScaledFrame(minHeight: 52, relativeTo: PulseDynamicType.controlHeightStyle)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

/// The second choice that must be as easy as the first ("No thanks" next to "Turn on AI Coaching"): same size and weight, glass fill.
struct OnboardingGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .pulseFont(17, .semibold, relativeTo: .headline)
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .pulseScaledFrame(minHeight: 52, relativeTo: PulseDynamicType.controlHeightStyle)
            .background(OnboardingTheme.chipFill, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// A quiet text button ("Not now").
struct OnboardingTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pulseFont(17, .semibold, relativeTo: .headline)
            .foregroundStyle(configuration.isPressed ? Color.white : OnboardingTheme.onMediaSecondary)
            .frame(maxWidth: .infinity)
            .pulseScaledFrame(minHeight: 48, relativeTo: PulseDynamicType.controlHeightStyle)
            .contentShape(Rectangle())
    }
}

/// An inline green link button ("Log in", "Forgot password?").
struct OnboardingLinkButtonStyle: ButtonStyle {
    var size: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pulseFont(size, .semibold, relativeTo: .subheadline)
            .foregroundStyle(OnboardingTheme.green)
            .padding(.horizontal, 6)
            .pulseScaledFrame(minHeight: 44, relativeTo: PulseDynamicType.controlHeightStyle)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// The round glass buttons at the edges (back, pause, close): a 44 pt hit area with a 34 pt disc.
struct OnboardingRoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.24 : 0.10)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            )
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - Rich text

enum OnboardingRichText {
    /// A sentence with bold parts and links to the legal pages. Links are underlined and keep the colour of the text around them
    /// when the `Text` is given a matching `.tint`.
    static func attributed(_ runs: [OnboardingRun], copy: OnboardingCopy) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var piece = AttributedString(run.text)
            switch run.style {
            case .plain:
                break
            case .bold:
                piece.foundation.inlinePresentationIntent = .stronglyEmphasized
            case .link(let document):
                // The scope is named (`foundation`, `swiftUI`): UIKit's attribute scope has an `underlineStyle` of its own, and the plain
                // property would be ambiguous in a module that imports both.
                piece.foundation.link = copy.legalURL(document)
                piece.swiftUI.underlineStyle = .single
            }
            result.append(piece)
        }
        return result
    }
}

// MARK: - The brand mark

/// The Rebase mark: a low baseline that steps up to a higher one (a placeholder until the final logo exists).
/// Drawn on a 24 x 24 grid like the prototype's SVG.
struct OnboardingMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let originX = rect.minX
        let originY = rect.minY
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }
        // A quarter circle of radius 3 as a cubic Bezier (control distance 0.5523 * r).
        let control: CGFloat = 0.5523 * 3

        var path = Path()
        path.move(to: point(3, 17.5))
        path.addLine(to: point(8.5, 17.5))
        path.addCurve(to: point(11.5, 14.5), control1: point(8.5 + control, 17.5), control2: point(11.5, 14.5 + control))
        path.addLine(to: point(11.5, 9.5))
        path.addCurve(to: point(14.5, 6.5), control1: point(11.5, 9.5 - control), control2: point(14.5 - control, 6.5))
        path.addLine(to: point(21, 6.5))
        return path
    }
}

/// The rounded green tile with the mark: 30 pt in the top bar, 40 pt in the example notification.
struct OnboardingMarkTile: View {
    var size: CGFloat = 30
    /// 0...1: how much of the line is drawn (it draws itself when the welcome screen appears).
    var drawn: CGFloat = 1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [OnboardingTheme.markTop, OnboardingTheme.markBottom], startPoint: .top, endPoint: .bottom))
            shape.strokeBorder(Color.white.opacity(0.24), lineWidth: 0.5)
            OnboardingMarkShape()
                .trim(from: 0, to: drawn)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.4 * size * 0.62 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.62, height: size * 0.62)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.35), radius: 5, x: 0, y: 2)
        .accessibilityHidden(true)
    }
}

// MARK: - Icon tiles and rows

/// A rounded square with a tinted icon: the leading element of the option cards and the rows.
struct OnboardingIconTile<Icon: View>: View {
    let tint: Color
    var size: CGFloat = 44
    var radius: CGFloat = 12
    private let icon: Icon

    init(tint: Color, size: CGFloat = 44, radius: CGFloat = 12, @ViewBuilder icon: () -> Icon) {
        self.tint = tint
        self.size = size
        self.radius = radius
        self.icon = icon()
    }

    var body: some View {
        icon
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A symbol sized for an icon tile.
struct OnboardingSymbol: View {
    let name: String
    var size: CGFloat = 20
    var weight: Font.Weight = .semibold

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size, weight: weight))
    }
}

/// One row of a grouped list: tile, title with subtitle, an optional tag at the end.
struct OnboardingRow<Icon: View>: View {
    let tint: Color
    let title: String
    let subtitle: String
    var tag: String?
    var tagIsWrite = false
    private let icon: Icon

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(tint: Color, title: String, subtitle: String, tag: String? = nil, tagIsWrite: Bool = false, @ViewBuilder icon: () -> Icon) {
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.tag = tag
        self.tagIsWrite = tagIsWrite
        self.icon = icon()
    }

    /// At accessibility text sizes the tag goes under the text instead of beside it, which would leave the text a narrow column.
    private var tagIsBelow: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        HStack(spacing: 14) {
            OnboardingIconTile(tint: tint, size: 40, radius: 10) { icon }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .pulseFont(16, .semibold, relativeTo: .body)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .pulseFont(13, .regular, relativeTo: .footnote)
                    .foregroundStyle(OnboardingTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if tagIsBelow, let tag = tag {
                    tagView(tag)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !tagIsBelow, let tag = tag {
                tagView(tag)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private func tagView(_ tag: String) -> some View {
        Text(tag)
            .pulseFont(12, .semibold, relativeTo: .caption)
            .foregroundStyle(tagIsWrite ? OnboardingTheme.green : OnboardingTheme.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tagIsWrite ? OnboardingTheme.greenTint : OnboardingTheme.chipFill, in: Capsule())
    }
}

/// Rows in one rounded group with a hairline between them (the hairline starts after the icon tile, like Settings).
struct OnboardingRowGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity)
        .onboardingPanel()
        .clipShape(RoundedRectangle(cornerRadius: PulseTheme.cardRadius, style: .continuous))
    }
}

/// A hairline that starts after the icon tile.
struct OnboardingRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(OnboardingTheme.separator)
            .frame(height: 0.5)
            .padding(.leading, 70)
            .accessibilityHidden(true)
    }
}

/// A small note with a lock (what stays on the phone, what is never sent).
struct OnboardingNote<Words: View>: View {
    private let label: Words

    init(@ViewBuilder label: () -> Words) {
        self.label = label()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OnboardingTheme.inkSecondary)
                .padding(.top, 2)
                .accessibilityHidden(true)
            label
                .pulseFont(13, .regular, relativeTo: .footnote)
                .foregroundStyle(OnboardingTheme.onMediaTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
    }
}
#endif
