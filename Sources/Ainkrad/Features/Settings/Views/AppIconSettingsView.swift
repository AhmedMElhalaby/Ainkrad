import SwiftUI

/// Settings → App Icon: a manual picker for the running app's Dock icon.
struct AppIconSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let tokens = environment.themeManager.tokens
        let store = environment.appIconStore
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsSectionHeader(title: "APP ICON", tokens: tokens)
                Text("Choose the Dock icon. It follows the system light/dark appearance.")
                    .font(AinkradFont.display(11))
                    .foregroundStyle(tokens.foreground.opacity(0.5))
                HStack(spacing: 14) {
                    tile(.blue, label: "Blue", store: store, tokens: tokens)
                    tile(.purple, label: "Purple", store: store, tokens: tokens)
                    Spacer()
                }
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    private func tile(_ choice: AppIconChoice, label: String, store: AppIconStore, tokens: DesignTokens) -> some View {
        let selected = store.choice == choice
        // Preview: the dark composed variant reads well on the HUD surface.
        // TODO(v2 Task 3): rewritten to use the appearance setting + theme.
        let previewName = AppIconResolver.resourceName(for: choice, theme: .neonBlue, appearance: .system, systemDark: true)
        return Button {
            store.select(choice)
        } label: {
            VStack(spacing: 8) {
                Group {
                    if let url = Bundle.main.url(forResource: previewName, withExtension: "icns"),
                       let img = NSImage(contentsOf: url) {
                        Image(nsImage: img).resizable().scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 14).fill(tokens.surfaceElevated)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(label)
                    .font(AinkradFont.display(11, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(selected ? 0.95 : 0.6))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? tokens.accentPrimary.opacity(0.13) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tokens.accentPrimary.opacity(selected ? 0.4 : 0.12), lineWidth: 1))
            .overlay(TargetingBrackets(length: 9).stroke(selected ? tokens.accentSecondary.opacity(0.9) : .clear, lineWidth: 1.4).padding(1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: selected)
    }
}
