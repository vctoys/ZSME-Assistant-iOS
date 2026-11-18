import Foundation
import UserNotifications
import BackgroundTasks

final class NotificationManager {
    static let shared = NotificationManager()
    static let backgroundTaskIdentifier = "pl.zsme.assistant.sync"

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func sendLocalNotification(title: String, body: String, id: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func scheduleBackgroundRefresh(intervalMinutes: Int) {
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(max(intervalMinutes, 15) * 60))
        try? BGTaskScheduler.shared.submit(request)
    }
}
