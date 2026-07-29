import Testing
import AinkradAppKit
import AinkradAppKitContract

@Suite("SettingsRow layout")
@MainActor
struct SettingsRowTests {
    @Test("layout is side-by-side only above the wide breakpoint")
    func layoutForWidth() {
        #expect(SettingsRowLayout(detailWidth: 500) == .stacked)
        #expect(SettingsRowLayout(detailWidth: 899) == .stacked)
        #expect(SettingsRowLayout(detailWidth: 901) == .sideBySide)
    }

    @Test("badges reflect the field's flags")
    func badges() {
        let path = SettingsPath(["a", "b", "c"])
        let plain = SettingsField(path: path, label: "Plain", kind: .toggle(.constant(false)))
        #expect(SettingsRow.badges(for: plain).isEmpty)

        let flagged = SettingsField(path: path, label: "Flagged", kind: .toggle(.constant(false)),
                                    isAdvanced: true, requiresRestart: true)
        #expect(SettingsRow.badges(for: flagged) == ["Advanced", "Restart required"])
    }

    @Test("the revert affordance appears only for a modified field with a reset")
    func revertVisibility() {
        let path = SettingsPath(["a", "b", "c"])
        let modified = SettingsField(path: path, label: "X", kind: .toggle(.constant(false)),
                                     isModified: { true }, reset: {})
        let unmodified = SettingsField(path: path, label: "X", kind: .toggle(.constant(false)),
                                       isModified: { false }, reset: {})
        let noReset = SettingsField(path: path, label: "X", kind: .toggle(.constant(false)),
                                    isModified: { true })
        #expect(SettingsRow.showsRevert(for: modified))
        #expect(!SettingsRow.showsRevert(for: unmodified))
        #expect(!SettingsRow.showsRevert(for: noReset))
    }
}
