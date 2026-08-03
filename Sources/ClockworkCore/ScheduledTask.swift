import Foundation

public enum IntervalUnit: String, Codable, CaseIterable, Sendable {
    case minutes
    case hours

    public var singular: String {
        switch self {
        case .minutes: "minute"
        case .hours: "hour"
        }
    }

    public func seconds(for value: Int) -> Int {
        switch self {
        case .minutes: value * 60
        case .hours: value * 3600
        }
    }
}

public enum Weekday: Int, Codable, CaseIterable, Identifiable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    public var id: Int {
        self.rawValue
    }

    public var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }
}

public enum TaskSchedule: Codable, Equatable, Sendable {
    case interval(value: Int, unit: IntervalUnit)
    case daily(hour: Int, minute: Int)
    case weekly(days: [Weekday], hour: Int, minute: Int)

    public var summary: String {
        switch self {
        case let .interval(value, unit):
            let name = value == 1 ? unit.singular : unit.rawValue
            return "Every \(value) \(name)"
        case let .daily(hour, minute):
            return "Every day at \(Self.time(hour: hour, minute: minute))"
        case let .weekly(days, hour, minute):
            let names = days.sorted { $0.rawValue < $1.rawValue }.map(\.shortName).joined(separator: ", ")
            return "\(names.isEmpty ? "No days" : names) at \(Self.time(hour: hour, minute: minute))"
        }
    }

    public var isValid: Bool {
        switch self {
        case let .interval(value, _): value > 0
        case let .daily(hour, minute): Self.validTime(hour: hour, minute: minute)
        case let .weekly(days, hour, minute): !days.isEmpty && Self.validTime(hour: hour, minute: minute)
        }
    }

    public func nextRun(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case let .interval(value, unit):
            date.addingTimeInterval(TimeInterval(unit.seconds(for: value)))
        case let .daily(hour, minute):
            calendar.nextDate(
                after: date,
                matching: DateComponents(hour: hour, minute: minute),
                matchingPolicy: .nextTime)
        case let .weekly(days, hour, minute):
            days.compactMap { day in
                calendar.nextDate(
                    after: date,
                    matching: DateComponents(hour: hour, minute: minute, weekday: day.rawValue),
                    matchingPolicy: .nextTime)
            }.min()
        }
    }

    private static func validTime(hour: Int, minute: Int) -> Bool {
        (0...23).contains(hour) && (0...59).contains(minute)
    }

    private static func time(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }
}

public struct ScheduledTask: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var commands: [String]
    public var workingDirectory: String?
    public var schedule: TaskSchedule
    public var isEnabled: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        commands: [String],
        workingDirectory: String? = nil,
        schedule: TaskSchedule,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date())
    {
        self.id = id
        self.name = name
        self.commands = commands
        self.workingDirectory = workingDirectory
        self.schedule = schedule
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var validationError: String? {
        if self.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Give the task a name."
        }
        if self.commands.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Add at least one command."
        }
        if !self.schedule.isValid {
            return "Choose a valid schedule."
        }
        return nil
    }
}

public struct TaskRunResult: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var exitCode: Int?
    public var standardOutput: String
    public var standardError: String
    public var event: TaskRunEvent?

    public init(
        id: String,
        startedAt: Date,
        finishedAt: Date?,
        exitCode: Int?,
        standardOutput: String,
        standardError: String,
        event: TaskRunEvent? = nil)
    {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.event = event
    }

    public var isRunning: Bool {
        self.finishedAt == nil
    }

    public var succeeded: Bool {
        self.exitCode == 0 && self.finishedAt != nil
    }

    public var requiresAttention: Bool {
        self.finishedAt != nil && self.event?.kind == .attention
    }

    public var summary: String {
        if self.isRunning {
            return "Running now"
        }
        if self.requiresAttention {
            return "Needs attention"
        }
        if self.succeeded {
            return "Succeeded"
        }
        if let exitCode {
            return "Failed (exit \(exitCode))"
        }
        return "No result"
    }

    public var combinedOutput: String {
        [self.standardOutput, self.standardError]
            .filter { !$0.isEmpty }
            .joined(separator: self.standardOutput.isEmpty || self.standardError.isEmpty ? "" : "\n")
    }
}

public struct TaskSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var task: ScheduledTask
    public var lastRun: TaskRunResult?

    public init(task: ScheduledTask, lastRun: TaskRunResult?) {
        self.task = task
        self.lastRun = lastRun
    }

    public var id: UUID {
        self.task.id
    }
}
