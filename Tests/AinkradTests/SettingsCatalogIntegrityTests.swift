import Testing
@testable import Ainkrad
import AinkradAppKitContract

@Suite("HostSettingsCatalog integrity")
@MainActor
struct HostSettingsCatalogIntegrityTests {
    @Test("every path in the host catalog is unique")
    func pathsUnique() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        let all = catalog.pages.map(\.path)
            + catalog.pages.flatMap { $0.groups.map(\.path) }
            + catalog.allFields.map(\.path)
        #expect(Set(all).count == all.count)
    }

    @Test("every field lives under exactly one page")
    func fieldsHaveOnePage() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        for field in catalog.allFields {
            let owners = catalog.pages.filter { $0.allFields.contains { $0.path == field.path } }
            #expect(owners.count == 1, "\(field.path) is owned by \(owners.count) pages")
        }
    }

    @Test("every field path is prefixed by its group path")
    func pathsNest() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        for page in catalog.pages {
            for group in page.groups {
                #expect(group.path.segments.starts(with: page.path.segments))
                for field in group.fields {
                    #expect(field.path.segments.starts(with: group.path.segments))
                }
            }
        }
    }

    @Test("no group is empty")
    func noEmptyGroups() {
        for page in HostSettingsCatalog.build(environment: .preview()).pages {
            for group in page.groups {
                #expect(!group.fields.isEmpty, "\(group.path) has no fields")
            }
        }
    }

    @Test("the WORKSPACE pages are present and ordered")
    func workspacePages() {
        let titles = HostSettingsCatalog.build(environment: .preview())
            .pages(in: .workspace).map(\.title)
        #expect(titles == ["General", "Appearance", "Sound & Voice", "Keyboard"])
    }
}
