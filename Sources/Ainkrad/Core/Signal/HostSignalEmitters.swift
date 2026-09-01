import Foundation
import AinkradSignal

extension SignalDraft {
    /// Maps a finished `AgentRun` onto the feed.
    ///
    /// `dedupeKey` is the run id: `finish(_:outcome:)` is guarded against
    /// double-calling, but a coalescing key costs nothing and makes a
    /// duplicated delivery invisible to the user rather than a doubled row.
    static func runCompleted(_ run: AgentRun) -> SignalDraft {
        let kind: String
        let severity: SignalSeverity
        let title: String
        switch run.status {
        case .done:
            kind = "run.finished"; severity = .success; title = "Run finished"
        case .failed:
            kind = "run.failed"; severity = .failure; title = "Run failed"
        case .interrupted:
            kind = "run.interrupted"; severity = .warning; title = "Run interrupted"
        case .queued, .running, .paused:
            kind = "run.updated"; severity = .info; title = "Run update"
        }
        var body = String(run.prompt.prefix(80))
        if let result = run.result, !result.isEmpty {
            body += "\n" + result.prefix(120)
        }
        return SignalDraft(kind: kind, severity: severity, title: title, body: body,
                           importance: run.status == .failed ? .urgent : .normal,
                           dedupeKey: "run:\(run.id.uuidString)")
    }

    /// An app finished installing or updating from the store.
    static func appInstalled(displayName: String) -> SignalDraft {
        SignalDraft(kind: "install.completed", severity: .success,
                    title: "\(displayName) installed", importance: .normal,
                    dedupeKey: "install:\(displayName)")
    }

    /// A plugin bundle failed to load. Almost always a pin mismatch, so the
    /// body says so rather than leaving the user to guess.
    static func appLoadFailed(displayName: String, reason: String) -> SignalDraft {
        SignalDraft(kind: "install.failed", severity: .failure,
                    title: "\(displayName) failed to load", body: reason,
                    importance: .urgent, dedupeKey: "loadfail:\(displayName)")
    }
}
