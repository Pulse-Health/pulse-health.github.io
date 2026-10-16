// PauseControl.swift
//
// CT-06 Pause / resume: a toggle that is on while the workout is paused. The system flips it at once and runs `SetPausedIntent` with the new state
// (true pauses, false resumes); the provider then reports the state the app wrote. The glyph stays the pause symbol, the on / off state is what the
// system draws (a lit toggle) and what the status text says, so the meaning is never carried by the symbol alone.

#if os(iOS)
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct PauseControl: ControlWidget {
    static let kind = "health.pulse.strength.control.pause"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: WorkoutControlProvider()) { state in
            ControlWidgetToggle("Pause workout", isOn: state.isPaused, action: SetPausedIntent()) { isPaused in
                Label(isPaused ? "Paused" : state.pauseStatus, systemImage: "pause.fill")
            }
        }
        .displayName("Pause workout")
        .description("Pauses your running workout and its rest timer. Press it again to resume.")
    }
}
#endif
