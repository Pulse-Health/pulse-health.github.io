// WorkoutControlProvider.swift
//
// The value provider of the controls whose label depends on the workout: Start workout, Log set, Rest timer, Pause and Next up. The system asks it for
// the current value when the app reloads the controls (after the snapshot changed), after one of the control's own intents ran, and now and then on
// its own. A control cannot tick, so what moves by itself, the rest countdown, is drawn by a system timer text (see RestControl) and needs no refresh.
// The value is read like a widget reads its entry: the stored WidgetSnapshot, rebuilt when it dates from an earlier day; the gallery and the
// placeholder get `WorkoutControlState.preview`, never live data.

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
