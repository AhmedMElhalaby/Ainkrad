import SwiftUI

/// Settings' root view for a Block: exactly two tabs — General and
/// Built-in Apps. Every control persists immediately on change; there is
/// no Save button or draft state. See Navigation & Settings
/// Architecture.md.
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
            Picker("Settings section", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

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
}
