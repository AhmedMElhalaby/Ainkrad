import Testing
import Foundation
@testable import Ainkrad
import AinkradHostRuntime

/// Wave 0 / Blocker 1: the plugin trust boundary.
///
/// Before this, `DeveloperIDSignaturePolicy` was an always-failing stub that
/// nothing referenced, and every wiring site used `DevModeSignaturePolicy`
/// (which accepts anything). These tests pin the two properties that matter:
/// the production policy actually rejects untrusted code, and the *choice* of
/// policy is made by build configuration rather than by hand.
@Suite("Plugin trust policy")
struct PluginTrustPolicyTests {

    // MARK: - The Developer-ID requirement

    @Test("Requirement demands the Developer-ID CA and leaf markers")
    func requirementUsesDeveloperIDMarkers() {
        let text = DeveloperIDSignaturePolicy().requirementText
        // Chains to Apple, not to an arbitrary self-signed anchor.
        #expect(text.contains("anchor apple generic"))
        // Developer ID Certification Authority marker — excludes Mac App Store
        // and plain "Apple Development" certs.
        #expect(text.contains("1.2.840.113635.100.6.2.6"))
        // Developer ID Application leaf marker — excludes Developer ID Installer.
        #expect(text.contains("1.2.840.113635.100.6.1.13"))
    }

    @Test("Team pinning is opt-in and absent by default")
    func teamPinningIsOptIn() {
        // Third-party plugins ship under their OWN team, so pinning to ours by
        // default would reject the entire catalog.
        #expect(!DeveloperIDSignaturePolicy().requirementText.contains("subject.OU"))
        #expect(DeveloperIDSignaturePolicy(teamIdentifier: "PSY67XNHG4")
            .requirementText.contains("certificate leaf[subject.OU] = \"PSY67XNHG4\""))
        // An empty string must not produce a requirement that matches an empty OU.
        #expect(!DeveloperIDSignaturePolicy(teamIdentifier: "").requirementText.contains("subject.OU"))
    }

    // MARK: - Rejection behaviour

    @Test("Rejects a bundle that carries no code signature")
    func rejectsUnsignedBundle() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Fake.bundle")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Contents"),
                                                withIntermediateDirectories: true)
        try "not a plist".write(to: dir.appendingPathComponent("Contents/Info.plist"),
                                atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        let result = DeveloperIDSignaturePolicy().validate(bundleURL: dir)
        guard case .failure(let rejection) = result else {
            Issue.record("unsigned bundle was accepted")
            return
        }
        // The reason is what surfaces to the user in the App Store overlay, so
        // it must be non-empty and not a bare OSStatus number.
        #expect(!rejection.reason.isEmpty)
        #expect(rejection.reason.rangeOfCharacter(from: .letters) != nil)
    }

    @Test("Rejects a path that does not exist at all")
    func rejectsMissingPath() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).bundle")
        guard case .failure = DeveloperIDSignaturePolicy().validate(bundleURL: missing) else {
            Issue.record("missing path was accepted")
            return
        }
    }

    // MARK: - Build-configuration selection

    @Test("Policy and DevPlugins scanning follow the build configuration")
    func selectionFollowsBuildConfiguration() {
        #if DEBUG
        #expect(PluginTrust.policyForCurrentBuild() is DevModeSignaturePolicy)
        #expect(PluginTrust.scansDevPluginsDirectory)
        #else
        // The whole point of Blocker 1's fix: Release cannot get the permissive
        // policy, and cannot scan the unmanaged sideload directory.
        #expect(PluginTrust.policyForCurrentBuild() is DeveloperIDSignaturePolicy)
        #expect(!PluginTrust.scansDevPluginsDirectory)
        #endif
    }
}

/// Wave 0 / RC-5: `loadFailures` was written by the loader and read by nothing,
/// which is what would have made Blocker 0 undiagnosable.
@MainActor
@Suite("Plugin load failures are surfaced")
struct PluginLoadFailureSurfacingTests {

    @Test("Store exposes the registry's load failures")
    func storeExposesFailures() {
        let registry = BuiltInAppRegistry(persistence: InMemoryPersistenceStore())
        #expect(registry.loadFailures.isEmpty)

        let failure = PluginLoadFailure(
            url: URL(fileURLWithPath: "/tmp/Plugins/Terminal.bundle"),
            reason: "signature: not signed (needs a Developer-ID signature)")
        registry.install(builtIn: [], loaded: [], failures: [failure])

        let store = AppStoreStore(service: FakeAppStoreService(), registry: registry)
        #expect(store.loadFailures == [failure])
    }

    @Test("Failure text names the bundle and the reason, not the raw path")
    func failureTextIsReadable() {
        let text = AppStoreStore.failureText(PluginLoadFailure(
            url: URL(fileURLWithPath: "/Users/x/Library/Application Support/Plugins/GitMage.bundle"),
            reason: "Bundle.load() failed"))
        #expect(text == "GitMage — Bundle.load() failed")
        #expect(!text.contains("Application Support"))
    }
}
