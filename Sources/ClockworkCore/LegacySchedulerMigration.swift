import Foundation

public enum LegacySchedulerMigration {
    /// Moves pre-release Scheduler data into Clockwork once. Launch-agent registration is
    /// repaired separately so a failed `launchctl` call can be retried on the next run.
    public static func migrateDataIfNeeded(
        destination: ClockworkPaths = .default,
        legacyRoot: URL? = nil) throws -> Bool
    {
        let manager = FileManager.default
        let source = legacyRoot ?? manager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Scheduler", isDirectory: true)

        guard source.standardizedFileURL != destination.root.standardizedFileURL,
              manager.fileExists(atPath: source.path),
              !manager.fileExists(atPath: destination.root.path)
        else { return false }

        try manager.createDirectory(
            at: destination.root.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try manager.moveItem(at: source, to: destination.root)
        try Data().write(to: destination.legacyMigrationMarker, options: .atomic)
        return true
    }
}
