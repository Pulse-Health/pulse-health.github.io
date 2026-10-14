// WorkoutLiveActivity.swift
//
// The Pulse Strength Live Activity: Lock Screen presentation and Dynamic Island.
//
// TARGET MEMBERSHIP: compiled into the widget extension (PulseStrengthWidgets) together with
// Apps/Shared/Intents/StrengthIntents.swift and the other files of this folder. The extension's
// `@main WidgetBundle` only has to list `WorkoutLiveActivity()`.
//
// The app (LiveActivityManager) updates the activity with a `WorkoutSnapshot` and sets
// `ActivityContent.staleDate = restEndsAt` while a rest runs. A widget view cannot tick on its own, so when
// that date passes the system re-renders with `context.isStale == true`; the views then treat a resting
// snapshot as "rest over" ("Go" + Log set).

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
            LockScreenActivityView(
                state: context.state,
                workoutName: WorkoutLiveActivity.workoutName(state: context.state, attributes: context.attributes),
                isStale: context.isStale
            )
            .activityBackgroundTint(ActivityTheme.lockBackground)
            .activitySystemActionForegroundColor(ActivityTheme.textPrimary)
            .widgetURL(StrengthConfig.workoutURL)
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
            .widgetURL(StrengthConfig.workoutURL)
            .keylineTint(ActivityTheme.accent)
        }
    }

    /// The live name from the snapshot (it follows a rename), falling back to the name the activity started with.
    static func workoutName(state: WorkoutSnapshot, attributes: WorkoutActivityAttributes) -> String {
        state.workoutName.isEmpty ? attributes.workoutName : state.workoutName
    }
}
#endif
