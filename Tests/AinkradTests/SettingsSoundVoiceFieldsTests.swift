import Testing
import SwiftUI
@testable import Ainkrad
import AinkradAppKitContract

/// Pins the Task 7 decomposition — as it stands AFTER review.
///
/// SCOPE NOTE — this asserts over the **Voice group only**, narrowed twice, both
/// times deliberately:
///
///  1. `Speech` (`TTSSettingsView`) was never in this task's scope, so a
///     whole-page "no `.custom`" assertion could never have passed.
///  2. `Sound` was decomposed and then **reverted after the review gate**. One
///     field per control turned each of the 13 `UISound` events into three rows
///     with near-duplicate labels; the bespoke pane puts them on one line. Sound
///     is `.custom` again on purpose, and `soundStaysAPaneOnPurpose` below pins
///     that so re-decomposing it is a deliberate act with a failing test to
///     answer, not a silent drift.
///
/// The one `.custom` inside Voice (the read-only push-to-talk chord) is named by
/// exact path rather than waved through by a loose filter, so any NEW `.custom`
/// appearing in Voice still fails.
@Suite("Sound & Voice fields")
@MainActor
struct SettingsSoundVoiceFieldsTests {
    private var page: SettingsPage {
        HostSettingsCatalog.build(environment: .preview())
            .pages(in: .workspace).first { $0.title == "Sound & Voice" }!
    }

    private var voiceGroup: SettingsGroup? {
        page.groups.first { $0.title == "Voice" }
    }

    private var voiceFields: [SettingsField] { voiceGroup?.fields ?? [] }

    /// The single tolerated escape hatch inside Voice: a read-only chord display.
    private var allowedCustomPath: SettingsPath {
        SettingsPath(["workspace", "soundAndVoice", "voice", "hotkey"])
    }

    @Test("the page carries Sound, Voice and Speech groups")
    func groupsExist() {
        let titles = page.groups.map(\.title)
        #expect(titles.contains("Sound"))
        #expect(titles.contains("Voice"))
        #expect(titles.contains("Speech"))
    }

    @Test("the Voice group is declarative — only the named .custom survives")
    func noCustomFields() {
        for field in voiceFields {
            if case .custom = field.kind, field.path != allowedCustomPath {
                Issue.record("\(field.path) is still .custom after decomposition")
            }
        }
    }

    /// Value-bearing fields only. `.action` and `.custom` carry no value, so
    /// `SettingsField` documents `reset == nil` as "no meaningful reset" — a
    /// no-op reset closure just to satisfy a test would be a lie, and would
    /// paint a revert arrow on a row that has nothing to revert.
    private var valueFields: [SettingsField] {
        voiceFields.filter {
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
        for field in voiceFields {
            #expect(!field.keywords.isEmpty, "\(field.path) has no keywords")
        }
    }

    @Test("a toggle round-trips through its real store")
    func toggleRoundTrips() throws {
        let field = try #require(voiceFields.first {
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

    /// Every control the voice pane exposed, including the chord display which
    /// is the one allowed `.custom`.
    @Test("every voice control survived the conversion")
    func voiceControlsSurvived() {
        let labels = Set(voiceFields.map(\.label))
        for expected in ["Backend", "Push-to-talk mode", "Auto-send after dictation",
                         "Upload audio to provider", "Connection", "Model", "Locale",
                         "Push-to-talk hotkey"] {
            #expect(labels.contains(expected), "\(expected) became unreachable")
        }
    }

    /// The Sound half was reverted at the review gate. The pane owns the master
    /// toggle, the volume slider and all 13 per-event rows, so every sound
    /// setting is reachable through it — but only while the field is still
    /// there and still pointed at the pane.
    @Test("Sound stays one .custom pane on purpose after the review-gate revert")
    func soundStaysAPaneOnPurpose() throws {
        let sound = try #require(page.groups.first { $0.title == "Sound" })
        #expect(sound.fields.count == 1, "Sound was re-decomposed — see the scope note")
        let field = try #require(sound.fields.first)
        #expect(field.label == "Sound effects")
        if case .custom = field.kind {} else {
            Issue.record("Sound effects should be .custom until the SDK gains a composite row kind")
        }
        // The pane has no single value, so it declares no default and no reset.
        #expect(field.reset == nil)
        // Search must still reach the pane by the words it used to answer to.
        for keyword in ["audio", "volume", "mute", "chime"] {
            #expect(field.keywords.contains(keyword), "search lost \"\(keyword)\"")
        }
    }

    // MARK: - Defaults were read from the store, not inferred from labels

    /// Both of these read as affirmative but default to `false` in
    /// `VoiceSettingsDocument`. Pass 1 shipped "On" for one of them.
    @Test("affirmative-sounding voice toggles declare their real Off default")
    func affirmativeTogglesDefaultOff() {
        for label in ["Auto-send after dictation", "Upload audio to provider"] {
            let field = voiceFields.first { $0.label == label }
            #expect(field?.defaultDescription == "Off",
                    "\(label) must declare Off — the store default is false")
        }
    }

    /// A model NAME is not a credential; marking it `.secure` would hide it
    /// from search for no security benefit.
    @Test("the voice text fields are .text — neither holds a credential")
    func voiceTextFieldsAreNotSecure() {
        for label in ["Model", "Locale"] {
            let field = voiceFields.first { $0.label == label }
            if case .text = field?.kind {} else {
                Issue.record("\(label) should be .text")
            }
        }
    }
}
