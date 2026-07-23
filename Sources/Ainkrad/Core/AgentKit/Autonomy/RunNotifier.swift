import Foundation
import UserNotifications

/// Posts a "run finished" notification when a background/scheduled `AgentRun`
/// completes while the user isn't watching. `RunManager` (Task 3) is the sole
/// caller — notification is always best-effort and must never fail the run.
@MainActor
protocol RunNotifier: AnyObject {
    func notifyCompleted(_ run: AgentRun)
}

/// Production implementation backed by `UNUserNotificationCenter`.
///
/// Authorization is requested lazily (on first completed run, not at launch)
/// so we don't prompt the user before there's anything to notify about. If
/// the user denies authorization, or the request hasn't resolved yet, posting
/// is silently skipped — a denied/pending notification permission must never
/// surface as a run failure.
@MainActor
final class UserNotificationRunNotifier: RunNotifier {
    private var didRequestAuthorization = false

    func notifyCompleted(_ run: AgentRun) {
        requestAuthorizationIfNeeded()

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = Self.title(for: run)
            content.body = Self.body(for: run)
            let request = UNNotificationRequest(
                identifier: run.id.uuidString, content: content, trigger: nil)
            center.add(request) { _ in
                // Best-effort: posting failures are swallowed by design — a
                // run's success/failure is never gated on notification delivery.
            }
        }
    }

    private func requestAuthorizationIfNeeded() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in
                // Result is re-checked per-notification via getNotificationSettings,
                // so nothing needs to be cached from this callback.
            }
    }

    nonisolated private static func title(for run: AgentRun) -> String {
        switch run.status {
        case .done: return "Run finished"
        case .failed: return "Run failed"
        case .interrupted: return "Run interrupted"
        default: return "Run update"
        }
    }

    nonisolated private static func body(for run: AgentRun) -> String {
        let head = run.prompt.prefix(80)
        if let result = run.result, !result.isEmpty {
            return "\(head)\n\(result.prefix(120))"
        }
        return String(head)
    }
}

/// Test double: records completed runs instead of touching
/// `UNUserNotificationCenter`, so unit tests never require real notification
/// authorization or post a real system notification.
@MainActor
final class RecordingRunNotifier: RunNotifier {
    private(set) var notified: [AgentRun] = []

    func notifyCompleted(_ run: AgentRun) {
        notified.append(run)
    }
}
