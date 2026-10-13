import Foundation

/// Stores the strength feature's data as JSON files in one directory (ISO-8601 dates, sorted keys, atomic writes).
///
/// A missing or corrupt file reads as an empty value and never crashes; in a list or dictionary file an element that cannot be
/// decoded is skipped and the readable ones are kept. All file access is serialised by a lock, so one instance can be shared.
public final class FileStrengthPersistence: @unchecked Sendable {
    /// The directory that holds the files.
    public let directory: URL

    private let lock = NSLock()

    private enum FileName {
        static let activeWorkout = "active-workout.json"
        static let templates = "templates.json"
        static let history = "history.json"
        static let customExercises = "custom-exercises.json"
        static let personalBests = "personal-bests.json"
    }

    /// Stores files in `directory` (created when needed).
    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Persistence inside the shared App Group container (`<container>/PulseStrength`); nil elsewhere than Apple platforms or without the group.
    public static func appGroup(identifier: String) -> FileStrengthPersistence? {
        #if canImport(Darwin)
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return nil }
        return FileStrengthPersistence(directory: container.appendingPathComponent("PulseStrength", isDirectory: true))
        #else
        return nil
        #endif
    }

    /// Persistence in a new, unique directory inside the system temporary directory (tests, previews).
    public static func temporary() -> FileStrengthPersistence {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PulseStrength-" + UUID().uuidString, isDirectory: true)
        return FileStrengthPersistence(directory: directory)
    }

    // MARK: Active workout

    /// The workout in progress, or nil when there is none or the file is unreadable.
    public func loadActiveWorkout() -> WorkoutState? {
        guard let data = read(FileName.activeWorkout) else { return nil }
        return try? StrengthJSON.makeDecoder().decode(WorkoutState.self, from: data)
    }

    /// Saves the workout in progress; nil deletes the file.
    public func saveActiveWorkout(_ state: WorkoutState?) throws {
        guard let state else {
            try remove(FileName.activeWorkout)
            return
        }
        try write(state, to: FileName.activeWorkout)
    }

    // MARK: Templates

    /// The saved workout templates (empty when none or unreadable).
    public func loadTemplates() -> [WorkoutTemplate] { readList(FileName.templates) }

    /// Replaces the saved workout templates.
    public func saveTemplates(_ templates: [WorkoutTemplate]) throws { try write(templates, to: FileName.templates) }

    // MARK: History

    /// The finished workouts, newest first (empty when none or unreadable).
    public func loadHistory() -> [CompletedWorkout] { readList(FileName.history) }

    /// Replaces the finished workouts (newest first).
    public func saveHistory(_ history: [CompletedWorkout]) throws { try write(history, to: FileName.history) }

    // MARK: Custom exercises

    /// The user's own exercises (empty when none or unreadable).
    public func loadCustomExercises() -> [Exercise] { readList(FileName.customExercises) }

    /// Replaces the user's own exercises.
    public func saveCustomExercises(_ exercises: [Exercise]) throws { try write(exercises, to: FileName.customExercises) }

    // MARK: Personal bests

    /// The personal bests by exercise id (empty when none or unreadable).
    public func loadPersonalBests() -> [String: PersonalBest] {
        guard let data = read(FileName.personalBests),
              let decoded = try? StrengthJSON.makeDecoder().decode([String: LossyElement<PersonalBest>].self, from: data)
        else { return [:] }
        return decoded.compactMapValues { $0.value }
    }

    /// Replaces the personal bests.
    public func savePersonalBests(_ bests: [String: PersonalBest]) throws { try write(bests, to: FileName.personalBests) }

    // MARK: File access

    private func url(_ name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    private func read(_ name: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return try? Data(contentsOf: url(name))
    }

    private func readList<Element: Decodable>(_ name: String) -> [Element] {
        guard let data = read(name),
              let decoded = try? StrengthJSON.makeDecoder().decode([LossyElement<Element>].self, from: data)
        else { return [] }
        return decoded.compactMap { $0.value }
    }

    private func write<Value: Encodable>(_ value: Value, to name: String) throws {
        let data = try StrengthJSON.makeEncoder().encode(value)
        lock.lock()
        defer { lock.unlock() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(name), options: .atomic)
    }

    private func remove(_ name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let target = url(name)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }
}

/// Decodes one element of a stored list or dictionary, yielding nil (instead of failing the whole file) when it is unreadable.
private struct LossyElement<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: Decoder) throws {
        value = try? Element(from: decoder)
    }
}
