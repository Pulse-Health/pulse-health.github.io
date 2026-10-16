import Foundation

// MARK: - Load issues and errors

/// A problem found while reading a data file. The data that could be read is still used; nothing is overwritten by the load itself.
public struct PersistenceIssue: Equatable, Hashable, Sendable, Identifiable {
    /// What was wrong with the file.
    public enum Kind: Equatable, Hashable, Sendable {
        /// The file exists but could not be read at all (damaged, wrong shape, not readable). Its content counts as empty.
        case unreadableFile
        /// A list or dictionary file was read, but this many of its elements could not be decoded and were left out.
        case skippedElements(Int)
        /// The data directory was written by a newer version of the app. It is read as far as possible and never written.
        case newerSchema
        /// A migration to the current data format failed. The directory is read as far as possible and never written.
        case migrationFailed
    }

    /// The file name inside the data directory (`schema.json` for the two schema kinds).
    public var fileName: String
    public var kind: Kind
    /// The copy of the original bytes made before anything was rewritten (`<name>.corrupt-<yyyyMMdd-HHmmss>.json`, UTC); nil when
    /// there is none (the schema kinds, or a copy that could not be made).
    public var backupFileName: String?

    /// One issue per file, so the file name identifies it.
    public var id: String { fileName }

    public init(fileName: String, kind: Kind, backupFileName: String? = nil) {
        self.fileName = fileName
        self.kind = kind
        self.backupFileName = backupFileName
    }
}

/// Why `FileStrengthPersistence` refuses to write.
public enum PersistenceError: Error, Equatable, Sendable, LocalizedError {
    /// The data directory has data format `found`, newer than the `supported` one of this version of the app.
    case newerSchema(found: Int, supported: Int)
    /// A migration of the data directory to format `toVersion` failed; the directory may be partly migrated.
    case migrationFailed(toVersion: Int)
    /// The file could not be read when it was loaded and its original bytes still cannot be copied, so replacing it would destroy
    /// them. The write is refused until the copy works or the user acknowledges the load issues.
    case originalNotPreserved(fileName: String)

    public var errorDescription: String? {
        switch self {
        case let .newerSchema(found, supported):
            return String(
                format: "Your data was saved by a newer version of the app (data format %d; this version understands %d), so it was left unchanged. Update the app to continue.",
                found, supported
            )
        case let .migrationFailed(toVersion):
            return String(
                format: "Your data could not be updated to data format %d, so it was left unchanged.",
                toVersion
            )
        case let .originalNotPreserved(fileName):
            return String(
                format: "The damaged file %@ could not be copied to a safe place first, so it was left unchanged.",
                fileName
            )
        }
    }
}

/// One step of the data format: turns a data directory of version N into one of version N + 1.
///
/// The step runs while the persistence lock is held, so it must work on the files directly and must not call back into the
/// persistence. It should write atomically and be safe to run twice, because a step that fails is run again from its start.
public struct PersistenceMigration: Sendable {
    /// Migrates the files in the given directory.
    public var run: @Sendable (URL) throws -> Void

    public init(_ run: @escaping @Sendable (URL) throws -> Void) {
        self.run = run
    }

    /// The migrations this version of the app ships, in order: the first upgrades version 1 to 2, and so on. Version 1 is the
    /// current format, so there are none yet.
    public static let shipped: [PersistenceMigration] = []
}

// MARK: - Persistence

/// Stores the strength feature's data as JSON files in one directory (ISO-8601 dates, sorted keys, atomic writes).
///
/// Reading never crashes and never changes what is on disk. A missing file reads as an empty value. When a file cannot be decoded
/// completely, the original bytes are first copied to `<name>.corrupt-<yyyyMMdd-HHmmss>.json` (UTC; at most three copies per file,
/// the oldest is deleted; a copy with identical bytes is reused), every element that did decode is kept and the problem is recorded
/// as a `PersistenceIssue` (`loadIssues`). The damaged file itself is only replaced by the next legitimate save.
///
/// `schema.json` (`{"version": 1}`) holds the data format version. A directory without it is version 1, as is every existing
/// install. Migrations run when the directory is first used; a directory written by a newer app version is never written.
///
/// Each file is written atomically; writing several files (see `StrengthDataModel`) is not transactional.
/// All file access is serialised by a lock, so one instance can be shared.
public final class FileStrengthPersistence: @unchecked Sendable {
    /// The directory that holds the files.
    public let directory: URL
    /// The data format version this app writes: one more than the number of migrations.
    public let currentSchemaVersion: Int

    /// The data files, by name. Backups (`*.corrupt-*.json`) and `schema.json` are not data files.
    static let dataFileNames = [
        FileName.activeWorkout, FileName.templates, FileName.history, FileName.customExercises,
        FileName.personalBests, FileName.bodyWeights, FileName.weighInPreferences, FileName.preferences,
        FileName.acknowledgedCommands,
    ]

    /// The files whose content is the user's data: a save of one of them first makes sure the original of a damaged file is copied.
    /// The workout in progress and the acknowledged command ids are transient and exempt.
    static let protectedFileNames = [
        FileName.templates, FileName.history, FileName.customExercises,
        FileName.personalBests, FileName.bodyWeights, FileName.weighInPreferences, FileName.preferences,
    ]

    /// At most this many `.corrupt-` copies are kept per file.
    static let maximumBackupsPerFile = 3

    enum FileName {
        static let activeWorkout = "active-workout.json"
        static let templates = "templates.json"
        static let history = "history.json"
        static let customExercises = "custom-exercises.json"
        static let personalBests = "personal-bests.json"
        static let bodyWeights = "body-weights.json"
        static let weighInPreferences = "weigh-in-preferences.json"
        static let preferences = "preferences.json"
        static let acknowledgedCommands = "acknowledged-commands.json"
        static let schema = "schema.json"
    }

    private enum SchemaState {
        case ready(version: Int)
        case newer(found: Int)
        case failed(toVersion: Int)
    }

    private struct SchemaFile: Codable {
        var version: Int
    }

    private let lock = NSLock()
    private let migrations: [PersistenceMigration]
    private let clock: @Sendable () -> Date
    private var schemaState: SchemaState?
    /// True while `schema.json` is missing or was unreadable: the next write stamps it.
    private var schemaNeedsStamp = false
    private var issues: [String: PersistenceIssue] = [:]

    /// Stores files in `directory` (created when needed). `migrations` and `clock` are injectable for tests.
    public init(
        directory: URL,
        migrations: [PersistenceMigration] = PersistenceMigration.shipped,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.migrations = migrations
        self.currentSchemaVersion = migrations.count + 1
        self.clock = clock
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

    // MARK: Schema and issues

    /// The data format version of the directory: 1 without `schema.json`, the current version once migrations ran, or the newer
    /// version a newer app wrote.
    public var schemaVersion: Int {
        lock.lock()
        defer { lock.unlock() }
        switch prepareLocked() {
        case let .ready(version): return version
        case let .newer(found): return found
        case let .failed(toVersion): return toVersion - 1
        }
    }

    /// False while a write would be refused: the directory was written by a newer app version, or a migration failed.
    public var canWrite: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .ready = prepareLocked() { return true }
        return false
    }

    /// Looks at `schema.json` again (and runs the migrations that are due), as after another process changed the directory.
    public func rescanSchema() {
        lock.lock()
        defer { lock.unlock() }
        schemaState = nil
        _ = prepareLocked()
    }

    /// The issues found by the loads so far, one per file at most (a clean load of a file clears its entry), ordered by file name.
    /// After a full load of everything (`StrengthDataModel` does that) these are the issues of that load.
    public var loadIssues: [PersistenceIssue] {
        lock.lock()
        defer { lock.unlock() }
        return issues.values.sorted { $0.fileName < $1.fileName }
    }

    /// Forgets the recorded issues (the user acknowledged them). The backups stay on disk.
    public func clearLoadIssues() {
        lock.lock()
        defer { lock.unlock() }
        issues = [:]
    }

    /// True when at least one data file exists (a backup of a damaged file or `schema.json` alone does not count).
    public var hasDataFiles: Bool {
        lock.lock()
        defer { lock.unlock() }
        return Self.dataFileNames.contains { FileManager.default.fileExists(atPath: url($0).path) }
    }

    /// True when a file of the user's own data exists, `preferences.json` excepted (the workout in progress and the acknowledged
    /// command ids are transient). A directory like that was written by a build that had no preferences file yet.
    var hasUserDataFilesBesidesPreferences: Bool {
        lock.lock()
        defer { lock.unlock() }
        return Self.protectedFileNames.contains {
            $0 != FileName.preferences && FileManager.default.fileExists(atPath: url($0).path)
        }
    }

    /// True when `personal-bests.json` exists.
    public var hasPersonalBestsFile: Bool {
        lock.lock()
        defer { lock.unlock() }
        return FileManager.default.fileExists(atPath: url(FileName.personalBests).path)
    }

    /// True when `preferences.json` exists (readable or not).
    public var hasPreferencesFile: Bool {
        lock.lock()
        defer { lock.unlock() }
        return FileManager.default.fileExists(atPath: url(FileName.preferences).path)
    }

    // MARK: Active workout

    /// The workout in progress, or nil when there is none or the file is unreadable (an unreadable file is an issue).
    public func loadActiveWorkout() -> WorkoutState? {
        loadValue(FileName.activeWorkout, empty: nil as WorkoutState?) { data in
            guard let state = try? StrengthJSON.makeDecoder().decode(WorkoutState.self, from: data) else { return nil }
            return (state, 0)
        }
    }

    /// Saves the workout in progress; nil deletes the file.
    public func saveActiveWorkout(_ state: WorkoutState?) throws {
        guard let state else {
            try remove(FileName.activeWorkout)
            return
        }
        try write(state, to: FileName.activeWorkout)
    }

    // MARK: Acknowledged commands

    /// The ids of the Watch commands the phone dealt with, oldest first: at most `SyncReconciler.acknowledgedMemory` of them (empty
    /// when there is no file or it is unreadable). They let a relaunched phone drop a command the Watch redelivers and acknowledge
    /// the commands it applied before it was relaunched.
    public func loadAcknowledgedCommands() -> [UUID] {
        let ids: [UUID] = loadList(FileName.acknowledgedCommands)
        return Array(ids.suffix(SyncReconciler.acknowledgedMemory))
    }

    /// Replaces the remembered command ids; only the most recent `SyncReconciler.acknowledgedMemory` are kept (about 10 KB).
    public func saveAcknowledgedCommands(_ ids: [UUID]) throws {
        try write(Array(ids.suffix(SyncReconciler.acknowledgedMemory)), to: FileName.acknowledgedCommands)
    }

    // MARK: Templates

    /// The saved workout templates, in the order the user arranged them (empty when none or unreadable).
    public func loadTemplates() -> [WorkoutTemplate] { loadList(FileName.templates) }

    /// Replaces the saved workout templates. The array order is the user's order.
    public func saveTemplates(_ templates: [WorkoutTemplate]) throws { try write(templates, to: FileName.templates) }

    // MARK: History

    /// The finished workouts, newest first (empty when none or unreadable).
    public func loadHistory() -> [CompletedWorkout] { loadList(FileName.history) }

    /// Replaces the finished workouts (newest first).
    public func saveHistory(_ history: [CompletedWorkout]) throws { try write(history, to: FileName.history) }

    // MARK: Custom exercises

    /// The user's own exercises (empty when none or unreadable).
    public func loadCustomExercises() -> [Exercise] { loadList(FileName.customExercises) }

    /// Replaces the user's own exercises.
    public func saveCustomExercises(_ exercises: [Exercise]) throws { try write(exercises, to: FileName.customExercises) }

    // MARK: Personal bests

    /// The personal bests by exercise id (empty when none or unreadable).
    public func loadPersonalBests() -> [String: PersonalBest] { loadDictionary(FileName.personalBests) }

    /// Replaces the personal bests.
    public func savePersonalBests(_ bests: [String: PersonalBest]) throws { try write(bests, to: FileName.personalBests) }

    // MARK: Body weight

    /// The weigh-ins, newest first (empty when none or unreadable).
    public func loadBodyWeights() -> [BodyWeightEntry] { loadList(FileName.bodyWeights) }

    /// Replaces the weigh-ins.
    public func saveBodyWeights(_ entries: [BodyWeightEntry]) throws { try write(entries, to: FileName.bodyWeights) }

    /// The weigh-in reminder preferences (the defaults, with the reminder off, when none or unreadable).
    public func loadWeighInPreferences() -> WeighInPreferences {
        loadValue(FileName.weighInPreferences, empty: WeighInPreferences()) { data in
            guard let preferences = try? StrengthJSON.makeDecoder().decode(WeighInPreferences.self, from: data) else { return nil }
            return (preferences, 0)
        }
    }

    /// Replaces the weigh-in reminder preferences.
    public func saveWeighInPreferences(_ preferences: WeighInPreferences) throws {
        try write(preferences, to: FileName.weighInPreferences)
    }

    // MARK: Preferences

    /// The user's workout preferences, or nil when there is no file or it is unreadable (an unreadable file is an issue). Fields that
    /// the file lacks read as their defaults, so a file written by another version loads.
    public func loadPreferences() -> StrengthPreferences? {
        loadValue(FileName.preferences, empty: nil as StrengthPreferences?) { data in
            guard let preferences = try? StrengthJSON.makeDecoder().decode(StrengthPreferences.self, from: data) else { return nil }
            return (preferences, 0)
        }
    }

    /// Replaces the user's workout preferences.
    public func savePreferences(_ preferences: StrengthPreferences) throws {
        try write(preferences, to: FileName.preferences)
    }

    // MARK: File access

    private func url(_ name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    /// Reads one file: `decode` returns the value and the number of elements it had to leave out, or nil when the file as a whole
    /// cannot be decoded. A damaged file is backed up and recorded as an issue; a missing file reads as `empty` without an issue.
    func loadValue<Value>(_ name: String, empty: Value, decode: (Data) -> (value: Value, skipped: Int)?) -> Value {
        lock.lock()
        defer { lock.unlock() }
        _ = prepareLocked()
        guard FileManager.default.fileExists(atPath: url(name).path) else {
            issues[name] = nil
            return empty
        }
        guard let data = try? Data(contentsOf: url(name)) else {
            issues[name] = PersistenceIssue(fileName: name, kind: .unreadableFile)
            return empty
        }
        guard let decoded = decode(data) else {
            issues[name] = PersistenceIssue(fileName: name, kind: .unreadableFile, backupFileName: backUpLocked(name, data: data))
            return empty
        }
        if decoded.skipped > 0 {
            issues[name] = PersistenceIssue(
                fileName: name, kind: .skippedElements(decoded.skipped), backupFileName: backUpLocked(name, data: data)
            )
        } else {
            issues[name] = nil
        }
        return decoded.value
    }

    /// A list file; elements that cannot be decoded are skipped and counted.
    func loadList<Element: Decodable>(_ name: String) -> [Element] {
        loadValue(name, empty: []) { data in
            guard let decoded = try? StrengthJSON.makeDecoder().decode([LossyElement<Element>].self, from: data) else { return nil }
            let values = decoded.compactMap { $0.value }
            return (values, decoded.count - values.count)
        }
    }

    /// A dictionary file; entries that cannot be decoded are skipped and counted.
    func loadDictionary<Element: Decodable>(_ name: String) -> [String: Element] {
        loadValue(name, empty: [:]) { data in
            guard let decoded = try? StrengthJSON.makeDecoder().decode([String: LossyElement<Element>].self, from: data) else { return nil }
            let values = decoded.compactMapValues { $0.value }
            return (values, decoded.count - values.count)
        }
    }

    func write<Value: Encodable>(_ value: Value, to name: String) throws {
        let data = try StrengthJSON.makeEncoder().encode(value)
        lock.lock()
        defer { lock.unlock() }
        try requireWritableLocked()
        try preserveOriginalLocked(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try stampSchemaLocked()
        try data.write(to: url(name), options: .atomic)
    }

    /// Makes sure the original of a damaged file is copied before the file is replaced. A file that could not be read or copied when
    /// it was loaded gets another try here; when that fails too, nothing is replaced. Acknowledging the issues lifts the check.
    private func preserveOriginalLocked(_ name: String) throws {
        guard Self.protectedFileNames.contains(name),
              let issue = issues[name], issue.backupFileName == nil,
              FileManager.default.fileExists(atPath: url(name).path)
        else { return }
        guard let original = try? Data(contentsOf: url(name)), let backup = backUpLocked(name, data: original) else {
            throw PersistenceError.originalNotPreserved(fileName: name)
        }
        issues[name]?.backupFileName = backup
    }

    func remove(_ name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireWritableLocked()
        let target = url(name)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    // MARK: Reset

    /// Removes every data file: the workout in progress, the templates, the history, the custom exercises, the personal bests, the
    /// weigh-ins, the reminder preferences, the workout preferences and the remembered command ids. `schema.json` stays, and so do the copies of damaged
    /// files (`<name>.corrupt-<timestamp>.json`) and the pre-migration folders.
    ///
    /// Refused like a write (`PersistenceError.newerSchema` / `.migrationFailed`), and also when the original of a damaged file
    /// cannot be copied first (`.originalNotPreserved`, see `write`); nothing is removed in that case. Otherwise every file is
    /// attempted, even after one fails to go; the first such error is thrown at the end.
    public func deleteAll() throws {
        try deleteAll(removing: { try FileManager.default.removeItem(at: $0) })
    }

    /// `deleteAll()` with the removal of one file passed in, so a failing removal can be tested.
    func deleteAll(removing remove: (URL) throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireWritableLocked()
        let manager = FileManager.default
        for name in Self.protectedFileNames where manager.fileExists(atPath: url(name).path) {
            try preserveOriginalLocked(name)
        }
        var firstError: Error?
        for name in Self.dataFileNames where manager.fileExists(atPath: url(name).path) {
            do {
                try remove(url(name))
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }

    // MARK: Schema (all called with the lock held)

    private func requireWritableLocked() throws {
        switch prepareLocked() {
        case .ready: return
        case let .newer(found): throw PersistenceError.newerSchema(found: found, supported: currentSchemaVersion)
        case let .failed(toVersion): throw PersistenceError.migrationFailed(toVersion: toVersion)
        }
    }

    /// The state of the directory's data format, worked out once: reads `schema.json`, records the schema issues and runs the
    /// migrations that are due.
    private func prepareLocked() -> SchemaState {
        if let schemaState { return schemaState }
        let state = evaluateSchemaLocked()
        schemaState = state
        return state
    }

    private func evaluateSchemaLocked() -> SchemaState {
        issues[FileName.schema] = nil
        schemaNeedsStamp = false
        let manager = FileManager.default
        var version: Int
        if !manager.fileExists(atPath: url(FileName.schema).path) {
            // A directory without a schema file is version 1 (every install so far); an empty one has nothing to migrate.
            let hasData = Self.dataFileNames.contains { manager.fileExists(atPath: url($0).path) }
            version = hasData ? 1 : currentSchemaVersion
            schemaNeedsStamp = true
        } else if let data = try? Data(contentsOf: url(FileName.schema)),
                  let file = try? JSONDecoder().decode(SchemaFile.self, from: data), file.version >= 1 {
            version = file.version
        } else {
            let backup = (try? Data(contentsOf: url(FileName.schema))).flatMap { backUpLocked(FileName.schema, data: $0) }
            issues[FileName.schema] = PersistenceIssue(fileName: FileName.schema, kind: .unreadableFile, backupFileName: backup)
            version = 1
            schemaNeedsStamp = true
        }

        if version > currentSchemaVersion {
            issues[FileName.schema] = PersistenceIssue(fileName: FileName.schema, kind: .newerSchema)
            return .newer(found: version)
        }
        if version < currentSchemaVersion {
            preserveBeforeMigrationLocked(from: version)
            while version < currentSchemaVersion {
                do {
                    try migrations[version - 1].run(directory)
                    try writeSchemaLocked(version + 1)
                    schemaNeedsStamp = false
                } catch {
                    issues[FileName.schema] = PersistenceIssue(fileName: FileName.schema, kind: .migrationFailed)
                    return .failed(toVersion: version + 1)
                }
                version += 1
            }
        }
        return .ready(version: version)
    }

    private func writeSchemaLocked(_ version: Int) throws {
        let data = try StrengthJSON.makeEncoder().encode(SchemaFile(version: version))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(FileName.schema), options: .atomic)
    }

    /// Writes `schema.json` the first time a file is written to a directory that has none (or whose schema file was unreadable).
    private func stampSchemaLocked() throws {
        guard case let .ready(version) = prepareLocked(),
              schemaNeedsStamp || !FileManager.default.fileExists(atPath: url(FileName.schema).path)
        else { return }
        try writeSchemaLocked(version)
        schemaNeedsStamp = false
    }

    /// Copies the data files to `schema-v<version>-backup/` before the first migration step, so a step that goes wrong cannot
    /// destroy the only copy. An existing copy is kept (it is the state before the first attempt).
    private func preserveBeforeMigrationLocked(from version: Int) {
        let manager = FileManager.default
        let folder = directory.appendingPathComponent("schema-v\(version)-backup", isDirectory: true)
        guard !manager.fileExists(atPath: folder.path) else { return }
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in Self.dataFileNames where manager.fileExists(atPath: url(name).path) {
                try manager.copyItem(at: url(name), to: folder.appendingPathComponent(name))
            }
        } catch {
            // Without the copy the migration still runs: the data files stay the source and the steps are atomic per file.
            try? manager.removeItem(at: folder)
        }
    }

    // MARK: Backups of damaged files (lock held)

    /// Keeps the original bytes of a damaged file as `<name>.corrupt-<timestamp>.json` and returns that file name; nil when the copy
    /// cannot be written. A copy with the same bytes is reused, and only the newest `maximumBackupsPerFile` copies are kept.
    private func backUpLocked(_ name: String, data: Data) -> String? {
        let manager = FileManager.default
        let base = String(name.dropLast(".json".count))
        let prefix = base + ".corrupt-"
        let existing = ((try? manager.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }
            .sorted()
        for candidate in existing where (try? Data(contentsOf: url(candidate))) == data {
            return candidate
        }

        var moment = clock()
        var fileName = prefix + Self.timestamp(moment) + ".json"
        var attempts = 0
        while manager.fileExists(atPath: url(fileName).path), attempts < 1_000 {
            moment = moment.addingTimeInterval(1)
            fileName = prefix + Self.timestamp(moment) + ".json"
            attempts += 1
        }
        do {
            try data.write(to: url(fileName), options: .atomic)
        } catch {
            return nil
        }
        var surplus = existing.count + 1 - Self.maximumBackupsPerFile
        for old in existing where surplus > 0 {
            try? manager.removeItem(at: url(old))
            surplus -= 1
        }
        return fileName
    }

    /// `yyyyMMdd-HHmmss` in UTC, built from calendar components (no formatter, no locale).
    private static func timestamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02d-%02d%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }
}

/// Decodes one element of a stored list or dictionary, yielding nil (instead of failing the whole file) when it is unreadable.
private struct LossyElement<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: Decoder) throws {
        value = try? Element(from: decoder)
    }
}
