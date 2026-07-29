import Testing
import SwiftUI
@testable import Ainkrad
import AinkradAppKitContract

/// Pins the Task 7 decomposition: the Sound, Sound Effects, and Voice groups of
/// `workspace.soundAndVoice` are declarative fields rather than bespoke panes.
///
/// SCOPE NOTE — this asserts over the three DECOMPOSED groups, not the whole
/// page. The page also carries a `Speech` group holding `TTSSettingsView`, a
/// third `.custom` pane that was never in this task's scope; a whole-page
/// assertion could not pass no matter how well the two named views converted.
/// The one `.custom` inside Voice (the read-only push-to-talk chord) is named
/// and allowed explicitly below rather than waved through by a loose filter.
@Suite("Sound & Voice fields")
@MainActor
struct SettingsSoundVoiceFieldsTests {
    private var page: SettingsPage {
        HostSettingsCatalog.build(environment: .preview())
            .pages(in: .workspace).first { $0.title == "Sound & Voice" }!
    }

    /// The groups this task decomposed. `Speech` (TTS) is deliberately absent.
    private var decomposedGroups: [SettingsGroup] {
        page.groups.filter { ["Sound", "Sound Effects", "Voice"].contains($0.title) }
    }

    private var decomposedFields: [SettingsField] {
        decomposedGroups.flatMap(\.fields)
    }

    /// The single tolerated escape hatch: a read-only chord display.
    private var allowedCustomPath: SettingsPath {
        SettingsPath(["workspace", "soundAndVoice", "voice", "hotkey"])
    }

    @Test("all three decomposed groups exist")
    func groupsExist() {
        #expect(decomposedGroups.count == 3, "expected Sound, Sound Effects and Voice")
    }

    @Test("the decomposed groups are declarative — only the named .custom survives")
    func noCustomFields() {
        for field in decomposedFields {
            if case .custom = field.kind, field.path != allowedCustomPath {
                Issue.record("\(field.path) is still .custom after decomposition")
            }
        }
    }

    /// Value-bearing fields only. `.action` carries no value, so
    /// `SettingsField` documents `reset == nil` as "no meaningful reset" — a
    /// no-op reset closure just to satisfy a test would be a lie.
    private var valueFields: [SettingsField] {
        decomposedFields.filter {
            switch $0.kind {
            case .action, .custom: return false
            default: return true
            }
        }
    }

    @Test("every value field carries a default, a modified check, and a reset")
    func fieldsAreResettable() {
        for field in valueFields {
            #expect(field.defaultDescription != nil, "\(field.path) has no declared default")
            #expect(field.reset != nil, "\(field.path) cannot be reset")
        }
    }

    @Test("every field carries keywords so search finds it by synonym")
    func fieldsHaveKeywords() {
        for field in decomposedFields {
            #expect(!field.keywords.isEmpty, "\(field.path) has no keywords")
        }
    }

    @Test("a toggle round-trips through its real store")
    func toggleRoundTrips() throws {
        let field = try #require(decomposedFields.first {
            if case .toggle = $0.kind { return true }
            return false
        })
        guard case .toggle(let binding) = field.kind else { return }
        let original = binding.wrappedValue
        binding.wrappedValue = !original
        #expect(binding.wrappedValue == !original, "write did not reach the store")
        binding.wrappedValue = original
    }

    @Test("reset restores the declared default for every value field")
    func resetRestoresDefault() {
        for field in valueFields {
            field.reset?()
            let why = "\(field.path) still reads as modified after reset — its declared default "
                + "probably disagrees with the store's real default"
            #expect(field.isModified() == false, "\(why)")
        }
    }

    // MARK: - Nothing became unreachable

    @Test("the master sound toggle and the volume slider survived")
    func soundBasicsSurvived() {
        let sound = try? #require(page.groups.first { $0.title == "Sound" })
        #expect(sound?.fields.contains { $0.label == "Sound effects" } == true)
        #expect(sound?.fields.contains { $0.label == "Volume" } == true)
    }

    /// The bespoke pane rendered a toggle, an effect chooser AND a ▶ preview
    /// for each of the 13 `UISound` events. All three must still be reachable.
    @Test("every sound event keeps its toggle, its chooser, and its preview")
    func everySoundEventFullyReachable() {
        let group = page.groups.first { $0.title == "Sound Effects" }
        let paths = Set((group?.fields ?? []).map(\.path))

        for event in UISound.allCases {
            let base = SettingsPath(["workspace", "soundAndVoice", "soundEffects", event.rawValue])
            #expect(paths.contains(base.appending("enabled")), "\(event.rawValue) lost its toggle")
            #expect(paths.contains(base.appending("effect")), "\(event.rawValue) lost its chooser")
            #expect(paths.contains(base.appending("preview")), "\(event.rawValue) lost its preview")
        }
        #expect(group?.fields.count == UISound.allCases.count * 3)
    }

    @Test("every preview action is invokable")
    func previewsAreInvokable() {
        let group = page.groups.first { $0.title == "Sound Effects" }
        let actions = (group?.fields ?? []).filter {
            if case .action = $0.kind { return true }
            return false
        }
        #expect(actions.count == UISound.allCases.count)
        for field in actions {
            guard case .action(_, let handler) = field.kind else { continue }
            handler()  // must not trap
        }
    }

    /// Every control the voice pane exposed, minus the chord display which is
    /// the one allowed `.custom`.
    @Test("every voice control survived the conversion")
    func voiceControlsSurvived() {
        let labels = Set((page.groups.first { $0.title == "Voice" }?.fields ?? []).map(\.label))
        for expected in ["Backend", "Push-to-talk mode", "Auto-send after dictation",
                         "Upload audio to provider", "Connection", "Model", "Locale",
                         "Push-to-talk hotkey"] {
            #expect(labels.contains(expected), "\(expected) became unreachable")
        }
    }

    // MARK: - Defaults were read from the store, not inferred from labels

    /// Both of these read as affirmative but default to `false` in
    /// `VoiceSettingsDocument`. Pass 1 shipped "On" for one of them.
    @Test("affirmative-sounding voice toggles declare their real Off default")
    func affirmativeTogglesDefaultOff() {
        let voice = page.groups.first { $0.title == "Voice" }?.fields ?? []
        for label in ["Auto-send after dictation", "Upload audio to provider"] {
            let field = voice.first { $0.label == label }
            #expect(field?.defaultDescription == "Off",
                    "\(label) must declare Off — the store default is false")
        }
    }

    /// A model NAME is not a credential; marking it `.secure` would hide it
    /// from search for no security benefit.
    @Test("the voice text fields are .text — neither holds a credential")
    func voiceTextFieldsAreNotSecure() {
        let voice = page.groups.first { $0.title == "Voice" }?.fields ?? []
        for label in ["Model", "Locale"] {
            let field = voice.first { $0.label == label }
            if case .text = field?.kind {} else {
                Issue.record("\(label) should be .text")
            }
        }
    }
}
