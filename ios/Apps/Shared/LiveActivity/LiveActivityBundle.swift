// LiveActivityBundle.swift
//
// Both Live Activities of the app in one bundle: the running workout (Lock Screen, Dynamic Island, StandBy) and the pre-workout
// countdown. PulseStrengthWidgetsBundle lists this bundle instead of `WorkoutLiveActivity()`.

#if os(iOS)
import SwiftUI
import WidgetKit

struct LiveActivityBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        PlannedSessionActivity()
    }
}
#endif
