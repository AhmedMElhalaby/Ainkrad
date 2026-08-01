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

/// The "You" step: who the user is, in the assistant's own words.
///
/// Name and role ARE required — this reverses the step's original "everything
/// is optional" design at the product owner's decision, because an assistant
/// with no idea who it works for is the thing first-run exists to prevent. The
/// rules live in `SetupValidation`, and each unmet one is rendered beneath its
/// own field, not only as a disabled Continue. "What to call you" and
/// "Timezone" stay optional; timezone in particular is merely prefilled, and a
/// user who clears it must still be able to continue.
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
    @Environment(\.setupGroupWidth) private var groupWidth

    let coordinator: SetupCoordinator

    @State private var name = ""
    @State private var callMe = ""
    @State private var role = ""
    @State private var timezone = TimeZone.current.identifier
    /// Fields the user has typed in. A requirement note appears only for a
    /// field they have touched — see `message(for:)`.
    @State private var touched: Set<String> = []
    /// Which fields this step requires, asked of `SetupValidation` with every
    /// value blank so the answer is "what is required", not "what is missing".
    /// Derived rather than hardcoded: a rule added to `SetupValidation` shows
    /// up here without touching this view.
    private static let requiredFields = Set(
        SetupValidation.unmet(for: .you, values: [:]).map(\.field))

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro(tokens: tokens)
                    AinkradSettingsPanel(
                        title: "About you",
                        hint: "Saved as you type — all of it stays editable later in Memory."
                    ) {
                        fieldGrid(tokens: tokens)
                    }
                }
                .padding(20)
                // FILLS the group, like every other step. The FIELDS are what
                // hold their own width — see `fieldGrid`.
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SetupStepFooter(coordinator: coordinator,
                            isPrimaryDisabled: !unmet.isEmpty) {
                commit()
                coordinator.advance()
            }
        }
        .onAppear { write(timezone, for: "timezone") }
    }

    /// The rules live in `SetupValidation` so the next change to them is one
    /// file, not a `.disabled(...)` condition buried in this view.
    private var unmet: [SetupValidation.Requirement] {
        SetupValidation.unmet(for: .you, values: [
            "name": name, "callMe": callMe, "role": role, "timezone": timezone,
        ])
    }

    /// The warning for `key`, shown only once the user has typed in that field
    /// and left it blank.
    ///
    /// Shown unconditionally, a first-time user arrives to two warnings about
    /// fields they have not yet been given the chance to answer, which reads as
    /// an error state on a blank form. What keeps the reason visible from
    /// arrival instead is the persistent "Required" marker beside those fields
    /// — a statement of the rule rather than an accusation. The warning is the
    /// escalation when the rule has actually been broken.
    ///
    /// Either way Continue stays disabled the whole time: this gates the note,
    /// never the gate.
    private func message(for key: String) -> String? {
        guard touched.contains(key) else { return nil }
        return unmet.first { $0.field == key }?.message
    }

    private func intro(tokens: DesignTokens) -> some View {
        Text("Anything you fill in here goes into the assistant's memory, so it knows who "
             + "it's working with. Your name and role are needed so it knows who it is "
             + "working for; the rest is optional, and all of it is editable later in "
             + "Memory.")
            .font(AinkradFont.display(12))
            .foregroundStyle(tokens.foreground.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
            // Prose is capped even though the column fills.
            .frame(maxWidth: SetupStageLayout.readingWidth(inGroupOf: groupWidth),
                   alignment: .leading)
    }

    /// The four fields, each one full width, stacked.
    ///
    /// A single column by decision, not by default: an adaptive two-column grid
    /// was tried and rejected. One field per row keeps the form a single
    /// top-to-bottom sequence — there is no reading order to work out, and the
    /// labels all start on the same left edge.
    ///
    /// The cards therefore take the whole column, which on a wide window means a
    /// wide text field. That is the accepted trade.
    private func fieldGrid(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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

    private func field(tokens: DesignTokens, title: String, subtitle: String,
                       placeholder: String, text: Binding<String>, key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                // Visible from arrival, for required fields only. This is what
                // keeps the rule on screen without greeting a blank form with
                // warnings — see `message(for:)`.
                if Self.requiredFields.contains(key) {
                    Text("Required")
                        .font(AinkradFont.display(9, weight: .medium)).kerning(0.5)
                        .foregroundStyle(tokens.accentTertiary)
                        .accessibilityIdentifier("setup.you.\(key).required")
                }
                Spacer(minLength: 0)
            }
            Text(subtitle)
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.5))
            AinkradTextField(text: text, placeholder: placeholder)
                .onChange(of: text.wrappedValue) { _, new in
                    touched.insert(key)
                    write(new, for: key)
                }
            // Beside the field it is about, not only at the Continue button.
            if let message = message(for: key) {
                SetupRequirementNote(message: message, tokens: tokens)
                    .accessibilityIdentifier("setup.you.\(key).requirement")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
