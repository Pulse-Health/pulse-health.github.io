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

    /// True while the walkthrough should be on screen. The root view presents it and clears the flag when it closes.
    @Published public var showsWalkthrough = false

    /// Keeps the weigh-in reminder notifications up to date; nil for previews and UI tests (no notifications, no permission prompts).
    let weightReminders: WeightReminderScheduler?

    /// Remembers that the user has seen the walkthrough; nil for previews and UI tests (they never open it by themselves
    /// and never touch the real defaults).
    let walkthroughMemory: WalkthroughMemory?

    /// Exchanges the body weight with Apple Health when the user turned that on; nil for previews and UI tests (no Health access, no prompts).
    let healthSync: BodyWeightHealthSync?

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
        walkthroughMemory: WalkthroughMemory?
    ) {
        self.persistence = persistence
        self.store = store
        self.controller = controller
        self.services = services
        self.hasSystemServices = hasSystemServices
        self.watchStatus = watchStatus
        self.weightReminders = weightReminders
        self.healthSync = healthSync
        self.walkthroughMemory = walkthroughMemory
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
        let environment = StrengthAppEnvironment(
            persistence: persistence,
            store: store,
            controller: controller,
            services: services,
            hasSystemServices: true,
            watchStatus: services.watchStatus,
            weightReminders: WeightReminderScheduler(store: store),
            healthSync: BodyWeightHealthSync.make(store: store),
            walkthroughMemory: WalkthroughMemory()
        )
        environment.connectWeightReminders()
        environment.connectHealthSync()
        environment.installCommandBus()
        environment.connectWatchStatus()
        // Last, so that the services (Live Activity re-attach, Watch sync) see the restored workout.
        controller.restoreFromDisk()
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
            healthSync: nil,
            walkthroughMemory: nil
        )
        if withActiveWorkout {
            controller.startWorkout(template: store.templates.first)
        }
        return environment
    }

    // MARK: Walkthrough

    /// Opens the walkthrough now (the hub's More > App Walkthrough replays it). Do not call it while the active-workout screen
    /// is up: the sheet would sit behind it.
    public func startWalkthrough() {
        showsWalkthrough = true
    }

    /// The hook for the end of onboarding: opens the walkthrough the first time it is called (and again only after the tour
    /// has been revised, see `Walkthrough.version`). Later calls do nothing, so the host can call it every time onboarding
    /// ends or on every launch. It also stays out of the way of a running workout, and of previews and UI tests (no memory).
    public func showWalkthroughAfterOnboarding() {
        guard let memory = walkthroughMemory, memory.shouldShow else { return }
        guard controller.state == nil else { return }
        showsWalkthrough = true
    }

    /// Called when the walkthrough has closed (finished, skipped or swiped away): it will not open by itself again.
    func walkthroughClosed() {
        walkthroughMemory?.markSeen()
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

    private static func makeLivePersistence() -> FileStrengthPersistence {
        if let shared = FileStrengthPersistence.appGroup(identifier: StrengthConfig.appGroupID) {
            return shared
        }
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory
        // `FileStrengthPersistence` creates the directory when needed.
        return FileStrengthPersistence(directory: base.appendingPathComponent("PulseStrength", isDirectory: true))
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
