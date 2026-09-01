import Foundation
import UserNotifications
import AinkradSignal

@MainActor protocol BannerPosting: AnyObject {
    func post(_ event: SignalEvent)
}

/// macOS banner delivery. Authorization is requested lazily on the first
/// banner-routed event, not at launch, so the user is not prompted before there
/// is anything to show — the behaviour the old run notifier established and
/// this generalizes.
///
/// As of generation 9 this channel is the ONLY thing that posts a macOS banner,
/// including for completed agent runs. There is no second path any more, so a
/// bug here is a notification the user never sees rather than one they see
/// twice.
@MainActor
final class UserNotificationBannerChannel: BannerPosting {
    private var didRequestAuthorization = false

    func post(_ event: SignalEvent) {
        requestAuthorizationIfNeeded()
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = event.title
            if let body = event.body { content.body = body }
            content.userInfo = ["signalEventID": event.id.uuidString]
            let request = UNNotificationRequest(identifier: event.id.uuidString,
                                                content: content, trigger: nil)
            center.add(request) { _ in
                // Best-effort: a failed banner never surfaces as an error. The
                // feed row exists regardless, which is the durable record.
            }
        }
    }

    private func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            // Re-checked per post via getNotificationSettings; nothing to cache.
        }
    }
}
