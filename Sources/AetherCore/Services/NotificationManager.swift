import Foundation
import UserNotifications

/// Schedules and cancels local notifications for EPG programme reminders.
public actor NotificationManager {
    public static let shared = NotificationManager()
    private init() {}

    /// Requests notification authorization from the user. Returns true if granted.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        guard Bundle.main.bundleIdentifier != nil else {
            print("[NotificationManager] Skipping notification auth — no bundle identifier")
            return false
        }
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        } catch {
            return false
        }
    }

    /// Schedules a reminder 5 minutes before the programme starts.
    /// Silently no-ops if the start time is in the past or within 5 minutes.
    public func scheduleReminder(for entry: EPGEntry, channelName: String) async throws {
        let fireDate = entry.start.addingTimeInterval(-5 * 60)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = channelName
        content.body = "\"\(entry.title)\" starts in 5 minutes"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: fireDate.timeIntervalSinceNow,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: reminderID(for: entry.id.uuidString),
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    /// Cancels a pending reminder for the given entry ID.
    public func cancelReminder(for entryID: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [reminderID(for: entryID)]
        )
    }

    /// Returns the set of entry ID strings that have pending reminders, filtered from the given list.
    public func scheduledEntryIDs(from entryIDs: [String]) async -> Set<String> {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let pendingIDs = Set(requests.map(\.identifier))
        return Set(entryIDs.filter { pendingIDs.contains(reminderID(for: $0)) })
    }

    private func reminderID(for entryID: String) -> String {
        "aether.epg-reminder.\(entryID)"
    }
}
