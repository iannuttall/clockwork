import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum ClockworkError: LocalizedError {
    case invalidTask(String)
    case taskNotFound(String)
    case launchctl(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidTask(message), let .taskNotFound(message), let .launchctl(message): message
        }
    }
}

public struct LaunchAgentManager: Sendable {
    public let paths: ClockworkPaths

    public init(paths: ClockworkPaths = .default) {
        self.paths = paths
    }

    public static func label(for id: UUID) -> String {
        "is.ian.clockwork.task.\(id.uuidString.lowercased())"
    }

    public static func legacyLabel(for id: UUID) -> String {
        "com.iannuttall.scheduler.task.\(id.uuidString.lowercased())"
    }

    /// Completes the one-time Scheduler-to-Clockwork migration. The marker remains until
    /// every task has been registered, so an interrupted migration is safe to retry.
    public func repairLegacyRegistrationsIfNeeded(_ tasks: [ScheduledTask]) throws {
        guard FileManager.default.fileExists(atPath: self.paths.legacyMigrationMarker.path) else { return }

        for task in tasks {
            self.unload(label: Self.legacyLabel(for: task.id))
            try? FileManager.default.removeItem(at: self.paths.legacyLaunchAgent(for: task.id))
            try self.sync(task)
        }

        try FileManager.default.removeItem(at: self.paths.legacyMigrationMarker)
    }

    public func sync(_ task: ScheduledTask) throws {
        if let error = task.validationError { throw ClockworkError.invalidTask(error) }
        try self.paths.prepare()
        try self.writeWrapper(for: task)
        self.unload(task.id)
        let plistURL = self.paths.launchAgent(for: task.id)
        if task.isEnabled {
            try self.writePlist(for: task, to: plistURL)
            try self.runLaunchctl(["bootstrap", self.domain, plistURL.path])
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    public func remove(_ task: ScheduledTask) throws {
        self.unload(task.id)
        try? FileManager.default.removeItem(at: self.paths.launchAgent(for: task.id))
        try? FileManager.default.removeItem(at: self.paths.wrapper(for: task.id))
    }

    public func runNow(_ task: ScheduledTask) throws {
        try self.writeWrapper(for: task)
        let process = Process()
        process.executableURL = self.paths.wrapper(for: task.id)
        try process.run()
    }

    public func syncAll(_ tasks: [ScheduledTask]) throws {
        for task in tasks {
            try self.sync(task)
        }
    }

    private var domain: String {
        "gui/\(getuid())"
    }

    private func unload(_ id: UUID) {
        self.unload(label: Self.label(for: id))
    }

    private func unload(label: String) {
        try? self.runLaunchctl(["bootout", "\(self.domain)/\(label)"])
    }

    private func writePlist(for task: ScheduledTask, to url: URL) throws {
        var plist: [String: Any] = [
            "Label": Self.label(for: task.id),
            "ProgramArguments": [self.paths.wrapper(for: task.id).path],
            "RunAtLoad": false,
            "ProcessType": "Background",
        ]
        switch task.schedule {
        case let .interval(value, unit):
            plist["StartInterval"] = unit.seconds(for: value)
        case let .daily(hour, minute):
            plist["StartCalendarInterval"] = ["Hour": hour, "Minute": minute]
        case let .weekly(days, hour, minute):
            plist["StartCalendarInterval"] = days.map { ["Weekday": $0.rawValue, "Hour": hour, "Minute": minute] }
        }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    private func writeWrapper(for task: ScheduledTask) throws {
        let result = self.paths.resultDirectory(for: task.id)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        let commandText = task.commands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let workingDirectory = Self.expanded(task.workingDirectory)
        let shellBody = ["set -e\nset -o pipefail", workingDirectory.map { "cd \(Self.shellQuote($0))" }, commandText]
            .compactMap(\.self)
            .joined(separator: "\n")
        let script = """
        #!/bin/zsh
        result=\(Self.shellQuote(result.path))
        run_id="$(date +%s)-$$"
        run_dir="$result/runs/$run_id"
        mkdir -p "$run_dir"
        date +%s > "$run_dir/started"
        printf '%s\n' "$run_id" > "$result/latest.tmp"
        mv "$result/latest.tmp" "$result/latest"
        export \(TaskRunEvent.environmentKey)="$run_dir/\(TaskRunEvent.filename)"
        set +e
        /bin/zsh -lc \(Self.shellQuote(shellBody)) > "$run_dir/stdout.log" 2> "$run_dir/stderr.log"
        exit_code=$?
        printf '%s\n' "$exit_code" > "$run_dir/exit.tmp"
        mv "$run_dir/exit.tmp" "$run_dir/exit"
        date +%s > "$run_dir/finished.tmp"
        mv "$run_dir/finished.tmp" "$run_dir/finished"
        run_dirs=("$result/runs"/*(N/om))
        if (( ${#run_dirs} > 50 )); then
            rm -rf -- "${run_dirs[@]:50}"
        fi
        exit "$exit_code"
        """
        let url = self.paths.wrapper(for: task.id)
        try Data(script.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func runLaunchctl(_ arguments: [String]) throws {
        #if os(macOS)
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let message = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ClockworkError.launchctl(message.isEmpty ? "launchctl failed" : message)
        }
        #else
        _ = arguments
        #endif
    }

    private static func expanded(_ path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
        if path == "~" { return FileManager.default.homeDirectoryForCurrentUser.path }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(String(path.dropFirst(2)))
                .path
        }
        return path
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
