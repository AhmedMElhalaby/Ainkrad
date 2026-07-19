import Foundation

/// A single active background run as the menu-bar popover shows it.
struct MenuBarRunItem: Equatable, Identifiable {
    let id: UUID
    let title: String
    let isActive: Bool   // running (true) vs queued/paused (false)
}

/// Seam over Slice-3 `RunManager`. Keeps the menu-bar subsystem compiling and
/// testable without a hard dependency on the (PROVISIONAL) RunManager type.
@MainActor
protocol MenuBarRunSource: AnyObject {
    var activeRunItems: [MenuBarRunItem] { get }
    func stopRun(_ id: UUID)
}

/// Used until Slice 3 lands and in tests: reports no runs, stops nothing.
@MainActor
final class EmptyMenuBarRunSource: MenuBarRunSource {
    var activeRunItems: [MenuBarRunItem] { [] }
    func stopRun(_ id: UUID) {}
}
