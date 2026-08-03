import ClockworkCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct CLIArguments {
    var values: [String]

    mutating func flag(_ name: String) -> Bool {
        guard let index = self.values.firstIndex(of: name) else { return false }
        self.values.remove(at: index)
        return true
    }

    mutating func option(_ name: String) -> String? {
        guard let index = self.values.firstIndex(of: name), index + 1 < self.values.count else { return nil }
        self.values.remove(at: index)
        return self.values.remove(at: index)
    }

    mutating func options(_ name: String) -> [String] {
        var found: [String] = []
        while let value = self.option(name) {
            found.append(value)
        }
        return found
    }
}

struct JSONSnapshot: Codable {
    var task: ScheduledTask
    var lastRun: TaskRunResult?
}

let repository = TaskRepository()
let launchAgents = LaunchAgentManager()

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("clockwork: \(error.localizedDescription)\n".utf8))
    exit(1)
}

/// Command dispatch is deliberately kept in one place so the CLI stays easy to scan.
func run() throws {
    _ = try LegacySchedulerMigration.migrateDataIfNeeded(destination: repository.paths)
    let migratedTasks = try repository.list()
    try launchAgents.repairLegacyRegistrationsIfNeeded(migratedTasks)

    var arguments = CLIArguments(values: Array(CommandLine.arguments.dropFirst()))
    guard let command = arguments.values.first else {
        printHelp()
        return
    }
    arguments.values.removeFirst()
    let json = arguments.flag("--json")

    switch command {
    case "list":
        try listTasks(json: json)

    case "show":
        try showTask(arguments.values.first, json: json)

    case "runs":
        try printRuns(arguments.values.first, json: json)

    case "add":
        let name = try required(arguments.option("--name"), message: "--name is required")
        let commands = arguments.options("--command")
        guard !commands.isEmpty else { throw ClockworkError.invalidTask("Add at least one --command.") }
        let schedule = try parseSchedule(arguments: &arguments)
        let task = ScheduledTask(
            name: name,
            commands: commands,
            workingDirectory: arguments.option("--cwd"),
            schedule: schedule,
            isEnabled: !arguments.flag("--disabled"))
        let saved = try repository.save(task)
        try launchAgents.sync(saved)
        if json {
            try printJSON(saved)
        } else {
            print("Added \(saved.name): \(saved.schedule.summary)")
        }

    case "update":
        let existing = try requireTask(arguments.values.first)
        if !arguments.values.isEmpty {
            arguments.values.removeFirst()
        }
        var draft = existing
        if let name = arguments.option("--name") {
            draft.name = name
        }
        let commands = arguments.options("--command")
        if !commands.isEmpty {
            draft.commands = commands
        }
        if let cwd = arguments.option("--cwd") {
            draft.workingDirectory = cwd == "-" ? nil : cwd
        }
        if hasSchedule(arguments.values) {
            draft.schedule = try parseSchedule(arguments: &arguments)
        }
        if arguments.flag("--enable") {
            draft.isEnabled = true
        }
        if arguments.flag("--disable") {
            draft.isEnabled = false
        }
        let saved = try repository.save(draft)
        try launchAgents.sync(saved)
        if json {
            try printJSON(saved)
        } else {
            print("Updated \(saved.name)")
        }

    case "enable", "disable":
        var task = try requireTask(arguments.values.first)
        task.isEnabled = command == "enable"
        let saved = try repository.save(task)
        try launchAgents.sync(saved)
        if json {
            try printJSON(saved)
        } else {
            print("\(saved.isEnabled ? "Enabled" : "Disabled") \(saved.name)")
        }

    case "delete":
        let task = try requireTask(arguments.values.first)
        try launchAgents.remove(task)
        _ = try repository.delete(id: task.id)
        if json {
            print("{\"deleted\":true,\"id\":\"\(task.id.uuidString.lowercased())\"}")
        } else {
            print("Deleted \(task.name)")
        }

    case "run":
        let task = try requireTask(arguments.values.first)
        try launchAgents.runNow(task)
        if json {
            print("{\"started\":true,\"id\":\"\(task.id.uuidString.lowercased())\"}")
        } else {
            print("Started \(task.name)")
        }

    case "attention":
        try reportAttention(arguments: &arguments, json: json)

    case "sync":
        let tasks = try repository.list()
        try launchAgents.syncAll(tasks)
        print(json ? "{\"synced\":\(tasks.count)}" : "Synced \(tasks.count) tasks with launchd")

    case "explain-cron":
        let expression = arguments.values.joined(separator: " ")
        try print(explainCron(expression))

    case "help", "--help", "-h":
        printHelp()

    default:
        throw ClockworkError.invalidTask("Unknown command '\(command)'. Run clockwork help.")
    }
}

func listTasks(json: Bool) throws {
    let tasks = try repository.list()
    if json {
        try printJSON(tasks.map { JSONSnapshot(task: $0, lastRun: repository.result(for: $0.id)) })
    } else if tasks.isEmpty {
        print("No scheduled tasks.")
    } else {
        for task in tasks {
            let state = task.isEnabled ? "enabled" : "disabled"
            let result = repository.result(for: task.id)?.summary ?? "never run"
            let identity = "\(task.id.uuidString.lowercased())  \(task.name)"
            print("\(identity)  ·  \(task.schedule.summary)  ·  \(state)  ·  \(result)")
        }
    }
}

func showTask(_ identifier: String?, json: Bool) throws {
    let task = try requireTask(identifier)
    if json {
        try printJSON(JSONSnapshot(task: task, lastRun: repository.result(for: task.id)))
    } else {
        printTask(task)
    }
}

func printRuns(_ identifier: String?, json: Bool) throws {
    let task = try requireTask(identifier)
    let runs = repository.results(for: task.id)
    if json {
        try printJSON(runs)
    } else if runs.isEmpty {
        print("No runs for \(task.name).")
    } else {
        print("Runs for \(task.name):")
        for result in runs {
            let time = result.startedAt.formatted(.iso8601)
            print("\(time)  ·  \(result.summary)  ·  \(result.id)")
            if !result.combinedOutput.isEmpty {
                print(result.combinedOutput)
            }
        }
    }
}

func reportAttention(arguments: inout CLIArguments, json: Bool) throws {
    let title = try required(arguments.option("--title"), message: "--title is required")
    let message = try required(arguments.option("--message"), message: "--message is required")
    let event = TaskRunEvent.attention(
        title: title,
        message: message,
        nextStep: arguments.option("--next-step"))
    if let path = ProcessInfo.processInfo.environment[TaskRunEvent.environmentKey], !path.isEmpty {
        try event.write(to: URL(fileURLWithPath: path))
    }
    if json {
        try printJSON(event)
    } else {
        print("\(title): \(message)")
    }
}

func requireTask(_ identifier: String?) throws -> ScheduledTask {
    let value = try required(identifier, message: "Task ID or exact name is required.")
    guard let task = try repository.find(value)
    else { throw ClockworkError.taskNotFound("No task found for '\(value)'.") }
    return task
}

func required<T>(_ value: T?, message: String) throws -> T {
    guard let value else { throw ClockworkError.invalidTask(message) }
    return value
}

func hasSchedule(_ values: [String]) -> Bool {
    values.contains("--every") || values.contains("--daily") || values.contains("--weekly")
}

func parseSchedule(arguments: inout CLIArguments) throws -> TaskSchedule {
    if let every = arguments.option("--every") {
        guard let suffix = every.last, let value = Int(every.dropLast()), value > 0 else {
            throw ClockworkError.invalidTask("Use --every 30m or --every 6h.")
        }
        switch suffix {
        case "m": return .interval(value: value, unit: .minutes)
        case "h": return .interval(value: value, unit: .hours)
        default: throw ClockworkError.invalidTask("Use --every 30m or --every 6h.")
        }
    }
    if let daily = arguments.option("--daily") {
        let time = try parseTime(daily)
        return .daily(hour: time.hour, minute: time.minute)
    }
    if let weekly = arguments.option("--weekly") {
        let parts = weekly.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw ClockworkError.invalidTask("Use --weekly mon,wed@09:00.") }
        let days = try parts[0].split(separator: ",").map { try parseWeekday(String($0)) }
        let time = try parseTime(parts[1])
        return .weekly(days: days, hour: time.hour, minute: time.minute)
    }
    throw ClockworkError.invalidTask("Choose one schedule: --every 6h, --daily 09:00, or --weekly mon,fri@09:00.")
}

func parseTime(_ value: String) throws -> (hour: Int, minute: Int) {
    let parts = value.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else {
        throw ClockworkError.invalidTask("Time must use 24-hour HH:MM format.")
    }
    return (parts[0], parts[1])
}

func parseWeekday(_ value: String) throws -> Weekday {
    guard let day = Weekday.allCases.first(where: { $0.shortName.lowercased().hasPrefix(value.lowercased()) }) else {
        throw ClockworkError.invalidTask("Unknown weekday '\(value)'.")
    }
    return day
}

func explainCron(_ expression: String) throws -> String {
    let fields = expression.split(whereSeparator: \.isWhitespace).map(String.init)
    guard fields.count == 5 else { throw ClockworkError.invalidTask("A cron expression needs five fields.") }
    if fields[0].hasPrefix("*/"), fields[1] == "*", let minutes = Int(fields[0].dropFirst(2)) {
        return "Every \(minutes) minutes"
    }
    if fields[0] == "0", fields[1].hasPrefix("*/"), let hours = Int(fields[1].dropFirst(2)) {
        return "Every \(hours) hours"
    }
    if let minute = Int(fields[0]), let hour = Int(fields[1]), fields[2] == "*", fields[3] == "*" {
        let time = String(format: "%02d:%02d", hour, minute)
        if fields[4] == "*" {
            return "Every day at \(time)"
        }
        if fields[4] == "1-5" {
            return "Monday to Friday at \(time)"
        }
    }
    return "Valid-looking cron, but Clockwork cannot translate this pattern yet. " +
        "Use the visual schedule picker instead."
}

func printTask(_ task: ScheduledTask) {
    let enabled = task.isEnabled ? "yes" : "no"
    print("\(task.name)\nID: \(task.id.uuidString.lowercased())")
    print("Schedule: \(task.schedule.summary)\nEnabled: \(enabled)")
    if let workingDirectory = task.workingDirectory {
        print("Folder: \(workingDirectory)")
    }
    print("Commands:\n\(task.commands.map { "  \($0)" }.joined(separator: "\n"))")
    if let result = repository.result(for: task.id) {
        print("Last run: \(result.summary) at \(result.startedAt.formatted(.iso8601))")
    } else {
        print("Last run: never")
    }
}

func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    print(String(data: data, encoding: .utf8) ?? "")
}

func printHelp() {
    print("""
    Clockwork, human-friendly recurring commands

    clockwork list [--json]
    clockwork show <id|name> [--json]
    clockwork runs <id|name> [--json]
    clockwork add --name NAME --command CMD [--command CMD] [--cwd PATH] --every 6h|--daily 09:00|--weekly mon,fri@09:00
    clockwork update <id|name> [--name NAME] [--command CMD] [--cwd PATH|-] [schedule] [--enable|--disable]
    clockwork enable|disable|delete|run <id|name> [--json]
    clockwork attention --title TITLE --message MESSAGE [--next-step TEXT]
    clockwork sync
    clockwork explain-cron '0 */6 * * *'
    """)
}
