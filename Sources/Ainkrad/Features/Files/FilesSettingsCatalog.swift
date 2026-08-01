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
///
/// **Organisation:** two groups, ordered by how often they're reached for.
/// *Appearance* holds everything about how the pane looks as a surface —
/// transparency and blur adjacent because they're the same decision (blur only
/// does anything when translucent), then the font overrides. *List* holds what
/// changes the file list itself. Files is exempted from the host's
/// auto-appended blur group precisely so blur can live beside transparency
/// instead of stranded in a fourth group below the fonts.
@MainActor
enum FilesSettingsCatalog {
    static func groups(root: SettingsPath, environment: AppEnvironment) -> [SettingsGroup] {
        [appearanceGroup(root: root, environment: environment),
         listGroup(root: root, environment: environment)]
    }

    private static func appearanceGroup(root: SettingsPath, environment: AppEnvironment) -> SettingsGroup {
        let appearance = environment.appAppearanceStore
        let manager = environment.themeManager
        let group = root.appending("appearance")

        let familyOptions = [SettingsOption(id: "default", title: "Default (follow Appearance)")]
            + UIFontFamily.allCases.map { SettingsOption(id: $0.rawValue, title: familyTitle($0)) }
        let scaleOptions = [SettingsOption(id: "default", title: "Default (follow Appearance)")]
            + UIFontScale.allCases.map { SettingsOption(id: $0.rawValue, title: scaleTitle($0)) }

        return SettingsGroup(
            path: group,
            title: "Appearance",
            footerNote: "Blur only has an effect while the pane is translucent — the host draws the workspace island behind it.",
            fields: [
                SettingsField(
                    path: group.appending("opacity"),
                    label: "Transparency",
                    help: "Lower values reveal the workspace island behind the pane. The title bar follows the same value, so the window stays one continuous surface.",
                    keywords: ["transparency", "opacity", "translucent", "island", "glass"],
                    kind: .slider(range: 0.3...1.0, step: 0.05, value: Binding(
                        get: { appearance.surfaceOpacity(FilesApp.id) },
                        set: { appearance.setSurfaceOpacity(FilesApp.id, $0) })),
                    defaultDescription: "Opaque",
                    isModified: { appearance.surfaceOpacity(FilesApp.id) != 1.0 },
                    reset: { appearance.setSurfaceOpacity(FilesApp.id, 1.0) }),
                SettingsField(
                    path: group.appending("blur"),
                    label: "Blur",
                    help: "Blur the workspace revealed behind this app when it's translucent.",
                    keywords: ["blur", "transparency", "translucent", "backdrop"],
                    kind: .toggle(Binding(
                        get: { appearance.blurEnabled(FilesApp.id) },
                        set: { appearance.setBlurEnabled(FilesApp.id, $0) })),
                    defaultDescription: "Off",
                    isModified: { appearance.blurEnabled(FilesApp.id) != false },
                    reset: { appearance.setBlurEnabled(FilesApp.id, false) }),
                SettingsField(
                    path: group.appending("font-family"),
                    label: "Font",
                    help: "Override the workspace font for this app only.",
                    keywords: ["font", "typeface", "family", "typography"],
                    kind: .select(options: familyOptions, selection: Binding(
                        get: { appearance.fontFamily(FilesApp.id)?.rawValue ?? "default" },
                        set: { appearance.setFontFamily(FilesApp.id, UIFontFamily(rawValue: $0)) })),
                    defaultDescription: familyTitle(manager.uiFontFamily),
                    isModified: { appearance.fontFamily(FilesApp.id) != nil },
                    reset: { appearance.setFontFamily(FilesApp.id, nil) }),
                SettingsField(
                    path: group.appending("font-scale"),
                    label: "Font size",
                    help: "Override the workspace font scale for this app only.",
                    keywords: ["font size", "scale", "text size", "typography"],
                    kind: .select(options: scaleOptions, selection: Binding(
                        get: { appearance.fontScale(FilesApp.id)?.rawValue ?? "default" },
                        set: { appearance.setFontScale(FilesApp.id, UIFontScale(rawValue: $0)) })),
                    defaultDescription: scaleTitle(manager.uiFontScale),
                    isModified: { appearance.fontScale(FilesApp.id) != nil },
                    reset: { appearance.setFontScale(FilesApp.id, nil) })
            ])
    }

    private static func listGroup(root: SettingsPath, environment: AppEnvironment) -> SettingsGroup {
        let store = environment.filesSettingsStore
        let group = root.appending("list")
        return SettingsGroup(
            path: group,
            title: "List",
            footerNote: "Row height follows the icon size, so it doubles as the list's density control.",
            fields: [
                SettingsField(
                    path: group.appending("icon-size"),
                    label: "Icon size",
                    help: "Row icon size, in points.",
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
}
