import ClockworkCore
import Foundation
import Observation

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
final class ClockworkModel {
    private let repository: TaskRepository
    private let launchAgents: LaunchAgentManager
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var historyTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var refreshRequested = false
    private var attentionRevision = 0

    var snapshots: [TaskSnapshot] = []
    var runHistory: [UUID: [TaskRunResult]] = [:]
    var loadingHistoryIDs: Set<UUID> = []
    var selectedTaskID: UUID?
    var draft: TaskDraft?
    var errorMessage: String?
    var notice: String?
    var isRefreshing = false
    var isPerformingAction = false

    init(
        repository: TaskRepository = TaskRepository(),
        launchAgents: LaunchAgentManager = LaunchAgentManager(),
        defaults: UserDefaults = .standard)
    {
        self.repository = repository
        self.launchAgents = launchAgents
        self.defaults = defaults
        self.snapshots = ClockworkSnapshotCache.load()
    }

    var enabledCount: Int {
        self.snapshots.count { $0.task.isEnabled }
    }

    var attentionStateRevision: Int {
        self.attentionRevision
    }

    func refresh() {
        guard self.refreshTask == nil else {
            self.refreshRequested = true
            return
        }

        self.isRefreshing = true
        let repository = self.repository
        let launchAgents = self.launchAgents
        self.refreshTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) {
                do {
                    _ = try LegacySchedulerMigration.migrateDataIfNeeded(destination: repository.paths)
                    let tasks = try repository.list()
                    try launchAgents.repairLegacyRegistrationsIfNeeded(tasks)
                    let snapshots = tasks.map { task in
                        TaskSnapshot(task: task, lastRun: repository.result(for: task.id, includeOutput: false))
                    }
                    return RefreshOutcome.loaded(snapshots)
                } catch {
                    return RefreshOutcome.failed(error.localizedDescription)
                }
            }.value

            guard let self else { return }
            self.apply(outcome)
            self.refreshTask = nil
            self.isRefreshing = false

            if self.refreshRequested {
                self.refreshRequested = false
                self.refresh()
            }
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
        self.loadHistory(for: id)
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
        let existing = self.snapshots.first(where: { $0.id == draft.id })?.task
        let task = draft.task(existing: existing)
        let repository = self.repository
        let launchAgents = self.launchAgents
        self.performOperation {
            do {
                let saved = try repository.save(task)
                try launchAgents.sync(saved)
                return .saved(saved)
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard var task = self.snapshots.first(where: { $0.id == id })?.task else { return }
        task.isEnabled = enabled
        let updatedTask = task
        let repository = self.repository
        let launchAgents = self.launchAgents
        self.performOperation {
            do {
                let saved = try repository.save(updatedTask)
                try launchAgents.sync(saved)
                return .enabled(saved)
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }

    func delete(_ id: UUID) {
        guard let task = self.snapshots.first(where: { $0.id == id })?.task else { return }
        let repository = self.repository
        let launchAgents = self.launchAgents
        self.performOperation {
            do {
                try launchAgents.remove(task)
                _ = try repository.delete(id: id)
                return .deleted(id)
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }

    func runNow(_ id: UUID) {
        guard let task = self.snapshots.first(where: { $0.id == id })?.task else { return }
        let launchAgents = self.launchAgents
        self.performOperation {
            do {
                try launchAgents.runNow(task)
                return .started(task.name)
            } catch {
                return .failed(error.localizedDescription)
            }
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

    private func loadHistory(for id: UUID) {
        self.historyTasks[id]?.cancel()
        self.loadingHistoryIDs.insert(id)
        let repository = self.repository

        self.historyTasks[id] = Task { [weak self] in
            let runs = await Task.detached(priority: .utility) {
                repository.results(for: id)
            }.value

            guard let self, !Task.isCancelled else { return }
            self.runHistory[id] = runs
            self.loadingHistoryIDs.remove(id)
            self.historyTasks[id] = nil
        }
    }

    private func performOperation(_ operation: @escaping @Sendable () -> OperationOutcome) {
        guard self.operationTask == nil else { return }
        self.errorMessage = nil
        self.notice = nil
        self.isPerformingAction = true

        self.operationTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated, operation: operation).value
            guard let self else { return }
            self.apply(outcome)
            self.operationTask = nil
            self.isPerformingAction = false
        }
    }

    private func apply(_ outcome: RefreshOutcome) {
        switch outcome {
        case let .loaded(snapshots):
            let changed = snapshots != self.snapshots
            if changed {
                self.snapshots = snapshots
            }
            if let selectedTaskID = self.selectedTaskID,
               !snapshots.contains(where: { $0.id == selectedTaskID })
            {
                self.selectedTaskID = nil
                self.draft = nil
            }
            self.errorMessage = nil
            if changed {
                Task.detached(priority: .background) {
                    ClockworkSnapshotCache.save(snapshots)
                }
            }
        case let .failed(message):
            self.errorMessage = message
        }
    }

    private func apply(_ outcome: OperationOutcome) {
        switch outcome {
        case let .saved(task):
            self.selectedTaskID = task.id
            self.draft = TaskDraft(task: task)
            self.notice = "Saved"
            self.refresh()
            self.loadHistory(for: task.id)
        case let .enabled(task):
            if self.draft?.id == task.id {
                self.draft?.isEnabled = task.isEnabled
            }
            self.refresh()
        case let .deleted(id):
            self.runHistory.removeValue(forKey: id)
            self.cancelEditing()
            self.refresh()
        case let .started(name):
            self.notice = "Started \(name)"
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.refresh()
                if let id = self?.selectedTaskID {
                    self?.loadHistory(for: id)
                }
            }
        case let .failed(message):
            self.errorMessage = message
        }
    }

    private enum RefreshOutcome {
        case loaded([TaskSnapshot])
        case failed(String)
    }

    private enum OperationOutcome {
        case saved(ScheduledTask)
        case enabled(ScheduledTask)
        case deleted(UUID)
        case started(String)
        case failed(String)
    }
}

private enum ClockworkSnapshotCache {
    private static var url: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("is.ian.clockwork", isDirectory: true)
            .appendingPathComponent("snapshot.json")
    }

    static func load() -> [TaskSnapshot] {
        guard let url = self.url,
              let data = try? Data(contentsOf: url),
              let snapshots = try? JSONDecoder().decode([TaskSnapshot].self, from: data)
        else { return [] }
        return snapshots
    }

    static func save(_ snapshots: [TaskSnapshot]) {
        guard let url = self.url, let data = try? JSONEncoder().encode(snapshots) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
