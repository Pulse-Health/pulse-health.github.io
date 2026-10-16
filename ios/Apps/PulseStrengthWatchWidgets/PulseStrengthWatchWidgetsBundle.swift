// PulseStrengthWatchWidgetsBundle.swift
//
// Entry point of the watchOS widget extension: the Apple Watch widgets of widgets/SPEC.md (WA-01...WA-10: watch-face complications and
// Smart Stack cards). They live in Apps/Shared/Widgets/Watch and read the widget snapshot that the Watch app saved into the App Group
// container (WatchWidgetSnapshotReceiver). A `WidgetBundle` is not itself a `Widget` (its `body` is), so the bundle is listed through its `body`.

#if os(watchOS)
import SwiftUI
import WidgetKit

@main
struct PulseStrengthWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchWidgetBundle().body
    }
}
#endif
