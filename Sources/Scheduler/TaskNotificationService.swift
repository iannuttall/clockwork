import Foundation
import OSLog
import SchedulerCore
import UserNotifications

@MainActor
final class TaskNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let openTask: (UUID) -> Void
    private let logger = Logger(subsystem: "com.iannuttall.scheduler", category: "Notifications")
    private var deliveriesInProgress: Set<String> = []

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        openTask: @escaping (UUID) -> Void)
    {
        self.center = center
        self.defaults = defaults
        self.openTask = openTask
        super.init()
        self.center.delegate = self
    }

    func process(_ snapshots: [TaskSnapshot]) {
        for snapshot in snapshots {
            guard let run = snapshot.lastRun,
                  !run.isRunning,
                  let event = run.event,
                  event.kind == .attention
            else { continue }

            let key = self.seenKey(taskID: snapshot.id)
            guard self.defaults.string(forKey: key) != run.id else { continue }
            let requestID = self.requestID(taskID: snapshot.id, runID: run.id)
            guard self.deliveriesInProgress.insert(requestID).inserted else { continue }

            Task {
                let outcome = await self.deliver(event, taskID: snapshot.id, runID: run.id)
                self.deliveriesInProgress.remove(requestID)
                if outcome != .failed {
                    self.defaults.set(run.id, forKey: key)
                }
            }
        }
    }

    private func deliver(_ event: TaskRunEvent, taskID: UUID, runID: String) async -> DeliveryOutcome {
        let authorization = await self.authorization()
        guard authorization == .allowed else {
            if authorization == .denied {
                self.logger.notice("Notifications are disabled for Scheduler")
            }
            return authorization == .denied ? .disabled : .failed
        }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.message
        content.sound = .default
        content.interruptionLevel = .active
        content.userInfo = [
            "taskID": taskID.uuidString,
            "runID": runID,
        ]

        let request = UNNotificationRequest(
            identifier: self.requestID(taskID: taskID, runID: runID),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        do {
            try await self.center.add(request)
            self.logger.info("Queued attention notification for task \(taskID.uuidString, privacy: .public)")
            try? await Task.sleep(for: .seconds(2))
            let delivered = await self.center.deliveredNotifications()
            if delivered.contains(where: { $0.request.identifier == request.identifier }) {
                self.logger.info("Confirmed attention notification delivery")
            } else {
                self.logger.notice("Notification request was accepted but is not present in Notification Center")
            }
            return .delivered
        } catch {
            self.logger.error("Could not queue attention notification: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    private func authorization() async -> AuthorizationOutcome {
        let settings = await self.center.notificationSettings()
        self.logger.info(
            """
            Notification settings: authorization=\(settings.authorizationStatus.rawValue), \
            alerts=\(settings.alertSetting.rawValue), \
            center=\(settings.notificationCenterSetting.rawValue), \
            sound=\(settings.soundSetting.rawValue)
            """)
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .allowed
        case .notDetermined:
            do {
                let allowed = try await self.center.requestAuthorization(options: [.alert, .sound])
                if allowed {
                    try? await Task.sleep(for: .milliseconds(500))
                    return .allowed
                }
                return .denied
            } catch {
                self.logger
                    .error("Could not request notification permission: \(error.localizedDescription, privacy: .public)")
                return .failed
            }
        case .denied:
            return .denied
        @unknown default:
            return .failed
        }
    }

    private func requestID(taskID: UUID, runID: String) -> String {
        "\(taskID.uuidString.lowercased())-\(runID)"
    }

    private func seenKey(taskID: UUID) -> String {
        "notifications.lastAttentionRun.\(taskID.uuidString.lowercased())"
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions
    {
        Logger(subsystem: "com.iannuttall.scheduler", category: "Notifications")
            .info("Presenting attention notification while Scheduler is active")
        return [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async
    {
        guard let value = response.notification.request.content.userInfo["taskID"] as? String,
              let taskID = UUID(uuidString: value)
        else { return }
        await MainActor.run {
            self.openTask(taskID)
        }
    }
}

private enum AuthorizationOutcome {
    case allowed
    case denied
    case failed
}

private enum DeliveryOutcome {
    case delivered
    case disabled
    case failed
}
