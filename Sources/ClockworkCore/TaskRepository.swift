import Foundation

public struct TaskRepository: Sendable {
    public let paths: ClockworkPaths

    private struct RankedRun {
        var url: URL
        var id: String
        var started: Int
    }

    public init(paths: ClockworkPaths = .default) {
        self.paths = paths
    }

    public func list() throws -> [ScheduledTask] {
        try self.paths.prepare()
        guard FileManager.default.fileExists(atPath: self.paths.tasksFile.path) else { return [] }
        let data = try Data(contentsOf: self.paths.tasksFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ScheduledTask].self, from: data)
            .sorted { $0.createdAt < $1.createdAt }
    }

    @discardableResult
    public func save(_ task: ScheduledTask) throws -> ScheduledTask {
        var tasks = try self.list()
        var saved = task
        saved.updatedAt = Date()
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            saved.createdAt = tasks[index].createdAt
            tasks[index] = saved
        } else {
            tasks.append(saved)
        }
        try self.write(tasks)
        return saved
    }

    public func find(_ identifier: String) throws -> ScheduledTask? {
        let tasks = try self.list()
        if let id = UUID(uuidString: identifier) {
            return tasks.first { $0.id == id }
        }
        return tasks.first { $0.name.localizedCaseInsensitiveCompare(identifier) == .orderedSame }
    }

    @discardableResult
    public func delete(id: UUID) throws -> ScheduledTask? {
        var tasks = try self.list()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = tasks.remove(at: index)
        try self.write(tasks)
        return removed
    }

    public func result(for id: UUID, includeOutput: Bool = true) -> TaskRunResult? {
        let resultDirectory = self.paths.resultDirectory(for: id)
        let latestURL = resultDirectory.appendingPathComponent("latest")

        if let runID = try? String(contentsOf: latestURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !runID.isEmpty
        {
            let directory = self.paths.runsDirectory(for: id).appendingPathComponent(runID)
            if let result = self.readResult(at: directory, id: runID, includeOutput: includeOutput) {
                return result
            }
        }

        return self.results(for: id, limit: 1, includeOutput: includeOutput).first
    }

    public func results(for id: UUID, limit: Int = 50, includeOutput: Bool = true) -> [TaskRunResult] {
        guard limit > 0 else { return [] }

        let manager = FileManager.default
        let runsDirectory = self.paths.runsDirectory(for: id)
        let directories = (try? manager.contentsOfDirectory(
            at: runsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []

        // Rank using the tiny timestamp files before reading any logs. The old path
        // decoded stdout and stderr for every retained run and only then applied the
        // limit, so asking for the latest result could read 50 large logs.
        let ranked = directories.compactMap { directory -> RankedRun? in
            guard let started = Self.epoch(at: directory.appendingPathComponent("started")) else { return nil }
            return RankedRun(url: directory, id: directory.lastPathComponent, started: started)
        }.sorted {
            if $0.started != $1.started { return $0.started > $1.started }
            return $0.id > $1.id
        }

        let runs = ranked.prefix(limit).compactMap {
            self.readResult(at: $0.url, id: $0.id, includeOutput: includeOutput)
        }
        if !runs.isEmpty { return runs }

        let legacy = self.paths.resultDirectory(for: id)
        guard let result = self.readResult(at: legacy, id: "legacy", includeOutput: includeOutput) else { return [] }
        return [result]
    }

    private func readResult(at directory: URL, id: String, includeOutput: Bool) -> TaskRunResult? {
        guard let started = Self.epoch(at: directory.appendingPathComponent("started")) else { return nil }
        let finished = Self.epoch(at: directory.appendingPathComponent("finished"))
        let exitCode = Self.integer(at: directory.appendingPathComponent("exit"))
        let output = includeOutput
            ? (try? String(contentsOf: directory.appendingPathComponent("stdout.log"), encoding: .utf8)) ?? ""
            : ""
        let error = includeOutput
            ? (try? String(contentsOf: directory.appendingPathComponent("stderr.log"), encoding: .utf8)) ?? ""
            : ""
        let eventURL = directory.appendingPathComponent(TaskRunEvent.filename)
        let event = try? JSONDecoder().decode(TaskRunEvent.self, from: Data(contentsOf: eventURL))
        return TaskRunResult(
            id: id,
            startedAt: Date(timeIntervalSince1970: TimeInterval(started)),
            finishedAt: finished.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            exitCode: exitCode,
            standardOutput: output,
            standardError: error,
            event: event)
    }

    private func write(_ tasks: [ScheduledTask]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(tasks)
        try data.write(to: self.paths.tasksFile, options: .atomic)
    }

    private static func epoch(at url: URL) -> Int? {
        self.integer(at: url)
    }

    private static func integer(at url: URL) -> Int? {
        guard let value = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
