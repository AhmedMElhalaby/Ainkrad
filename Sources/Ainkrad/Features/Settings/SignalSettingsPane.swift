import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// Ainkrad → Notifications. Every change writes straight through to
/// `SignalCenter`, whose `didSet` hooks persist it — no Save button, matching
/// the rest of Settings.
struct SignalSettingsPane: View {
    let center: SignalCenter
    var sources: [SignalSource] = [.host, .sage]
    /// Cross-app access rows, or empty when no app has ever asked. Passed in
    /// rather than read from the environment so the pane stays renderable in a
    /// snapshot.
    var subscriptionRows: [SubscriptionSettingsSection.Row] = []
    /// Nil in a snapshot, where there is no bootstrap and so no engine — the
    /// panel is then simply absent rather than bound to a stand-in that lies
    /// about what the app will do.
    var notificationSounds: NotificationSoundStore?
    var displayName: (String) -> String = { $0 }

    /// An app's real display name where the host knows it, falling back to the
    /// kit's label. `SignalPresentation.sourceLabel` only capitalises the bundle
    /// id's last component, which turns "gitmage" into "Gitmage".
    private func displayName(for source: SignalSource) -> String {
        if case .app(let id) = source { return displayName(id) }
        return SignalPresentation.sourceLabel(source)
    }
    var onApproveSubscriptions: (String) -> Void = { _ in }
    var onRevokeSubscriptions: (String) -> Void = { _ in }

    @Environment(\.ainkradTheme) private var theme
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AinkradSettingsPanel(
                title: "Delivery",
                hint: "What each source is allowed to interrupt you with. Every source "
                    + "still lands in the feed, whatever you choose here — the log is "
                    + "not optional."
            ) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                        AinkradCaptionedRow(displayName(for: source)) {
                            // Three states, not a toggle: "off" and "recorded
                            // but never surfaced" are different answers, and a
                            // toggle can only offer one of them.
                            AinkradSegmentedPicker(
                                items: SignalDeliveryMode.allCases,
                                selection: Binding(
                                    get: { SignalDeliveryMode(rules: center.rules, source: source) },
                                    set: { $0.apply(to: &center.rules, source: source) }),
                                label: \.label)
                        }
                    }
                }
            }

            if let sounds = notificationSounds {
                AinkradSettingsPanel(
                    title: "Sound",
                    hint: "Separate from interface sounds — turning those off in General "
                        + "will not silence a failure."
                ) {
                    VStack(alignment: .leading, spacing: 9) {
                        AinkradCaptionedRow("Play a sound") {
                            AinkradToggle(isOn: Binding(
                                get: { sounds.settings.isEnabled },
                                set: { sounds.settings.isEnabled = $0 }))
                        }
                        AinkradCaptionedRow("Volume") {
                            AinkradSlider(value: Binding(
                                get: { sounds.settings.volume },
                                set: { sounds.settings.volume = $0 }), in: 0...1)
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
                        // A count is a readout, so mono.
                        Text("\(center.eventCount) events stored")
                            .font(AinkradFont.mono(10.5))
                            .foregroundStyle(theme.foreground.opacity(0.5))
                        Spacer()
                        AinkradButton(title: "Clear feed", style: .danger) {
                            confirmingClear = true
                        }
                    }
                }
            }


            // Only when something has asked. An empty permissions panel on
            // every install teaches the user that this section is furniture,
            // and then they stop reading it on the day it matters.
            if !subscriptionRows.isEmpty {
                AinkradSettingsPanel(
                    title: "Cross-app access",
                    hint: "Apps that asked to read another app's notifications. "
                        + "Revoking takes effect immediately; the app keeps working."
                ) {
                    SubscriptionSettingsSection(rows: subscriptionRows,
                                                displayName: displayName,
                                                onApprove: onApproveSubscriptions,
                                                onRevoke: onRevokeSubscriptions)
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
