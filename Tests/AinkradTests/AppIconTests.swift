import Testing
import Foundation
@testable import Ainkrad

struct ThemeIconFamilyTests {
    @Test("every theme maps to its locked icon color family")
    func families() {
        #expect(Theme.neonBlue.iconColorFamily      == .blue)
        #expect(Theme.cyberPurple.iconColorFamily   == .purple)
        #expect(Theme.dracula.iconColorFamily       == .purple)
        #expect(Theme.nord.iconColorFamily          == .blue)
        #expect(Theme.tokyoNight.iconColorFamily    == .blue)
        #expect(Theme.gruvbox.iconColorFamily       == .blue)
        #expect(Theme.solarizedDark.iconColorFamily == .blue)
    }
}

struct AppIconResolverTests {
    @Test("color resolves auto→theme family, else the explicit color")
    func color() {
        #expect(AppIconResolver.color(for: .auto, theme: .cyberPurple) == .purple)
        #expect(AppIconResolver.color(for: .auto, theme: .neonBlue)    == .blue)
        #expect(AppIconResolver.color(for: .blue, theme: .cyberPurple) == .blue)
        #expect(AppIconResolver.color(for: .purple, theme: .neonBlue)  == .purple)
    }

    @Test("isDark: system passes through, light/dark pin")
    func isDark() {
        #expect(AppIconResolver.isDark(.system, systemDark: true)  == true)
        #expect(AppIconResolver.isDark(.system, systemDark: false) == false)
        #expect(AppIconResolver.isDark(.light, systemDark: true)   == false)
        #expect(AppIconResolver.isDark(.dark,  systemDark: false)  == true)
    }

    @Test("resourceName composes color + appearance into the bundled name")
    func resourceName() {
        #expect(AppIconResolver.resourceName(for: .auto, theme: .cyberPurple, appearance: .system, systemDark: true) == "purple-dark")
        #expect(AppIconResolver.resourceName(for: .auto, theme: .neonBlue, appearance: .light, systemDark: true) == "blue-light")
        #expect(AppIconResolver.resourceName(for: .blue, theme: .dracula, appearance: .dark, systemDark: false) == "blue-dark")
        #expect(AppIconResolver.resourceName(for: .purple, theme: .neonBlue, appearance: .system, systemDark: false) == "purple-light")
    }

    @Test("every (choice,appearance) resolves to a bundled .icns")
    func allBundled() {
        for choice in AppIconChoice.allCases {
            for appearance in AppIconAppearance.allCases {
                for dark in [true, false] {
                    let name = AppIconResolver.resourceName(for: choice, theme: .neonBlue, appearance: appearance, systemDark: dark)
                    #expect(Bundle.main.url(forResource: name, withExtension: "icns") != nil, "missing \(name).icns")
                }
            }
        }
    }
}

struct GlobalSettingsAppIconTests {
    @Test("fresh defaults: color auto, appearance system")
    func defaults() {
        let s = GlobalSettings()
        #expect(s.appIconChoice == .auto)
        #expect(s.appIconAppearance == .system)
    }

    @Test("round-trips both fields")
    func roundTrip() throws {
        var s = GlobalSettings()
        s.appIconChoice = .purple
        s.appIconAppearance = .dark
        let back = try JSONDecoder().decode(GlobalSettings.self, from: try JSONEncoder().encode(s))
        #expect(back.appIconChoice == .purple)
        #expect(back.appIconAppearance == .dark)
    }

    @Test("a v1 doc (appIconChoice only) decodes: choice preserved, appearance defaults to system")
    func legacyV1Decodes() throws {
        let legacy = Data(#"{"theme":"neonBlue","appIconChoice":"blue"}"#.utf8)
        let s = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(s.appIconChoice == .blue)
        #expect(s.appIconAppearance == .system)
    }
}

// A type whose bundle is the host app module, so tests can find app resources.
final class AinkradBundleToken {}

// TODO(v2 Task 2): rewritten in Task 2
// @MainActor
// private final class FakeApplier: AppIconApplying {
//     private(set) var applied: [AppIconChoice] = []
//     func apply(_ choice: AppIconChoice) { applied.append(choice) }
// }

// TODO(v2 Task 2): rewritten in Task 2
// @MainActor
// struct AppIconStoreTests {
//     @Test("loads the persisted choice")
//     func loads() {
//         let p = InMemoryPersistenceStore()
//         p.save(GlobalSettings(theme: .neonBlue, appIconChoice: .purple))
//         let store = AppIconStore(persistence: p, applier: FakeApplier())
//         #expect(store.choice == .purple)
//     }
//
//     @Test("select persists the choice (preserving theme) and applies it")
//     func select() {
//         let p = InMemoryPersistenceStore()
//         p.save(GlobalSettings(theme: .dracula, appIconChoice: .blue))
//         let applier = FakeApplier()
//         let store = AppIconStore(persistence: p, applier: applier)
//         store.select(.purple)
//         #expect(store.choice == .purple)
//         #expect(p.load(GlobalSettings.self)?.appIconChoice == .purple)
//         #expect(p.load(GlobalSettings.self)?.theme == .dracula)   // theme preserved
//         #expect(applier.applied.last == .purple)
//     }
//
//     @Test("applyCurrent applies the loaded choice")
//     func applyCurrent() {
//         let p = InMemoryPersistenceStore()
//         p.save(GlobalSettings(theme: .neonBlue, appIconChoice: .purple))
//         let applier = FakeApplier()
//         AppIconStore(persistence: p, applier: applier).applyCurrent()
//         #expect(applier.applied == [.purple])
//     }
// }
