import SwiftUI
import AinkradAppKit
import AinkradSignal

@MainActor
@Observable
final class SignalToastModel: ToastPresenting {
    static let maxVisible = 3

    private(set) var visible: [SignalEvent] = []
    private var queued: [SignalEvent] = []
    var overflowCount: Int { queued.count }

    /// `nil` means "requires an explicit dismissal". A failure that vanished on
    /// its own is exactly the case this feature exists to prevent.
    static func autoDismissDelay(for severity: SignalSeverity) -> TimeInterval? {
        switch severity {
        case .info, .success: return 4
        case .warning: return 8
        case .failure: return nil
        @unknown default: return 4
        }
    }

    /// Severity order, so a more urgent arrival can take a slot from a less
    /// urgent toast. Not `CaseIterable`'s order: that is a declaration detail
    /// and must not silently become behaviour.
    private static func rank(_ severity: SignalSeverity) -> Int {
        switch severity {
        case .info: return 0
        case .success: return 1
        case .warning: return 2
        case .failure: return 3
        @unknown default: return 0
        }
    }

    /// Past the cap, an arrival queues UNLESS it is strictly more severe than
    /// the least-severe toast on screen, in which case it takes that slot and
    /// the displaced toast goes back to the front of the queue.
    ///
    /// Plain FIFO queueing was the first cut and looked wrong the moment it was
    /// rendered: three chatty `.info` toasts filled the stack and a real
    /// failure sat behind "+2 more" — the feed's most important event hidden
    /// behind its least. Strictness matters in both directions: because the
    /// comparison is `>` and not `>=`, a `.failure` can never be displaced by
    /// another failure, so the toast that never auto-dismisses is never the one
    /// that silently disappears.
    func present(_ event: SignalEvent) {
        guard !visible.contains(where: { $0.id == event.id }),
              !queued.contains(where: { $0.id == event.id }) else { return }

        if visible.count < Self.maxVisible {
            visible.insert(event, at: 0)
            scheduleAutoDismiss(event)
            return
        }

        let arriving = Self.rank(event.severity)
        if let weakest = visible.enumerated().min(by: {
            Self.rank($0.element.severity) < Self.rank($1.element.severity)
        }), Self.rank(weakest.element.severity) < arriving {
            let displaced = visible.remove(at: weakest.offset)
            queued.insert(displaced, at: 0)
            visible.insert(event, at: 0)
            scheduleAutoDismiss(event)
        } else {
            queued.insert(event, at: 0)
        }
    }

    func dismiss(id: UUID) {
        visible.removeAll { $0.id == id }
        // Promote the NEWEST queued event, and to the top - the same ordering
        // the visible stack already uses, so a promotion does not shuffle the
        // stack into a different order than arrivals produce.
        if !queued.isEmpty {
            let next = queued.removeFirst()
            visible.insert(next, at: 0)
            scheduleAutoDismiss(next)
        }
    }

    private func scheduleAutoDismiss(_ event: SignalEvent) {
        guard let delay = Self.autoDismissDelay(for: event.severity) else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            self?.dismiss(id: event.id)
        }
    }
}

/// Bottom-trailing stack of transient toasts.
///
/// Each toast is its own layer with its own transition, so the stack settles as
/// separated live layers rather than one image sliding — the host's motion rule.
struct SignalToastStack: View {
    let model: SignalToastModel
    var now: Date = Date()
    var onActivate: (SignalEvent) -> Void = { _ in }

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if model.overflowCount > 0 {
                Text("+\(model.overflowCount) more")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.foreground.opacity(0.6))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(theme.surfaceElevated))
                    .transition(.opacity)
            }
            ForEach(model.visible) { event in
                toast(event)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity.combined(with: .scale(scale: 0.96))))
            }
        }
        .padding(16)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.visible.map(\.id))
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.overflowCount)
    }

    private func toast(_ event: SignalEvent) -> some View {
        let accent = SignalRowFormatter.color(for: event.severity, in: status)
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: SignalRowFormatter.iconSymbol(for: event.severity))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.foreground)
                    .lineLimit(1)
                if let body = event.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.foreground.opacity(0.6))
                        .lineLimit(2)
                }
            }
            Button {
                model.dismiss(id: event.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.foreground.opacity(0.45))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // A fixed width, not content-sized: a stack of toasts with ragged
        // right edges reads as a layout accident rather than one surface.
        .frame(width: 330, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(theme.surfaceElevated)
        )
        // A failure toast carries a hairline of its own severity colour rather
        // than a separator: it has to be distinguishable at a glance, since it
        // is the one toast that never auto-dismisses.
        .overlay(alignment: .leading) {
            if event.severity == .failure {
                Capsule().fill(accent).frame(width: 2.5).padding(.vertical, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onActivate(event) }
    }
}
