import Testing
import Foundation
@testable import Ainkrad

@Suite("WorkingDirectoryResolver")
struct WorkingDirectoryResolverTests {

    private let validPath = URL(fileURLWithPath: "/valid")
    private let otherValidPath = URL(fileURLWithPath: "/other-valid")
    private let invalidPath = URL(fileURLWithPath: "/invalid")
    private let home = URL(fileURLWithPath: "/Users/someone")

    private func makeResolver(validDirectories: Set<URL>) -> WorkingDirectoryResolver {
        WorkingDirectoryResolver(
            isValidDirectory: { validDirectories.contains($0) },
            homeDirectory: { self.home }
        )
    }

    @Test("a valid session override wins, with no rejections")
    func validSessionOverrideWins() {
        let resolver = makeResolver(validDirectories: [validPath, otherValidPath])
        let result = resolver.resolveWorkingDirectory(sessionOverride: validPath, settingsDefault: otherValidPath)

        #expect(result.url == validPath)
        #expect(!result.rejectedSessionOverride)
        #expect(!result.rejectedSettingsDefault)
    }

    @Test("an invalid session override falls through to a valid settings default")
    func invalidSessionOverrideFallsThroughToSettingsDefault() {
        let resolver = makeResolver(validDirectories: [otherValidPath])
        let result = resolver.resolveWorkingDirectory(sessionOverride: invalidPath, settingsDefault: otherValidPath)

        #expect(result.url == otherValidPath)
        #expect(result.rejectedSessionOverride)
        #expect(!result.rejectedSettingsDefault)
    }

    @Test("invalid session override and invalid settings default both fall through to home")
    func bothInvalidFallThroughToHome() {
        let resolver = makeResolver(validDirectories: [])
        let result = resolver.resolveWorkingDirectory(sessionOverride: invalidPath, settingsDefault: invalidPath)

        #expect(result.url == home)
        #expect(result.rejectedSessionOverride)
        #expect(result.rejectedSettingsDefault)
    }

    @Test("with no session override, a valid settings default is used")
    func noSessionOverrideUsesSettingsDefault() {
        let resolver = makeResolver(validDirectories: [otherValidPath])
        let result = resolver.resolveWorkingDirectory(sessionOverride: nil, settingsDefault: otherValidPath)

        #expect(result.url == otherValidPath)
        #expect(!result.rejectedSessionOverride)
        #expect(!result.rejectedSettingsDefault)
    }

    @Test("with nothing set, the home directory is used with no rejections")
    func nothingSetUsesHome() {
        let resolver = makeResolver(validDirectories: [])
        let result = resolver.resolveWorkingDirectory(sessionOverride: nil, settingsDefault: nil)

        #expect(result.url == home)
        #expect(!result.rejectedSessionOverride)
        #expect(!result.rejectedSettingsDefault)
    }

    @Test("an invalid settings default with no session override falls through to home")
    func invalidSettingsDefaultAloneFallsThroughToHome() {
        let resolver = makeResolver(validDirectories: [])
        let result = resolver.resolveWorkingDirectory(sessionOverride: nil, settingsDefault: invalidPath)

        #expect(result.url == home)
        #expect(!result.rejectedSessionOverride)
        #expect(result.rejectedSettingsDefault)
    }
}
