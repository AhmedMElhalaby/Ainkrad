import Foundation
import Testing
@testable import Ainkrad

@Suite("Setup validation")
struct SetupValidationTests {
    @Test func theYouStepRequiresNameAndRole() {
        #expect(!SetupValidation.canAdvance(from: .you, values: [:]))
        #expect(!SetupValidation.canAdvance(from: .you, values: ["name": "Ahmed"]))
        #expect(SetupValidation.canAdvance(from: .you, values: ["name": "Ahmed", "role": "Engineer"]))
    }

    @Test func whitespaceIsNotAValue() {
        #expect(!SetupValidation.canAdvance(from: .you, values: ["name": "  ", "role": "\n"]))
    }

    @Test func unmetRequirementsNameTheFieldAndExplain() {
        let unmet = SetupValidation.unmet(for: .you, values: ["role": "Engineer"])
        #expect(unmet.map(\.field) == ["name"])
        #expect(!(unmet.first?.message.isEmpty ?? true))
    }

    /// Timezone is prefilled from `TimeZone.current`, but a user may clear it —
    /// it must never be what stands between them and Continue.
    @Test func timezoneIsNotRequired() {
        #expect(SetupValidation.canAdvance(from: .you,
                                           values: ["name": "Ahmed", "role": "Engineer",
                                                    "timezone": ""]))
    }

    // A custom persona is only required to be complete if the user chose one.
    @Test func theAssistantStepOnlyRequiresACustomPersonaWhenCustom() {
        #expect(SetupValidation.canAdvance(from: .assistant, values: [:]))
        #expect(!SetupValidation.canAdvance(from: .assistant,
                                            values: ["isCustom": "true", "personaName": "Scribe"]))
        #expect(SetupValidation.canAdvance(from: .assistant,
                                           values: ["isCustom": "true", "personaName": "Scribe",
                                                    "personaInstructions": "Be terse."]))
    }

    @Test func theAssistantStepNamesBothMissingCustomFields() {
        let unmet = SetupValidation.unmet(for: .assistant, values: ["isCustom": "true"])
        #expect(unmet.map(\.field) == ["personaName", "personaInstructions"])
    }

    // Appearance and Motion apply live defaults, so they are never blocking.
    @Test func stepsWithLiveDefaultsNeverBlock() {
        for step in [SetupStep.welcome, .appearance, .motionAndSound, .done] {
            #expect(SetupValidation.canAdvance(from: step, values: [:]))
            #expect(SetupValidation.unmet(for: step, values: [:]).isEmpty)
        }
    }

    /// Home and Providers enforce their requirement structurally (a vault must
    /// be adopted; a connection must pass a live probe), so the dictionary has
    /// no field-level rule to add for them.
    @Test func structurallyEnforcedStepsHaveNoFieldRules() {
        for step in [SetupStep.home, .providers] {
            #expect(SetupValidation.unmet(for: step, values: [:]).isEmpty)
        }
    }
}
