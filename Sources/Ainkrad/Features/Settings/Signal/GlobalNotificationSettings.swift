import SwiftUI
import AinkradAppKit
import AinkradHostRuntime
import AinkradSignal

/// An ad-hoc quiet spell, and the only place its durations are written down.
///
/// The dropdown used to offer one hour, Settings offered one hour or until
/// tomorrow, and the overlay offered nothing — the same action with three
/// different answers depending on where the user happened to be standing.
/// Every surface now renders THIS, in whatever chrome suits it.
enum SignalSnooze: String, CaseIterable, Identifiable {
    case hour
    case tomorrow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hour: return "Quiet for an hour"
        case .tomorrow: return "Quiet until tomorrow"
        }
    }

    /// When this snooze would end, starting now.
    ///
    /// `tomorrow` is 08:00 the next day — "until tomorrow" means until the
    /// working day, not until midnight, which would end it in the middle of
    /// the night.
    func until(after now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .hour:
            return now.addingTimeInterval(3600)
        case .tomorrow:
            let next = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: next) ?? next
        }
    }

    /// Writes into the SAME field quiet hours reads, so the two can never
    /// disagree about whether now is quiet.
    func apply(to suppression: inout SuppressionWindow,
               at now: Date, calendar: Calendar = .current) {
        suppression.snoozedUntil = until(after: now, calendar: calendar)
    }

    /// Ends the snooze and nothing else. A user ending an ad-hoc quiet spell
    /// has not asked to be woken at 3am, so the schedule survives.
    static func lift(_ suppression: inout SuppressionWindow) {
        suppression.snoozedUntil = nil
    }
}

/// The settings that are not per-source: the global off switch, quiet hours,
/// and sound.
struct GlobalNotificationSettings: View {
    @Binding var rules: RoutingRules
    /// Nil in a snapshot, where there is no bootstrap and so no engine.
    var sounds: NotificationSoundStore?
    var now: Date = Date()

    @Environment(\.ainkradTheme) private var theme

    private static let hourOptions: [Int] = Array(0...23)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            quietHours
            if let sounds { sound(sounds) }
        }
    }

    private var quietHours: some View {
        AinkradSettingsPanel(
            title: "Quiet hours",
            hint: "A window when nothing interrupts. Events are still recorded, and "
                + "unread counts still move — quiet hours defer interruptions, they "
                + "do not lose information."
        ) {
            VStack(alignment: .leading, spacing: 9) {
                AinkradCaptionedRow("Schedule") {
                    AinkradToggle(isOn: Binding(
                        get: { rules.suppression.quietStartMinute != nil },
                        set: { on in
                            // Both ends together: a start with no end is a
                            // half-finished setting, and `SuppressionWindow`
                            // deliberately ignores one, so writing only the
                            // start would look like a broken control.
                            rules.suppression.quietStartMinute = on ? 22 * 60 : nil
                            rules.suppression.quietEndMinute = on ? 7 * 60 : nil
                        }))
                }
                if rules.suppression.quietStartMinute != nil {
                    AinkradCaptionedRow("From") { hourPicker(\.quietStartMinute) }
                    AinkradCaptionedRow("Until") { hourPicker(\.quietEndMinute) }
                    AinkradCaptionedRow("During quiet hours") {
                        AinkradSelect(
                            items: [SuppressionWindow.Mode.everything, .soundOnly],
                            selection: Binding(get: { rules.suppression.mode },
                                               set: { rules.suppression.mode = $0 }),
                            label: { $0.label })
                    }
                }
                snoozeRow
            }
        }
    }

    /// Ad-hoc mute, in the same panel as the schedule because they are the same
    /// concept — `SuppressionWindow` stores both.
    private var snoozeRow: some View {
        HStack(spacing: AinkradSpacing.sm) {
            if let until = rules.suppression.snoozedUntil, until > now {
                Text("Quiet until \(Self.timeFormatter.string(from: until))")
                    .font(AinkradFont.mono(10.5))
                    .foregroundStyle(theme.accentSecondary)
                Spacer()
                AinkradButton(title: "Resume now", style: .ghost) {
                    SignalSnooze.lift(&rules.suppression)
                }
            } else {
                Spacer()
                ForEach(SignalSnooze.allCases) { snooze in
                    AinkradButton(title: snooze.label, style: .ghost) {
                        snooze.apply(to: &rules.suppression, at: now)
                    }
                }
            }
        }
    }

    private func sound(_ sounds: NotificationSoundStore) -> some View {
        AinkradSettingsPanel(
            title: "Sound",
            hint: "Separate from interface sounds — turning those off in General will "
                + "not silence a failure."
        ) {
            VStack(alignment: .leading, spacing: 9) {
                AinkradCaptionedRow("Play a sound") {
                    AinkradToggle(isOn: Binding(get: { sounds.settings.isEnabled },
                                                set: { sounds.settings.isEnabled = $0 }))
                }
                AinkradCaptionedRow("Volume") {
                    AinkradSlider(value: Binding(get: { sounds.settings.volume },
                                                 set: { sounds.settings.volume = $0 }),
                                  in: 0...1)
                }
            }
        }
    }

    private func hourPicker(_ key: WritableKeyPath<SuppressionWindow, Int?>) -> some View {
        AinkradSelect(
            items: Self.hourOptions,
            selection: Binding(
                get: { (rules.suppression[keyPath: key] ?? 0) / 60 },
                set: { rules.suppression[keyPath: key] = $0 * 60 }),
            label: { String(format: "%02d:00", $0) })
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

private extension SuppressionWindow.Mode {
    var label: String {
        switch self {
        case .everything: return "Nothing interrupts"
        case .soundOnly: return "Silent, but still visible"
        // Resilient enum from a library-evolution module: a mode added to the
        // SDK later must render rather than fail to build.
        @unknown default: return "Nothing interrupts"
        }
    }
}
