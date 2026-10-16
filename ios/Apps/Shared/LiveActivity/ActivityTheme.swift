// ActivityTheme.swift
//
// Colours, fonts and metrics of the Lock Screen Live Activity and the Dynamic Island.
// Compiled into the widget extension only (it does not import PulseStrengthIOS). Both surfaces are
// always dark, and the system does not honour `.environment(\.colorScheme, .dark)` for Live Activities,
// so every colour here is explicit: nothing in these views uses `.primary` / `.secondary`.
//
// Hex values come from LockScreen.dc.html and DynamicIsland.dc.html. Where the design uses a green
// fill with white text (#1B8448) that is what the buttons use; the ring and countdown use #34C759.

#if os(iOS)
import SwiftUI

// MARK: - Surface

/// The surface a shared component is drawn on. The Lock Screen card is translucent grey,
/// the Dynamic Island is pure black, so the secondary fills differ slightly.
enum ActivitySurface {
    case lockScreen
    case island
}

extension ActivitySurface {
    /// Secondary text (set label, "Next" line, unit suffixes).
    var secondaryText: Color {
        switch self {
        case .lockScreen: return ActivityTheme.lockTextSecondary
        case .island: return ActivityTheme.islandTextSecondary
        }
    }

    /// Fill of the "-15 s" / "+15 s" buttons.
    var controlFill: Color {
        switch self {
        case .lockScreen: return ActivityTheme.lockControlFill
        case .island: return ActivityTheme.islandControlFill
        }
    }

    /// Fill of the capsule behind a stepper.
    var pillFill: Color {
        switch self {
        case .lockScreen: return ActivityTheme.lockPillFill
        case .island: return ActivityTheme.islandControlFill
        }
    }

    /// Fill of the round - / + buttons inside a stepper.
    var pillButtonFill: Color {
        switch self {
        case .lockScreen: return ActivityTheme.lockControlFill
        case .island: return ActivityTheme.islandPillButtonFill
        }
    }

    /// Fill of a superset member row that is not the current one.
    var rowFill: Color {
        switch self {
        case .lockScreen: return ActivityTheme.lockRowFill
        case .island: return ActivityTheme.islandControlFill
        }
    }

    /// Corner radius of a rest button of the given height (12 on the Lock Screen, a full pill on the island).
    func buttonRadius(height: CGFloat) -> CGFloat {
        switch self {
        case .lockScreen: return 12
        case .island: return height / 2
        }
    }
}

// MARK: - Tokens

enum ActivityTheme {
    /// sRGB colour from a 0xRRGGBB value.
    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255,
              opacity: alpha)
    }

    // MARK: Backgrounds

    /// Lock Screen card: rgba(58,58,62,0.78).
    static let lockBackground = ActivityTheme.hex(0x3A3A3E, 0.78)
    /// The Dynamic Island is black (drawn by the system).
    static let islandBackground = Color.black

    // MARK: Text

    static let textPrimary = Color.white
    static let lockTextSecondary = Color.white.opacity(0.7)
    static let lockTextTertiary = Color.white.opacity(0.55)
    static let islandTextSecondary = Color.white.opacity(0.65)

    // MARK: Accents

    /// Ring, countdown, keyline tint (#34C759).
    static let accent = ActivityTheme.hex(0x34C759)
    /// Primary button fill, app badge (#1B8448); text on it is white.
    static let buttonGreen = ActivityTheme.hex(0x1B8448)
    /// Heart glyph (#FF453A).
    static let heart = ActivityTheme.hex(0xFF453A)
    /// Paused clock (dark-mode amber of the design's #9A5B00 paused clock).
    static let paused = ActivityTheme.hex(0xFF9F0A)

    // MARK: Live moments (LiveActivityNext.dc.html)

    /// Personal record: "NEW RECORD", the trophy disc, the PR tile and the compact "PR" (#FFD60A).
    static let gold = ActivityTheme.hex(0xFFD60A)
    /// Fill behind the record banner and the PR tile (rgba(255,214,10,0.18)).
    static let goldFill = ActivityTheme.hex(0xFFD60A, 0.18)
    /// Trophy on the gold disc (#3A2E00).
    static let goldInk = ActivityTheme.hex(0x3A2E00)
    /// Superset: the current member's ring and tag disc, and the compact tag (#0A84FF).
    static let blue = ActivityTheme.hex(0x0A84FF)
    /// Fill of the current member's row (rgba(10,132,255,0.22)).
    static let blueRowFill = ActivityTheme.hex(0x0A84FF, 0.22)
    /// Fill of the "Superset A · round 2/3" chip (rgba(10,132,255,0.3)).
    static let blueChipFill = ActivityTheme.hex(0x0A84FF, 0.3)
    /// Text of the chip and of the compact round "2/3" (#64D2FF).
    static let blueText = ActivityTheme.hex(0x64D2FF)
    /// Logged member, logged set dot and the coach label (#30D158).
    static let done = ActivityTheme.hex(0x30D158)
    /// Fill behind the coach tip text (rgba(48,209,88,0.16)).
    static let tipFill = ActivityTheme.hex(0x30D158, 0.16)
    /// A set that is still to do in the compact dots (#3A3A3C).
    static let dotDim = ActivityTheme.hex(0x3A3A3C)

    // MARK: StandBy (bench mode, StandBy.dc.html)

    /// The full-screen presentation is pure black.
    static let benchBackground = Color.black
    /// Track of the big ring, fill of the +15 s / Skip buttons (#2C2C2E).
    static let benchFill = ActivityTheme.hex(0x2C2C2E)
    /// "Resting · Bench Press" (#98989D).
    static let benchSecondary = ActivityTheme.hex(0x98989D)

    // MARK: Fills

    static let lockTrack = Color.white.opacity(0.2)
    static let compactTrack = Color.white.opacity(0.25)
    static let lockControlFill = Color.white.opacity(0.16)
    static let lockPillFill = Color.white.opacity(0.1)
    /// A member row of the superset card and a plate row (rgba(255,255,255,0.1)).
    static let lockRowFill = Color.white.opacity(0.1)
    /// A stat tile of the finish card and the plate row (rgba(255,255,255,0.08)).
    static let lockTileFill = Color.white.opacity(0.08)
    static let islandControlFill = ActivityTheme.hex(0x2C2C2E)
    static let islandPillButtonFill = ActivityTheme.hex(0x3A3A3C)

    // MARK: Fonts

    /// SF text.
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight)
    }

    /// SF Pro Rounded figures with fixed-width digits (the design's `.num` class).
    static func number(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    // MARK: Metrics

    /// Width reserved for a running timer so `Text(date, style: .timer)` cannot stretch.
    /// "59:59" needs about 3.1 em with fixed-width digits, "9:59:59" about 4.1 em.
    static func clockWidth(fontSize: CGFloat, hasHours: Bool) -> CGFloat {
        fontSize * (hasHours ? 4.1 : 3.1)
    }

    /// Width reserved for a rest countdown ("m:ss", up to "99:59").
    static func countdownWidth(fontSize: CGFloat) -> CGFloat {
        fontSize * 2.75
    }

    enum Metrics {
        // Lock Screen: the system cuts a Live Activity off at about 160 pt, so the rows are
        // tighter than the design mock-up (which is taller) while keeping every control and string.
        // Controls and the header badge have the design's sizes (stepper pill and Log set 48, round - / + buttons 40,
        // badge 26); both the logging card (10 + 26 + 8 + 48 + 6 + 48 + 12) and the rest card (10 + 26 + 8 + 56 + 6 + 40 + 12)
        // come to 158 pt.
        static let lockSideInset: CGFloat = 16
        static let lockTopInset: CGFloat = 10
        static let lockBottomInset: CGFloat = 12
        static let lockSectionSpacing: CGFloat = 8
        static let lockRowSpacing: CGFloat = 6
        static let lockHeaderHeight: CGFloat = 26
        static let lockRestButtonHeight: CGFloat = 40
        static let lockControlHeight: CGFloat = 48
        static let lockRingDiameter: CGFloat = 56

        // Lock Screen states of widgets/SPEC.md LA-01...LA-05. The mock-ups (LiveActivityNext.dc.html) are taller than the system
        // allows, so each card is rebuilt to the same 160 pt budget (10 top + 12 bottom inset included in the sums):
        //   record banner, resting    26 + 8 + 56 (banner) + 6 + 34 (countdown line)                       = 152
        //   record banner, logging    26 + 8 + 56 + 6 + 40 (exercise and Log set)                          = 158
        //   superset of 2 / 3         26 + 8 + 84 / 98 (member rows, Log button as tall as the rows)         = 140 / 154
        //   plates, logging           26 + 8 + 48 (plate row and Log set) + 6 + 48 (steppers)              = 158
        //   coach tip                 34 (countdown and title) + 6 + 47 (two lines of tip) + 6 + 40        = 155 (plus the 22 pt insets)
        //   finish                    32 + 10 + 52 (tiles)                                                 = 116
        static let lockBannerHeight: CGFloat = 56
        static let lockBannerDisc: CGFloat = 36
        static let lockMomentLineHeight: CGFloat = 34
        static let lockTipTopHeight: CGFloat = 34
        static let lockTipChoiceHeight: CGFloat = 40
        static let lockTipPadding: CGFloat = 7
        static let lockTileHeight: CGFloat = 52
        static let lockFinishBadge: CGFloat = 32
        static let lockSupersetButtonWidth: CGFloat = 92
        static let lockSupersetRowSpacing: CGFloat = 4
        /// Most member rows the superset card draws (a longer group shows the current member and its neighbours).
        static let supersetRowLimit = 3

        /// Height of one member row of the superset card: two members get the roomy rows of the design, three need smaller ones.
        static func lockSupersetRowHeight(members: Int) -> CGFloat {
            members <= 2 ? 40 : 30
        }

        // Dynamic Island, expanded bottom region: 94 pt below the camera row while logging, 88 pt while resting (the whole
        // island is about 149 / 147 pt in the snapshot harness; the system allows 160 pt). The design's 48 pt controls
        // do not fit there, so the steppers are 44 pt (round buttons 36) and Log set 40 pt.
        static let islandBottomTopInset: CGFloat = 4
        static let islandRowSpacing: CGFloat = 6
        static let islandRestButtonHeight: CGFloat = 38
        static let islandControlHeight: CGFloat = 44
        static let islandLogButtonHeight: CGFloat = 40
        /// Expanded record banner: 4 + 44 + 6 + 38 (rest buttons) = 92 pt, 94 pt with the 40 pt Log set row.
        static let islandBannerHeight: CGFloat = 44
        static let islandSupersetButtonWidth: CGFloat = 84
        static let islandSupersetRowSpacing: CGFloat = 3

        /// Member row of the expanded superset: 2 / 3 members take 68 / 78 pt.
        static func islandSupersetRowHeight(members: Int) -> CGFloat {
            members <= 2 ? 32 : 24
        }

        // Compact and minimal
        static let compactRingDiameter: CGFloat = 22
        static let compactRingLineWidth: CGFloat = 3
        /// Width of a compact leading / trailing slot (HIG: 52.33 pt on a 393 pt wide iPhone); the elapsed clock with hours is squeezed into it.
        static let compactSlotWidth: CGFloat = 52
        /// Width the set dots may take inside the compact leading slot.
        static let compactDotsWidth: CGFloat = 46

        // StandBy (bench mode): the canvas sizes of StandBy.dc.html.
        static let benchRingDiameter: CGFloat = 220
        static let benchRingLineWidth: CGFloat = 16
        static let benchCountdownSize: CGFloat = 64
        static let benchButtonHeight: CGFloat = 48
        static let benchColumnSpacing: CGFloat = 36
    }
}

// MARK: - Static clock (snapshot tests only)

/// Environment key behind `\.activityStaticNow`.
private struct ActivityStaticNowKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    /// TEST-ONLY switch used by the snapshot tests (Apps/PulseStrengthLiveSnapshotTests); the widget never sets it.
    ///
    /// `nil` (the default, and the only value in production) leaves every view exactly as it is: the live system timer
    /// views (`Text(timerInterval:)`, `Text(_:style: .timer)`, `ProgressView(timerInterval:)`) and the current time are used.
    /// When a date is set, the views draw the state at that instant with static equivalents instead: the same "m:ss" /
    /// "h:mm:ss" strings and a static ring at the same fraction. `ImageRenderer` cannot run (or reliably draw) the
    /// system timer views and their text depends on the wall clock, so a snapshot would not be reproducible without it.
    var activityStaticNow: Date? {
        get { self[ActivityStaticNowKey.self] }
        set { self[ActivityStaticNowKey.self] = newValue }
    }
}

extension View {
    /// Draws the Live Activity views below this one as they look at `now`, without live timers (snapshot tests only).
    func activityStaticClock(_ now: Date?) -> some View {
        environment(\.activityStaticNow, now)
    }
}
#endif
