import Testing
@testable import Ainkrad
import AinkradAppKitContract

@Suite("Settings path migration")
@MainActor
struct SettingsPathMigrationTests {
    @Test("retired paths resolve forward to their new homes")
    func retiredPathsResolve() {
        let cases: [(String, String)] = [
            ("workspace.livingSky",            "workspace.appearance"),
            ("workspace.appIcon",              "workspace.appearance"),
            ("workspace.sound",                "workspace.soundAndVoice"),
            ("workspace.shortcuts",            "workspace.keyboard"),
            ("assistant.models",               "intelligence.model"),
            ("assistant.access",               "intelligence.permissions"),
            ("assistant.data",                 "intelligence.privacy"),
            ("assistant.web",                  "intelligence.tools"),
            ("assistant.voice",                "workspace.soundAndVoice"),
            ("workspace.mcp",                  "intelligence.tools"),
            ("workspace.lsp",                  "intelligence.tools"),
            ("workspace.skills",               "intelligence.skills"),
            ("workspace.memory",               "intelligence.memory")
        ]
        for (old, new) in cases {
            let resolved = SettingsPathAliases.resolve(SettingsPath(rawValue: old)!)
            #expect(resolved.rawValue == new, "\(old) resolved to \(resolved.rawValue)")
        }
    }

    @Test("a current path resolves to itself")
    func currentPathsAreStable() {
        let current = SettingsPath(rawValue: "intelligence.tools")!
        #expect(SettingsPathAliases.resolve(current) == current)
    }

    @Test("every alias target exists in the live catalog")
    func aliasTargetsAreReal() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        for target in SettingsPathAliases.allTargets {
            #expect(catalog.page(containing: target) != nil, "\(target) is a dangling alias")
        }
    }

    @Test("the navigator follows aliases")
    func navigatorFollowsAliases() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        let navigator = SettingsNavigator(initial: SettingsPath(["workspace", "general"]))
        navigator.navigate(to: SettingsPath(rawValue: "workspace.livingSky")!, in: catalog)
        #expect(navigator.selection.rawValue == "workspace.appearance")
    }
}
