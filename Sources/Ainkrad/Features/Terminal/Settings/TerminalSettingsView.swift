import SwiftUI
import UniformTypeIdentifiers

/// Terminal's per-app settings: default shell and default working
/// directory. Both persist immediately on change, with no Save button —
/// see Terminal App Architecture.md and Navigation & Settings
/// Architecture.md.
struct TerminalSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var settings = TerminalSettings()
    @State private var shellPathText = ""
    @State private var shellValidationMessage: String?
    @State private var isChoosingFolder = false
    @State private var isLoaded = false

    var body: some View {
        Form {
            Section("Default Shell") {
                TextField("Path, e.g. /bin/bash", text: $shellPathText)
                    .onSubmit(updateShell)
                if let shellValidationMessage {
                    Text(shellValidationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Default Working Directory") {
                HStack {
                    Text(settings.defaultWorkingDirectory?.path ?? "Home directory")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { isChoosingFolder = true }
                }
            }
        }
        .padding()
        .onAppear(perform: loadIfNeeded)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            settings.defaultWorkingDirectory = url
            persist()
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
