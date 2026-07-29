import SwiftUI
import AinkradAppKit
import AinkradAppKitContract
import AinkradHostRuntime

/// Assembles the host's own settings pages into descriptors. Each field
/// binds straight through to the existing store — the catalog describes
/// settings, it does not own their persistence.
///
/// This builds the WORKSPACE pages (General, Appearance, Sound & Voice,
/// Keyboard), appends the INTELLIGENCE pages from
/// `IntelligenceSettingsCatalog`, and the APPS pages (BUILT-IN APPS /
/// INSTALLED) from `AppSettingsCatalog`.
@MainActor
enum HostSettingsCatalog {
    static func build(environment: AppEnvironment) -> SettingsCatalog {
        SettingsCatalog(pages: [
            general(environment),
            appearance(environment),
            soundAndVoice(environment),
            keyboard(environment)
        ] + IntelligenceSettingsCatalog.pages(environment: environment)
          + AppSettingsCatalog.pages(environment: environment))
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
                soundGroup(environment, page: page),
                soundEffectsGroup(environment, page: page),
                voiceGroup(environment, page: page),
                SettingsGroup(path: page.appending("speech"), title: "Speech", fields: [
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

    // MARK: - Sound & Voice — declarative groups
    //
    // Decomposed from `SoundSettingsView` + `VoiceSettingsView` (Task 7). Every
    // default below is read from the store, never inferred from the label:
    // `soundEnabled`/`soundVolume` from `GlobalSettings` (true / 0.7), the
    // per-event defaults from `GeneralSettingsStore` (a missing key means
    // enabled, and an event's default effect is its own sound), and the voice
    // defaults from `VoiceSettingsDocument`'s member-wise init — where BOTH
    // `autoSend` and `providerOptIn` are `false` despite affirmative labels.

    private static func soundGroup(_ environment: AppEnvironment, page: SettingsPath) -> SettingsGroup {
        let sound = page.appending("sound")
        let store = environment.generalSettingsStore

        return SettingsGroup(path: sound, title: "Sound", fields: [
            SettingsField(
                path: sound.appending("effects"),
                label: "Sound effects",
                help: "Plays a short chime on HUD open/close, install, and other key actions.",
                keywords: ["audio", "chime", "mute", "click", "sfx"],
                kind: .toggle(Binding(
                    get: { store.soundEnabled },
                    set: { store.setSoundEnabled($0) })),
                defaultDescription: "On",
                isModified: { store.soundEnabled != true },
                reset: { store.setSoundEnabled(true) }),
            SettingsField(
                path: sound.appending("volume"),
                label: "Volume",
                help: "Playback level for every workspace sound effect.",
                keywords: ["loudness", "level", "quiet", "loud", "audio"],
                kind: .slider(range: 0...1, step: 0.05, value: Binding(
                    get: { store.soundVolume },
                    set: { store.setSoundVolume($0) })),
                defaultDescription: "0.7",
                isModified: { store.soundVolume != 0.7 },
                reset: { store.setSoundVolume(0.7) })
        ])
    }

    /// One enable toggle, one effect chooser, and one preview action per
    /// `UISound` — 13 events, 39 fields. Collapsed by default so the page reads
    /// as two rows plus a section the user opens deliberately; the reachability
    /// audit covers `.collapsedByDefault` because a deep-link expands the group.
    private static func soundEffectsGroup(_ environment: AppEnvironment, page: SettingsPath) -> SettingsGroup {
        let effects = page.appending("soundEffects")
        let store = environment.generalSettingsStore

        let fields: [SettingsField] = UISound.allCases.flatMap { event -> [SettingsField] in
            let base = effects.appending(event.rawValue)
            let name = event.displayName
            return [
                SettingsField(
                    path: base.appending("enabled"),
                    label: name,
                    help: event.eventDescription,
                    keywords: ["cue", "event", "sound", name.lowercased()],
                    kind: .toggle(Binding(
                        get: { store.isEventEnabled(event) },
                        set: { store.setEventEnabled($0, for: event) })),
                    // A missing key means enabled — see `isEventEnabled`.
                    defaultDescription: "On",
                    isModified: { store.isEventEnabled(event) != true },
                    reset: { store.setEventEnabled(true, for: event) }),
                SettingsField(
                    path: base.appending("effect"),
                    label: "\(name) sound",
                    help: "Which effect \(name.lowercased()) plays.",
                    keywords: ["effect", "chooser", "cue", name.lowercased()],
                    kind: .select(
                        options: UISound.allCases.map {
                            SettingsOption(id: $0.rawValue,
                                           title: $0 == event ? "Default (\($0.displayName))" : $0.displayName)
                        },
                        selection: Binding(
                            get: { store.effect(for: event).rawValue },
                            set: { raw in
                                guard let chosen = UISound(rawValue: raw) else { return }
                                store.setEffect(chosen, for: event)
                                // Preserves the on-change preview the bespoke
                                // pane fired per item tap — picking an effect
                                // plays it, so the chooser stays audible.
                                environment.sounds.preview(chosen)
                            })),
                    defaultDescription: "Default (\(name))",
                    isModified: { store.effect(for: event) != event },
                    reset: { store.setEffect(event, for: event) }),
                // `.action` carries no value, so it declares no default and no
                // reset — `SettingsField.reset == nil` is documented as "no
                // meaningful reset". This is the ▶ preview button from the old
                // per-event row, kept so the current effect stays re-playable
                // without changing the selection.
                SettingsField(
                    path: base.appending("preview"),
                    label: "Preview \(name)",
                    help: "Play the effect currently chosen for \(name.lowercased()).",
                    keywords: ["preview", "play", "listen", "audition", name.lowercased()],
                    kind: .action(title: "Preview", handler: {
                        environment.sounds.preview(store.effect(for: event))
                    }))
            ]
        }

        return SettingsGroup(path: effects, title: "Sound Effects",
                             disclosure: .collapsedByDefault,
                             footerNote: "Enable each cue individually and choose which effect it plays. "
                                       + "Picking an effect previews it; Preview replays the current one.",
                             fields: fields)
    }

    private static func voiceGroup(_ environment: AppEnvironment, page: SettingsPath) -> SettingsGroup {
        let voice = page.appending("voice")
        // The voice store lives on the service — there is no
        // `environment.voiceSettingsStore`.
        let settings = environment.voiceService.settings
        let connections = environment.connectionStore
        let shortcuts = environment.shortcutStore
        let tokens = environment.themeManager.tokens

        func backendTitle(_ kind: TranscriptionBackendKind) -> String {
            kind == .onDevice ? "On-device (private)" : "Provider (Whisper)"
        }

        return SettingsGroup(path: voice, title: "Voice", fields: [
            SettingsField(
                path: voice.appending("backend"),
                label: "Backend",
                help: "On-device keeps audio private; Provider sends it to a configured connection.",
                keywords: ["transcription", "whisper", "on-device", "offline", "stt", "engine"],
                kind: .select(
                    options: TranscriptionBackendKind.allCases.map {
                        SettingsOption(id: $0.rawValue, title: backendTitle($0))
                    },
                    selection: Binding(
                        get: { settings.document.backend.rawValue },
                        set: { raw in
                            guard let kind = TranscriptionBackendKind(rawValue: raw) else { return }
                            settings.setBackend(kind)
                        })),
                defaultDescription: backendTitle(.onDevice),
                isModified: { settings.document.backend != .onDevice },
                reset: { settings.setBackend(.onDevice) }),
            SettingsField(
                path: voice.appending("mode"),
                label: "Push-to-talk mode",
                help: "Hold records while the hotkey is down; Toggle starts and stops on separate presses.",
                keywords: ["hold", "toggle", "ptt", "dictation", "microphone"],
                kind: .select(
                    options: PushToTalkMode.allCases.map {
                        SettingsOption(id: $0.rawValue, title: $0 == .hold ? "Hold" : "Toggle")
                    },
                    selection: Binding(
                        get: { settings.document.mode.rawValue },
                        set: { raw in
                            guard let mode = PushToTalkMode(rawValue: raw) else { return }
                            settings.setMode(mode)
                        })),
                defaultDescription: "Hold",
                isModified: { settings.document.mode != .hold },
                reset: { settings.setMode(.hold) }),
            SettingsField(
                path: voice.appending("autoSend"),
                label: "Auto-send after dictation",
                help: "Sends the transcript to the assistant as soon as dictation ends.",
                keywords: ["send", "submit", "dictation", "automatic", "enter"],
                kind: .toggle(Binding(
                    get: { settings.document.autoSend },
                    set: { settings.setAutoSend($0) })),
                // Reads as an affirmative label but the store default is false.
                defaultDescription: "Off",
                isModified: { settings.document.autoSend != false },
                reset: { settings.setAutoSend(false) }),
            SettingsField(
                path: voice.appending("providerOptIn"),
                label: "Upload audio to provider",
                help: "Opt in to sending dictated audio to the selected connection for transcription.",
                keywords: ["upload", "opt-in", "privacy", "cloud", "consent"],
                kind: .toggle(Binding(
                    get: { settings.document.providerOptIn },
                    set: { settings.setProviderOptIn($0) })),
                defaultDescription: "Off",
                isModified: { settings.document.providerOptIn != false },
                reset: { settings.setProviderOptIn(false) }),
            SettingsField(
                path: voice.appending("connection"),
                label: "Connection",
                help: "Which configured connection transcribes uploaded audio.",
                keywords: ["provider", "endpoint", "openai", "server", "account"],
                kind: .select(
                    options: connections.connections.map {
                        SettingsOption(id: $0.id.uuidString, title: $0.displayName)
                    },
                    selection: Binding(
                        get: { settings.document.providerConnectionID?.uuidString
                            ?? connections.connections.first?.id.uuidString ?? "" },
                        set: { settings.setProviderConnection(UUID(uuidString: $0)) })),
                defaultDescription: "None",
                isModified: { settings.document.providerConnectionID != nil },
                reset: { settings.setProviderConnection(nil) }),
            // Not `.secure`: this is a MODEL NAME ("whisper-1"), not a
            // credential. Marking it secure would hide it from search for no
            // security gain. The TTS API key is the page's only real secret and
            // it lives in the out-of-scope `TTSSettingsView` pane.
            SettingsField(
                path: voice.appending("providerModel"),
                label: "Model",
                help: "Transcription model requested from the provider.",
                keywords: ["whisper", "model", "engine", "name"],
                kind: .text(Binding(
                    get: { settings.document.providerModel },
                    set: { settings.setProviderModel($0) })),
                defaultDescription: "whisper-1",
                isModified: { settings.document.providerModel != "whisper-1" },
                reset: { settings.setProviderModel("whisper-1") }),
            SettingsField(
                path: voice.appending("locale"),
                label: "Locale",
                help: "Language hint for speech recognition, as a BCP-47 tag.",
                keywords: ["language", "region", "bcp-47", "en-US", "accent"],
                kind: .text(Binding(
                    get: { settings.document.localeIdentifier },
                    set: { settings.setLocale($0) })),
                defaultDescription: "en-US",
                isModified: { settings.document.localeIdentifier != "en-US" },
                reset: { settings.setLocale("en-US") }),
            // The one deliberate `.custom` here: a READ-ONLY display of the
            // current chord. It is rebound in Settings → Keyboard, so there is
            // nothing to edit; the kit has no informational field kind and one
            // is not worth adding for a single row.
            SettingsField(
                path: voice.appending("hotkey"),
                label: "Push-to-talk hotkey",
                help: "Change this in Settings → Keyboard.",
                // Deliberately NOT "hotkey": Keyboard ▸ "Keyboard shortcuts" is
                // where a chord is actually rebound and must stay the top hit
                // for that word. This row is a read-only pointer to it.
                keywords: ["push to talk", "ptt", "chord", "dictation shortcut"],
                kind: .custom(AnyView(VoiceHotkeyDisplay(shortcuts: shortcuts, tokens: tokens))))
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
