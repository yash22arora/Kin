import UserNotifications

/// One notification per day, always about the sky, never about a person's
/// neglect. That's the whole notification strategy.
enum NotificationScheduler {
    static let identifier = "stargazing"

    /// Copy rotates so the ritual never goes stale. None of these guilt.
    private static let lines = [
        "The sky is out.",
        "Your stars are up.",
        "A quiet minute under the sky?",
        "The night is clear where it counts.",
    ]

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Schedules (or reschedules) the single daily stargazing notification.
    static func schedule(hour: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Kin"
        content.body = lines.randomElement()!
        content.sound = .none // arrive quietly

        var components = DateComponents()
        components.hour = hour
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
