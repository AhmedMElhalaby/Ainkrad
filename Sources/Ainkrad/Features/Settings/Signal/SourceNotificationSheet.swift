import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// Full notification control for ONE source — an app, Host, or Sage.
///
/// The same sheet for every source, deliberately: one shape the user learns
/// once, instead of Host being a special case with two toggles while the apps
/// that actually generate the noise have none.
///
/// Takes everything as parameters and reaches for no environment, so it renders
/// in a snapshot. `SignalFeedOverlayView`'s comment records what happens
/// otherwise — a view that reaches for the whole environment crashed the
/// snapshot runner, and the run then reported "passed" for the tests that had
/// already finished.
struct SourceNotificationSheet: View {
    let source: SignalSource
    let sourceName: String
    @Binding var rules: RoutingRules
    /// What this source has actually emitted. Empty is a legitimate state —
    /// a source can be configurable before it has ever spoken.
    var activity: [SignalKindActivity] = []

    @Environment(\.ainkradTheme) private var theme

    /// Wide enough for the longer of the two segment labels at its heaviest
    /// weight, so no row is clipped and none is ragged. Narrower since the
    /// labels became "Alert" and "Quiet" — 190 was sized for "Everything" and
    /// "Feed only", and left the column floating well clear of its rows.
    private static let kindPickerWidth: CGFloat = 124

    private var mode: SignalDeliveryMode {
        SignalDeliveryMode(rules: rules, source: source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            delivery
            // Everything below is meaningless once the source is off, so it
            // goes away rather than sitting there inert and inviting the user
            // to configure something that cannot happen.
            if mode != .off {
                interruption
                if !activity.isEmpty { kinds }
            }
        }
    }

    private var delivery: some View {
        // No hint here any more: it repeated the pane's own caption word for
        // word, one panel below it.
        AinkradSettingsPanel(title: "\(sourceName) notifications") {
            AinkradCaptionedRow("Delivery") {
                AinkradSegmentedPicker(
                    items: SignalDeliveryMode.allCases,
                    selection: Binding(get: { mode },
                                       set: { $0.apply(to: &rules, source: source) }),
                    label: \.label)
            }
        }
    }

    private var interruption: some View {
        AinkradSettingsPanel(
            title: "Interruptions",
            hint: "Below the floor, events go quiet — recorded, never interrupting."
        ) {
            VStack(alignment: .leading, spacing: 9) {
                AinkradCaptionedRow("Interrupt me at") {
                    AinkradSelect(
                        items: SignalSeverity.allCases,
                        selection: Binding(
                            get: { rules.interruptFloor[source] ?? .info },
                            set: { floor in
                                // `.info` is the absence of a floor, not a
                                // floor at the bottom: storing it would freeze
                                // an opinion where the user expressed none.
                                rules.interruptFloor[source] = floor == .info ? nil : floor
                            }),
                        label: { $0.floorLabel })
                }
                AinkradCaptionedRow("Sound") {
                    AinkradSelect(
                        items: SignalSoundChoice.offered,
                        selection: Binding(
                            get: { rules.soundOverride[source] ?? .bySeverity },
                            set: { choice in
                                rules.soundOverride[source] =
                                    choice == .bySeverity ? nil : choice
                            }),
                        label: { $0.label })
                }
                AinkradCaptionedRow("Let urgent through quiet hours and Focus") {
                    AinkradToggle(isOn: Binding(
                        get: { rules.urgentBypass.contains(source) },
                        set: { allowed in
                            if allowed { rules.urgentBypass.insert(source) }
                            else { rules.urgentBypass.remove(source) }
                        }))
                }
                AinkradCaption("Only events the app marks urgent — something waiting "
                               + "on you, not its usual chatter.")
            }
        }
    }

    /// The centrepiece. Every kind this source has emitted, noisiest first,
    /// each with the same three-state control as the source itself.
    ///
    /// The list is discovered from the feed, so a kind an app starts emitting
    /// tomorrow appears on its own. A hand-maintained list would go stale the
    /// first time that happened, and the user would be unable to silence the
    /// one thing actually bothering them.
    private var kinds: some View {
        AinkradSettingsPanel(
            title: "What \(sourceName) tells you",
            hint: "Noisiest first. Quiet keeps a kind in the feed without interrupting."
        ) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(activity) { entry in
                    HStack(spacing: AinkradSpacing.sm) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.kind)
                                .font(AinkradFont.mono(11))
                                .foregroundStyle(theme.foreground)
                            Text(entry.count == 1 ? "once" : "\(entry.count) times")
                                .font(AinkradFont.mono(9.5))
                                .foregroundStyle(theme.foreground.opacity(0.45))
                        }
                        Spacer(minLength: AinkradSpacing.sm)
                        AinkradSegmentedPicker(
                            items: SignalDeliveryMode.kindOptions,
                            selection: Binding(
                                get: { SignalDeliveryMode(rules: rules,
                                                          source: source, kind: entry.kind) },
                                set: { $0.apply(to: &rules, source: source, kind: entry.kind) }),
                            label: \.label)
                        // Fixed, because the control sizes to its content and
                        // the SELECTED segment is heavier — so an unconstrained
                        // column of these is ragged at both edges, with each
                        // row's width depending on what it happens to be set
                        // to. It reads as a rendering fault rather than a list.
                        .frame(width: Self.kindPickerWidth, alignment: .trailing)
                    }
                }
            }
        }
    }
}

private extension SignalSeverity {
    /// Phrased as the floor it sets, not as the severity it names — the row
    /// reads "Interrupt me at: anything", not "Interrupt me at: info".
    var floorLabel: String {
        switch self {
        case .info: return "Anything"
        case .success: return "Success and above"
        case .warning: return "Warnings and failures"
        case .failure: return "Failures only"
        @unknown default: return "Anything"
        }
    }
}

private extension SignalSoundChoice {
    /// The cues offered today. `named` carries the host's own asset name, so
    /// this list grows when the notification cue family lands without the SDK
    /// needing to know any of them.
    static var offered: [SignalSoundChoice] {
        [.bySeverity, .silent, .named(UISound.confirm.rawValue),
         .named(UISound.error.rawValue)]
    }

    var label: String {
        switch self {
        case .bySeverity: return "Match severity"
        case .silent: return "Silent"
        case .named(let name):
            return UISound(rawValue: name)?.displayName ?? name
        // Resilient enum in a library-evolution module: a cue kind added to
        // the SDK later must render as something rather than failing to build.
        @unknown default:
            return "Match severity"
        }
    }
}
