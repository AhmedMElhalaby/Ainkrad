import SwiftUI
import AinkradAppKit

/// The menu-bar popover: the SAME Assistant surface as ⌘⇧Space, plus live run
/// status and a quick Agent/model switch. Complements — does not replace —
/// ⌘⇧Space and the main Assistant pane (all three share `agentSession`).
@MainActor
struct MenuBarPopoverView: View {
    @Environment(AppEnvironment.self) private var environment
    let presence: MenuBarPresence

    /// Owned locally — same pattern as `AssistantComposerBar`'s caller: the
    /// connection·model picker's logic lives in this `@State`-held model,
    /// independent of whichever surface is rendering the pill.
    @State private var modelPicker = AssistantModelPickerModel()

    var body: some View {
        let tokens = environment.themeManager.tokens
        VStack(alignment: .leading, spacing: 0) {
            header(tokens: tokens)
            runStatus(tokens: tokens)
            Divider().overlay(tokens.foreground.opacity(0.06))
            AssistantRootView(showsHeader: false, autoFocusComposer: true)
                .frame(minHeight: 260, maxHeight: 360)
            quickSwitch(tokens: tokens)
        }
        .frame(width: 360)
        .hudPanelChrome(tokens: tokens)
    }

    private func header(tokens: DesignTokens) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.system(size: 12))
                .foregroundStyle(tokens.accentSecondary)
            Text("ASSISTANT").font(AinkradFont.display(12, weight: .medium)).kerning(0.6)
                .foregroundStyle(tokens.foreground.opacity(0.7))
            Spacer()
            AinkradIconButton(systemName: "arrow.up.forward.app") {
                environment.workspaceManager.activeWorkspace.tileLayout.openApp(AssistantApp.id)
                presence.close()
            }
            .help("Open in the Assistant pane")
        }
        .padding(.horizontal, 14).frame(height: 40)
    }

    @ViewBuilder
    private func runStatus(tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(presence.runSummary)
                .font(AinkradFont.display(11)).kerning(0.4)
                .foregroundStyle(tokens.foreground.opacity(0.5))
            ForEach(presence.runItems) { item in
                HStack(spacing: 8) {
                    Circle().fill(item.isActive ? tokens.accentPrimary : tokens.accentSecondary)
                        .frame(width: 6, height: 6)
                    Text(item.title).font(AinkradFont.display(12)).lineLimit(1)
                        .foregroundStyle(tokens.foreground.opacity(0.85))
                    Spacer()
                    AinkradIconButton(systemName: "stop.fill", size: 9, tooltip: "Stop this run") {
                        presence.stop(item.id)
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 8)
    }

    /// Quick Agent + model switch strip — the real Slice 5 controls
    /// (`AgentSwitcherView`, `AssistantConnectionModelPicker`), driving the
    /// canonical `AgentStore.setActive` / `RuntimeOptionsStore.pinModel` seams.
    /// Same components the composer bar embeds; this is a second, independent
    /// surface onto the same shared stores.
    private func quickSwitch(tokens: DesignTokens) -> some View {
        HStack(spacing: 8) {
            AgentSwitcherView(store: environment.agentStore, tokens: tokens)
            AssistantConnectionModelPicker(
                model: modelPicker,
                tokens: tokens,
                onManageConnections: {
                    environment.isSettingsPresented = true
                    presence.close()
                }
            )
            Spacer()
        }
        .padding(.horizontal, 14).frame(height: 40)
    }
}
