import SwiftUI

/// Settings' root view for a Block: exactly two tabs — General and
/// Built-in Apps. Every control persists immediately on change; there is
/// no Save button or draft state. See Navigation & Settings
/// Architecture.md. Chrome follows the app's HUD language (targeting-
/// bracket tabs, energy-seam divider) rather than stock macOS forms.
struct SettingsRootView: View {
    private enum Tab: String, CaseIterable {
        case general = "General"
        case builtInApps = "Built-in Apps"
    }

    @Environment(AppEnvironment.self) private var environment
    @State private var selectedTab: Tab = .general

    var body: some View {
        let tokens = environment.themeManager.tokens

        VStack(spacing: 0) {
            tabBar(tokens: tokens)

            LinearGradient(
                colors: [.clear, tokens.accentPrimary.opacity(0.4), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            switch selectedTab {
            case .general:
                GeneralSettingsView()
            case .builtInApps:
                BuiltInAppsSettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(tokens.surface)
    }

    private func tabBar(tokens: DesignTokens) -> some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases, id: \.self) { tab in
                tabButton(tab, tokens: tokens)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func tabButton(_ tab: Tab, tokens: DesignTokens) -> some View {
        let isActive = tab == selectedTab
        return Button {
            selectedTab = tab
        } label: {
            Text(tab.rawValue)
                .font(AinkradFont.display(12, weight: .medium))
                .kerning(0.5)
                .foregroundStyle(tokens.foreground.opacity(isActive ? 0.95 : 0.55))
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? tokens.accentPrimary.opacity(0.16) : tokens.surfaceElevated.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isActive ? tokens.accentPrimary.opacity(0.5) : .clear, lineWidth: 1)
                )
                .overlay(
                    TargetingBrackets(length: 6)
                        .stroke(isActive ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.2)
                        .padding(-1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: isActive)
    }
}
