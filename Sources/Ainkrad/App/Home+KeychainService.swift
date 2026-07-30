import Foundation
import CryptoKit
import AinkradAppKit

/// Where the Keychain service name comes from.
///
/// Secrets never live in the vault — they live in the Keychain, which sits outside
/// the Home entirely. But the Keychain still needs a *namespace*, and until now that
/// namespace was `Bundle.main.bundleIdentifier`: one global service shared by every
/// process using this bundle, the test runner included. That was the last hole left
/// after `bootstrap` started taking a `Home`. A test bootstrapping onto a throwaway
/// vault would still have read and written the developer's real API keys.
///
/// So the service name is a pure function of the vault location. There is no
/// "am I a test" branch — a throwaway vault simply yields a throwaway namespace,
/// which makes test isolation a property of the derivation rather than something a
/// caller has to remember to ask for.
extension Home {
    /// The app's canonical Keychain service — the exact string every release has
    /// stored secrets under.
    static var canonicalKeychainService: String {
        Bundle.main.bundleIdentifier ?? "com.ainkrad.app"
    }

    /// Vault locations a real installation uses. A vault at one of these keeps the
    /// canonical service name, so an existing user's saved API keys still resolve
    /// after this refactor — get this list wrong and every stored key is orphaned.
    ///
    /// **Task 8 must add its adoption target here if it chooses a location not
    /// already listed.** Both current candidates are covered:
    ///   - `~/Ainkrad` — the default vault the milestone plan adopts.
    ///   - `~/Library/Application Support/<bundle-id>` — the pre-Home location, and
    ///     the interim root `AinkradHostApp.init` passes until Task 8 lands.
    static var canonicalVaultRoots: [URL] {
        var roots = [FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Ainkrad", isDirectory: true)]
        if let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            roots.append(support.appendingPathComponent(canonicalKeychainService, isDirectory: true))
        }
        return roots
    }

    /// The Keychain service every secret for this Home is namespaced under.
    ///
    /// Deliberately **lexical** — `standardizedFileURL.path`, with no symlink
    /// resolution and no filesystem access. A derivation that consulted the disk
    /// could return one name before the vault exists and another after, which would
    /// silently strand secrets written during the same session.
    var keychainServiceName: String {
        let path = vaultRoot.standardizedFileURL.path
        if Home.canonicalVaultRoots.contains(where: { $0.standardizedFileURL.path == path }) {
            return Home.canonicalKeychainService
        }
        // Hashed rather than path-appended: Keychain service names are opaque
        // strings, and a vault path can be long, non-ASCII, or something the user
        // would not want surfaced in a Keychain Access listing.
        let digest = SHA256.hash(data: Data(path.utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(Home.canonicalKeychainService).vault.\(digest)"
    }
}
