import Foundation

/// Where the app leaves the `WidgetSnapshot` for the widget extension, the controls and the Watch widgets.
///
/// One JSON file `widget-snapshot.json` next to the strength data, in the App Group container (`<container>/PulseStrength`) on the
/// iPhone; the Watch app writes the copy it receives from the phone into its own group container. Writes are atomic.
public enum WidgetSnapshotStore {
    public static let fileName = "widget-snapshot.json"

    /// The directory of the App Group container that holds the files, nil when the process is not entitled to the group.
    public static func directory(groupID: String = StrengthConfig.appGroupID) -> URL? {
        #if canImport(Darwin)
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return nil }
        return container.appendingPathComponent("PulseStrength", isDirectory: true)
        #else
        return nil
        #endif
    }

    /// The stored snapshot; nil when there is none, it is unreadable or it comes from a newer schema.
    public static func load(directory: URL? = WidgetSnapshotStore.directory()) -> WidgetSnapshot? {
        guard let directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              let snapshot = try? StrengthJSON.makeDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.schemaVersion <= WidgetSnapshot.currentSchemaVersion
        else { return nil }
        return snapshot
    }

    /// Writes the snapshot atomically (creates the directory when needed).
    public static func save(_ snapshot: WidgetSnapshot, directory: URL? = WidgetSnapshotStore.directory()) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try StrengthJSON.makeEncoder().encode(snapshot)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }

    /// What a widget timeline provider shows: the stored snapshot, or - when it was written on an earlier day of its own time zone, so
    /// "3 days ago" and the week strip would be out of date - one rebuilt from the strength data in the same directory. Nil without any data.
    public static func loadForDisplay(now: Date = Date(), directory: URL? = WidgetSnapshotStore.directory()) -> WidgetSnapshot? {
        guard let directory else { return nil }
        let stored = load(directory: directory)
        if let stored {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: stored.timeZoneID) ?? .current
            if calendar.isDate(stored.generatedAt, inSameDayAs: now) { return stored }
        }
        let persistence = FileStrengthPersistence(directory: directory)
        let data = StrengthData(
            templates: persistence.loadTemplates(),
            history: persistence.loadHistory(),
            customExercises: persistence.loadCustomExercises(),
            personalBests: persistence.loadPersonalBests()
        )
        guard stored != nil || !data.isEmpty else { return nil }
        var context = WidgetContext(weeklyGoal: stored?.week.goal ?? WidgetContext.defaultWeeklyGoal)
        context.bodyweightKg = stored?.strengthRatio?.bodyweightKg
        context.readiness = stored?.readiness
        context.partners = stored?.partners ?? []
        context.active = stored?.active
        if let identifier = stored?.timeZoneID { context.timeZoneID = identifier }
        return WidgetSnapshotBuilder.build(data: data, context: context, now: now)
    }
}
