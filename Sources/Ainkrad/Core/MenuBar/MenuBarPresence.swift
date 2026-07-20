import Foundation

/// Observable state powering the menu-bar popover: open/closed plus a derived
/// live summary of background runs. UI-agnostic so it is unit-testable.
@MainActor
@Observable
final class MenuBarPresence {
    private let runs: MenuBarRunSource
    var isPopoverOpen = false

    init(runs: MenuBarRunSource) { self.runs = runs }

    func toggle() { isPopoverOpen.toggle() }
    func open() { isPopoverOpen = true }
    func close() { isPopoverOpen = false }

    var runItems: [MenuBarRunItem] { runs.activeRunItems }

    var runSummary: String {
        let items = runItems
        guard !items.isEmpty else { return "No active runs" }
        let running = items.filter(\.isActive).count
        if running == items.count { return "\(running) running" }
        if running == 0 { return "\(items.count) queued" }
        return "\(running) running · \(items.count - running) queued"
    }

    func stop(_ id: UUID) { runs.stopRun(id) }
}
