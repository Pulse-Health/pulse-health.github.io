// WorkoutLiveActivity.swift
//
// The Pulse Strength Live Activity: Lock Screen presentation and Dynamic Island.
//
// TARGET MEMBERSHIP: compiled into the widget extension (PulseStrengthWidgets) together with
// Apps/Shared/Intents/StrengthIntents.swift and the other files of this folder. The extension's
// `@main WidgetBundle` lists `LiveActivityBundle()` (LiveActivityBundle.swift), which holds this activity and the planned-session one.
//
// The app (LiveActivityManager) updates the activity with a `WorkoutSnapshot` and sets
// `ActivityContent.staleDate = restEndsAt` while a rest runs. A widget view cannot tick on its own, so when
// that date passes the system re-renders with `context.isStale == true`; the views then treat a resting
// snapshot as "rest over" ("Go" + Log set).
//
// The live moments ride in the same snapshot (record, superset, plates, coach tip, finish); the views choose the card from
// them (ActivityState.swift). A finished workout ends the activity with `finish` set and the system keeps it on the Lock Screen
// for two hours: its tap opens the Strength hub, because no workout is left to open.

#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit
import PulseStrengthActivity
import PulseStrengthCore

public struct WorkoutLiveActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenContainer(
                state: context.state,
                workoutName: WorkoutLiveActivity.workoutName(state: context.state, attributes: context.attributes),
                isStale: context.isStale
            )
            .widgetURL(WorkoutLiveActivity.url(for: context.state))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandExpandedLeading(state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandExpandedTrailing(state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IslandExpandedBottom(
                        state: context.state,
                        workoutName: WorkoutLiveActivity.workoutName(state: context.state, attributes: context.attributes),
                        isStale: context.isStale
                    )
                }
            } compactLeading: {
                IslandCompactLeading(state: context.state, isStale: context.isStale)
            } compactTrailing: {
                IslandCompactTrailing(state: context.state, isStale: context.isStale)
            } minimal: {
                IslandMinimal(state: context.state, isStale: context.isStale)
            }
            .widgetURL(WorkoutLiveActivity.url(for: context.state))
            .keylineTint(context.state.moment != nil ? ActivityTheme.gold : ActivityTheme.accent)
        }
    }

    /// The live name from the snapshot (it follows a rename), falling back to the name the activity started with.
    static func workoutName(state: WorkoutSnapshot, attributes: WorkoutActivityAttributes) -> String {
        state.workoutName.isEmpty ? attributes.workoutName : state.workoutName
    }

    /// What a tap opens: the running workout, or the Strength hub once the workout is finished.
    static func url(for state: WorkoutSnapshot) -> URL {
        state.finish == nil ? StrengthConfig.workoutURL : StrengthDeepLink.hub.url
    }
}

// MARK: - Lock Screen root

/// The Lock Screen view of the activity. It reads `isActivityFullscreen` (StandBy, SB-02), which only exists from iOS 17.2, so the
/// read lives in a view of its own that is chosen with `#available`; before 17.2 the card is always the normal one.
struct WorkoutLockScreenContainer: View {
    let state: WorkoutSnapshot
    let workoutName: String
    let isStale: Bool

    var body: some View {
        if #available(iOS 17.2, *) {
            FullscreenAwareLockScreen(state: state, workoutName: workoutName, isStale: isStale)
        } else {
            WorkoutLockScreenSurface(state: state, workoutName: workoutName, isStale: isStale, isFullscreen: false)
        }
    }
}

@available(iOS 17.2, *)
private struct FullscreenAwareLockScreen: View {
    let state: WorkoutSnapshot
    let workoutName: String
    let isStale: Bool
    @Environment(\.isActivityFullscreen) private var isFullscreen

    var body: some View {
        WorkoutLockScreenSurface(state: state, workoutName: workoutName, isStale: isStale, isFullscreen: isFullscreen)
    }
}

/// The card with the tint the system draws behind it: the translucent grey of the Lock Screen, pure black in StandBy.
struct WorkoutLockScreenSurface: View {
    let state: WorkoutSnapshot
    let workoutName: String
    let isStale: Bool
    let isFullscreen: Bool

    var body: some View {
        LockScreenActivityView(state: state, workoutName: workoutName, isStale: isStale, isFullscreen: isFullscreen)
            .activityBackgroundTint(isFullscreen && state.finish == nil ? ActivityTheme.benchBackground : ActivityTheme.lockBackground)
            .activitySystemActionForegroundColor(ActivityTheme.textPrimary)
    }
}
#endif
