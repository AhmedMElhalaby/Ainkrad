import SwiftUI
import AinkradAppKit

/// The five tabs of the Assistant settings pane. Each tab owns an ordered set
/// of sections; only the active tab's sections render below the tab bar.
enum AssistantSettingsTab: String, CaseIterable, Hashable {
    case models, access, data, voice, appearance

    var title: String {
        switch self {
        case .models: return "Models"
        case .access: return "Access"
        case .data: return "Data"
        case .voice: return "Voice"
        case .appearance: return "Appearance"
        }
    }

    var icon: String {
        switch self {
        case .models: return "brain"
        case .access: return "lock.shield"
        case .data: return "eye.slash"
        case .voice: return "waveform"
        case .appearance: return "paintbrush"
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
        case .appearance: return [.appearance]
        }
    }
}

/// The individual settings sections. `.model` includes the model list, refresh,
/// and the effort picker (one builder). `.sandbox` is `SandboxPolicyUIView`.
enum AssistantSettingsSection: String, CaseIterable, Hashable {
    case connections, model, permissions, sandbox, contextPrivacy, voice, appearance
}

/// A horizontal pill selector for the Assistant settings tabs, in the outer
/// Settings sidebar's HUD idiom: a chamfered fill with targeting brackets on
/// the selected pill. Icon-and-label pills; selection animates via
/// `AinkradMotion.hover`, gated on Reduce Motion.
struct AssistantSettingsTabBar: View {
    @Binding var selection: AssistantSettingsTab
    let tokens: DesignTokens
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AssistantSettingsTab.allCases, id: \.self) { tab in
                pill(tab)
            }
            Spacer(minLength: 0)
        }
    }

    private func pill(_ tab: AssistantSettingsTab) -> some View {
        let isSelected = selection == tab
        return Button { selection = tab } label: {
            HStack(spacing: 7) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? tokens.accentSecondary : tokens.foreground.opacity(0.55))
                Text(tab.title)
                    .font(AinkradFont.display(12, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(isSelected ? 0.95 : 0.6))
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                ChamferShape(cut: AinkradRadius.md)
                    .fill(isSelected ? tokens.accentPrimary.opacity(0.14) : tokens.surfaceElevated.opacity(0.3))
            )
            .overlay(
                TargetingBrackets(length: 6)
                    .stroke(isSelected ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.2)
                    .padding(1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : AinkradMotion.hover, value: selection)
    }
}
