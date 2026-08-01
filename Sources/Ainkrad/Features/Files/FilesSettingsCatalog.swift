import SwiftUI
import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime

/// Files' settings as DECLARED fields.
///
/// Built here rather than in `FilesApp.settingsCatalog(host:)` because that
/// entry point is static and sees only `HostServices` — it cannot reach
/// `AppEnvironment`, where the appearance and Files stores live. Since Files is
/// a host-embedded built-in (not a loadable plugin), the host is entitled to
/// build its page directly; see `AppSettingsCatalog`'s built-in seam.
///
/// Declared fields rather than one `.custom` wrapped view, so these settings
/// are searchable, deep-linkable and resettable like every other setting — and
/// so they don't trip the `.custom` ratchet.
@MainActor
enum FilesSettingsCatalog {
    static func groups(root: SettingsPath, environment: AppEnvironment) -> [SettingsGroup] {
        [appearanceGroup(root: root, environment: environment),
         typographyGroup(root: root, environment: environment),
         listGroup(root: root, environment: environment)]
    }

    /// Transparency. Mirrors the Assistant's opacity slider, and drives
    /// `FilesApp.surfaceFill` → a translucent pane revealing the island.
    private static func appearanceGroup(root: SettingsPath, environment: AppEnvironment) -> SettingsGroup {
        let store = environment.appAppearanceStore
        let group = root.appending("surface")
        return SettingsGroup(path: group, title: "Surface", fields: [
            SettingsField(
                path: group.appending("opacity"),
                label: "Transparency",
                help: "Lower values reveal the workspace island behind the pane. The title bar follows the same value, so the window stays one continuous surface.",
                keywords: ["transparency", "opacity", "translucent", "island", "glass"],
                kind: .slider(range: 0.3...1.0, step: 0.05, value: Binding(
                    get: { store.surfaceOpacity(FilesApp.id) },
                    set: { store.setSurfaceOpacity(FilesApp.id, $0) })),
                defaultDescription: "Opaque",
                isModified: { store.surfaceOpacity(FilesApp.id) != 1.0 },
                reset: { store.setSurfaceOpacity(FilesApp.id, 1.0) })
        ])
    }

    /// Per-app font overrides. Both default to inheriting the global Appearance
    /// setting — "Default" is a real option, not the absence of one, so the
    /// user can always get back to inheriting.
    private static func typographyGroup(root: SettingsPath, environment: AppEnvironment) -> SettingsGroup {
        let appearance = environment.appAppearanceStore
        let group = root.appending("typography")

        let familyOptions = [SettingsOption(id: "default", title: "Default (follow Appearance)")]
            + UIFontFamily.allCases.map { SettingsOption(id: $0.rawValue, title: familyTitle($0)) }
        let scaleOptions = [SettingsOption(id: "default", title: "Default (follow Appearance)")]
            + UIFontScale.allCases.map { SettingsOption(id: $0.rawValue, title: scaleTitle($0)) }

        return SettingsGroup(path: group, title: "Typography", fields: [
            SettingsField(
                path: group.appending("family"),
                label: "Font",
                help: "Override the workspace font for this app only.",
                keywords: ["font", "typeface", "family", "typography"],
                kind: .select(options: familyOptions, selection: Binding(
                    get: { appearance.fontFamily(FilesApp.id)?.rawValue ?? "default" },
                    set: { appearance.setFontFamily(FilesApp.id, UIFontFamily(rawValue: $0)) })),
                defaultDescription: "Default",
                isModified: { appearance.fontFamily(FilesApp.id) != nil },
                reset: { appearance.setFontFamily(FilesApp.id, nil) }),
            SettingsField(
                path: group.appending("scale"),
                label: "Font size",
                help: "Override the workspace font scale for this app only.",
                keywords: ["font size", "scale", "text size", "typography"],
                kind: .select(options: scaleOptions, selection: Binding(
                    get: { appearance.fontScale(FilesApp.id)?.rawValue ?? "default" },
                    set: { appearance.setFontScale(FilesApp.id, UIFontScale(rawValue: $0)) })),
                defaultDescription: "Default",
                isModified: { appearance.fontScale(FilesApp.id) != nil },
                reset: { appearance.setFontScale(FilesApp.id, nil) })
        ])
    }

    private static func familyTitle(_ family: UIFontFamily) -> String {
        switch family {
        case .exo2: return "Exo 2"
        case .jetBrainsMono: return "JetBrains Mono"
        case .system: return "System"
        }
    }

    private static func scaleTitle(_ scale: UIFontScale) -> String {
        switch scale {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    private static func listGroup(root: SettingsPath, environment: AppEnvironment) -> SettingsGroup {
        let store = environment.filesSettingsStore
        let group = root.appending("list")
        return SettingsGroup(path: group, title: "List", fields: [
            SettingsField(
                path: group.appending("icon-size"),
                label: "Icon size",
                help: "Row icon size. Row height follows it, so this is the list's density control.",
                keywords: ["icon", "size", "density", "row height", "compact"],
                kind: .slider(range: 10...22, step: 1, value: Binding(
                    get: { store.iconSize },
                    set: { store.iconSize = $0 })),
                defaultDescription: "13 pt",
                isModified: { store.iconSize != 13 },
                reset: { store.iconSize = 13 }),
            SettingsField(
                path: group.appending("metadata-columns"),
                label: "Show size and date",
                help: "Turn off for a name-only list.",
                keywords: ["columns", "size", "date", "modified", "metadata"],
                kind: .toggle(Binding(
                    get: { store.showMetadataColumns },
                    set: { store.showMetadataColumns = $0 })),
                defaultDescription: "On",
                isModified: { store.showMetadataColumns != true },
                reset: { store.showMetadataColumns = true })
        ])
    }
}
