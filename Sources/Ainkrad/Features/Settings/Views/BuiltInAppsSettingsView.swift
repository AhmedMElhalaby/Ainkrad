import SwiftUI

/// The Built-in Apps tab: every registered app (`registry.allApps`, so
/// disabled apps stay visible) with an enable/disable toggle, and a
/// drill-in to the app's own settings view via its factory. Layout chrome
/// only — per-app settings content belongs to the owning app's module.
/// See Navigation & Settings Architecture.md.
struct BuiltInAppsSettingsView: View {
    /// Plain value snapshot of a registered app's display fields. Iterating
    /// SwiftUI Lists over `BuiltInApp.Type` metatypes directly crashes the
    /// Swift 6 (Xcode 27 beta) SILGen — rows carry values, and the metatype
    /// is looked back up by id only where a factory call is needed.
    private struct AppRow: Identifiable {
        let id: String
        let displayName: String
        let icon: String
    }

    @Environment(AppEnvironment.self) private var environment
    @State private var selectedAppID: String?

    private var appRows: [AppRow] {
        environment.registry.allApps.map { AppRow(id: $0.id, displayName: $0.displayName, icon: $0.icon) }
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        if let selectedAppID, let app = environment.registry.allApps.first(where: { $0.id == selectedAppID }) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    self.selectedAppID = nil
                } label: {
                    Label("Built-in Apps", systemImage: "chevron.left")
                        .foregroundStyle(tokens.accentPrimary)
                }
                .buttonStyle(.plain)
                .padding(12)

                Divider()

                app.makeSettingsView()
            }
        } else {
            appList(tokens: tokens)
        }
    }

    private func appList(tokens: DesignTokens) -> some View {
        List(appRows) { app in
            HStack(spacing: 10) {
                Image(systemName: app.icon)
                    .foregroundStyle(tokens.accentPrimary)
                    .frame(width: 18)
                Text(app.displayName)
                    .foregroundStyle(tokens.foreground)
                Spacer()
                Toggle("Enabled", isOn: Binding(
                    get: { environment.registry.isEnabled(app.id) },
                    set: { environment.registry.setEnabled($0, for: app.id) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(tokens.foreground.opacity(0.4))
            }
            .contentShape(Rectangle())
            .onTapGesture { selectedAppID = app.id }
        }
        .scrollContentBackground(.hidden)
    }
}
