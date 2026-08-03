import Foundation

public struct ClockworkPaths: Sendable {
    public var root: URL
    public var launchAgentsDirectory: URL

    public init(root: URL, launchAgentsDirectory: URL? = nil) {
        self.root = root
        self.launchAgentsDirectory = launchAgentsDirectory ?? root.appendingPathComponent(
            "LaunchAgents",
            isDirectory: true)
    }

    public static var `default`: ClockworkPaths {
        if let override = ProcessInfo.processInfo.environment["CLOCKWORK_HOME"], !override.isEmpty {
            return ClockworkPaths(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ClockworkPaths(
            root: home.appendingPathComponent("Library/Application Support/Clockwork", isDirectory: true),
            launchAgentsDirectory: home.appendingPathComponent("Library/LaunchAgents", isDirectory: true))
    }

    public var tasksFile: URL {
        self.root.appendingPathComponent("tasks.json")
    }

    public var jobsDirectory: URL {
        self.root.appendingPathComponent("Jobs", isDirectory: true)
    }

    public var resultsDirectory: URL {
        self.root.appendingPathComponent("Results", isDirectory: true)
    }

    public var legacyMigrationMarker: URL {
        self.root.appendingPathComponent(".migrated-from-scheduler")
    }

    public func wrapper(for id: UUID) -> URL {
        self.jobsDirectory.appendingPathComponent("\(id.uuidString.lowercased()).sh")
    }

    public func resultDirectory(for id: UUID) -> URL {
        self.resultsDirectory.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    public func runsDirectory(for id: UUID) -> URL {
        self.resultDirectory(for: id).appendingPathComponent("runs", isDirectory: true)
    }

    public func launchAgent(for id: UUID) -> URL {
        self.launchAgentsDirectory.appendingPathComponent("\(LaunchAgentManager.label(for: id)).plist")
    }

    public func legacyLaunchAgent(for id: UUID) -> URL {
        self.launchAgentsDirectory.appendingPathComponent("\(LaunchAgentManager.legacyLabel(for: id)).plist")
    }

    public func prepare() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: self.root, withIntermediateDirectories: true)
        try manager.createDirectory(at: self.jobsDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: self.resultsDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: self.launchAgentsDirectory, withIntermediateDirectories: true)
    }
}
