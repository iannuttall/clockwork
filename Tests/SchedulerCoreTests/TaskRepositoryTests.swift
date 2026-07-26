import Foundation
import Testing
@testable import SchedulerCore

struct TaskRepositoryTests {
    @Test func `saves updates finds and deletes tasks`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = TaskRepository(paths: SchedulerPaths(root: root))
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
        let paths = SchedulerPaths(root: root)
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
        let paths = SchedulerPaths(root: root)
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
}
