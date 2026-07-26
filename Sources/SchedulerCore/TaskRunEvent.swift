import Foundation

public enum TaskRunEventKind: String, Codable, Equatable, Sendable {
    case attention
}

public struct TaskRunEvent: Codable, Equatable, Sendable {
    public static let environmentKey = "SCHEDULER_EVENT_FILE"
    public static let filename = "event.json"

    public var kind: TaskRunEventKind
    public var title: String
    public var message: String
    public var nextStep: String?

    public init(kind: TaskRunEventKind, title: String, message: String, nextStep: String? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.nextStep = nextStep
    }

    public static func attention(title: String, message: String, nextStep: String? = nil) -> TaskRunEvent {
        TaskRunEvent(kind: .attention, title: title, message: message, nextStep: nextStep)
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
