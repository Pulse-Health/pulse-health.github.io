#if os(iOS)
import Foundation
import Combine
import SwiftUI
import PulseStrengthCore
import PulseStrengthActivity

/// Everything the strength feature needs at runtime, created once and shared by the screens:
/// persistence (Application Support, or the App Group container when the app is entitled), the store, the workout controller (the phone is the authority),
/// the platform services (Live Activity, notifications, HealthKit, Watch bridge) and the Watch status.
///
/// `StrengthAppEnvironment.shared` is created lazily on the main actor. Touching it early (for example
/// in the `App` initializer) is enough for a Live Activity button press to work when the app was launched
/// in the background by an App Intent: `live(seedDemoData:)` restores the running workout from disk and
/// installs the `WorkoutCommandBus` handler that forwards the button's action to the controller.
@MainActor
public final class StrengthAppEnvironment: ObservableObject {
    public let persistence: FileStrengthPersistence
    public let store: StrengthStore
    public let controller: WorkoutController
    public let services: PulseServices
    /// False for `preview(withActiveWorkout:)`: the services are inert and must not ask for permissions.
    public let hasSystemServices: Bool

    /// Apple Watch state worth telling the user about; the root view publishes it as `\.watchStatus`.
    @Published public var watchStatus: WatchStatus

    /// True while the body weight entry should be on screen because the user tapped a weigh-in reminder (or the `pulse-strength://weight` link).
    /// The root view presents the entry and clears the flag.
    @Published public var showsWeightEntry = false

    /// Keeps the weigh-in reminder notifications up to date; nil for previews and UI tests (no notifications, no permission prompts).
    let weightReminders: WeightReminderScheduler?

    /// Exchanges the body weight with Apple Health when the user turned that on; nil for previews and UI tests (no Health access, no prompts).
    let healthSync: BodyWeightHealthSync?

    /// The exercise whose detail a widget or control asked for (`pulse-strength://exercise/<id>`). The hub shows it and sets it back to nil.
    @Published public var pendingExerciseID: String?

    /// A deep link that arrived from a widget, a control or the Action button through the command inbox (not as an opened URL). The root view
    /// handles it like `onOpenURL` and sets it back to nil.
    @Published public var pendingDeepLink: StrengthDeepLink?

    /// Keeps the widget snapshot current (nil in previews and UI tests) and applies what widgets left in the command inbox.
    private let widgetPublisher: WidgetPublisher?
    private var commandDrain: WidgetCommandDrain?

    /// The live environment of the running app (persistence in Application Support or the App Group container, demo data when the store is empty).
    public static let shared: StrengthAppEnvironment = StrengthAppEnvironment.live()

    private init(
        persistence: FileStrengthPersistence,
        store: StrengthStore,
        controller: WorkoutController,
        services: PulseServices,
        hasSystemServices: Bool,
        watchStatus: WatchStatus,
        weightReminders: WeightReminderScheduler?,
        healthSync: BodyWeightHealthSync?,
        widgetPublisher: WidgetPublisher? = nil
    ) {
        self.persistence = persistence
        self.store = store
        self.controller = controller
        self.services = services
        self.hasSystemServices = hasSystemServices
        self.watchStatus = watchStatus
        self.weightReminders = weightReminders
        self.healthSync = healthSync
        self.widgetPublisher = widgetPublisher
    }

    // MARK: Live

    /// Builds the environment of the running app: persistence in the App Group container when the app is
    /// entitled to one, otherwise in Application Support/PulseStrength (the standalone build), the platform services, the command-bus handler for the Live Activity
    /// buttons, and restores a workout that was running when the app was last closed.
    public static func live(seedDemoData: Bool = true) -> StrengthAppEnvironment {
        let persistence = makeLivePersistence()
        let store = StrengthStore(persistence: persistence, seedDemoData: seedDemoData)
        let controller = WorkoutController(store: store, persistence: persistence, role: .authority)
        let services = PulseServices(controller: controller)
        let publisher = WidgetPublisher(
            store: store,
            controller: controller,
            directory: WidgetSnapshotStore.directory(),
            providers: WidgetPublisher.Providers(weeklyGoal: { store.weeklyGoal })
        )
        controller.addEffect(publisher)
        let environment = StrengthAppEnvironment(
            persistence: persistence,
            store: store,
            controller: controller,
            services: services,
            hasSystemServices: true,
            watchStatus: services.watchStatus,
            weightReminders: WeightReminderScheduler(store: store),
            healthSync: BodyWeightHealthSync.make(store: store),
            widgetPublisher: publisher
        )
        environment.connectWeightReminders()
        environment.connectHealthSync()
        environment.installCommandBus()
        environment.connectWatchStatus()
        // Last, so that the services (Live Activity re-attach, Watch sync, widget snapshot) see the restored workout.
        controller.restoreFromDisk()
        environment.startWidgetSupport()
        return environment
    }

    // MARK: Preview

    /// Temporary persistence with the sample data and no live services; optionally with a workout already running.
    ///
    /// `services` is a required property, so previews get a `PulseServices` that is registered with a detached
    /// controller nobody uses: the preview's own controller has no effects, so nothing reaches ActivityKit,
    /// HealthKit, notifications or the Watch.
    public static func preview(withActiveWorkout: Bool = false) -> StrengthAppEnvironment {
        let persistence = FileStrengthPersistence.temporary()
        let store = StrengthStore(persistence: persistence, seedDemoData: true)
        let controller = WorkoutController(store: store, persistence: persistence, role: .authority)
        let detached = WorkoutController(store: store, persistence: nil, role: .mirror)
        let services = PulseServices(controller: detached)
        let environment = StrengthAppEnvironment(
            persistence: persistence,
            store: store,
            controller: controller,
            services: services,
            hasSystemServices: false,
            watchStatus: .connected,
            weightReminders: nil,
            healthSync: nil
        )
        if withActiveWorkout {
            controller.startWorkout(template: store.templates.first)
        }
        return environment
    }

    // MARK: Weigh-in reminder

    /// Asks the user to enter their weight: presents the entry unless a workout is in progress (its screen would hide it; the hub card
    /// stays until the user has weighed in).
    public func requestWeightEntry() {
        guard controller.state == nil else { return }
        showsWeightEntry = true
    }

    /// Asks for the notification permission (call when the user turns the reminder on); true when notifications are allowed.
    /// Previews have no notifications and answer true.
    public func requestWeightReminderPermission() async -> Bool {
        guard let reminders = weightReminders else { return true }
        return await reminders.requestAuthorization()
    }

    /// True when the user has refused notifications, so the reminder can only show in the app.
    public func weightReminderPermissionDenied() async -> Bool {
        guard let reminders = weightReminders else { return false }
        return await reminders.isDenied()
    }

    /// Brings the scheduled reminders up to date and, when the Health sync is on, reads the new body weights of Health
    /// (call when the app becomes active).
    public func refreshOnActive() {
        weightReminders?.refresh()
        guard let sync = healthSync else { return }
        Task {
            await sync.readFromHealth()
        }
    }

    // MARK: Apple Health body weight

    /// False when this device has no Health (previews, UI tests, iPads): the switch in Settings is then disabled.
    public var isHealthSyncAvailable: Bool {
        healthSync?.isAvailable ?? false
    }

    /// Turns the sync on: asks for the Health permission, then reads the weights Health already has.
    /// True when the app may save to Health (a refused READ cannot be seen, only a refused save).
    public func startHealthSync() async -> Bool {
        guard let sync = healthSync else { return false }
        let canSave = await sync.requestAuthorization()
        await sync.readFromHealth()
        return canSave
    }

    private func connectHealthSync() {
        guard let sync = healthSync else { return }
        store.onBodyWeightSaved = { [weak sync] (entry: BodyWeightEntry) in
            sync?.save(entry)
        }
        store.onBodyWeightRemoved = { [weak sync] (entry: BodyWeightEntry) in
            sync?.remove(entry)
        }
    }

    private func connectWeightReminders() {
        let reference = EnvironmentReference(self)
        weightReminders?.onOpenEntry = {
            reference.environment?.requestWeightEntry()
        }
    }

    // MARK: Wiring

    /// Routes the Live Activity / Dynamic Island buttons (App Intents) to the controller.
    /// The handler holds the environment weakly and hops to the main actor. It returns only after the Live Activity
    /// update that the action caused was delivered to ActivityKit, because the intent's `perform()` returns with it and
    /// the process, when the intent launched it in the background, may be suspended right after.
    private func installCommandBus() {
        let reference = EnvironmentReference(self)
        WorkoutCommandBus.shared.install { action, origin in
            let services = await MainActor.run { () -> PulseServices? in
                guard let environment = reference.environment else { return nil }
                environment.controller.send(action, origin: origin)
                return environment.services
            }
            await services?.waitForPendingUpdates()
        }
    }

    /// Starts the widget snapshot publisher and the command-inbox drain. Called once the running workout was restored: a command left by an
    /// intent that launched the app in the background is applied to that workout.
    private func startWidgetSupport() {
        widgetPublisher?.start()
        let drain = WidgetCommandDrain(controller: controller, inbox: WidgetCommandInbox.shared()) { [weak self] link in
            self?.pendingDeepLink = link
        }
        commandDrain = drain
        drain.start()
    }

    /// The app became active: apply what widgets left meanwhile and refresh the snapshot (the day may have changed).
    public func sceneBecameActive() {
        commandDrain?.drain()
        widgetPublisher?.publishNow()
    }

    /// Mirrors the services' Watch status into the published `watchStatus`.
    /// The callback may arrive from a WatchConnectivity queue, so it hops to the main actor.
    private func connectWatchStatus() {
        let reference = EnvironmentReference(self)
        services.onWatchStatusChange = { status in
            Task { @MainActor in
                reference.environment?.applyWatchStatus(status)
            }
        }
        applyWatchStatus(services.watchStatus)
    }

    private func applyWatchStatus(_ status: WatchStatus) {
        if watchStatus != status {
            watchStatus = status
        }
    }

    /// The strength data lives in the App Group container, where the widgets, controls and Watch widgets can read it. Data that an earlier
    /// version of the app kept in Application Support is copied there once (`StrengthDataMigration`). Without the App Group (an unsigned
    /// simulator build) the app keeps using Application Support and the widgets show their sample content.
    private static func makeLivePersistence() -> FileStrengthPersistence {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory
        let legacy = base.appendingPathComponent("PulseStrength", isDirectory: true)
        if let shared = FileStrengthPersistence.appGroup(identifier: StrengthConfig.appGroupID) {
            StrengthDataMigration.copyMissingFiles(from: legacy, to: shared.directory)
            return shared
        }
        // `FileStrengthPersistence` creates the directory when needed.
        return FileStrengthPersistence(directory: legacy)
    }
}

/// Lets the `Sendable` command-bus handler reach the environment without keeping it alive.
/// The reference is only read inside `MainActor.run`.
private final class EnvironmentReference: @unchecked Sendable {
    weak var environment: StrengthAppEnvironment?

    init(_ environment: StrengthAppEnvironment) {
        self.environment = environment
    }
}
#endif
