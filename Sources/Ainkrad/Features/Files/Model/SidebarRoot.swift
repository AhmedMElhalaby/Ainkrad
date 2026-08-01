import Foundation

/// One entry in the Files sidebar.
struct SidebarRoot: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// SF Symbol name — tinted from the theme at render time, never here.
    var icon: String
    var url: URL
}

/// The built-in roots, home first. Takes `home` as a parameter rather than
/// reading `FileManager` so it is pure and testable.
///
/// These are shown unconditionally, without checking existence: a missing
/// Desktop (possible with iCloud Desktop disabled) should render as an entry
/// whose listing fails visibly, not silently vanish from the sidebar.
func standardRoots(home: URL) -> [SidebarRoot] {
    [
        SidebarRoot(id: "home", name: "Home", icon: "house", url: home),
        SidebarRoot(id: "desktop", name: "Desktop", icon: "menubar.dock.rectangle",
                    url: home.appendingPathComponent("Desktop")),
        SidebarRoot(id: "documents", name: "Documents", icon: "doc",
                    url: home.appendingPathComponent("Documents")),
        SidebarRoot(id: "downloads", name: "Downloads", icon: "arrow.down.circle",
                    url: home.appendingPathComponent("Downloads")),
        SidebarRoot(id: "applications", name: "Applications", icon: "square.grid.2x2",
                    url: URL(fileURLWithPath: "/Applications"))
    ]
}
