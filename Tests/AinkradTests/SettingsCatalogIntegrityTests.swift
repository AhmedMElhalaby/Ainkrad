import Testing
@testable import Ainkrad
import AinkradAppKit
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

    /// Every field in the live catalog must be genuinely reachable, not just
    /// present. This is the property that broke for App Icon: it was in the
    /// catalog, indexed by search, and returned as a result, but nothing
    /// could open its `collapsedByDefault` group — so a deep-link to it
    /// scrolled to nothing. `page(containing:)` resolving is necessary but
    /// not sufficient; `SettingsGroupView.mustExpand` returning true for a
    /// field highlighted inside its own collapsed group is the missing half,
    /// and it is what this test pins.
    @Test("every field in the host catalog is reachable via deep-link")
    func everyFieldIsReachable() {
        let catalog = HostSettingsCatalog.build(environment: .preview())
        var unreachable: [SettingsPath] = []

        for page in catalog.pages {
            // The field's page must actually be part of the catalog the
            // sidebar renders from (`catalog.pages`) — a page built but never
            // appended to `HostSettingsCatalog.build`'s array would be
            // unreachable regardless of what's inside it.
            guard catalog.pages.contains(where: { $0.path == page.path }) else {
                unreachable.append(page.path)
                continue
            }
            for group in page.groups {
                for field in group.fields {
                    // A deep-link must resolve to the page that owns the field.
                    guard catalog.page(containing: field.path)?.path == page.path else {
                        unreachable.append(field.path)
                        continue
                    }
                    // The group that owns the field must actually reveal it:
                    // `.always` groups never hide content, and a
                    // `.collapsedByDefault` group must open when this field
                    // is the highlighted deep-link target.
                    let revealed = group.disclosure == .always
                        || SettingsGroupView.mustExpand(
                            group: group, highlightedPath: field.path, matchedPaths: nil)
                    if !revealed {
                        unreachable.append(field.path)
                    }
                }
            }
        }

        #expect(unreachable.isEmpty, "Unreachable fields: \(unreachable.map(\.description))")
    }
}
