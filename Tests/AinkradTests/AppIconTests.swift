import Testing
import Foundation
@testable import Ainkrad

struct AppIconResolverTests {
    @Test("resolves each choice × appearance to the right resource name")
    func resolves() {
        #expect(AppIconResolver.resourceName(for: .blue,   dark: false) == "blue-light")
        #expect(AppIconResolver.resourceName(for: .blue,   dark: true)  == "blue-dark")
        #expect(AppIconResolver.resourceName(for: .purple, dark: false) == "purple-light")
        #expect(AppIconResolver.resourceName(for: .purple, dark: true)  == "purple-dark")
    }

    @Test("the composed .icns for every combo is bundled")
    func iconsBundled() {
        for choice in AppIconChoice.allCases {
            for dark in [true, false] {
                let name = AppIconResolver.resourceName(for: choice, dark: dark)
                #expect(Bundle(for: AinkradBundleToken.self).url(forResource: name, withExtension: "icns") != nil
                        || Bundle.main.url(forResource: name, withExtension: "icns") != nil,
                        "missing \(name).icns")
            }
        }
    }
}

// A type whose bundle is the host app module, so the test can find app resources.
final class AinkradBundleToken {}

struct GlobalSettingsAppIconTests {
    @Test("appIconChoice defaults to blue and round-trips")
    func roundTrip() throws {
        var s = GlobalSettings()
        #expect(s.appIconChoice == .blue)
        s.appIconChoice = .purple
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(GlobalSettings.self, from: data)
        #expect(back.appIconChoice == .purple)
    }

    @Test("a doc written before appIconChoice existed decodes to blue")
    func legacyDecodes() throws {
        let legacy = Data(#"{"theme":"neonBlue"}"#.utf8)
        let s = try JSONDecoder().decode(GlobalSettings.self, from: legacy)
        #expect(s.appIconChoice == .blue)
    }
}

@MainActor
private final class FakeApplier: AppIconApplying {
    private(set) var applied: [AppIconChoice] = []
    func apply(_ choice: AppIconChoice) { applied.append(choice) }
}

@MainActor
struct AppIconStoreTests {
    @Test("loads the persisted choice")
    func loads() {
        let p = InMemoryPersistenceStore()
        p.save(GlobalSettings(theme: .neonBlue, appIconChoice: .purple))
        let store = AppIconStore(persistence: p, applier: FakeApplier())
        #expect(store.choice == .purple)
    }

    @Test("select persists the choice (preserving theme) and applies it")
    func select() {
        let p = InMemoryPersistenceStore()
        p.save(GlobalSettings(theme: .dracula, appIconChoice: .blue))
        let applier = FakeApplier()
        let store = AppIconStore(persistence: p, applier: applier)
        store.select(.purple)
        #expect(store.choice == .purple)
        #expect(p.load(GlobalSettings.self)?.appIconChoice == .purple)
        #expect(p.load(GlobalSettings.self)?.theme == .dracula)   // theme preserved
        #expect(applier.applied.last == .purple)
    }

    @Test("applyCurrent applies the loaded choice")
    func applyCurrent() {
        let p = InMemoryPersistenceStore()
        p.save(GlobalSettings(theme: .neonBlue, appIconChoice: .purple))
        let applier = FakeApplier()
        AppIconStore(persistence: p, applier: applier).applyCurrent()
        #expect(applier.applied == [.purple])
    }
}
