// PulseStrengthWidgetsBundle.swift
//
// Entry point of the widget extension: the Pulse Strength Live Activity (Lock Screen and Dynamic Island) and the widgets of
// widgets/SPEC.md. `WorkoutLiveActivity` lives in Apps/Shared/LiveActivity and every widget bundle in Apps/Shared/Widgets/<area>/;
// all of them are compiled into this target.

#if os(iOS)
import SwiftUI
import WidgetKit

@main
struct PulseStrengthWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        HomeWidgetBundle()
    }
}
#endif
