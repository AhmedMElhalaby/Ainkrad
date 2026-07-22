// Sources/Ainkrad/Core/AgentKit/Auth/ClaudeOAuthLoginController.swift
import Foundation
import AppKit

/// Orchestrates the subscription OAuth login flow for the settings UI:
/// PKCE + state → open the browser authorize URL → loopback callback (falling
/// back to a pasted code/URL when the loopback port can't bind) → token
/// exchange → persisted via `OAuthCredentialStore`. Also supports importing an
/// existing Claude Code CLI login in place of a fresh browser round-trip.
@MainActor
final class ClaudeOAuthLoginController: ObservableObject {
    private let store: OAuthCredentialStore
    private let flow: ClaudeOAuthFlow
    private let importer: ClaudeCodeCredentialImporter
    private var pendingPKCE: PKCE?
    private var pendingState: String?

    @Published var authorizeURL: URL?
    @Published var usePasteFallback = false
    @Published var errorMessage: String?

    init(store: OAuthCredentialStore,
         flow: ClaudeOAuthFlow,
         importer: ClaudeCodeCredentialImporter = ClaudeCodeCredentialImporter()) {
        self.store = store; self.flow = flow; self.importer = importer
    }

    var canImportFromClaudeCode: Bool { importer.isAvailable }

    /// Pure parser for a pasted callback: a full redirect URL
    /// (`…/callback?code=…&state=…`), a `code#state` pair, or a bare code.
    /// Empty/whitespace-only input yields `nil`.
    nonisolated static func parsePastedCode(_ raw: String) -> CallbackResult? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let comps = URLComponents(string: s), comps.queryItems?.contains(where: { $0.name == "code" }) == true {
            return try? LoopbackCallbackServer.parseCallback(query: comps.query ?? "")
        }
        let parts = s.split(separator: "#", maxSplits: 1).map(String.init)
        return CallbackResult(code: parts[0], state: parts.count > 1 ? parts[1] : "")
    }

    func beginLogin(for connection: Connection) async {
        errorMessage = nil
        let pkce = PKCE.generate()
        let state = UUID().uuidString
        pendingPKCE = pkce; pendingState = state
        let url = ClaudeOAuthFlow.authorizeURL(state: state, challenge: pkce.challenge)
        authorizeURL = url
        NSWorkspace.shared.open(url)

        let server = LoopbackCallbackServer()
        do {
            let cb = try await server.waitForCallback(timeout: 300)
            try await complete(cb, for: connection)
        } catch LoopbackError.bindFailed {
            usePasteFallback = true    // UI shows the paste field + authorizeURL
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func pasteCode(_ raw: String, for connection: Connection) async {
        errorMessage = nil
        do {
            guard let cb = Self.parsePastedCode(raw) else { throw LoopbackError.malformedCallback }
            try await complete(cb, for: connection)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func importFromClaudeCode(for connection: Connection) {
        errorMessage = nil
        do {
            let token = try importer.load()
            store.store(token, for: connection.id, source: .claudeCodeImport)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case LoopbackError.malformedCallback:
            return "That code or link didn't look right. Try pasting it again."
        case ClaudeOAuthError.tokenEndpoint(let status, let body):
            let detail = body.isEmpty ? "" : " — \(body.prefix(300))"
            return "Sign-in failed (token endpoint \(status))\(detail)"
        case ClaudeOAuthError.allEndpointsFailed:
            return "Sign-in failed: couldn't reach the token endpoint."
        case ClaudeOAuthError.malformedResponse:
            return "Sign-in failed: unexpected token response."
        default:
            return "Sign-in failed: \(error.localizedDescription)"
        }
    }

    private func complete(_ cb: CallbackResult, for connection: Connection) async throws {
        guard let pkce = pendingPKCE, let state = pendingState else { throw LoopbackError.malformedCallback }
        guard cb.state.isEmpty || cb.state == state else { throw LoopbackError.malformedCallback } // CSRF guard
        let token = try await flow.exchange(code: cb.code, verifier: pkce.verifier, state: state)
        store.store(token, for: connection.id, source: .freshLogin)
        pendingPKCE = nil; pendingState = nil; usePasteFallback = false
    }
}
