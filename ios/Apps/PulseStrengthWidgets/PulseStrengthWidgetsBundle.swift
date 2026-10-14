// PulseStrengthWidgetsBundle.swift
//
// Entry point of the widget extension. The extension only hosts the Pulse Strength Live Activity (Lock Screen and
// Dynamic Island); `WorkoutLiveActivity` lives in Apps/Shared/LiveActivity, which is compiled into this target.

#if os(iOS)
import SwiftUI
import WidgetKit

@main
struct PulseStrengthWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}
#endif
