import Foundation
import ScheduledTextsCore
import UserNotifications

/// Keeps the system's notifications in line with the message queue.
enum NotificationScheduler {
    /// Notifications that arrive late in the evening leave out "Remind Me
    /// Tonight", so they use a second category.
    static let categoryID = "DUE_MESSAGE"
    static let lateCategoryID = "DUE_MESSAGE_LATE"

    /// The buttons that appear when you press and hold a notification.
    enum Action {
        static let send = "SEND"
        static let cancel = "CANCEL"
        static let remindPrefix = "REMIND_"

        static func remind(_ option: RemindLater) -> String { remindPrefix + option.rawValue }

        static func remindOption(_ identifier: String) -> RemindLater? {
            guard identifier.hasPrefix(remindPrefix) else { return nil }
            return RemindLater(rawValue: String(identifier.dropFirst(remindPrefix.count)))
        }
    }

    private static var center: UNUserNotificationCenter { .current() }

    static func registerCategories() {
        let send = UNNotificationAction(
            identifier: Action.send,
            title: "Send",
            options: [.foreground],
            icon: UNNotificationActionIcon(systemImageName: "paperplane")
        )
        // Runs in the background: the text moves to the new time and the
        // app doesn't open.
        func remind(_ option: RemindLater) -> UNNotificationAction {
            UNNotificationAction(
                identifier: Action.remind(option),
                title: option.notificationTitle,
                options: [],
                icon: UNNotificationActionIcon(systemImageName: "clock")
            )
        }
        let cancel = UNNotificationAction(
            identifier: Action.cancel,
            title: "Don't Send",
            options: [.destructive],
            icon: UNNotificationActionIcon(systemImageName: "xmark")
        )
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [send, remind(.inAnHour), remind(.tonight), remind(.tomorrowMorning), cancel],
            intentIdentifiers: [],
            options: []
        )
        let late = UNNotificationCategory(
            identifier: lateCategoryID,
            actions: [send, remind(.inAnHour), remind(.tomorrowMorning), cancel],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category, late])
    }

    /// Asks the first time; afterwards just reports the current answer.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// Replaces every pending notification with a fresh plan, clears
    /// delivered notifications for texts that were sent, deleted or moved
    /// to later, and sets the badge.
    ///
    /// Delivered notifications for texts that are still due are left alone,
    /// so a missed one stays in Notification Center until it's handled.
    static func sync(with queue: MessageQueue, now: Date = Date()) async {
        center.removeAllPendingNotificationRequests()

        for planned in NotificationPlanner.plan(for: queue, now: now) {
            let content = UNMutableNotificationContent()
            content.title = planned.title
            content.body = planned.body
            content.sound = .default
            content.badge = NSNumber(value: planned.badge)
            content.categoryIdentifier = planned.offersTonight ? categoryID : lateCategoryID
            // A time interval fires at the same moment wherever the phone is,
            // even if it changes time zone before then.
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, planned.fireDate.timeIntervalSince(now)),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: planned.id, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                print("Couldn't schedule notification \(planned.id): \(error)")
            }
        }

        let dueIDs = Set(queue.due(at: now).map { NotificationPlanner.notificationID(for: $0.id) })
        let stale = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { !dueIDs.contains($0) }
        if !stale.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: stale)
        }

        try? await center.setBadgeCount(queue.badgeCount(at: now))
    }
}
