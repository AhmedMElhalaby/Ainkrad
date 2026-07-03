import SwiftUI
import AppKit
import SwiftTerm

/// Hosts SwiftTerm's `LocalProcessTerminalView` (an AppKit `NSView`) inside
/// SwiftUI. Spawns the session's PTY-backed login shell on creation and
/// terminates it deterministically when this view leaves the hierarchy —
/// see ADR-0002 Terminal Emulation Approach and Terminal App
/// Architecture.md. The resolved `appearance` (colors + ANSI palette + font)
/// is applied on creation and re-applied on every update, so a theme,
/// color-scheme, or font change restyles running terminals live.
struct TerminalContainerView: NSViewRepresentable {
    let session: TerminalSession
    let appearance: TerminalRenderAppearance

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        apply(appearance, to: view)
        view.startProcess(
            executable: session.shellPath,
            args: ["-l"],
            environment: nil,
            currentDirectory: session.workingDirectory.path
        )
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        apply(appearance, to: nsView)
    }

    /// Applies the resolved appearance: the 16-color ANSI palette, then the
    /// background/foreground/caret, then the font.
    private func apply(_ appearance: TerminalRenderAppearance, to view: LocalProcessTerminalView) {
        let palette = appearance.ansi.compactMap(Self.terminalColor(hex:))
        if palette.count == 16 {
            view.installColors(palette)
        }
        view.nativeBackgroundColor = Self.nsColor(hex: appearance.background)
        view.nativeForegroundColor = Self.nsColor(hex: appearance.foreground)
        view.caretColor = Self.nsColor(hex: appearance.cursor)
        view.font = Self.font(family: appearance.fontFamily, size: appearance.fontSize)
    }

    // MARK: - Color / font conversion

    private static func rgb(hex: String) -> (r: UInt8, g: UInt8, b: UInt8)? {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let int = UInt32(value, radix: 16) else { return nil }
        return (UInt8((int >> 16) & 0xFF), UInt8((int >> 8) & 0xFF), UInt8(int & 0xFF))
    }

    private static func nsColor(hex: String) -> NSColor {
        guard let c = rgb(hex: hex) else { return .black }
        return NSColor(
            srgbRed: CGFloat(c.r) / 255,
            green: CGFloat(c.g) / 255,
            blue: CGFloat(c.b) / 255,
            alpha: 1
        )
    }

    private static func terminalColor(hex: String) -> SwiftTerm.Color? {
        guard let c = rgb(hex: hex) else { return nil }
        // SwiftTerm.Color components are 16-bit; scale 8-bit up by 257.
        return SwiftTerm.Color(red: UInt16(c.r) * 257, green: UInt16(c.g) * 257, blue: UInt16(c.b) * 257)
    }

    private static func font(family: String, size: Double) -> NSFont {
        NSFont(name: family, size: CGFloat(size))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
    }

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        let pid = nsView.process.shellPid
        nsView.terminate()
        PTYReaper.reapAfterTerminate(pid)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private let session: TerminalSession

        init(session: TerminalSession) {
            self.session = session
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor [session] in
                session.terminate()
            }
        }
    }
}
