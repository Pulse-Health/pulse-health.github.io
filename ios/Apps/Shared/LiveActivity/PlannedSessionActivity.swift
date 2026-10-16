// PlannedSessionActivity.swift
//
// LA-06 Pre-workout countdown: the second Live Activity of the app (LiveActivityNext.dc.html, "Pre-workout"). A session the user planned
// shows "Planned 18:00", its name, the first set, a countdown to the start and the buttons "Start now" and "Snooze" on the Lock
// Screen, and the same in the Dynamic Island. `PlannedSessionManager` (PulseStrengthIOS) starts, moves and ends it.
//
// The attributes live in PulseStrengthActivity (the app starts the activity, the extension draws it). The countdown is the system's
// `Text(timerInterval:)`; the manager sets `staleDate = startsAt`, so when the time comes the system re-renders with `isStale` and
// the card says "Time to train" and "Now". The card is 134 pt tall (10 + 18 + 8 + 37 + 8 + 40 + 12).
//
// Compiled into the widget extension and the Live Activity snapshot tests with the other files of this folder.

#if os(iOS)
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit
import PulseStrengthActivity
import PulseStrengthCore

public struct PlannedSessionActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlannedSessionAttributes.self) { context in
            PlannedSessionLockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(ActivityTheme.lockBackground)
                .activitySystemActionForegroundColor(ActivityTheme.textPrimary)
                .widgetURL(StrengthDeepLink.hub.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PlannedIslandLeading(state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PlannedCountdownText(
                        startsAt: context.state.startsAt,
                        isStale: context.isStale,
                        size: 28,
                        weight: .bold,
                        color: ActivityTheme.accent,
                        maximumWidth: 110
                    )
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PlannedIslandBottom(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                PlannedClockGlyph(size: 16)
            } compactTrailing: {
                PlannedCountdownText(
                    startsAt: context.state.startsAt,
                    isStale: context.isStale,
                    size: 14,
                    weight: .semibold,
                    color: ActivityTheme.accent,
                    maximumWidth: ActivityTheme.Metrics.compactSlotWidth
                )
            } minimal: {
                PlannedClockGlyph(size: 15)
            }
            .widgetURL(StrengthDeepLink.hub.url)
            .keylineTint(ActivityTheme.accent)
        }
    }
}

// MARK: - Lock Screen

struct PlannedSessionLockScreenView: View {
    let attributes: PlannedSessionAttributes
    let state: PlannedSessionAttributes.ContentState
    /// `ActivityViewContext.isStale`: the manager sets `staleDate = startsAt`, so stale means the start time has come.
    let isStale: Bool
    /// Snapshot tests only (nil in production): the instant the views are drawn at.
    @Environment(\.activityStaticNow) private var staticNow

    private var isDue: Bool {
        isStale || state.startsAt <= (staticNow ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ActivityTheme.Metrics.lockSectionSpacing) {
            header
            titleBlock
            PlannedSessionButtons(
                attributes: attributes,
                surface: .lockScreen,
                height: ActivityTheme.Metrics.lockRestButtonHeight
            )
        }
        .padding(.horizontal, ActivityTheme.Metrics.lockSideInset)
        .padding(.top, ActivityTheme.Metrics.lockTopInset)
        .padding(.bottom, ActivityTheme.Metrics.lockBottomInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
    }

    /// Clock, "Planned 18:00" (or "Time to train") and the countdown.
    private var header: some View {
        HStack(spacing: 8) {
            PlannedClockGlyph(size: 18)
            Group {
                if isDue {
                    Text("Time to train")
                } else {
                    Text("Planned ") + Text(state.startsAt, style: .time)
                }
            }
            .font(ActivityTheme.text(14, .semibold))
            .foregroundStyle(ActivityTheme.accent)
            .lineLimit(1)
            Spacer(minLength: 8)
            PlannedCountdownText(
                startsAt: state.startsAt,
                isStale: isStale,
                size: 14,
                weight: .regular,
                color: ActivityTheme.lockTextSecondary
            )
        }
        .frame(height: 18)
    }

    /// "Lower A · Quads" over "Squat first: 4 × 5 at 100 kg".
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.templateName)
                .font(ActivityTheme.text(17, .bold))
                .foregroundStyle(ActivityTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let first = state.firstLine {
                Text(first)
                    .font(ActivityTheme.text(14))
                    .foregroundStyle(ActivityTheme.lockTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Components

/// The clock glyph of the planned session.
struct PlannedClockGlyph: View {
    var size: CGFloat

    var body: some View {
        Image(systemName: "clock")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(ActivityTheme.accent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Planned workout")
    }
}

/// The time left until `startsAt`, counting down on its own (`Text(timerInterval:)`); "Now" once the time has come. Snapshot tests
/// draw a static "m:ss" at their fixed instant instead of the system timer.
struct PlannedCountdownText: View {
    let startsAt: Date
    let isStale: Bool
    let size: CGFloat
    let weight: Font.Weight
    let color: Color
    /// Upper bound of the reserved width (a compact island slot); the countdown scales down inside it. nil: no bound.
    var maximumWidth: CGFloat? = nil
    /// Snapshot tests only (nil in production): the instant the countdown is drawn at.
    @Environment(\.activityStaticNow) private var staticNow

    private var now: Date {
        staticNow ?? Date()
    }

    private var isDue: Bool {
        isStale || startsAt <= now
    }

    /// True when an hours digit is needed ("1:25:00").
    private var hasHours: Bool {
        startsAt.timeIntervalSince(now) >= 3600
    }

    private var label: Text {
        if isDue {
            return Text("Now")
        }
        if let fixed = staticNow {
            return Text(NumberText.clock(seconds: Int(startsAt.timeIntervalSince(fixed).rounded(.up))))
        }
        return Text(timerInterval: min(Date(), startsAt)...startsAt, countsDown: true, showsHours: hasHours)
    }

    private var reservedWidth: CGFloat {
        let width = ActivityTheme.clockWidth(fontSize: size, hasHours: hasHours)
        guard let limit = maximumWidth else { return width }
        return min(width, limit)
    }

    var body: some View {
        label
            .font(ActivityTheme.number(size, weight))
            .monospacedDigit()
            .foregroundStyle(color)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: reservedWidth, alignment: .trailing)
    }
}

/// "Start now" (opens the app on the template) and "Snooze" (moves the start by ten minutes).
struct PlannedSessionButtons: View {
    let attributes: PlannedSessionAttributes
    let surface: ActivitySurface
    let height: CGFloat

    var body: some View {
        ActivityWeightedRow(weights: [1.4, 1], spacing: 8) {
            Button(intent: StartPlannedNowIntent(templateID: attributes.templateID.uuidString)) {
                Text("Start now")
                    .font(ActivityTheme.text(15, .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background(
                        ActivityTheme.buttonGreen,
                        in: RoundedRectangle(cornerRadius: surface.buttonRadius(height: height), style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start the planned workout now")
            Button(intent: SnoozePlannedIntent(minutes: PlannedSessionAttributes.snoozeMinutes)) {
                Text("Snooze")
                    .font(ActivityTheme.text(15, .semibold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .background(
                        surface.controlFill,
                        in: RoundedRectangle(cornerRadius: surface.buttonRadius(height: height), style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Snooze for " + String(PlannedSessionAttributes.snoozeMinutes) + " minutes")
        }
        .frame(height: height)
    }
}

// MARK: - Dynamic Island

/// Expanded leading: the clock and "Planned" over the time of day.
struct PlannedIslandLeading: View {
    let state: PlannedSessionAttributes.ContentState
    let isStale: Bool
    @Environment(\.activityStaticNow) private var staticNow

    private var isDue: Bool {
        isStale || state.startsAt <= (staticNow ?? Date())
    }

    var body: some View {
        HStack(spacing: 8) {
            PlannedClockGlyph(size: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(isDue ? "Time to train" : "Planned")
                    .font(ActivityTheme.text(15, .semibold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(state.startsAt, style: .time)
                    .font(ActivityTheme.text(11, .semibold))
                    .foregroundStyle(ActivityTheme.accent)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Expanded bottom: the template and its first set, then the two buttons (4 + 37 + 8 + 38 = 87 pt).
struct PlannedIslandBottom: View {
    let attributes: PlannedSessionAttributes
    let state: PlannedSessionAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(state.templateName)
                    .font(ActivityTheme.text(17, .semibold))
                    .foregroundStyle(ActivityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let first = state.firstLine {
                    Text(first)
                        .font(ActivityTheme.text(14))
                        .foregroundStyle(ActivityTheme.islandTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            PlannedSessionButtons(
                attributes: attributes,
                surface: .island,
                height: ActivityTheme.Metrics.islandRestButtonHeight
            )
        }
        .padding(.top, ActivityTheme.Metrics.islandBottomTopInset)
    }
}
#endif
