import Foundation

/// Per-step required fields.
///
/// Required means *Continue is disabled and the reason is visible beside the
/// field* — never a silent no-op. A disabled button at the other end of the
/// screen with nothing explaining it is the failure mode this exists to
/// prevent, so every rule here carries user-facing copy, not just a Bool.
///
/// Steps whose controls all have real defaults already applied live
/// (Appearance, Motion & Sound) are deliberately never blocking: there is
/// nothing for the user to supply. Home and Providers enforce their
/// requirement structurally — a vault must be adopted, a connection must pass
/// a live probe — so they have no field-level rule here either.
///
/// The `[String: String]` shape keeps this pure and testable: no SwiftUI, no
/// stores. Each step's view builds the dictionary from its own `@State` (the
/// Assistant step's `isCustom` lives in the view, and arrives here as
/// `"isCustom": "true"`).
enum SetupValidation {
    struct Requirement: Equatable {
        let field: String
        let message: String
    }

    static func unmet(for step: SetupStep, values: [String: String]) -> [Requirement] {
        func blank(_ key: String) -> Bool {
            (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        switch step {
        case .you:
            var unmet: [Requirement] = []
            if blank("name") {
                unmet.append(Requirement(field: "name",
                                         message: "Your assistant needs something to call you."))
            }
            if blank("role") {
                unmet.append(Requirement(field: "role",
                                         message: "What you do shapes how the assistant helps."))
            }
            // `timezone` is prefilled from `TimeZone.current` but deliberately
            // not required: a user may clear it, and being unable to continue
            // because of a field they never typed in would be absurd.
            return unmet

        case .assistant:
            guard values["isCustom"] == "true" else { return [] }
            var unmet: [Requirement] = []
            if blank("personaName") {
                unmet.append(Requirement(field: "personaName", message: "Give your assistant a name."))
            }
            if blank("personaInstructions") {
                unmet.append(Requirement(field: "personaInstructions",
                                         message: "Describe how it should work."))
            }
            return unmet

        // Home and Providers enforce their own requirement structurally — a vault
        // must be adopted, and a connection must pass a live probe — so there is
        // no field-level rule to add here.
        case .welcome, .home, .appearance, .motionAndSound, .providers, .done:
            return []
        }
    }

    static func canAdvance(from step: SetupStep, values: [String: String]) -> Bool {
        unmet(for: step, values: values).isEmpty
    }
}
