import Foundation
import Testing
@testable import SchedulerCore

struct ScheduleTests {
    @Test func `interval summary is human readable`() {
        #expect(TaskSchedule.interval(value: 6, unit: .hours).summary == "Every 6 hours")
        #expect(TaskSchedule.interval(value: 1, unit: .minutes).summary == "Every 1 minute")
    }

    @Test func `daily and weekly summaries avoid cron syntax`() {
        #expect(TaskSchedule.daily(hour: 9, minute: 5).summary == "Every day at 09:05")
        #expect(TaskSchedule.weekly(days: [.monday, .friday], hour: 17, minute: 30).summary == "Mon, Fri at 17:30")
    }

    @Test func `interval next run uses the chosen unit`() {
        let now = Date(timeIntervalSince1970: 1000)
        let next = TaskSchedule.interval(value: 6, unit: .hours).nextRun(after: now)
        #expect(next == Date(timeIntervalSince1970: 22600))
    }

    @Test func `task validation requires A name command and schedule`() {
        let task = ScheduledTask(name: "", commands: [], schedule: .interval(value: 0, unit: .hours))
        #expect(task.validationError == "Give the task a name.")
    }

    @Test func `task round trips through JSON`() throws {
        let task = ScheduledTask(
            name: "Update Codex",
            commands: ["codex update"],
            schedule: .interval(value: 6, unit: .hours))
        let data = try JSONEncoder().encode(task)
        #expect(try JSONDecoder().decode(ScheduledTask.self, from: data) == task)
    }
}
