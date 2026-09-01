import SwiftUI
import AinkradAppKit
import AinkradSignal

struct SignalDayGroup: Identifiable, Equatable {
    let id: Date          // start of day
    let events: [SignalEvent]
}

/// Pure presentation helpers, kept out of the `View` so they are testable
/// without rendering. Anything in here that needs a clock takes it as a
/// parameter - no `Date()` inside a formatter.
enum SignalRowFormatter {
    static func relativeTime(_ date: Date, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        switch elapsed {
        case ..<60: return "now"
        case ..<3600: return "\(Int(elapsed / 60))m"
        case ..<86400: return "\(Int(elapsed / 3600))h"
        default: return "\(Int(elapsed / 86400))d"
        }
    }

    static func dayGroups(_ events: [SignalEvent], calendar: Calendar) -> [SignalDayGroup] {
        let sorted = events.sorted { $0.timestamp > $1.timestamp }
        var order: [Date] = []
        var buckets: [Date: [SignalEvent]] = [:]
        for event in sorted {
            let day = calendar.startOfDay(for: event.timestamp)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(event)
        }
        return order.map { SignalDayGroup(id: $0, events: buckets[$0] ?? []) }
    }

    static func iconSymbol(for severity: SignalSeverity) -> String {
        switch severity {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .failure: return "xmark.octagon"
        @unknown default: return "info.circle"
        }
    }

    static func color(for severity: SignalSeverity, in status: AinkradStatusColors) -> Color {
        switch severity {
        case .info: return status.success.opacity(0.55)
        case .success: return status.success
        case .warning: return status.warning
        case .failure: return status.danger
        @unknown default: return status.success.opacity(0.55)
        }
    }

    static func sourceLabel(_ source: SignalSource) -> String {
        switch source {
        case .host: return "Ainkrad"
        case .sage: return "Sage"
        case .app(let id): return id.split(separator: ".").last.map(String.init)?.capitalized ?? id
        @unknown default: return "Ainkrad"
        }
    }
}

/// One event. No separator lines anywhere: separation is carried by the
/// elevated surface on hover and by spacing, per the host's design language.
struct SignalFeedRow: View {
    let event: SignalEvent
    var repeatCount: Int = 1
    var isUnread: Bool = true
    var now: Date = Date()
    var onActivate: (SignalEvent) -> Void = { _ in }
    var onAction: (SignalEvent, SignalAction) -> Void = { _, _ in }

    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    @State private var isHovered = false

    private var accent: Color { SignalRowFormatter.color(for: event.severity, in: status) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // The severity glyph is its own layer: it lifts slightly on hover
            // rather than the whole row sliding as one image.
            Image(systemName: SignalRowFormatter.iconSymbol(for: event.severity))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 16, height: 16)
                .scaleEffect(isHovered ? 1.12 : 1)
                .offset(y: isHovered ? -1 : 0)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 12.5, weight: isUnread ? .semibold : .regular))
                        .foregroundStyle(theme.foreground)
                        .lineLimit(1)
                    if repeatCount > 1 {
                        Text("+\(repeatCount - 1)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.foreground.opacity(0.7))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(theme.surfaceElevated))
                    }
                    Spacer(minLength: 4)
                    Text(SignalRowFormatter.relativeTime(event.timestamp, now: now))
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.foreground.opacity(0.45))
                        .monospacedDigit()
                }

                if let body = event.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.foreground.opacity(0.62))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    Text(SignalRowFormatter.sourceLabel(event.source))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.foreground.opacity(0.5))
                    if !event.actions.isEmpty {
                        ForEach(event.actions, id: \.id) { action in
                            Button(action.label) { onAction(event, action) }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(action.isDestructive ? status.danger : theme.accentPrimary)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(theme.surfaceElevated.opacity(isHovered ? 1 : 0.55)))
                        }
                    }
                }
                .opacity(isHovered || !event.actions.isEmpty ? 1 : 0.85)
            }

            // The dot's column is always reserved, even when read: letting it
            // collapse pulled the timestamps of read rows further right than
            // unread ones, so a column that should read as a straight edge
            // visibly zig-zagged.
            Circle()
                .fill(accent)
                .frame(width: 5, height: 5)
                .opacity(isUnread ? 1 : 0)
                .padding(.top, 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.surfaceElevated.opacity(isHovered ? 0.9 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture { onActivate(event) }
        .onHover { hovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { isHovered = hovering }
        }
    }
}
