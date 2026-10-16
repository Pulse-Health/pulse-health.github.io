#if os(iOS)
import SwiftUI
import PulseStrengthCore

/// Settings of the strength feature (opened from the hub's "More" menu): the user's body weight with its history, the
/// weigh-in reminder (on/off, how often, at what time) and the Apple Health sync.
///
/// * Tapping the weight opens `BodyWeightEntrySheet`; a history row entered here swipes away (delete). A row read from Apple Health
///   says so and stays: Health owns it.
/// * Turning "Sync with Apple Health" on asks for the Health permission right then and reads the weights Health already has.
/// * Turning the reminder on asks for the notification permission right then (not at launch). If the user refuses, the reminder
///   still shows as a card on the hub, and the footer says how to allow notifications.
@MainActor
struct StrengthSettingsView: View {
    @ObservedObject private var store: StrengthStore
    private let environment: StrengthAppEnvironment

    @State private var showsEntry = false
    @State private var notificationsDenied = false
    @State private var healthCannotSave = false

    @Environment(\.scenePhase) private var scenePhase

    init(environment: StrengthAppEnvironment) {
        self._store = ObservedObject(wrappedValue: environment.store)
        self.environment = environment
    }

    // MARK: Body

    var body: some View {
        List {
            weightSection
            if !store.bodyWeights.isEmpty {
                historySection
            }
            reminderSection
            healthSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PulseTheme.ground.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsEntry) {
            BodyWeightEntrySheet(store: store)
        }
        .task {
            notificationsDenied = await environment.weightReminderPermissionDenied()
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from the Settings app, where the user may have allowed notifications.
            guard phase == .active else { return }
            Task {
                notificationsDenied = await environment.weightReminderPermissionDenied()
            }
        }
    }

    // MARK: Body weight

    private var weightSection: some View {
        Section {
            Button {
                showsEntry = true
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Body weight")
                            .pulseFont(17, relativeTo: .body)
                            .foregroundStyle(PulseTheme.ink)
                        if let latest = store.latestBodyWeight {
                            Text("Updated " + StrengthResultText.monthDay(latest.date, now: Date()))
                                .pulseFont(12, relativeTo: .footnote)
                                .foregroundStyle(PulseTheme.inkSecondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(store.latestBodyWeight.map { NumberText.kg($0.kg) + " kg" } ?? "Add")
                        .pulseNumber(17, .semibold, relativeTo: .body)
                        .foregroundStyle(store.latestBodyWeight == nil ? PulseTheme.green : PulseTheme.inkSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PulseTheme.inkTertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PulsePlainButtonStyle())
            .accessibilityIdentifier("settings-weight")
            .listRowBackground(PulseTheme.card)
        } header: {
            Text("Body weight")
        }
    }

    private var historySection: some View {
        let now = Date()
        // Every weigh-in is listed, so every one entered here can be deleted.
        let entries = store.bodyWeights
        return Section {
            ForEach(entries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(NumberText.kg(entry.kg) + " kg")
                            .pulseNumber(17, .semibold, relativeTo: .body)
                            .foregroundStyle(PulseTheme.ink)
                        if entry.source == .health {
                            Text("Apple Health")
                                .pulseFont(12, relativeTo: .footnote)
                                .foregroundStyle(PulseTheme.inkSecondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(StrengthResultText.monthDay(entry.date, now: now))
                        .pulseFont(15, relativeTo: .subheadline)
                        .foregroundStyle(PulseTheme.inkSecondary)
                }
                .listRowBackground(PulseTheme.card)
                .deleteDisabled(entry.source == .health)
                .accessibilityElement(children: .combine)
            }
            .onDelete { (offsets: IndexSet) in
                for index in offsets where entries.indices.contains(index) && entries[index].source == .app {
                    store.deleteBodyWeight(id: entries[index].id)
                }
            }
        } header: {
            Text("History")
        }
    }

    // MARK: Reminder

    private var reminderSection: some View {
        Section {
            Toggle("Remind me to update my weight", isOn: reminderBinding)
                .tint(PulseTheme.green)
                .listRowBackground(PulseTheme.card)
                .accessibilityIdentifier("settings-reminder-toggle")
            if store.weighIn.isEnabled {
                Picker("How often", selection: intervalBinding) {
                    ForEach(WeighInInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .listRowBackground(PulseTheme.card)
                .accessibilityIdentifier("settings-reminder-interval")
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .listRowBackground(PulseTheme.card)
                    .accessibilityIdentifier("settings-reminder-time")
            }
        } header: {
            Text("Reminder")
        } footer: {
            Text(reminderFooter)
        }
    }

    // MARK: Apple Health

    private var healthSection: some View {
        Section {
            Toggle("Sync with Apple Health", isOn: healthBinding)
                .tint(PulseTheme.green)
                .disabled(!environment.isHealthSyncAvailable)
                .listRowBackground(PulseTheme.card)
                .accessibilityIdentifier("settings-health-toggle")
        } header: {
            Text("Apple Health")
        } footer: {
            Text(healthFooter)
        }
    }

    private var healthFooter: String {
        if !environment.isHealthSyncAvailable {
            return "Apple Health is not available on this device."
        }
        var text = "Saves the weights you enter to Apple Health and adds the weights Health already has, for example from a smart scale. "
            + "Weights that come from Health can only be removed in the Health app."
        if store.weighIn.syncWithHealth, healthCannotSave {
            text += "\nPulse Strength may not save to Health yet. Allow Weight under Health > Data Access & Devices > Pulse Strength."
        }
        return text
    }

    private var healthBinding: Binding<Bool> {
        Binding<Bool>(
            get: { store.weighIn.syncWithHealth },
            set: { (enabled: Bool) in
                setHealthSync(enabled)
            }
        )
    }

    private func setHealthSync(_ enabled: Bool) {
        var preferences = store.weighIn
        preferences.syncWithHealth = enabled
        store.setWeighInPreferences(preferences)
        guard enabled else {
            healthCannotSave = false
            return
        }
        Task {
            let canSave = await environment.startHealthSync()
            healthCannotSave = !canSave
        }
    }

    // MARK: Reminder footer

    private var reminderFooter: String {
        let preferences = store.weighIn
        guard preferences.isEnabled else {
            return "Get a reminder to weigh in. You can log your weight right from the notification."
        }
        var text = ""
        let now = Date()
        let next = WeighInSchedule.reminders(
            lastWeighIn: store.latestBodyWeight?.date,
            preferences: preferences,
            now: now,
            calendar: Calendar.current,
            count: 1
        ).first
        if let next {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: next)
            text = "Next reminder: " + StrengthResultText.weekdayMonthDay(next, now: now)
                + " at " + Self.twoDigits(parts.hour ?? 0) + ":" + Self.twoDigits(parts.minute ?? 0) + ". Logging your weight restarts the countdown."
        }
        if notificationsDenied {
            if !text.isEmpty { text += "\n" }
            text += "Notifications are off for Pulse Strength, so the reminder only shows here in the app. Allow them in the Settings app."
        }
        return text
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0" + String(value) : String(value)
    }

    // MARK: Bindings

    private var reminderBinding: Binding<Bool> {
        Binding<Bool>(
            get: { store.weighIn.isEnabled },
            set: { (enabled: Bool) in
                setReminder(enabled)
            }
        )
    }

    private var intervalBinding: Binding<WeighInInterval> {
        Binding<WeighInInterval>(
            get: { store.weighIn.interval },
            set: { (interval: WeighInInterval) in
                var preferences = store.weighIn
                preferences.interval = interval
                store.setWeighInPreferences(preferences)
            }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding<Date>(
            get: {
                let preferences = store.weighIn
                return Calendar.current.date(bySettingHour: preferences.hour, minute: preferences.minute, second: 0, of: Date()) ?? Date()
            },
            set: { (date: Date) in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                var preferences = store.weighIn
                preferences.hour = min(max(parts.hour ?? preferences.hour, 0), 23)
                preferences.minute = min(max(parts.minute ?? preferences.minute, 0), 59)
                store.setWeighInPreferences(preferences)
            }
        )
    }

    private func setReminder(_ enabled: Bool) {
        var preferences = store.weighIn
        preferences.setEnabled(enabled, now: Date())
        store.setWeighInPreferences(preferences)
        guard enabled else { return }
        Task {
            let allowed = await environment.requestWeightReminderPermission()
            notificationsDenied = !allowed
        }
    }
}
#endif
