import SwiftUI
import AinkradAppKit
import AinkradHostRuntime

/// View-model for `MemoryUIView`: owns the three files' in-progress drafts
/// and the save/undo actions, kept separate from the view body so the
/// edit/undo logic is unit-testable without instantiating SwiftUI.
///
/// Save is an overwrite (not `MemoryService.write`'s append semantics — the
/// draft already contains the whole file's text), so it goes through
/// `store.write` + `log.record` directly with provenance `.edit`, mirroring
/// `MemoryConsolidator`'s own full-content-replace pattern. A no-op save
/// (draft unchanged from disk) skips the write/reindex/log churn.
@MainActor
@Observable
final class MemoryUIViewModel {
    let service: MemoryService
    private(set) var drafts: [MemoryFile: String]

    init(service: MemoryService) {
        self.service = service
        var initial: [MemoryFile: String] = [:]
        for file in MemoryFile.allCases { initial[file] = service.store.read(file) }
        self.drafts = initial
    }

    func draft(for file: MemoryFile) -> String { drafts[file] ?? "" }

    func setDraft(_ text: String, for file: MemoryFile) { drafts[file] = text }

    /// Whether `file`'s draft differs from what's currently on disk.
    func hasUnsavedChanges(_ file: MemoryFile) -> Bool {
        draft(for: file) != service.store.read(file)
    }

    /// Persists the draft as an edit, logging it with provenance `.edit` so
    /// it's reviewable/undoable in the log timeline. No-op when unchanged.
    func save(_ file: MemoryFile) {
        let prior = service.store.read(file)
        let text = draft(for: file)
        guard text != prior else { return }
        service.store.write(text, to: file)   // onChange reindexes
        service.log.record(file: file, provenance: .edit, addedText: text, priorSnapshot: prior)
    }

    var logEntries: [MemoryLogEntry] { service.log.entries() }

    /// Undoes a log entry and refreshes every draft from disk afterward, so
    /// an open editor for the restored file doesn't keep showing stale text
    /// (or clobber the restore on its next Save).
    func undo(_ id: UUID) {
        service.log.undo(id)
        for file in MemoryFile.allCases { drafts[file] = service.store.read(file) }
    }
}

/// Cardinal-HUD memory viewer/editor: the three always-loaded memory files
/// (USER.md / MEMORY.md / AGENTS.md) as editable text, plus a timeline of
/// every write the assistant has made on its own (with per-entry Undo).
/// Reads/writes exclusively through `MemoryService` — no direct file access.
@MainActor
struct MemoryUIView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: MemoryUIViewModel

    init(service: MemoryService) {
        _viewModel = State(initialValue: MemoryUIViewModel(service: service))
    }

    var body: some View {
        let tokens = environment.themeManager.tokens

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSectionHeader(title: "MEMORY FILES", tokens: tokens)

                ForEach(MemoryFile.allCases, id: \.self) { file in
                    fileEditor(file, tokens: tokens)
                }

                SettingsSectionHeader(title: "WHAT THE ASSISTANT HAS LEARNED", tokens: tokens)
                logTimeline(tokens: tokens)
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - File editors

    private func fileEditor(_ file: MemoryFile, tokens: DesignTokens) -> some View {
        let hasChanges = viewModel.hasUnsavedChanges(file)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(file.rawValue)
                    .font(AinkradFont.display(13, weight: .medium))
                    .foregroundStyle(tokens.foreground.opacity(0.9))
                if hasChanges {
                    Text("UNSAVED")
                        .font(AinkradFont.mono(8, weight: .medium))
                        .kerning(1.2)
                        .foregroundStyle(tokens.warning.opacity(0.9))
                }
                Spacer()
                AinkradButton(title: "Save", style: hasChanges ? .primary : .ghost) {
                    viewModel.save(file)
                }
            }

            AinkradTextArea(
                text: Binding(
                    get: { viewModel.draft(for: file) },
                    set: { viewModel.setDraft($0, for: file) }
                ),
                placeholder: "Empty — the assistant hasn't learned anything here yet.",
                minHeight: 120
            )
        }
        .padding(14)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.5)))
        .overlay(ChamferShape(cut: AinkradRadius.md).strokeBorder(tokens.accentPrimary.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Log timeline

    @ViewBuilder
    private func logTimeline(tokens: DesignTokens) -> some View {
        let entries = viewModel.logEntries

        if entries.isEmpty {
            AinkradEmptyState(
                icon: "brain",
                title: "Nothing learned yet",
                message: "Autonomous memory writes — from chats, /remember, and periodic consolidation — will show up here."
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    logRow(entry, tokens: tokens)
                }
            }
        }
    }

    private func logRow(_ entry: MemoryLogEntry, tokens: DesignTokens) -> some View {
        AinkradListRow(
            leading: {
                Image(systemName: provenanceIcon(entry.provenance))
                    .font(.system(size: 13))
                    .foregroundStyle(tokens.accentSecondary.opacity(0.85))
                    .frame(width: 18)
            },
            title: Self.summarize(entry.addedText),
            subtitle: "\(entry.file) · \(entry.provenance.rawValue) · \(Self.dateFormatter.string(from: entry.date))",
            trailing: {
                AinkradButton(title: "Undo", style: .secondary) {
                    viewModel.undo(entry.id)
                }
            }
        )
    }

    private func provenanceIcon(_ provenance: MemoryProvenance) -> String {
        switch provenance {
        case .agent: return "brain"
        case .remember: return "bookmark"
        case .consolidation: return "arrow.triangle.merge"
        case .edit: return "pencil"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Single-line row summary — long consolidation/edit payloads shouldn't
    /// blow out the row height; `AinkradListRow`'s title has no `lineLimit`
    /// of its own to lean on.
    private static func summarize(_ text: String) -> String {
        guard !text.isEmpty else { return "(empty)" }
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        return firstLine.count > 140 ? String(firstLine.prefix(140)) + "…" : firstLine
    }
}
