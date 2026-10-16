import Foundation

/// A command a widget, control or Watch widget asked for from a process that does not own the workout.
public struct PendingWidgetCommand: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var action: WorkoutAction
    public var origin: ActionOrigin
    public var issuedAt: Date

    public init(id: UUID = UUID(), action: WorkoutAction, origin: ActionOrigin = .liveActivity, issuedAt: Date = Date()) {
        self.id = id
        self.action = action
        self.origin = origin
        self.issuedAt = issuedAt
    }
}

/// The hand-off between the widget extension (which may run an App Intent in its own process) and the app (which owns the workout).
///
/// The extension appends; the app drains at launch, when it becomes active and on the Darwin notification
/// `StrengthConfig.commandInboxNotification`. The file is `pending-commands.json` in the App Group directory; every access holds an
/// exclusive `flock` on a sidecar lock file, so two processes cannot lose each other's entries. At most `capacity` commands are
/// kept (the oldest are dropped), and a command older than `maximumAge` is not returned.
public final class WidgetCommandInbox: @unchecked Sendable {
    public static let fileName = "pending-commands.json"
    public static let capacity = 64
    public static let maximumAge: TimeInterval = 600

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The inbox of the App Group container; nil when the process is not entitled to the group.
    public static func shared() -> WidgetCommandInbox? {
        WidgetSnapshotStore.directory().map { WidgetCommandInbox(directory: $0) }
    }

    /// Adds a command at the end.
    public func append(_ command: PendingWidgetCommand) throws {
        try locked {
            var commands = readAll()
            commands.append(command)
            if commands.count > Self.capacity { commands.removeFirst(commands.count - Self.capacity) }
            try writeAll(commands)
        }
    }

    /// Returns the commands that are not too old, oldest first, and empties the inbox.
    @discardableResult
    public func drain(now: Date = Date()) throws -> [PendingWidgetCommand] {
        try locked {
            let commands = readAll()
            if !commands.isEmpty { try writeAll([]) }
            return commands.filter { now.timeIntervalSince($0.issuedAt) <= Self.maximumAge }
        }
    }

    /// The pending commands without removing them (tests, diagnostics).
    public func peek() -> [PendingWidgetCommand] {
        (try? locked { readAll() }) ?? []
    }

    // MARK: Private

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    private func readAll() -> [PendingWidgetCommand] {
        guard let data = try? Data(contentsOf: fileURL),
              let commands = try? StrengthJSON.makeDecoder().decode([PendingWidgetCommand].self, from: data)
        else { return [] }
        return commands
    }

    private func writeAll(_ commands: [PendingWidgetCommand]) throws {
        let data = try StrengthJSON.makeEncoder().encode(commands)
        try data.write(to: fileURL, options: .atomic)
    }

    private func locked<Result>(_ body: () throws -> Result) throws -> Result {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockPath = directory.appendingPathComponent(Self.fileName + ".lock").path
        let descriptor = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}
