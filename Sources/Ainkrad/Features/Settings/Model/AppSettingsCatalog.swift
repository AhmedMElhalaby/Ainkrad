import SwiftUI
import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime

/// One settings page per ENABLED app — a disabled app has no settings page,
/// same as it has no Launcher entry. If the app publishes a catalog
/// (`AinkradApp.settingsCatalog(host:)`) we use its groups; otherwise its
/// `makeSettingsView` renders inside a single `.custom` field, so old
/// plugins keep working and stay findable by app name.
///
/// The host-owned "Appearance" group (the per-app blur toggle) is appended as
/// a NORMAL group, not a block bolted below whatever the app rendered. The
/// Assistant is exempt — it owns its own appearance in its in-app Appearance
/// tab.
@MainActor
enum AppSettingsCatalog {
    static func pages(environment: AppEnvironment) -> [SettingsPage] {
        environment.registry.enabledApps.enumerated().map { index, app in
            let isBuiltIn = app.source == .builtIn
            let root = SettingsPath(["app", app.id])
            let published = app.settingsCatalog()

            var groups = published?.groups ?? [
                SettingsGroup(path: root.appending("settings"), title: app.displayName, fields: [
                    SettingsField(
                        path: root.appending("settings").appending("pane"),
                        label: "\(app.displayName) settings",
                        help: nil,
                        keywords: [app.displayName.lowercased()],
                        kind: .custom(app.makeSettingsView()))
                ])
            ]

            if app.id != AssistantApp.id {
                groups.append(appearanceGroup(appID: app.id, root: root, environment: environment))
            }

            return SettingsPage(
                path: root, title: app.displayName, icon: app.icon,
                group: isBuiltIn ? .builtInApps : .installedApps,
                order: index, groups: groups, appID: app.id)
        }
    }

    /// The blur toggle every app but the Assistant gets — the host renders
    /// the blurred backdrop behind a translucent pane. Mirrors the semantics
    /// of the former `appAppearanceSection`: `AppAppearanceStore` defaults an
    /// app's blur to off.
    private static func appearanceGroup(
        appID: String, root: SettingsPath, environment: AppEnvironment
    ) -> SettingsGroup {
        let store = environment.appAppearanceStore
        let group = root.appending("appearance")
        return SettingsGroup(path: group, title: "Appearance", fields: [
            SettingsField(
                path: group.appending("blur"),
                label: "Blur",
                help: "Blur the workspace revealed behind this app when it's translucent.",
                keywords: ["blur", "transparency", "translucent", "backdrop"],
                kind: .toggle(Binding(
                    get: { store.blurEnabled(appID) },
                    set: { store.setBlurEnabled(appID, $0) })),
                defaultDescription: "Off",
                isModified: { store.blurEnabled(appID) != false },
                reset: { store.setBlurEnabled(appID, false) })
        ])
    }
}
