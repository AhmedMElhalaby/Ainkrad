import SwiftUI
import AinkradAppKit

/// The four tabs of the Assistant settings pane. Each tab owns an ordered set
/// of sections; only the active tab's sections render below the tab bar.
enum AssistantSettingsTab: String, CaseIterable, Hashable {
    case models, access, data, voice

    var title: String {
        switch self {
        case .models: return "Models"
        case .access: return "Access"
        case .data: return "Data"
        case .voice: return "Voice"
        }
    }

    var icon: String {
        switch self {
        case .models: return "brain"
        case .access: return "lock.shield"
        case .data: return "eye.slash"
        case .voice: return "waveform"
        }
    }

    /// The sections shown under this tab, in render order. Every section
    /// belongs to exactly one tab (see `AssistantSettingsTabTests`).
    var sections: [AssistantSettingsSection] {
        switch self {
        case .models: return [.connections, .model]
        case .access: return [.permissions, .sandbox]
        case .data: return [.contextPrivacy]
        case .voice: return [.voice]
        }
    }
}

/// The individual settings sections. `.model` includes the model list, refresh,
/// and the effort picker (one builder). `.sandbox` is `SandboxPolicyUIView`.
enum AssistantSettingsSection: String, CaseIterable, Hashable {
    case connections, model, permissions, sandbox, contextPrivacy, voice
}
