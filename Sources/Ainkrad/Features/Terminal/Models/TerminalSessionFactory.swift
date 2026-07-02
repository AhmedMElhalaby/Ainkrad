import Foundation

/// Resolves a new Terminal session's shell and working directory from
/// `TerminalSettings`, per the precedence orders in
/// Terminal App Architecture.md. An invalid configured shell is rejected by
/// `ShellResolving` and retried with no override rather than failing
/// session start.
@MainActor
struct TerminalSessionFactory {
    private let shellResolver: ShellResolving
    private let workingDirectoryResolver: WorkingDirectoryResolving
    private let settingsStore: SettingsStore

    init(
        shellResolver: ShellResolving = ShellResolver(),
        workingDirectoryResolver: WorkingDirectoryResolving = WorkingDirectoryResolver(),
        settingsStore: SettingsStore
    ) {
        self.shellResolver = shellResolver
        self.workingDirectoryResolver = workingDirectoryResolver
        self.settingsStore = settingsStore
    }

    func makeSession() -> TerminalSession {
        let settings = settingsStore.get(TerminalSettings.self, forKey: TerminalSettings.storeKey) ?? TerminalSettings()
        var notices: [String] = []

        let shellPath: String
        do {
            shellPath = try shellResolver.resolveDefaultShell(override: settings.defaultShell)
        } catch {
            shellPath = (try? shellResolver.resolveDefaultShell(override: nil)) ?? ShellResolver.fallback
            if let configuredShell = settings.defaultShell {
                notices.append("The configured shell “\(configuredShell)” isn’t valid, so \(shellPath) was used instead.")
            }
        }

        let resolution = workingDirectoryResolver.resolveWorkingDirectory(
            sessionOverride: nil,
            settingsDefault: settings.defaultWorkingDirectory
        )
        if resolution.rejectedSettingsDefault, let configuredDirectory = settings.defaultWorkingDirectory {
            notices.append("The configured working directory “\(configuredDirectory.path)” isn’t usable, so \(resolution.url.path) was used instead.")
        }

        return TerminalSession(
            workingDirectory: resolution.url,
            shellPath: shellPath,
            startupNotices: notices
        )
    }
}
