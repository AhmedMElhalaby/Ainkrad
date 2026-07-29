import SwiftUI
import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime

/// Assembles the host's own settings pages into descriptors. Each field
/// binds straight through to the existing store — the catalog describes
/// settings, it does not own their persistence.
///
/// This task builds only the WORKSPACE pages (General, Appearance, Sound &
/// Voice, Keyboard); INTELLIGENCE and APPS pages arrive in later tasks.
@MainActor
enum HostSettingsCatalog {
    static func build(environment: AppEnvironment) -> SettingsCatalog {
        SettingsCatalog(pages: [
            general(environment),
            appearance(environment),
            soundAndVoice(environment),
            keyboard(environment)
        ])
    }

    // MARK: - General

    private static func general(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["workspace", "general"])
        let startup = page.appending("startup")
        let store = environment.generalSettingsStore

        return SettingsPage(
            path: page, title: "General", icon: "gearshape",
            group: .workspace, order: 0,
            groups: [
                SettingsGroup(path: startup, title: "Workspace", fields: [
                    SettingsField(
                        path: startup.appending("fullScreenStatusBar"),
                        label: "Show status bar in full-screen",
                        help: "Clock, network, and battery in the title strip while full-screen.",
                        keywords: ["clock", "battery", "network", "menu bar"],
                        kind: .toggle(Binding(
                            get: { store.showFullScreenStatusBar },
                            set: { store.setShowFullScreenStatusBar($0) })),
                        defaultDescription: "On",
                        isModified: { store.showFullScreenStatusBar != true },
                        reset: { store.setShowFullScreenStatusBar(true) }),
                    SettingsField(
                        path: startup.appending("launcherLayout"),
                        label: "Launcher layout",
                        help: "Show apps in the ⌘K launcher as a list or a grid of icons.",
                        keywords: ["grid", "list", "command k", "apps"],
                        kind: .select(
                            options: LauncherViewMode.allCases.map {
                                SettingsOption(id: $0.rawValue, title: $0.label)
                            },
                            selection: Binding(
                                get: { store.launcherViewMode.rawValue },
                                set: { raw in
                                    guard let mode = LauncherViewMode(rawValue: raw) else { return }
                                    store.setLauncherViewMode(mode)
                                })),
                        defaultDescription: LauncherViewMode.allCases[0].label,
                        isModified: { store.launcherViewMode != LauncherViewMode.allCases[0] },
                        reset: { store.setLauncherViewMode(LauncherViewMode.allCases[0]) })
                ])
            ])
    }

    // MARK: - Appearance (theme + Living Sky + App Icon merged)

    private static func appearance(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["workspace", "appearance"])
        return SettingsPage(
            path: page, title: "Appearance", icon: "paintbrush",
            group: .workspace, order: 1,
            groups: [
                SettingsGroup(path: page.appending("theme"), title: "Theme", fields: [
                    SettingsField(
                        path: page.appending("theme").appending("picker"),
                        label: "Theme",
                        help: "Accent palette for the whole workspace.",
                        keywords: ["accent", "color", "dark mode", "neon", "palette"],
                        kind: .custom(AnyView(AppearanceSettingsView())))
                ]),
                SettingsGroup(path: page.appending("livingSky"), title: "Living Sky", fields: [
                    SettingsField(
                        path: page.appending("livingSky").appending("controls"),
                        label: "Living Sky",
                        help: "The animated backdrop behind the workspace.",
                        keywords: ["background", "wallpaper", "animation", "parallax"],
                        kind: .custom(AnyView(LivingSkySettingsView())))
                ]),
                SettingsGroup(path: page.appending("appIcon"), title: "App Icon",
                              disclosure: .collapsedByDefault, fields: [
                    SettingsField(
                        path: page.appending("appIcon").appending("picker"),
                        label: "App icon",
                        help: "The icon Ainkrad shows in the Dock.",
                        keywords: ["dock", "icon", "badge"],
                        kind: .custom(AnyView(AppIconSettingsView())))
                ])
            ])
    }

    // MARK: - Sound & Voice

    private static func soundAndVoice(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["workspace", "soundAndVoice"])
        let tokens = environment.themeManager.tokens
        return SettingsPage(
            path: page, title: "Sound & Voice", icon: "speaker.wave.2",
            group: .workspace, order: 2,
            groups: [
                SettingsGroup(path: page.appending("sound"), title: "Sound", fields: [
                    SettingsField(
                        path: page.appending("sound").appending("effects"),
                        label: "Sound effects",
                        help: "Workspace interaction sounds.",
                        keywords: ["audio", "volume", "mute", "chime"],
                        kind: .custom(AnyView(SoundSettingsView())))
                ]),
                SettingsGroup(path: page.appending("speech"), title: "Speech", fields: [
                    SettingsField(
                        path: page.appending("speech").appending("voice"),
                        label: "Voice input",
                        help: "Speech recognition for talking to the assistant.",
                        keywords: ["dictation", "microphone", "speech", "stt"],
                        kind: .custom(AnyView(VoiceSettingsView(
                            settings: environment.voiceService.settings,
                            connections: environment.connectionStore,
                            shortcuts: environment.shortcutStore,
                            tokens: tokens)))),
                    SettingsField(
                        path: page.appending("speech").appending("textToSpeech"),
                        label: "Spoken responses",
                        help: "How the assistant reads its replies aloud.",
                        keywords: ["tts", "speak", "read aloud", "voice"],
                        kind: .custom(AnyView(TTSSettingsView(
                            persistence: environment.persistence,
                            secrets: environment.secrets,
                            tokens: tokens))))
                ])
            ])
    }

    // MARK: - Keyboard

    private static func keyboard(_ environment: AppEnvironment) -> SettingsPage {
        let page = SettingsPath(["workspace", "keyboard"])
        return SettingsPage(
            path: page, title: "Keyboard", icon: "keyboard",
            group: .workspace, order: 3,
            groups: [
                SettingsGroup(path: page.appending("shortcuts"), title: "Shortcuts", fields: [
                    SettingsField(
                        path: page.appending("shortcuts").appending("list"),
                        label: "Keyboard shortcuts",
                        help: "Global and workspace key bindings.",
                        keywords: ["hotkey", "binding", "key", "chord", "command"],
                        kind: .custom(AnyView(ShortcutsSettingsView())))
                ])
            ])
    }
}
