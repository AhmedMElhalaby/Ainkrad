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

    @Test("quantize rounds to the nearest step, clamps to range, and passes through when step <= 0")
    func quantize() {
        // A value between two steps rounds to the nearer one.
        #expect(SettingsRow.quantize(12.0, step: 5, range: 0...100) == 10.0)
        #expect(SettingsRow.quantize(13.0, step: 5, range: 0...100) == 15.0)

        // A value below lowerBound clamps up.
        #expect(SettingsRow.quantize(-10.0, step: 5, range: 0...100) == 0.0)

        // A value above upperBound clamps down.
        #expect(SettingsRow.quantize(999.0, step: 5, range: 0...100) == 100.0)

        // step: 0 (and negative) passes the value through untouched, still
        // clamped to range — no divide-by-zero, no hang.
        #expect(SettingsRow.quantize(42.3, step: 0, range: 0...100) == 42.3)
        #expect(SettingsRow.quantize(42.3, step: -1, range: 0...100) == 42.3)
        #expect(SettingsRow.quantize(-5.0, step: 0, range: 0...100) == 0.0)
        #expect(SettingsRow.quantize(500.0, step: 0, range: 0...100) == 100.0)

        // A range that doesn't start at zero snaps relative to lowerBound,
        // not zero: 10...50 with step 5 must land on 10, 15, 20, ... never
        // on multiples of 5 measured from 0.
        #expect(SettingsRow.quantize(12.0, step: 5, range: 10...50) == 10.0)
        #expect(SettingsRow.quantize(13.0, step: 5, range: 10...50) == 15.0)
        #expect(SettingsRow.quantize(11.0, step: 5, range: 11...51) == 11.0)
    }
}
