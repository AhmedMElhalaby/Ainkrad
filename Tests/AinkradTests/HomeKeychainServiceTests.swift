import Foundation
import Testing
@testable import Ainkrad
import AinkradAppKit

/// Guards the seam that keeps the test suite out of the developer's real Keychain.
///
/// Secrets are not vault-resident, so `Home` does not obviously govern them — which
/// is exactly why this needs a test rather than a comment. `bootstrap` namespaces
/// every Keychain item by `home.keychainServiceName`; if that derivation ever
/// collapses to one shared value, a test writing a connection's API key silently
/// lands in the real `com.ainkrad.app` service.
@Suite("Home keychain service")
struct HomeKeychainServiceTests {
    private func home(vault: URL) -> Home {
        Home(vaultRoot: vault, cacheRoot: vault.appendingPathComponent("cache", isDirectory: true))
    }

    /// Requirement 1: a real installation's service name is unchanged, so secrets
    /// saved by every prior release still resolve. A wrong derivation here orphans
    /// every stored API key, which is why both production locations are asserted.
    @Test func aProductionVaultKeepsTheCanonicalServiceName() {
        for root in Home.canonicalVaultRoots {
            #expect(home(vault: root).keychainServiceName == Home.canonicalKeychainService)
        }
        // Both candidates must actually be covered — an empty list would make the
        // loop above vacuously true.
        #expect(Home.canonicalVaultRoots.count == 2)
    }

    /// Requirement 2: two throwaway vaults never share a namespace, so two suites
    /// running against `TestHome.make()` cannot see each other's secrets.
    @Test func twoDifferentVaultsGetDifferentServiceNames() {
        let a = TestHome.make("kc-a")
        defer { a.cleanup() }
        let b = TestHome.make("kc-b")
        defer { b.cleanup() }

        #expect(a.home.keychainServiceName != b.home.keychainServiceName)
        #expect(a.home.keychainServiceName != Home.canonicalKeychainService)
        #expect(b.home.keychainServiceName != Home.canonicalKeychainService)
    }

    /// Requirement 3: the derivation is stable — same vault, same name, every time.
    /// It must also be lexical: computing it before and after the vault exists on
    /// disk has to agree, or secrets written early in a session become unreadable
    /// later in it.
    @Test func theSameVaultAlwaysGetsTheSameServiceName() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("kc-stable-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let beforeItExists = home(vault: vault).keychainServiceName
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let afterItExists = home(vault: vault).keychainServiceName
        #expect(beforeItExists == afterItExists)

        // And a freshly-built `Home` over the same path agrees, as does an
        // equivalent but non-standardized spelling of that path.
        #expect(home(vault: vault).keychainServiceName == beforeItExists)
        let noisy = vault.appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent(vault.lastPathComponent, isDirectory: true)
        #expect(home(vault: noisy).keychainServiceName == beforeItExists)
    }

    /// The cache root is not part of the namespace: only the vault decides it.
    /// Otherwise relocating a disposable cache would strand the secrets.
    @Test func theCacheRootDoesNotAffectTheServiceName() {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("kc-cache-\(UUID().uuidString)", isDirectory: true)
        let one = Home(vaultRoot: vault, cacheRoot: vault.appendingPathComponent("c1"))
        let two = Home(vaultRoot: vault, cacheRoot: vault.appendingPathComponent("c2"))
        #expect(one.keychainServiceName == two.keychainServiceName)
    }

    /// End-to-end: the store `bootstrap` actually builds is namespaced to the
    /// throwaway vault, so writing through it leaves the canonical service alone.
    @Test @MainActor func bootstrapWritesSecretsOutsideTheCanonicalService() {
        let t = TestHome.make("kc-boot")
        defer { t.cleanup() }

        let environment = AppEnvironment.bootstrap(home: t.home, defaults: t.defaults)
        let id = "kc-probe-\(UUID().uuidString)"
        environment.secrets.setSecret("sk-should-be-isolated", for: id)
        defer { environment.secrets.setSecret(nil, for: id) }

        #expect(environment.secrets.secret(for: id) == "sk-should-be-isolated")
        // The same id read through the canonical service must not see it.
        #expect(KeychainSecretStore(service: Home.canonicalKeychainService).secret(for: id) == nil)
    }
}
