import Foundation
import Testing
@testable import ClockworkCore

struct TaskRepositoryTests {
    @Test func `migrates legacy scheduler data once`() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let legacy = parent.appendingPathComponent("Scheduler", isDirectory: true)
        let destinationRoot = parent.appendingPathComponent("Clockwork", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let task = ScheduledTask(
            name: "Nightly backup",
            commands: ["echo done"],
            schedule: .daily(hour: 23, minute: 30))
        _ = try TaskRepository(paths: ClockworkPaths(root: legacy)).save(task)

        let destination = ClockworkPaths(root: destinationRoot)
        #expect(try LegacySchedulerMigration.migrateDataIfNeeded(
            destination: destination,
            legacyRoot: legacy))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(FileManager.default.fileExists(atPath: destination.legacyMigrationMarker.path))
        #expect(try TaskRepository(paths: destination).list().map(\.name) == ["Nightly backup"])
        #expect(try !LegacySchedulerMigration.migrateDataIfNeeded(
            destination: destination,
            legacyRoot: legacy))
    }

    @Test func `saves updates finds and deletes tasks`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = TaskRepository(paths: ClockworkPaths(root: root))
        var task = ScheduledTask(
            name: "Update Codex",
            commands: ["codex update"],
            schedule: .interval(value: 6, unit: .hours))

        task = try repository.save(task)
        #expect(try repository.list().count == 1)
        #expect(try repository.find("Update Codex")?.id == task.id)

        task.isEnabled = false
        _ = try repository.save(task)
        #expect(try repository.find(task.id.uuidString)?.isEnabled == false)

        _ = try repository.delete(id: task.id)
        #expect(try repository.list().isEmpty)
    }

    @Test func `reads run result files`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ClockworkPaths(root: root)
        try paths.prepare()
        let id = UUID()
        let result = paths.resultDirectory(for: id)
        try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
        try Data("100\n".utf8).write(to: result.appendingPathComponent("started"))
        try Data("102\n".utf8).write(to: result.appendingPathComponent("finished"))
        try Data("0\n".utf8).write(to: result.appendingPathComponent("exit"))
        try Data("done\n".utf8).write(to: result.appendingPathComponent("stdout.log"))
        try TaskRunEvent.attention(
            title: "AMA inbox",
            message: "36 questions are waiting",
            nextStep: "pnpm ian ama answer --remote")
            .write(to: result.appendingPathComponent(TaskRunEvent.filename))

        let run = try #require(TaskRepository(paths: paths).result(for: id))
        #expect(run.succeeded)
        #expect(run.requiresAttention)
        #expect(run.summary == "Needs attention")
        #expect(run.event?.title == "AMA inbox")
        #expect(run.event?.nextStep == "pnpm ian ama answer --remote")
        #expect(run.standardOutput == "done\n")
    }

    @Test func `reads newest run history first`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ClockworkPaths(root: root)
        try paths.prepare()
        let id = UUID()
        let runs = paths.runsDirectory(for: id)

        for (runID, started, output) in [("older", 100, "first\n"), ("newer", 200, "second\n")] {
            let directory = runs.appendingPathComponent(runID)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("\(started)\n".utf8).write(to: directory.appendingPathComponent("started"))
            try Data("\(started + 2)\n".utf8).write(to: directory.appendingPathComponent("finished"))
            try Data("0\n".utf8).write(to: directory.appendingPathComponent("exit"))
            try Data(output.utf8).write(to: directory.appendingPathComponent("stdout.log"))
        }

        let history = TaskRepository(paths: paths).results(for: id)
        #expect(history.map(\.id) == ["newer", "older"])
        #expect(history.first?.standardOutput == "second\n")
        #expect(TaskRepository(paths: paths).results(for: id, limit: 1).count == 1)
    }

    @Test func `latest result follows pointer without loading output`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ClockworkPaths(root: root)
        try paths.prepare()
        let id = UUID()
        let runs = paths.runsDirectory(for: id)

        for (runID, started, output) in [("older", 100, "old output"), ("current", 200, "large output")] {
            let directory = runs.appendingPathComponent(runID)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("\(started)\n".utf8).write(to: directory.appendingPathComponent("started"))
            try Data("\(started + 2)\n".utf8).write(to: directory.appendingPathComponent("finished"))
            try Data("0\n".utf8).write(to: directory.appendingPathComponent("exit"))
            try Data(output.utf8).write(to: directory.appendingPathComponent("stdout.log"))
        }
        try Data("current\n".utf8).write(to: paths.resultDirectory(for: id).appendingPathComponent("latest"))

        let summary = try #require(TaskRepository(paths: paths).result(for: id, includeOutput: false))
        #expect(summary.id == "current")
        #expect(summary.standardOutput.isEmpty)

        let fullResult = try #require(TaskRepository(paths: paths).result(for: id))
        #expect(fullResult.standardOutput == "large output")
    }
}
