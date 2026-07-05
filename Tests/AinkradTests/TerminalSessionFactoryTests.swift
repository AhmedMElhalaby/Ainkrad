import Testing
import Foundation
@testable import Ainkrad

private struct SpyShellResolver: ShellResolving {
    var onResolve: (String?) throws -> String
    func resolveDefaultShell(override: String?) throws -> String {
        try onResolve(override)
    }
}

private struct SpyWorkingDirectoryResolver: WorkingDirectoryResolving {
    var onResolve: (URL?, URL?) -> WorkingDirectoryResolution
    func resolveWorkingDirectory(sessionOverride: URL?, settingsDefault: URL?) -> WorkingDirectoryResolution {
        onResolve(sessionOverride, settingsDefault)
    }
}

@Suite("TerminalSessionFactory")
final class TerminalSessionFactoryTests {
    @Test("with no settings, resolves shell and working directory with no configured override")
    @MainActor
    func noSettingsUsesDefaultResolution() {
        var capturedShellOverride: String??
        let factory = TerminalSessionFactory(
            shellResolver: SpyShellResolver(onResolve: { override in
                capturedShellOverride = override
                return "/bin/zsh"
            }),
            workingDirectoryResolver: SpyWorkingDirectoryResolver(onResolve: { _, _ in
                WorkingDirectoryResolution(url: URL(fileURLWithPath: "/Users/someone"), rejectedSessionOverride: false, rejectedSettingsDefault: false)
            }),
            settings: TerminalSettings()
        )

        let session = factory.makeSession()

        #expect(capturedShellOverride == .some(nil))
        #expect(session.shellPath == "/bin/zsh")
        #expect(session.workingDirectory == URL(fileURLWithPath: "/Users/someone"))
    }

    @Test("passes TerminalSettings' configured shell as the override")
    @MainActor
    func passesConfiguredShellAsOverride() {
        var capturedShellOverride: String??
        let factory = TerminalSessionFactory(
            shellResolver: SpyShellResolver(onResolve: { override in
                capturedShellOverride = override
                return override ?? "/bin/zsh"
            }),
            workingDirectoryResolver: SpyWorkingDirectoryResolver(onResolve: { _, _ in
                WorkingDirectoryResolution(url: URL(fileURLWithPath: "/home"), rejectedSessionOverride: false, rejectedSettingsDefault: false)
            }),
            settings: TerminalSettings(defaultShell: "/bin/bash", defaultWorkingDirectory: nil)
        )

        let session = factory.makeSession()

        #expect(capturedShellOverride == .some("/bin/bash"))
        #expect(session.shellPath == "/bin/bash")
    }

    @Test("falls back to no-override resolution when the configured shell is rejected")
    @MainActor
    func fallsBackWhenConfiguredShellIsInvalid() {
        var overridesSeen: [String?] = []
        let factory = TerminalSessionFactory(
            shellResolver: SpyShellResolver(onResolve: { override in
                overridesSeen.append(override)
                if let override { throw ShellResolutionError.invalidOverride(path: override) }
                return "/bin/zsh"
            }),
            workingDirectoryResolver: SpyWorkingDirectoryResolver(onResolve: { _, _ in
                WorkingDirectoryResolution(url: URL(fileURLWithPath: "/home"), rejectedSessionOverride: false, rejectedSettingsDefault: false)
            }),
            settings: TerminalSettings(defaultShell: "/not/real", defaultWorkingDirectory: nil)
        )

        let session = factory.makeSession()

        #expect(overridesSeen == ["/not/real", nil])
        #expect(session.shellPath == "/bin/zsh")
    }

    @Test("a rejected configured shell surfaces a calm startup notice on the session")
    @MainActor
    func rejectedShellSurfacesStartupNotice() {
        let factory = TerminalSessionFactory(
            shellResolver: SpyShellResolver(onResolve: { override in
                if let override { throw ShellResolutionError.invalidOverride(path: override) }
                return "/bin/zsh"
            }),
            workingDirectoryResolver: SpyWorkingDirectoryResolver(onResolve: { _, _ in
                WorkingDirectoryResolution(url: URL(fileURLWithPath: "/home"), rejectedSessionOverride: false, rejectedSettingsDefault: false)
            }),
            settings: TerminalSettings(defaultShell: "/not/real", defaultWorkingDirectory: nil)
        )

        let session = factory.makeSession()

        #expect(session.startupNotices == [
            "The configured shell “/not/real” isn’t valid, so /bin/zsh was used instead."
        ])
    }

    @Test("a rejected configured working directory surfaces a calm startup notice on the session")
    @MainActor
    func rejectedWorkingDirectorySurfacesStartupNotice() {
        let factory = TerminalSessionFactory(
            shellResolver: SpyShellResolver(onResolve: { _ in "/bin/zsh" }),
            workingDirectoryResolver: SpyWorkingDirectoryResolver(onResolve: { _, _ in
                WorkingDirectoryResolution(url: URL(fileURLWithPath: "/home"), rejectedSessionOverride: false, rejectedSettingsDefault: true)
            }),
            settings: TerminalSettings(defaultShell: nil, defaultWorkingDirectory: URL(fileURLWithPath: "/nonexistent"))
        )

        let session = factory.makeSession()

        #expect(session.startupNotices == [
            "The configured working directory “/nonexistent” isn’t usable, so /home was used instead."
        ])
    }

    @Test("a clean resolution produces no startup notices")
    @MainActor
    func cleanResolutionHasNoNotices() {
        let factory = TerminalSessionFactory(
            shellResolver: SpyShellResolver(onResolve: { _ in "/bin/zsh" }),
            workingDirectoryResolver: SpyWorkingDirectoryResolver(onResolve: { _, _ in
                WorkingDirectoryResolution(url: URL(fileURLWithPath: "/home"), rejectedSessionOverride: false, rejectedSettingsDefault: false)
            }),
            settings: TerminalSettings()
        )

        let session = factory.makeSession()

        #expect(session.startupNotices.isEmpty)
    }

    @Test("passes TerminalSettings' configured working directory as the settings default")
    @MainActor
    func passesConfiguredWorkingDirectoryAsSettingsDefault() {
        let configuredDirectory = URL(fileURLWithPath: "/projects")

        var capturedSettingsDefault: URL??
        let factory = TerminalSessionFactory(
            shellResolver: SpyShellResolver(onResolve: { _ in "/bin/zsh" }),
            workingDirectoryResolver: SpyWorkingDirectoryResolver(onResolve: { _, settingsDefault in
                capturedSettingsDefault = settingsDefault
                return WorkingDirectoryResolution(url: configuredDirectory, rejectedSessionOverride: false, rejectedSettingsDefault: false)
            }),
            settings: TerminalSettings(defaultShell: nil, defaultWorkingDirectory: configuredDirectory)
        )

        let session = factory.makeSession()

        #expect(capturedSettingsDefault == .some(configuredDirectory))
        #expect(session.workingDirectory == configuredDirectory)
    }
}
