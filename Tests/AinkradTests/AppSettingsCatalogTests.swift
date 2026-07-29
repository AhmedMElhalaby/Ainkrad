import Testing
@testable import Ainkrad
import AinkradAppKitContract

@Suite("App settings pages")
@MainActor
struct AppSettingsCatalogTests {
    @Test("an app that publishes no catalog still gets a page wrapping its view")
    func fallbackPage() {
        let pages = AppSettingsCatalog.pages(environment: .preview())
        #expect(!pages.isEmpty)
        for page in pages {
            #expect(page.appID != nil)
            #expect(!page.groups.isEmpty)
        }
    }

    @Test("every app page carries the host appearance group as a normal group")
    func appearanceGroupIsNormal() {
        let pages = AppSettingsCatalog.pages(environment: .preview())
            .filter { $0.appID != AssistantApp.id }
        for page in pages {
            #expect(page.groups.contains { $0.title == "Appearance" },
                    "\(page.title) is missing the host appearance group")
        }
    }

    @Test("built-in and installed apps land in different sidebar groups")
    func groupSplit() {
        let pages = AppSettingsCatalog.pages(environment: .preview())
        #expect(pages.allSatisfy { $0.group == .builtInApps || $0.group == .installedApps })
    }
}
