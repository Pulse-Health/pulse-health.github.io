// PulseStrengthWidgetsBundle.swift
//
// Entry point of the widget extension: the Live Activities (the workout on the Lock Screen and in the Dynamic Island, the planned-session
// countdown), the widgets and the controls of widgets/SPEC.md. `LiveActivityBundle` lives in Apps/Shared/LiveActivity, every widget bundle in
// Apps/Shared/Widgets/<area>/ and the controls in Apps/Shared/Controls; all of them are compiled into this target. A `WidgetBundle` is not
// itself a `Widget` (its `body` is), so a surrounding builder block lists each bundle through its `body`.

#if os(iOS)
import SwiftUI
import WidgetKit

@main
struct PulseStrengthWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LiveActivityBundle().body
        HomeWidgetBundle().body
        LockWidgetBundle().body
        ExtrasWidgetBundle().body
        ControlsBundle().body
    }
}
#endif
