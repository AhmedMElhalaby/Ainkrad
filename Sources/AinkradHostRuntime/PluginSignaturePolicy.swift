import Foundation

/// Dedicated error type for signature-policy failures — carries the reason
/// text that gets recorded verbatim in `PluginLoadFailure.reason`.
public struct PluginRejection: Error {
    public let reason: String
    public init(reason: String) { self.reason = reason }
}

extension PluginRejection: Equatable {}

/// Validates a bundle's code signature before the host loads its code. The
/// returned failure's reason is the text recorded for a skipped bundle.
public protocol PluginSignaturePolicy {
    func validate(bundleURL: URL) -> Result<Void, PluginRejection>
}

/// The default for un-enrolled development: accept any (incl. ad-hoc) signature,
/// logging what was accepted. NOT for production once Developer-ID lands.
public struct DevModeSignaturePolicy: PluginSignaturePolicy {
    public init() {}
    public func validate(bundleURL: URL) -> Result<Void, PluginRejection> {
        Log.registry.info("Dev-mode signature policy: accepting \(bundleURL.lastPathComponent, privacy: .public)")
        return .success(())
    }
}

/// SEAM for AIN-135: verifies a Developer-ID signature (e.g. via
/// `SecStaticCodeCreateWithPath` + a Developer-ID requirement). Not wired as
/// the default until Apple Developer-ID enrollment is complete.
public struct DeveloperIDSignaturePolicy: PluginSignaturePolicy {
    public init() {}
    public func validate(bundleURL: URL) -> Result<Void, PluginRejection> {
        .failure(PluginRejection(reason: "Developer-ID verification not yet implemented (AIN-135)"))
    }
}
