import Foundation

/// The `pulse-strength://` links that widgets, controls and the Live Activity open (widgets/SPEC.md section 4). The app parses them
/// with `init?(url:)`; the surfaces build them with `url`.
public enum StrengthDeepLink: Equatable, Sendable {
    /// Open the running workout (`pulse-strength://workout`).
    case workout
    /// Start the suggested next template.
    case startNext
    /// Start one template.
    case start(templateID: UUID)
    /// Start an empty workout with a name.
    case startEmpty(name: String)
    /// Open the detail of an exercise.
    case exercise(id: String)
    /// Open the Strength hub.
    case hub
    /// Open the running workout on the plate calculator.
    case plates
    /// Open the body weight entry (the weigh-in reminder notification).
    case weight

    public init?(url: URL) {
        guard url.scheme?.lowercased() == StrengthConfig.urlScheme, let host = url.host?.lowercased() else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch host {
        case "workout": self = .workout
        case "start-next": self = .startNext
        case "hub": self = .hub
        case "plates": self = .plates
        case "weight": self = .weight
        case "start":
            guard let text = value("template"), let id = UUID(uuidString: text) else { return nil }
            self = .start(templateID: id)
        case "start-empty":
            let name = (value("name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self = .startEmpty(name: name.isEmpty ? StrengthConfig.defaultWorkoutName : name)
        case "exercise":
            let id = url.pathComponents.dropFirst().first ?? ""
            guard !id.isEmpty else { return nil }
            self = .exercise(id: id)
        default:
            return nil
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = StrengthConfig.urlScheme
        switch self {
        case .workout: components.host = "workout"
        case .startNext: components.host = "start-next"
        case .hub: components.host = "hub"
        case .plates: components.host = "plates"
        case .weight: components.host = "weight"
        case .start(let id):
            components.host = "start"
            components.queryItems = [URLQueryItem(name: "template", value: id.uuidString.lowercased())]
        case .startEmpty(let name):
            components.host = "start-empty"
            components.queryItems = [URLQueryItem(name: "name", value: name)]
        case .exercise(let id):
            components.host = "exercise"
            components.path = "/" + id
        }
        return components.url ?? StrengthConfig.workoutURL
    }
}
