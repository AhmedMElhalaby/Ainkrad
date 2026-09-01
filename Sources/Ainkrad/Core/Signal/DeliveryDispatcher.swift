import Foundation
import AinkradSignal

@MainActor protocol ToastPresenting: AnyObject {
    func present(_ event: SignalEvent)
}

/// Turns a routing decision into effects. Holds no policy of its own - if you
/// find yourself adding an `if` about *whether* to deliver, it belongs in
/// `route(_:rules:context:)` where it is testable as a table row.
@MainActor
final class DeliveryDispatcher: SignalDeliverer {
    private let banner: any BannerPosting
    private let toast: any ToastPresenting
    private let sound: any SoundPlaying
    private let badge: (SignalSource) -> Void

    init(banner: any BannerPosting,
         toast: any ToastPresenting,
         sound: any SoundPlaying,
         badge: @escaping (SignalSource) -> Void) {
        self.banner = banner
        self.toast = toast
        self.sound = sound
        self.badge = badge
    }

    func deliver(_ event: SignalEvent, to channels: Set<DeliveryChannel>) {
        // `.feed` needs no work here: SignalCenter persisted the event before
        // routing, so the feed is already correct.
        if channels.contains(.banner) { banner.post(event) }
        if channels.contains(.toast) { toast.present(event) }
        if channels.contains(.sound) { sound.play(Self.sound(for: event.severity)) }
        if channels.contains(.badge) { badge(event.source) }
    }

    private static func sound(for severity: SignalSeverity) -> UISound {
        switch severity {
        case .failure, .warning: return .error
        case .success: return .confirm
        case .info: return .toggle
        @unknown default: return .toggle
        }
    }
}
