// PulseShortcuts.swift
//
// The App Shortcuts of Pulse Strength (widgets/SPEC.md CT-10): they appear in the Shortcuts app, answer to Siri and can be chosen for the Action
// button (Settings > Action Button > Shortcut). The Action button's "Controls" choice offers the controls of Apps/Shared/Controls instead.
// TARGET MEMBERSHIP: the app. Shortcuts are defined next to the intents they run, so this sits with the other files of Apps/Shared/Intents; the widget
// extension, the Watch widget extension and the snapshot-test bundle that compile that folder do not need it and may exclude this file (the app
// provides the shortcuts; if the Shortcuts app ever lists each one twice, exclude it there).
//
// "Primary action" is the Action-button shortcut (PrimaryActionIntent decides what a press means). The other three are spoken commands that
// each mean one thing, so Siri never skips a rest when the person asked to log a set. Every phrase contains the application name exactly once, as the
// system requires; `\(.applicationName)` is "Pulse Strength".

#if os(iOS)
import AppIntents

struct PulseShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PrimaryActionIntent(),
            phrases: ["Do my next step in \(.applicationName)"],
            shortTitle: "Primary action",
            systemImageName: "dumbbell.fill"
        )
        AppShortcut(
            intent: LogNextSetControlIntent(),
            phrases: ["Log my set in \(.applicationName)"],
            shortTitle: "Log set",
            systemImageName: "checkmark"
        )
        AppShortcut(
            intent: StartNextIntent(),
            phrases: ["Start my workout in \(.applicationName)"],
            shortTitle: "Start workout",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: SkipRestControlIntent(),
            phrases: ["Skip rest in \(.applicationName)"],
            shortTitle: "Skip rest",
            systemImageName: "forward.end.fill"
        )
    }
}
#endif
