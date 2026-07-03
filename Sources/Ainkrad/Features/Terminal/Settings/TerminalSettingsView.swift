import SwiftUI
import UniformTypeIdentifiers

/// Terminal's per-app settings, hosted in the Settings overlay's Terminal
/// section. Phase A covers Behavior (default shell + working directory);
/// Terminal Appearance (color scheme + font) arrives in Phase B. Both persist
/// immediately on change, with no Save button — see Terminal App
/// Architecture.md and Navigation & Settings Architecture.md.
struct TerminalSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var settings = TerminalSettings()
    @State private var shellPathText = ""
    @State private var shellValidationMessage: String?
    @State private var isChoosingFolder = false
    @State private var isLoaded = false

    var body: some View {
        let tokens = environment.themeManager.tokens

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSectionHeader(title: "BEHAVIOR", tokens: tokens)

                field(label: "Default Shell", tokens: tokens) {
                    TextField("/bin/zsh", text: $shellPathText)
                        .textFieldStyle(.plain)
                        .font(AinkradFont.mono(12))
                        .foregroundStyle(tokens.foreground)
                        .tint(tokens.accentSecondary)
                        .onSubmit(updateShell)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(tokens.surfaceElevated.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(tokens.accentPrimary.opacity(0.2), lineWidth: 1)
                        )

                    if let shellValidationMessage {
                        Text(shellValidationMessage)
                            .font(AinkradFont.display(11))
                            .foregroundStyle(Color(hex: "E5484D"))
                    } else {
                        Text("Must be listed in /etc/shells. Leave empty to use the login shell.")
                            .font(AinkradFont.display(11))
                            .foregroundStyle(tokens.foreground.opacity(0.45))
                    }
                }

                field(label: "Default Working Directory", tokens: tokens) {
                    HStack(spacing: 10) {
                        Text(settings.defaultWorkingDirectory?.path ?? "Home directory")
                            .font(AinkradFont.mono(12))
                            .foregroundStyle(tokens.foreground.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if settings.defaultWorkingDirectory != nil {
                            Button {
                                settings.defaultWorkingDirectory = nil
                                persist()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(tokens.foreground.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                            .help("Reset to home directory")
                        }

                        Button("Choose…") { isChoosingFolder = true }
                            .font(AinkradFont.display(12, weight: .medium))
                            .foregroundStyle(tokens.accentSecondary)
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tokens.surfaceElevated.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(tokens.accentPrimary.opacity(0.2), lineWidth: 1)
                    )
                }
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
        .onAppear(perform: loadIfNeeded)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            settings.defaultWorkingDirectory = url
            persist()
        }
    }

    /// A labeled settings field: a small caption over its control(s).
    private func field<Content: View>(
        label: String,
        tokens: DesignTokens,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(AinkradFont.display(12, weight: .medium))
                .foregroundStyle(tokens.foreground.opacity(0.85))
            content()
        }
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        settings = environment.settingsStore.get(TerminalSettings.self, forKey: TerminalSettings.storeKey) ?? TerminalSettings()
        shellPathText = settings.defaultShell ?? ""
    }

    private func updateShell() {
        let trimmed = shellPathText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            settings.defaultShell = nil
            shellValidationMessage = nil
            persist()
            return
        }

        do {
            _ = try ShellResolver().resolveDefaultShell(override: trimmed)
            settings.defaultShell = trimmed
            shellValidationMessage = nil
            persist()
        } catch {
            shellValidationMessage = "Not a shell listed in /etc/shells."
        }
    }

    private func persist() {
        environment.settingsStore.set(settings, forKey: TerminalSettings.storeKey)
    }
}
