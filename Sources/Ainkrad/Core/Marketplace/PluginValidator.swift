import Foundation
import AinkradAppKit

/// Shared plugin metadata validation, used by both the load-time `PluginLoader`
/// and the install-time `PluginInstaller` so the two cannot drift.
enum PluginValidator {
    /// Conservative charset for `AinkradAppID`: it is interpolated into a
    /// filesystem path segment, so it must not contain separators or traversal.
    private static let appIDAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")

    static func isValidAppID(_ id: String) -> Bool {
        guard !id.isEmpty, id != ".", id != ".." else { return false }
        return id.unicodeScalars.allSatisfy { appIDAllowed.contains($0) }
    }

    /// Validates app-id safety, executable presence, and API-version
    /// compatibility (NOT signature — separate policy — and NOT `Bundle.load()`).
    static func validate(_ metadata: PluginBundleMetadata,
                         infoDictionary: [String: Any],
                         minSupportedAPIVersion: Int) -> Result<Void, PluginRejection> {
        guard isValidAppID(metadata.appID) else {
            return .failure(PluginRejection(reason: "invalid app id"))
        }
        // The host renames an installed bundle to `<appID>.bundle`; without an
        // explicit CFBundleExecutable, CFBundle's filename-based fallback then
        // can't find the executable and `Bundle.load()` fails cryptically.
        guard let exe = infoDictionary["CFBundleExecutable"] as? String, !exe.isEmpty else {
            return .failure(PluginRejection(reason: "missing CFBundleExecutable"))
        }
        guard AinkradAppKit.isCompatible(bundleAPIVersion: metadata.apiVersion,
                                         minSupported: minSupportedAPIVersion,
                                         current: AinkradAppKit.apiVersion) else {
            return .failure(PluginRejection(reason: "API version \(metadata.apiVersion) unsupported"))
        }
        return .success(())
    }
}
