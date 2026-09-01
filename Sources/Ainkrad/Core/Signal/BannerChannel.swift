import Foundation
import UserNotifications
import AinkradSignal

@MainActor protocol BannerPosting: AnyObject {
    func post(_ event: SignalEvent)
}

/// macOS banner delivery. Authorization is requested lazily on the first
/// banner-routed event, not at launch, so the user is not prompted before
/// there is anything to show - the behaviour `UserNotificationRunNotifier`
/// established and this generalizes.
///
/// In M1 this channel never sees `run.*` from `.host`: `RunNotifier` still
/// owns those banners and `RoutingRules.suppressBannerForHostRuns` keeps them
/// away from here. M2 deletes `RunNotifier` and lifts the exemption.
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
