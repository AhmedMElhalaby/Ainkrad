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

        let shellPath: String
        do {
            shellPath = try shellResolver.resolveDefaultShell(override: settings.defaultShell)
        } catch {
            shellPath = (try? shellResolver.resolveDefaultShell(override: nil)) ?? ShellResolver.fallback
        }

        let workingDirectory = workingDirectoryResolver.resolveWorkingDirectory(
            sessionOverride: nil,
            settingsDefault: settings.defaultWorkingDirectory
        ).url

        return TerminalSession(workingDirectory: workingDirectory, shellPath: shellPath)
    }
}
