import SwiftUI
import AinkradAppKit
import AinkradSignal

/// Ainkrad → Notifications. Every change writes straight through to
/// `SignalCenter`, whose `didSet` hooks persist it — no Save button, matching
/// the rest of Settings.
struct SignalSettingsPane: View {
    let center: SignalCenter
    var sources: [SignalSource] = [.host, .sage]

    @Environment(\.ainkradTheme) private var theme
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AinkradSettingsPanel(
                title: "Delivery",
                hint: "What each source is allowed to interrupt you with. A muted source "
                    + "still lands in the feed — it just never surfaces."
            ) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                        AinkradCaptionedRow(SignalRowFormatter.sourceLabel(source)) {
                            AinkradToggle(isOn: Binding(
                                get: { !center.rules.mutedSources.contains(source) },
                                set: { allowed in
                                    if allowed { center.rules.mutedSources.remove(source) }
                                    else { center.rules.mutedSources.insert(source) }
                                }))
                        }
                    }
                }
            }

            AinkradSettingsPanel(
                title: "History",
                hint: "The feed keeps the most recent events and drops the rest. "
                    + "Pinned events are never dropped and do not count toward the limit."
            ) {
                VStack(alignment: .leading, spacing: 9) {
                    AinkradCaptionedRow("Keep for (days)") {
                        AinkradStepper(value: Binding(
                            get: { center.retention.maxAgeDays },
                            set: { center.retention.maxAgeDays = $0 }), in: 1...365)
                    }
                    AinkradCaptionedRow("Maximum events") {
                        AinkradStepper(value: Binding(
                            get: { center.retention.maxEvents },
                            set: { center.retention.maxEvents = $0 }), in: 100...100_000, step: 100)
                    }
                    HStack {
                        Text("\(center.eventCount) events stored")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.foreground.opacity(0.5))
                        Spacer()
                        Button("Clear feed") { confirmingClear = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.accentTertiary)
                    }
                }
            }

            AinkradSettingsPanel(
                title: "Agent runs",
                hint: "Completed background runs currently notify through the older run "
                    + "notifier, so the feed records them without posting a second banner. "
                    + "This goes away when runs move fully onto the feed."
            ) {
                AinkradCaptionedRow("Run banners") {
                    Text(center.rules.suppressBannerForHostRuns ? "Legacy notifier" : "Feed")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.foreground.opacity(0.55))
                }
            }
        }
        .confirmationDialog("Clear the notification feed?",
                            isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { center.clearFeed() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned events are kept. This cannot be undone.")
        }
    }
}
