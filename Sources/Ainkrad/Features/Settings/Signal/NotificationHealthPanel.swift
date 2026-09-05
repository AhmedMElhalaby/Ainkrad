import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// Whether notifications are working, and the single click that fixes the
/// worst offender.
///
/// The mute control sits ON the noisiest row deliberately. A readout that
/// names a problem and cannot fix it is half a feature; the whole point is
/// that the diagnosis and the remedy are the same click.
struct NotificationHealthPanel: View {
    enum Window: String, CaseIterable, Identifiable {
        case day, week, month
        var id: String { rawValue }
        var label: String {
            switch self {
            case .day: return "24 hours"
            case .week: return "7 days"
            case .month: return "30 days"
            }
        }
        var seconds: TimeInterval {
            switch self {
            case .day: return 86_400
            case .week: return 7 * 86_400
            case .month: return 30 * 86_400
            }
        }
    }

    @Binding var window: Window
    let health: SignalHealth
    var displayName: (String) -> String = { $0 }
    var onMuteKind: (SignalSource, String) -> Void = { _, _ in }

    @Environment(\.ainkradTheme) private var theme

    private func sourceName(_ source: SignalSource) -> String {
        if case .app(let id) = source { return displayName(id) }
        return SignalPresentation.sourceLabel(source)
    }

    /// Under this, the numbers describe noise rather than behaviour. Saying so
    /// beats rendering "0% read" at someone who has had three notifications.
    private static let minimumSample = 5

    var body: some View {
        AinkradSettingsPanel(
            title: "Notification health",
            hint: "Measured from your own feed and kept on this machine."
        ) {
            if health.total < Self.minimumSample {
                AinkradCaption("Not enough history yet.")
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    AinkradCaptionedRow("Window") {
                        AinkradSegmentedPicker(items: Window.allCases,
                                               selection: $window,
                                               label: \.label)
                    }
                    figures
                    if !health.noisiest.isEmpty { noisiest }
                }
            }
        }
    }

    private var figures: some View {
        HStack(spacing: AinkradSpacing.lg) {
            figure("Arrived", "\(health.total)")
            figure("Read", Self.percent(health.readRate))
            figure("Median reply", Self.duration(health.medianAcknowledgeSeconds))
        }
    }

    private func figure(_ caption: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(AinkradFont.mono(15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(theme.foreground)
            Text(caption)
                .font(AinkradFont.display(9.5))
                .foregroundStyle(theme.foreground.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.5)
        }
    }

    private var noisiest: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Loudest")
                .font(AinkradFont.display(10, weight: .medium))
                .foregroundStyle(theme.foreground.opacity(0.55))
                .textCase(.uppercase)
                .tracking(0.5)
            ForEach(health.noisiest) { entry in
                HStack(spacing: AinkradSpacing.sm) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.kind)
                            .font(AinkradFont.mono(11))
                            .foregroundStyle(theme.foreground)
                        // Named, because the same kind can come from two
                        // sources and muting one must not read as muting both.
                        if let source = entry.source {
                            Text(sourceName(source))
                                .font(AinkradFont.mono(9.5))
                                .foregroundStyle(theme.foreground.opacity(0.45))
                        }
                    }
                    Text("\(entry.count)")
                        .font(AinkradFont.mono(10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(theme.foreground.opacity(0.5))
                    Spacer(minLength: AinkradSpacing.sm)
                    if let source = entry.source {
                        AinkradButton(title: "Quiet", style: .ghost) {
                            onMuteKind(source, entry.kind)
                        }
                    }
                }
            }
        }
    }

    /// Whole percents. A read rate quoted to a decimal place claims a
    /// precision a few dozen events cannot support.
    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// Coarse on purpose, for the same reason: the number is read as "about
    /// this long", and seconds of precision on a median of eleven samples is
    /// a decoration pretending to be data.
    static func duration(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        switch seconds {
        case ..<60: return "\(Int(seconds.rounded()))s"
        case ..<3600: return "\(Int((seconds / 60).rounded()))m"
        case ..<86_400: return "\(Int((seconds / 3600).rounded()))h"
        default: return "\(Int((seconds / 86_400).rounded()))d"
        }
    }
}
