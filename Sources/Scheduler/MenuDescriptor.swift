import Foundation

struct MenuDescriptor: Equatable {
    var sections: [Section]

    struct Section: Equatable {
        var entries: [Entry]
    }

    enum Entry: Equatable {
        case action(String, MenuAction)
    }

    enum MenuAction: Equatable {
        case add
        case open
        case checkForUpdates
        case quit
    }

    static var standard: MenuDescriptor {
        MenuDescriptor(sections: [
            Section(entries: [
                .action("Add Scheduled Task…", .add),
                .action("Open Scheduler…", .open),
            ]),
            Section(entries: [
                .action("Check for Updates…", .checkForUpdates),
                .action("Quit Scheduler", .quit),
            ]),
        ])
    }
}

extension MenuDescriptor.MenuAction {
    var systemImage: String {
        switch self {
        case .add: "plus"
        case .open: "macwindow"
        case .checkForUpdates: "arrow.down.circle"
        case .quit: "power"
        }
    }

    var keyEquivalent: (key: String, command: Bool)? {
        switch self {
        case .add: ("n", true)
        case .open: (",", true)
        case .quit: ("q", true)
        case .checkForUpdates: nil
        }
    }
}
