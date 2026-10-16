// AddRestControl.swift
//
// CT-04 +30 s rest: a button that adds 30 seconds to the running rest timer. It reuses `AdjustRestIntent` of the Live Activity, so the rest changes
// exactly as the "+15 s" button does; as for the Live Activity, a rest that is not running starts one of 30 seconds (the engine's rule for
// `adjustRest`). The control does not depend on the workout state, so it has no value provider. The glyph is the circular arrow with "30".

#if os(iOS)
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct AddRestControl: ControlWidget {
    static let kind = "health.pulse.strength.control.addRest"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: AdjustRestIntent(seconds: 30)) {
                Label("Add 30 seconds of rest", systemImage: "goforward.30")
            }
        }
        .displayName("Add 30 s rest")
        .description("Adds 30 seconds to the rest timer of your running workout, or starts a 30-second rest when none is running.")
    }
}
#endif
