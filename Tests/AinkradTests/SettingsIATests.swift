import Testing
@testable import Ainkrad
import AinkradAppKitContract

/// The information-architecture invariant for Settings: everything is at most
/// two levels deep, and every section that used to live behind the Assistant's
/// pill bar has a home among the INTELLIGENCE pages.
@Suite("Settings information architecture")
@MainActor
struct SettingsIATests {
    private var catalog: SettingsCatalog { HostSettingsCatalog.build(environment: .preview()) }

    @Test("the INTELLIGENCE group holds the six agent pages in order")
    func intelligencePages() {
        #expect(catalog.pages(in: .intelligence).map(\.title) == [
            "Model & Connections",
            "Permissions & Sandbox",
            "Memory",
            "Skills",
            "Tools",
            "Privacy & Data"
        ])
    }

    @Test("every former Assistant tab section has a home in INTELLIGENCE")
    func everyAssistantSectionIsPlaced() {
        let labels = Set(catalog.pages(in: .intelligence).flatMap { $0.allFields.map(\.label) })
        for required in ["Connections", "Model", "Permissions", "Sandbox", "Tool hooks",
                         "Remote channel", "Context privacy", "Web search", "Media", "Video"] {
            #expect(labels.contains(required), "\(required) has no home")
        }
    }

    @Test("Memory, MCP, Language servers and Skills are catalog pages now")
    func formerSidebarRowsArePlaced() {
        let labels = Set(catalog.pages(in: .intelligence).flatMap { $0.allFields.map(\.label) })
        for required in ["Memory", "MCP servers", "Language servers", "Skills"] {
            #expect(labels.contains(required), "\(required) has no home")
        }
    }

    @Test("navigation depth is uniform — no page nests another page")
    func uniformDepth() {
        for page in catalog.pages {
            #expect(page.path.segments.count == 2, "\(page.path) is not top-level")
        }
    }

    @Test("search keywords reach settings whose label does not contain the query")
    func keywordsIndexed() {
        let fields = catalog.allFields
        func field(matching keyword: String) -> SettingsField? {
            fields.first { $0.keywords.contains(keyword) }
        }
        #expect(field(matching: "api key")?.label == "Connections")
        #expect(field(matching: "mcp")?.label == "MCP servers")
        #expect(field(matching: "hotkey")?.label == "Keyboard shortcuts")
    }

    @Test("Skills is a page of its own")
    func skillsPage() {
        let skills = catalog.pages(in: .intelligence).first { $0.title == "Skills" }
        #expect(skills != nil)
        #expect(skills?.icon == "sparkles")
    }
}
