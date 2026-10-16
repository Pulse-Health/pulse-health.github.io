#if os(iOS)
import Foundation
import Combine
import UserNotifications
import PulseStrengthCore

/// Hands a request to the notification center. Kept outside the main-actor class so the completion handler,
/// which the system calls on a background queue, is not main-actor isolated.
private func addWeightReminderRequest(_ request: UNNotificationRequest, to center: UNUserNotificationCenter) {
    center.add(request) { (error: Error?) in
        if let error = error {
            ServiceLog.error("Weigh-in reminder could not be scheduled: \(error.localizedDescription)")
        }
    }
}

/// Keeps the weigh-in reminder notifications in step with the store: the user's reminder preferences and their latest weigh-in
/// decide the next dates (`WeighInSchedule.reminders`), and every change of either replaces the pending requests.
///
/// * At most `WeighInSchedule.maximumReminders` future notifications are pending (identifiers `<prefix>.0`, `<prefix>.1`, ...), so a
///   user who never opens the app still hears from it a few times, one interval apart, and then it goes quiet.
/// * The notification offers a "Log weight" text action: the typed weight is recorded without opening the app. A tap on the
///   notification itself asks for the weight entry (`onOpenEntry`).
/// * The notification permission is NOT requested at launch; `requestAuthorization()` is called when the user turns the reminder on.
///   Without the permission nothing is shown, and the hub's in-app card is the reminder.
@MainActor
final class WeightReminderScheduler {
    /// Called on the main actor when the user taps a reminder (or types something that is not a weight into its action).
    var onOpenEntry: (() -> Void)?

    private let store: StrengthStore
    private let center: UNUserNotificationCenter
    private var subscription: AnyCancellable?
    /// The dates currently registered with the system; empty when none.
    private var scheduled: [Date] = []

    init(store: StrengthStore, center: UNUserNotificationCenter = .current()) {
        self.store = store
        self.center = center

        center.delegate = StrengthNotificationDelegate.shared
        StrengthNotificationDelegate.shared.onWeightReminder = { [weak self] (response: WeightReminderResponse) in
            Task { @MainActor in
                self?.handle(response)
            }
        }
        registerCategory()

        // The publishers emit before the properties change, so the values they deliver (not the store's properties) are the new ones.
        subscription = Publishers.CombineLatest(store.$bodyWeights, store.$weighIn)
            .sink { [weak self] (latest: ([BodyWeightEntry], WeighInPreferences)) in
                self?.reschedule(lastWeighIn: latest.0.first?.date, preferences: latest.1, force: false)
            }
    }

    // MARK: Permission

    /// Asks for permission to show alerts and play the sound; true when the user allowed (or had allowed) notifications.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            // Requests added before the answer are kept by the system, but a fresh set is cheap and certain.
            refresh(force: true)
            return granted
        } catch {
            ServiceLog.error("Notification authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    /// True when the user has refused notifications for the app (the reminder then only shows in the app).
    func isDenied() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .denied
    }

    // MARK: Scheduling

    /// Recomputes the reminders from the store's current data (call when the app comes to the foreground: a delivered reminder
    /// leaves the list of future dates, and the clock or time zone may have changed).
    func refresh(force: Bool = false) {
        reschedule(lastWeighIn: store.latestBodyWeight?.date, preferences: store.weighIn, force: force)
    }

    private func reschedule(lastWeighIn: Date?, preferences: WeighInPreferences, force: Bool) {
        let calendar = Calendar.current
        let dates = WeighInSchedule.reminders(
            lastWeighIn: lastWeighIn,
            preferences: preferences,
            now: Date(),
            calendar: calendar
        )
        guard force || dates != scheduled else { return }
        scheduled = dates
        clearSystemNotifications()

        for (index, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Weigh-in"
            content.body = "Time to update your weight."
            content.sound = UNNotificationSound.default
            content.categoryIdentifier = StrengthConfig.weightReminderCategoryID

            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.identifier(index),
                content: content,
                trigger: trigger
            )
            addWeightReminderRequest(request, to: center)
        }
    }

    /// Removes every pending request and every reminder already delivered (it is out of date once the schedule changed).
    private func clearSystemNotifications() {
        let identifiers = (0..<WeighInSchedule.maximumReminders).map { Self.identifier($0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private static func identifier(_ index: Int) -> String {
        StrengthConfig.weightReminderIDPrefix + "." + String(index)
    }

    // MARK: Notification actions

    private func registerCategory() {
        let log = UNTextInputNotificationAction(
            identifier: StrengthConfig.weightReminderLogActionID,
            title: "Log weight",
            options: [],
            textInputButtonTitle: "Save",
            textInputPlaceholder: "Weight in kg"
        )
        let category = UNNotificationCategory(
            identifier: StrengthConfig.weightReminderCategoryID,
            actions: [log],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    private func handle(_ response: WeightReminderResponse) {
        switch response {
        case .open:
            onOpenEntry?()
        case .log(let text):
            if let kg = BodyWeightRules.parse(text) {
                store.recordBodyWeight(kg: kg, date: Date())
            } else {
                // Not a weight: let the user type it in the app instead of losing it.
                onOpenEntry?()
            }
        }
    }
}
#endif
