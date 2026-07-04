import Foundation

/// Lets a plain `String` stand in as an `Error` so validation failures can be
/// carried as `Result<_, String>` — the reason text is already the payload
/// callers want (recorded verbatim in `PluginLoadFailure.reason`).
extension String: @retroactive Error {}

/// Validates a bundle's code signature before the host loads its code. The
/// returned failure string is the reason recorded for a skipped bundle.
protocol PluginSignaturePolicy {
    func validate(bundleURL: URL) -> Result<Void, String>
}

/// The default for un-enrolled development: accept any (incl. ad-hoc) signature,
/// logging what was accepted. NOT for production once Developer-ID lands.
struct DevModeSignaturePolicy: PluginSignaturePolicy {
    func validate(bundleURL: URL) -> Result<Void, String> {
        Log.registry.info("Dev-mode signature policy: accepting \(bundleURL.lastPathComponent, privacy: .public)")
        return .success(())
    }
}

/// SEAM for AIN-135: verifies a Developer-ID signature (e.g. via
/// `SecStaticCodeCreateWithPath` + a Developer-ID requirement). Not wired as
/// the default until Apple Developer-ID enrollment is complete.
struct DeveloperIDSignaturePolicy: PluginSignaturePolicy {
    func validate(bundleURL: URL) -> Result<Void, String> {
        .failure("Developer-ID verification not yet implemented (AIN-135)")
    }
}
