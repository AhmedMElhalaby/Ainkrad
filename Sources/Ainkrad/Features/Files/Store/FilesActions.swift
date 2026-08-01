import Foundation
import Observation

/// What the pane is currently asking the user for.
enum FilesPrompt: Identifiable {
    case rename(FileEntry)
    case newFolder
    /// Copy or move with nowhere to send it — only one Files pane is open.
    case noDestination(isMove: Bool)

    var id: String {
        switch self {
        case .rename(let entry): return "rename-\(entry.url.path)"
        case .newFolder: return "new-folder"
        case .noDestination(let isMove): return "no-destination-\(isMove)"
        }
    }
}

/// Turns a pane's selection into `FileOperation`s and submits them.
///
/// Sits between the views and `FileOperationEngine` so the keyboard layer, the
/// context menu and (later) the assistant all go through ONE place that knows
/// how to read a selection, find the destination pane, and refresh afterwards.
@MainActor
@Observable
final class FilesActions {
    private let engine: FileOperationEngine
    private let coordinator: PaneCoordinator
    private let resolver: ConflictResolver
    private let store: FilesPaneStore
    private let paneToken: UUID

    private(set) var prompt: FilesPrompt?
    /// Last operation's user-facing summary, surfaced as a toast.
    private(set) var lastMessage: String?

    init(engine: FileOperationEngine, coordinator: PaneCoordinator,
         resolver: ConflictResolver, store: FilesPaneStore, paneToken: UUID) {
        self.engine = engine
        self.coordinator = coordinator
        self.resolver = resolver
        self.store = store
        self.paneToken = paneToken
    }

    private var tab: FilesTab { store.activeTab }

    /// The selection, or the cursor row when nothing is explicitly selected —
    /// so F5 with a cursor but no selection does the obvious thing instead of
    /// nothing.
    private var operands: [URL] {
        if !tab.selection.isEmpty {
            return tab.visibleEntries.filter { tab.selection.contains($0.url) }.map(\.url)
        }
        return tab.cursorEntry.map { [$0.url] } ?? []
    }

    func present(_ prompt: FilesPrompt?) { self.prompt = prompt }
    func clearMessage() { lastMessage = nil }

    // MARK: - Cross-pane transfer

    func copyToOtherPane() async { await transfer(isMove: false) }
    func moveToOtherPane() async { await transfer(isMove: true) }

    private func transfer(isMove: Bool) async {
        let sources = operands
        guard !sources.isEmpty else { return }
        guard let destination = coordinator.otherPane(than: paneToken) else {
            // One pane open: say so rather than silently doing nothing.
            prompt = .noDestination(isMove: isMove)
            return
        }

        resolver.reset()
        let operation = FileOperation(
            kind: isMove ? .move : .copy, sources: sources,
            destinationDirectory: destination.activeTab.currentDirectory)
        let result = await engine.submit(operation, conflictResolver: resolver.resolve)

        report(result, verb: isMove ? "Moved" : "Copied")
        tab.reload()
        destination.activeTab.reload()
    }

    // MARK: - In-place operations

    func beginRename() {
        guard let entry = tab.cursorEntry else { return }
        prompt = .rename(entry)
    }

    func commitRename(_ entry: FileEntry, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.name else { prompt = nil; return }
        let result = await engine.submit(FileOperation(
            kind: .rename(newName: trimmed), sources: [entry.url], destinationDirectory: nil))
        prompt = nil
        report(result, verb: "Renamed")
        tab.reload()
    }

    func beginNewFolder() { prompt = .newFolder }

    func commitNewFolder(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { prompt = nil; return }
        let result = await engine.submit(FileOperation(
            kind: .createFolder(name: trimmed), sources: [],
            destinationDirectory: tab.currentDirectory))
        prompt = nil
        report(result, verb: "Created")
        tab.reload()
    }

    func trashSelection() async {
        let sources = operands
        guard !sources.isEmpty else { return }
        let result = await engine.submit(FileOperation(
            kind: .trash, sources: sources, destinationDirectory: nil))
        report(result, verb: "Moved to Trash")
        tab.reload()
    }

    // MARK: - Reporting

    /// A one-line summary. Partial failure is reported honestly — "47 copied,
    /// 3 failed" — rather than a bare success that hides the three.
    private func report(_ result: OperationResult, verb: String) {
        var parts: [String] = []
        if result.succeeded > 0 { parts.append("\(verb.lowercased()) \(result.succeeded)") }
        if result.skipped > 0 { parts.append("\(result.skipped) skipped") }
        if !result.failures.isEmpty { parts.append("\(result.failures.count) failed") }
        if result.wasCancelled { parts.append("cancelled") }
        lastMessage = parts.isEmpty ? nil : parts.joined(separator: ", ").capitalizedFirst
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
