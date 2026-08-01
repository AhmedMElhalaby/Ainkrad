import Testing
import SwiftUI
import AinkradAppKit
@testable import Ainkrad

@MainActor
@Suite("Files appearance and settings")
struct FilesAppearanceTests {
    @Test("opaque at full opacity means no fill, so no backdrop is rendered")
    func opaqueYieldsNoFill() {
        #expect(FilesApp.surfaceFill(opacity: 1.0, base: .black) == nil)
    }

    @Test("sub-opaque yields a translucent fill, which drives the island backdrop")
    func translucentYieldsFill() {
        let fill = FilesApp.surfaceFill(opacity: 0.6, base: .black)
        #expect(fill != nil)
        // `BlockView.isTranslucentPane` and `TileLayoutView.hasTranslucentPane`
        // both branch on this alpha being < 1.
        #expect(NSColor(fill!).alphaComponent < 1)
    }

    @Test("settings declare real fields, not a wrapped view")
    func settingsAreDeclaredFields() {
        let environment = AppEnvironment.preview()
        let groups = FilesSettingsCatalog.groups(
            root: SettingsPath(["app", FilesApp.id]), environment: environment)

        let fields = groups.flatMap(\.fields)
        #expect(!fields.isEmpty)
        // The whole point: zero `.custom` fields, so Files doesn't push the
        // wrap-a-view ratchet in SettingsKitCompositionTests.
        let customCount = fields.filter {
            if case .custom = $0.kind { return true }
            return false
        }.count
        #expect(customCount == 0)
    }

    @Test("settings cover transparency, typography and icon size")
    func settingsCoverage() {
        let environment = AppEnvironment.preview()
        let groups = FilesSettingsCatalog.groups(
            root: SettingsPath(["app", FilesApp.id]), environment: environment)
        let labels = groups.flatMap(\.fields).map(\.label)

        #expect(labels.contains("Transparency"))
        #expect(labels.contains("Font"))
        #expect(labels.contains("Font size"))
        #expect(labels.contains("Icon size"))
    }

    @Test("icon size clamps to a usable range")
    func iconSizeClamps() {
        let environment = AppEnvironment.preview()
        let store = environment.filesSettingsStore
        store.iconSize = 500
        #expect(store.iconSize == 22)
        store.iconSize = 0
        #expect(store.iconSize == 10)
        store.iconSize = 13
        #expect(store.iconSize == 13)
    }

    @Test("row padding scales with icon size so density stays coherent")
    func rowPaddingFollowsIconSize() {
        let environment = AppEnvironment.preview()
        let store = environment.filesSettingsStore
        store.iconSize = 10
        let small = store.rowVerticalPadding
        store.iconSize = 22
        #expect(store.rowVerticalPadding > small)
    }
}
