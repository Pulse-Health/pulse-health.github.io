// LiveMomentIntents.swift
//
// App Intents of the live moments of the Live Activity (widgets/SPEC.md LA-04, LA-06): the coach tip's suggested weight, the buttons of
// the pre-workout countdown, and the Shortcuts action that plans a session.
//
// TARGET MEMBERSHIP: like StrengthIntents.swift, with the app, the widget extension and the Live Activity snapshot tests (the Live
// Activity views create the intents inside `Button(intent:)`, the app executes them).
//
// * `ApplyCoachTipIntent` is a `LiveActivityIntent` and runs in the app. It hands `WorkoutAction.setWeight` for the set the tip names
//   to `WidgetIntentDispatch`, exactly like the other Live Activity buttons.
// * `StartPlannedNowIntent` opens the app (`openAppWhenRun`) and asks it, through the command inbox, to open
//   `pulse-strength://start?template=<id>`. The planned-session activity ends when the workout starts (`PlannedSessionManager`).
// * `SnoozePlannedIntent` is a `LiveActivityIntent`; the plan belongs to the app, so it reaches `PlannedSessionManager` through
//   `PlannedSessionBus` (PulseStrengthActivity), the module the app and the extension both link.
// * `PlanSessionIntent` is the one discoverable intent here (Shortcuts, Siri, Spotlight actions). It runs in the app
//   (`openAppWhenRun`, because ActivityKit starts an activity only from the foreground), plans the session through the same bus and
//   opens the Strength hub. The in-app entry point is `PlannedSessionManager.shared.schedule(template:startsAt:)`.

#if os(iOS)
import AppIntents
import Foundation
import PulseStrengthActivity
import PulseStrengthCore

// MARK: - Coach tip

/// The suggested-weight button of the coach tip: sets the weight of the set the tip names (`CoachTipBrief.targetSetID`) to the
/// suggestion. `WorkoutAction.setWeight` is absolute, so a repeated tap changes nothing more.
struct ApplyCoachTipIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Use suggested weight"
    static var description: IntentDescription? = IntentDescription("Sets the next set of the running strength workout to the weight the coach suggests.")
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    /// `UUID` string of the set (`CoachTipBrief.targetSetID`).
    @Parameter(title: "Set ID", default: "")
    var setID: String

    /// `UUID` string of the exercise entry (`CoachTipBrief.targetExerciseID`).
    @Parameter(title: "Exercise ID", default: "")
    var exerciseID: String

    /// The suggested weight in kilograms.
    @Parameter(title: "Weight", default: 0.0)
    var weightKg: Double

    init() {}

    init(setID: String, exerciseID: String, weightKg: Double) {
        self.setID = setID
        self.exerciseID = exerciseID
        self.weightKg = weightKg
    }

    func perform() async throws -> some IntentResult {
        guard let setUUID = UUID(uuidString: setID),
              let exerciseUUID = UUID(uuidString: exerciseID),
              weightKg.isFinite, weightKg > 0 else {
            return .result()
        }
        await WidgetIntentDispatch.send(.setWeight(exerciseID: exerciseUUID, setID: setUUID, kg: weightKg), origin: .liveActivity)
        return .result()
    }
}

// MARK: - Planned session

/// "Start now" of the pre-workout countdown: opens the app on the planned template.
struct StartPlannedNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Start planned workout"
    static var description: IntentDescription? = IntentDescription("Opens Pulse Strength and starts the workout you planned.")
    static var openAppWhenRun: Bool { true }
    static var isDiscoverable: Bool { false }

    /// `UUID` string of the template (`PlannedSessionAttributes.templateID`).
    @Parameter(title: "Template ID", default: "")
    var templateID: String

    init() {}

    init(templateID: String) {
        self.templateID = templateID
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: templateID) else {
            return .result()
        }
        WidgetIntentDispatch.openApp(.start(templateID: id))
        return .result()
    }
}

/// "Snooze" of the pre-workout countdown: moves the planned start later.
struct SnoozePlannedIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Snooze planned workout"
    static var description: IntentDescription? = IntentDescription("Moves the start of the planned strength workout later.")
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    /// Minutes to add (the activity's button uses `PlannedSessionAttributes.snoozeMinutes`).
    @Parameter(title: "Minutes", default: 10)
    var minutes: Int

    init() {}

    init(minutes: Int) {
        self.minutes = minutes
    }

    func perform() async throws -> some IntentResult {
        await PlannedSessionBus.shared.perform(.snooze(minutes: minutes))
        return .result()
    }
}

// MARK: - Plan a session (Shortcuts, Siri)

/// A saved workout template as Shortcuts shows it.
struct PlannedTemplateEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Workout template")
    static var defaultQuery = PlannedTemplateQuery()

    /// `WorkoutTemplate.id` as a string.
    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct PlannedTemplateQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PlannedTemplateEntity] {
        PlannedTemplates.entities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [PlannedTemplateEntity] {
        PlannedTemplates.entities()
    }
}

/// Where the intent finds the templates: the App Group container the app shares with its extensions when it has one, else the
/// app's own Application Support folder (the standalone build), the two places `StrengthAppEnvironment` stores them.
private enum PlannedTemplates {
    static func load() -> [WorkoutTemplate] {
        if let shared = FileStrengthPersistence.appGroup(identifier: StrengthConfig.appGroupID) {
            return shared.loadTemplates()
        }
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory
        return FileStrengthPersistence(directory: base.appendingPathComponent("PulseStrength", isDirectory: true)).loadTemplates()
    }

    static func entities() -> [PlannedTemplateEntity] {
        load().map { PlannedTemplateEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

enum PlanSessionError: Error, CustomLocalizedStringResourceConvertible {
    case noWorkout
    case inThePast

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noWorkout: return "Pulse Strength has no workout to plan yet."
        case .inThePast: return "Choose a time in the future."
        }
    }
}

/// "Plan Upper A · Push at 18:00": plans a session and shows its countdown on the Lock Screen (LA-06). Without a workout it plans the
/// one the app suggests next, else the first.
struct PlanSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Plan a strength session"
    static var description: IntentDescription? = IntentDescription("Plans a strength workout for later. A countdown with Start now and Snooze appears on your Lock Screen.")
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Workout")
    var template: PlannedTemplateEntity?

    @Parameter(title: "Starts at")
    var startsAt: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Plan \(\.$template) at \(\.$startsAt)")
    }

    init() {}

    init(template: PlannedTemplateEntity?, startsAt: Date) {
        self.template = template
        self.startsAt = startsAt
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard startsAt > Date() else {
            throw PlanSessionError.inThePast
        }
        let templates = PlannedTemplates.load()
        let wanted = template?.id ?? WidgetSnapshotStore.load()?.nextUp?.templateID.uuidString
        guard let chosen = templates.first(where: { $0.id.uuidString == wanted }) ?? templates.first else {
            throw PlanSessionError.noWorkout
        }
        await PlannedSessionBus.shared.perform(.schedule(PlannedSessionPlan(template: chosen, startsAt: startsAt)))
        WidgetIntentDispatch.openApp(.hub)
        return .result(dialog: "Planned \(chosen.name).")
    }
}
#endif
