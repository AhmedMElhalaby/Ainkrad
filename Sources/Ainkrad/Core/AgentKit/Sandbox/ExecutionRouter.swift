// Sources/Ainkrad/Core/AgentKit/Sandbox/ExecutionRouter.swift
import Foundation

enum ExecutionRouterError: Error, Equatable {
    /// The resolved backend's `isAvailable()` returned false, or no backend was
    /// registered for the resolved profile's `SandboxBackendKind`. NEVER
    /// substituted with host — the run is blocked.
    case backendUnavailable(SandboxBackendKind, String)
    /// The resolved profile targets `.cloud` but the Agent's policy did not
    /// explicitly set `allowCloud == true`. A tier alone never yields cloud.
    case cloudNotOptedIn
}

/// Chooses the backend + profile for a run from its trust tier + Agent policy.
///
/// Fail-closed invariants (do not weaken):
/// - `HostBackend` is reachable ONLY for `.mainInteractive`. Every other tier
///   resolves to a sandboxed profile; a policy naming a `.host` profile for a
///   non-main tier is downgraded to the restrictive default unless the named
///   profile explicitly sets `allowHostOverride == true` (persisted opt-in,
///   never a default).
/// - An unknown/unresolvable `sandboxProfileID` falls back to the tier's
///   restrictive default — never an error that could be mishandled upstream,
///   never escalation.
/// - `.cloud` requires `policy.allowCloud == true`; otherwise throws.
/// - If the resolved backend is unavailable (or unregistered), `route` throws
///   `.backendUnavailable` — it never substitutes a different (more
///   permissive) backend, and never falls back to host.
@MainActor
final class ExecutionRouter {
    private let profiles: SandboxProfileStore
    private let backends: [SandboxBackendKind: any ExecutionBackend]

    init(profiles: SandboxProfileStore, backends: [SandboxBackendKind: any ExecutionBackend]) {
        self.profiles = profiles
        self.backends = backends
    }

    /// Resolves the `SandboxProfile` for a (tier, policy) pair, applying the
    /// no-silent-escalation guard. Pure/synchronous — does not check backend
    /// availability (that happens in `route`).
    func resolveProfile(tier: TrustTier, policy: AgentExecutionPolicy?) -> SandboxProfile {
        let workspaceWrite = profiles.profile(id: BuiltInSandboxProfiles.defaultNonMainID)
            ?? BuiltInSandboxProfiles.workspaceWrite

        // Explicit per-Agent profile takes precedence when it resolves to a
        // known profile. An unknown id is NOT an error here — it falls back
        // to the tier's restrictive default (fail-closed, never a crash and
        // never an implicit escalation).
        if let id = policy?.sandboxProfileID, let p = profiles.profile(id: id) {
            // No silent escalation: a non-main tier may only use a `.host`
            // profile when that profile explicitly opted in.
            if p.backend == .host && tier != .mainInteractive && !p.allowHostOverride {
                return workspaceWrite
            }
            return p
        }

        switch tier {
        case .mainInteractive:
            return profiles.profile(id: BuiltInSandboxProfiles.mainID) ?? BuiltInSandboxProfiles.hostTrusted
        case .background, .scheduled, .subagent, .untrustedMCP:
            return workspaceWrite
        }
    }

    /// Resolves the backend + profile and verifies the backend is actually
    /// available. Fail-closed: unavailable/unregistered backends throw rather
    /// than falling back to a more permissive backend (host in particular).
    func route(tier: TrustTier, policy: AgentExecutionPolicy?) async throws
        -> (any ExecutionBackend, SandboxProfile) {
        let profile = resolveProfile(tier: tier, policy: policy)

        // Cloud is opt-in per-Agent, never a tier default. Checked before
        // backend lookup so an unregistered cloud backend never masks a
        // missing opt-in as a generic "unavailable" error.
        if profile.backend == .cloud && policy?.allowCloud != true {
            throw ExecutionRouterError.cloudNotOptedIn
        }
        guard let backend = backends[profile.backend] else {
            throw ExecutionRouterError.backendUnavailable(profile.backend, "No backend registered.")
        }
        guard await backend.isAvailable() else {
            throw ExecutionRouterError.backendUnavailable(
                profile.backend,
                "Backend \(profile.backend.rawValue) is unavailable — run blocked (never falls back to host).")
        }
        return (backend, profile)
    }
}
