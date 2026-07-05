import Testing
import Foundation
import SwiftUI
@testable import Ainkrad
import AinkradAppKit

@MainActor
private final class NoOpDock: DockIconUpdating { func updateDockIcon(_ icon: AppIcon) {} }

@Suite("HostServices theme")
@MainActor
struct HostServicesThemeTests {
    private func makeHost() -> (HostServicesImpl, ThemeManager) {
        let persistence = InMemoryPersistenceStore()
        let tm = ThemeManager(persistence: persistence, dockIconUpdater: NoOpDock())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let host = HostServicesImpl(appID: "t", dataRootURL: root,
                                    secretStore: InMemorySecretStore(), themeManager: tm)
        return (host, tm)
    }

    @Test("theme starts on the active theme")
    func startsOnActive() {
        let (host, _) = makeHost()
        #expect(host.theme.tokens.themeID == "neonBlue")
    }

    @Test("theme follows a theme change")
    func followsChange() async {
        let (host, tm) = makeHost()
        tm.setTheme(.dracula)
        for _ in 0..<20 where host.theme.tokens.themeID != "dracula" { await Task.yield() }
        #expect(host.theme.tokens.themeID == "dracula")
        #expect(host.theme.tokens.background == Color(hex: "282A36"))
    }

    @Test("HostThemeTokens(from:) records the theme rawValue as id")
    func fromThemeID() {
        #expect(HostThemeTokens(from: .neonBlue).themeID == "neonBlue")
        #expect(HostThemeTokens(from: .cyberPurple).themeID == "cyberPurple")
    }
}
