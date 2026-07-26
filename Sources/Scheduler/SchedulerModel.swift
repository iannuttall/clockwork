import Foundation
import Observation
import SchedulerCore

enum ScheduleKind: String, CaseIterable, Identifiable {
    case interval
    case daily
    case weekly

    var id: String {
        self.rawValue
    }

    var label: String {
        switch self {
        case .interval: "Every…"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }
}

struct TaskDraft: Equatable {
    var id: UUID?
    var name = ""
    var commandsText = ""
    var workingDirectory = ""
    var isEnabled = true
    var scheduleKind = ScheduleKind.interval
    var intervalValue = 6
    var intervalUnit = IntervalUnit.hours
    var hour = 9
    var minute = 0
    var weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    init() {}

    init(task: ScheduledTask) {
        self.id = task.id
        self.name = task.name
        self.commandsText = task.commands.joined(separator: "\n")
        self.workingDirectory = task.workingDirectory ?? ""
        self.isEnabled = task.isEnabled
        switch task.schedule {
        case let .interval(value, unit):
            self.scheduleKind = .interval
            self.intervalValue = value
            self.intervalUnit = unit
        case let .daily(hour, minute):
            self.scheduleKind = .daily
            self.hour = hour
            self.minute = minute
        case let .weekly(days, hour, minute):
            self.scheduleKind = .weekly
            self.weekdays = Set(days)
            self.hour = hour
            self.minute = minute
        }
    }

    var schedule: TaskSchedule {
        switch self.scheduleKind {
        case .interval: .interval(value: self.intervalValue, unit: self.intervalUnit)
        case .daily: .daily(hour: self.hour, minute: self.minute)
        case .weekly: .weekly(days: Array(self.weekdays), hour: self.hour, minute: self.minute)
        }
    }

    var commands: [String] {
        self.commandsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var validationError: String? {
        self.task().validationError
    }

    func task(existing: ScheduledTask? = nil) -> ScheduledTask {
        ScheduledTask(
            id: self.id ?? existing?.id ?? UUID(),
            name: self.name.trimmingCharacters(in: .whitespacesAndNewlines),
            commands: self.commands,
            workingDirectory: self.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            schedule: self.schedule,
            isEnabled: self.isEnabled,
            createdAt: existing?.createdAt ?? Date())
    }
}

@MainActor
@Observable
final class SchedulerModel {
    private let repository: TaskRepository
    private let launchAgents: LaunchAgentManager
    @ObservationIgnored private let defaults: UserDefaults
    private var attentionRevision = 0

    var snapshots: [TaskSnapshot] = []
    var runHistory: [UUID: [TaskRunResult]] = [:]
    var selectedTaskID: UUID?
    var draft: TaskDraft?
    var errorMessage: String?
    var notice: String?

    init(
        repository: TaskRepository = TaskRepository(),
        launchAgents: LaunchAgentManager = LaunchAgentManager(),
        defaults: UserDefaults = .standard)
    {
        self.repository = repository
        self.launchAgents = launchAgents
        self.defaults = defaults
        self.refresh()
    }

    var enabledCount: Int {
        self.snapshots.count { $0.task.isEnabled }
    }

    func refresh() {
        do {
            let tasks = try self.repository.list()
            let histories = Dictionary(uniqueKeysWithValues: tasks.map { task in
                (task.id, self.repository.results(for: task.id))
            })
            self.runHistory = histories
            self.snapshots = tasks.map { TaskSnapshot(task: $0, lastRun: histories[$0.id]?.first) }
            if let selectedTaskID = self.selectedTaskID, !tasks.contains(where: { $0.id == selectedTaskID }) {
                self.selectedTaskID = nil
                self.draft = nil
            }
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func runs(for id: UUID) -> [TaskRunResult] {
        self.runHistory[id] ?? []
    }

    func beginAdding() {
        self.selectedTaskID = nil
        self.draft = TaskDraft()
        self.notice = nil
    }

    func beginEditing(_ id: UUID) {
        guard let task = self.snapshots.first(where: { $0.id == id })?.task else { return }
        self.acknowledgeAttention(for: id)
        self.selectedTaskID = id
        self.draft = TaskDraft(task: task)
        self.notice = nil
    }

    func cancelEditing() {
        self.draft = nil
        self.selectedTaskID = nil
    }

    func saveDraft() {
        guard let draft = self.draft else { return }
        if let validationError = draft.validationError {
            self.errorMessage = validationError
            return
        }
        do {
            let existing = self.snapshots.first(where: { $0.id == draft.id })?.task
            let task = try self.repository.save(draft.task(existing: existing))
            try self.launchAgents.sync(task)
            self.selectedTaskID = task.id
            self.draft = TaskDraft(task: task)
            self.notice = "Saved"
            self.refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard var task = self.snapshots.first(where: { $0.id == id })?.task else { return }
        task.isEnabled = enabled
        do {
            task = try self.repository.save(task)
            try self.launchAgents.sync(task)
            if self.draft?.id == id { self.draft?.isEnabled = enabled }
            self.refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func delete(_ id: UUID) {
        guard let task = self.snapshots.first(where: { $0.id == id })?.task else { return }
        do {
            try self.launchAgents.remove(task)
            _ = try self.repository.delete(id: id)
            self.cancelEditing()
            self.refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func runNow(_ id: UUID) {
        guard let task = self.snapshots.first(where: { $0.id == id })?.task else { return }
        do {
            try self.launchAgents.runNow(task)
            self.notice = "Started \(task.name)"
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                self.refresh()
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func needsAttention(_ snapshot: TaskSnapshot) -> Bool {
        snapshot.task.isEnabled &&
            snapshot.lastRun?.requiresAttention == true &&
            !self.isAttentionAcknowledged(taskID: snapshot.id, run: snapshot.lastRun)
    }

    func isAttentionAcknowledged(taskID: UUID, run: TaskRunResult?) -> Bool {
        _ = self.attentionRevision
        guard let run,
              let acknowledgedThrough = self.defaults.object(forKey: self.attentionKey(taskID)) as? Double
        else { return false }
        return run.startedAt.timeIntervalSince1970 <= acknowledgedThrough
    }

    func acknowledgeAttention(for taskID: UUID) {
        guard let run = self.runHistory[taskID]?.first(where: \.requiresAttention) else { return }
        let key = self.attentionKey(taskID)
        let existing = self.defaults.object(forKey: key) as? Double ?? 0
        let acknowledgedThrough = max(existing, run.startedAt.timeIntervalSince1970)
        guard acknowledgedThrough != existing else { return }
        self.defaults.set(acknowledgedThrough, forKey: key)
        self.attentionRevision += 1
    }

    private func attentionKey(_ taskID: UUID) -> String {
        "attention.acknowledgedThrough.\(taskID.uuidString.lowercased())"
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
