// WorkoutControlProvider.swift
//
// The value provider of the controls whose label depends on the workout: Start workout, Log set, Rest timer, Pause and Next up. The system runs it in
// the widget extension and asks it for the current value when the app reloads the controls (after the snapshot changed), when a control's own intent
// returned from `perform()`, and now and then on its own. The value is read like a widget reads its entry: the stored WidgetSnapshot, rebuilt when it
// dates from an earlier day; the gallery, the Lock Screen editor and the Action button settings get `WorkoutControlState.preview`, never live data.

#if os(iOS)
import WidgetKit
import PulseStrengthCore

@available(iOS 18.0, *)
struct WorkoutControlProvider: ControlValueProvider {
    var previewValue: WorkoutControlState { .preview }

    func currentValue() async throws -> WorkoutControlState {
        WorkoutControlState(snapshot: WidgetSnapshotStore.loadForDisplay())
    }
}
#endif
