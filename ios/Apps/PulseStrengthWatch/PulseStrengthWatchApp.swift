// PulseStrengthWatchApp.swift
//
// Entry point of the watchOS app (a single-target watchOS 10 app embedded in the iOS app). The Watch mirrors the
// workout of the iPhone; the delegate starts the Health workout session when the phone launches the app.

#if os(watchOS)
import SwiftUI
import WatchKit
import PulseStrengthWatchUI

@main
@MainActor
struct PulseStrengthWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    /// The shared Watch environment (mirror controller, WatchConnectivity client, workout session).
    private let environment: WatchEnvironment

    init() {
        self.environment = WatchEnvironment.shared
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(environment: environment)
        }
    }
}
#endif
