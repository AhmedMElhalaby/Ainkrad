import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// Writes the You step into the profile store, which projects into `USER.md` so
/// the assistant can read it. Blank fields are omitted rather than stored empty:
/// an empty fact would still be projected as `- role: ` and read as a fact.
///
/// The keys (`name`, `callMe`, `role`, `timezone`) are a contract — they are
/// what the assistant sees in `USER.md`, not an implementation detail.
@MainActor
enum SetupYou {
    static func apply(name: String, callMe: String, role: String, timezone: String,
                      store: UserProfileStore) {
        let fields = ["name": name, "callMe": callMe, "role": role, "timezone": timezone]
        for (key, value) in fields {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            store.set(trimmed, for: key)
        }
    }
}

/// The "You" step: who the user is, in the assistant's own words. Nothing here
/// is required — Continue is never blocked, and a user may pass through with
/// every field blank.
///
/// Each field commits on change (no Save button, no draft state), matching the
/// rest of the wizard and Settings. A field cleared back to blank leaves the
/// previously written fact in place rather than storing an empty one: this step
/// is additive, and editing/removing profile facts is a Memory concern, not a
/// first-run one.
///
/// Timezone is prefilled with `TimeZone.current.identifier` and written on
/// appear — a prefill, not a blank, so it lands in `USER.md` for the common
/// case where the user simply continues.
struct SetupYouStepView: View {
    @Environment(AppEnvironment.self) private var environment

    let coordinator: SetupCoordinator

    @State private var name = ""
    @State private var callMe = ""
    @State private var role = ""
    @State private var timezone = TimeZone.current.identifier

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro(tokens: tokens)
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsSectionHeader(title: "ABOUT YOU", tokens: tokens)
                        field(tokens: tokens, title: "Name",
                              subtitle: "Your full name.",
                              placeholder: "Ada Lovelace",
                              text: $name, key: "name")
                        field(tokens: tokens, title: "What to call you",
                              subtitle: "How the assistant addresses you.",
                              placeholder: "Ada",
                              text: $callMe, key: "callMe")
                        field(tokens: tokens, title: "Role",
                              subtitle: "What you do — it shapes the assistant's defaults.",
                              placeholder: "Engineer",
                              text: $role, key: "role")
                        field(tokens: tokens, title: "Timezone",
                              subtitle: "Used for scheduling and time-aware answers.",
                              placeholder: TimeZone.current.identifier,
                              text: $timezone, key: "timezone")
                    }
                }
                .padding(20)
            }

            HStack {
                Spacer(minLength: 0)
                AinkradButton(title: "Continue", style: .primary) {
                    commit()
                    coordinator.advance()
                }
            }
            .padding(20)
        }
        .onAppear { write(timezone, for: "timezone") }
    }

    private func intro(tokens: DesignTokens) -> some View {
        Text("Anything you fill in here goes into the assistant's memory, so it knows who "
             + "it's working with. All of it is optional, and all of it is editable later "
             + "in Memory.")
            .font(AinkradFont.display(12))
            .foregroundStyle(tokens.foreground.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func field(tokens: DesignTokens, title: String, subtitle: String,
                       placeholder: String, text: Binding<String>, key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AinkradFont.display(13, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.9))
            Text(subtitle)
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.5))
            AinkradTextField(text: text, placeholder: placeholder)
                .onChange(of: text.wrappedValue) { _, new in write(new, for: key) }
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }

    /// Belt-and-braces: `onChange` already commits every keystroke, but a field
    /// left mid-composition when Continue is hit must not be lost.
    private func commit() {
        SetupYou.apply(name: name, callMe: callMe, role: role, timezone: timezone,
                       store: environment.userProfileStore)
    }

    private func write(_ value: String, for key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        environment.userProfileStore.set(trimmed, for: key)
    }
}
