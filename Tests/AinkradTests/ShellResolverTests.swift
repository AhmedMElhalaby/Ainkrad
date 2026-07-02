import Testing
@testable import Ainkrad

@Suite("ShellResolver")
struct ShellResolverTests {

    private func makeResolver(
        validShells: [String] = ["/bin/zsh", "/bin/bash"],
        environmentShell: String? = nil,
        accountShell: String? = nil
    ) -> ShellResolver {
        ShellResolver(
            validShells: { Set(validShells) },
            environmentShell: { environmentShell },
            accountShell: { accountShell }
        )
    }

    @Test("a valid override takes precedence over everything else")
    func validOverrideWins() throws {
        let resolver = makeResolver(environmentShell: "/bin/bash")
        let shell = try resolver.resolveDefaultShell(override: "/bin/zsh")
        #expect(shell == "/bin/zsh")
    }

    @Test("an invalid override throws rather than silently falling through")
    func invalidOverrideThrows() {
        let resolver = makeResolver()
        #expect(throws: ShellResolutionError.invalidOverride(path: "/not/a/real/shell")) {
            try resolver.resolveDefaultShell(override: "/not/a/real/shell")
        }
    }

    @Test("with no override, a valid $SHELL is used")
    func validEnvironmentShellUsed() throws {
        let resolver = makeResolver(environmentShell: "/bin/bash", accountShell: "/bin/zsh")
        let shell = try resolver.resolveDefaultShell(override: nil)
        #expect(shell == "/bin/bash")
    }

    @Test("with no override and no $SHELL, a valid account shell is used")
    func validAccountShellUsedWhenNoEnvironmentShell() throws {
        let resolver = makeResolver(environmentShell: nil, accountShell: "/bin/bash")
        let shell = try resolver.resolveDefaultShell(override: nil)
        #expect(shell == "/bin/bash")
    }

    @Test("an invalid $SHELL falls through to a valid account shell")
    func invalidEnvironmentShellFallsThroughToAccountShell() throws {
        let resolver = makeResolver(environmentShell: "/not/a/real/shell", accountShell: "/bin/bash")
        let shell = try resolver.resolveDefaultShell(override: nil)
        #expect(shell == "/bin/bash")
    }

    @Test("with no valid override, $SHELL, or account shell, /bin/zsh is the final fallback")
    func fallsBackToZshWhenNothingElseResolves() throws {
        let resolver = makeResolver(environmentShell: nil, accountShell: nil)
        let shell = try resolver.resolveDefaultShell(override: nil)
        #expect(shell == "/bin/zsh")
    }

    @Test("an invalid account shell also falls through to /bin/zsh")
    func invalidAccountShellFallsThroughToZsh() throws {
        let resolver = makeResolver(environmentShell: nil, accountShell: "/not/a/real/shell")
        let shell = try resolver.resolveDefaultShell(override: nil)
        #expect(shell == "/bin/zsh")
    }
}
