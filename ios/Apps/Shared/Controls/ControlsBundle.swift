// ControlsBundle.swift
//
// The Controls of widgets/SPEC.md: CT-01 Start workout, CT-02 Log set, CT-03 Rest timer, CT-04 +30 s rest, CT-05 Plate calculator, CT-06 Pause,
// CT-07 Finish and CT-08 Next up. A control shows in Control Center, can replace the two buttons at the bottom of the Lock Screen (CT-09) and can be
// chosen for the Action button (Settings > Action Button > Controls). The Action button's "primary action" (CT-10) is an App Intent, not a control:
// see Apps/Shared/Intents/ControlIntents.swift and PulseShortcuts.swift.
//
// Rules the controls follow:
//   * `ControlWidget` is iOS 18 API and the app supports iOS 17, so every control is `@available(iOS 18.0, *)` and the bundle lists them under
//     `#available`. PulseStrengthWidgetsBundle composes this bundle with the others.
//   * The Lock Screen slots and the small Control Center size draw only the glyph, so every control has an SF Symbol of its own, and the title of its
//     `Label` (which VoiceOver reads, and the medium size shows) says in words what a press does.
//   * Labels come from the WidgetSnapshot through `WorkoutControlProvider`. The app reloads the controls with `ControlCenter.shared.reloadAllControls()`
//     after it wrote a new snapshot; the system also refreshes a control after one of its own intents ran.
//   * A block of a WidgetBundle takes only a limited number of widgets, so the eight controls are listed as two groups of four.

#if os(iOS)
import SwiftUI
import WidgetKit

struct ControlsBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 18.0, *) {
            WorkoutFlowControls().body
            WorkoutToolControls().body
        }
    }
}

/// CT-01...CT-04: start a workout, log a set, watch the rest and add to it.
@available(iOS 18.0, *)
private struct WorkoutFlowControls: WidgetBundle {
    var body: some Widget {
        StartNextControl()
        LogSetControl()
        RestControl()
        AddRestControl()
    }
}

/// CT-05...CT-08: the plate calculator, pause, finish and the 2x2 Next up.
@available(iOS 18.0, *)
private struct WorkoutToolControls: WidgetBundle {
    var body: some Widget {
        PlatesControl()
        PauseControl()
        FinishControl()
        NextUpControl()
    }
}
#endif
