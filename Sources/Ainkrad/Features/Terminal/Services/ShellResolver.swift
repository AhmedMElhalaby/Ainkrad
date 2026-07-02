import Foundation

/// A shell path rejected by `ShellResolving`. Only the user-supplied
/// override throws — the `$SHELL`/account-shell and `/bin/zsh` tiers never
/// fail, so a session can always start. See Terminal App Architecture.md.
enum ShellResolutionError: Error, Equatable {
    case invalidOverride(path: String)
}

protocol ShellResolving {
    func resolveDefaultShell(override: String?) throws -> String
}

/// Resolves the shell to launch a Terminal session with: settings override
/// → `$SHELL`/account shell → `/bin/zsh`, each validated against
/// `/etc/shells`. See Terminal App Architecture.md.
struct ShellResolver: ShellResolving {
    static let fallback = "/bin/zsh"

    private let validShells: () -> Set<String>
    private let environmentShell: () -> String?
    private let accountShell: () -> String?

    init(
        validShells: @escaping () -> Set<String> = ShellResolver.readEtcShells,
        environmentShell: @escaping () -> String? = { ProcessInfo.processInfo.environment["SHELL"] },
        accountShell: @escaping () -> String? = ShellResolver.readAccountShell
    ) {
        self.validShells = validShells
        self.environmentShell = environmentShell
        self.accountShell = accountShell
    }

    func resolveDefaultShell(override: String?) throws -> String {
        let shells = validShells()

        if let override {
            guard shells.contains(override) else {
                throw ShellResolutionError.invalidOverride(path: override)
            }
            return override
        }

        if let environmentShell = environmentShell(), shells.contains(environmentShell) {
            return environmentShell
        }

        if let accountShell = accountShell(), shells.contains(accountShell) {
            return accountShell
        }

        return Self.fallback
    }

    private static func readEtcShells() -> Set<String> {
        guard let contents = try? String(contentsOfFile: "/etc/shells", encoding: .utf8) else {
            return [fallback]
        }
        let shells = contents
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return Set(shells)
    }

    private static func readAccountShell() -> String? {
        guard let passwd = getpwuid(getuid()) else { return nil }
        return passwd.pointee.pw_shell.map { String(cString: $0) }
    }
}
