import SwiftUI
import AppKit
import SwiftTerm

/// A `LocalProcessTerminalView` that **debounces the PTY window size**.
///
/// SwiftTerm reflows the buffer *and* pushes the new size to the shell on every
/// pixel of a resize. That SIGWINCH flood makes prompts like Powerlevel10k
/// redraw repeatedly, leaving stacked/duplicated output. We can't override the
/// (public, non-open) `sizeChanged`, but `getWindowSize()` is `open` and is
/// what `sizeChanged` reads before calling `TIOCSWINSZ` — so during a rapid
/// resize we keep reporting the last *committed* size (no size change → no
/// SIGWINCH) and push the real size to the PTY once, after the resize settles.
/// The visible buffer still reflows live, so there's no lag.
final class AinkradTerminalView: LocalProcessTerminalView {
    private var committedSize: winsize?
    private var pendingSize: winsize?
    private var commitWork: DispatchWorkItem?

    override func getWindowSize() -> winsize {
        let real = super.getWindowSize()
        pendingSize = real

        // First call (process start) commits immediately.
        guard let committed = committedSize else {
            committedSize = real
            return real
        }

        scheduleCommit()
        return committed
    }

    /// After the size has been quiet briefly, push the real size to the PTY
    /// once (one SIGWINCH → one clean prompt redraw) and repaint.
    private func scheduleCommit() {
        commitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let size = self.pendingSize, self.process?.running == true else { return }
            self.committedSize = size
            var s = size
            _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: self.process.childfd, windowSize: &s)
            let terminal = self.getTerminal()
            terminal.refresh(startRow: 0, endRow: max(terminal.rows - 1, 0))
            self.needsDisplay = true
        }
        commitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
}

/// Hosts the terminal (an AppKit `NSView`) inside SwiftUI. Spawns the session's
/// PTY-backed login shell on creation and terminates it deterministically when
/// this view leaves the hierarchy — see ADR-0002 and Terminal App
/// Architecture.md. The resolved `appearance` (colors + ANSI palette + font +
/// cursor + transparency) applies live; the scrollbar is hidden until the user
/// scrolls. When translucent, the blurred backdrop is provided by a SwiftUI
/// `Material` behind this view (see TerminalBlockRootView).
struct TerminalContainerView: NSViewRepresentable {
    let session: TerminalSession
    let appearance: TerminalRenderAppearance

    func makeNSView(context: Context) -> AinkradTerminalView {
        let view = AinkradTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        apply(appearance, to: view, coordinator: context.coordinator)
        context.coordinator.installScrollReveal(for: view)
        view.startProcess(
            executable: session.shellPath,
            args: ["-l"],
            environment: nil,
            currentDirectory: session.workingDirectory.path
        )
        return view
    }

    func updateNSView(_ nsView: AinkradTerminalView, context: Context) {
        apply(appearance, to: nsView, coordinator: context.coordinator)
    }

    /// Applies the resolved appearance. Skips entirely when nothing changed —
    /// crucially, a resize does NOT change the appearance, so we don't re-set
    /// the font mid-resize (that runs resetFont/selectNone).
    private func apply(_ appearance: TerminalRenderAppearance, to view: AinkradTerminalView, coordinator: Coordinator) {
        guard coordinator.appliedAppearance != appearance else { return }
        coordinator.appliedAppearance = appearance

        let palette = appearance.ansi.compactMap(Self.terminalColor(hex:))
        if palette.count == 16 {
            view.installColors(palette)
        }
        // Translucent background lets the SwiftUI Material behind this view
        // (the blurred island/sky) show through. The layer must be non-opaque.
        let isTranslucent = appearance.backgroundOpacity < 1
        view.nativeBackgroundColor = Self.nsColor(hex: appearance.background)
            .withAlphaComponent(CGFloat(appearance.backgroundOpacity))
        view.wantsLayer = true
        view.layer?.isOpaque = !isTranslucent
        view.layer?.backgroundColor = .clear
        view.nativeForegroundColor = Self.nsColor(hex: appearance.foreground)
        view.caretColor = Self.nsColor(hex: appearance.cursor)
        view.selectedTextBackgroundColor = Self.nsColor(hex: appearance.selection)
        view.font = Self.font(family: appearance.fontFamily, size: appearance.fontSize)
        view.optionAsMetaKey = appearance.optionAsMeta
        view.getTerminal().setCursorStyle(Self.cursorStyle(shape: appearance.cursorShape, blink: appearance.cursorBlink))

        // Rebuilding history is comparatively heavy — only when it changes.
        if coordinator.appliedScrollback != appearance.scrollback {
            view.changeScrollback(appearance.scrollback)
            coordinator.appliedScrollback = appearance.scrollback
        }
    }

    private static func cursorStyle(shape: TerminalCursorShape, blink: Bool) -> CursorStyle {
        switch (shape, blink) {
        case (.block, true): return .blinkBlock
        case (.block, false): return .steadyBlock
        case (.underline, true): return .blinkUnderline
        case (.underline, false): return .steadyUnderline
        case (.bar, true): return .blinkBar
        case (.bar, false): return .steadyBar
        }
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

    static func dismantleNSView(_ nsView: AinkradTerminalView, coordinator: Coordinator) {
        coordinator.teardown()
        let pid = nsView.process.shellPid
        nsView.terminate()
        PTYReaper.reapAfterTerminate(pid)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        private let session: TerminalSession
        var appliedAppearance: TerminalRenderAppearance?
        var appliedScrollback: Int?

        private weak var terminalView: NSView?
        private weak var scroller: NSScroller?
        private var scrollMonitor: Any?
        private var hideWork: DispatchWorkItem?

        init(session: TerminalSession) {
            self.session = session
        }

        /// Hides SwiftTerm's always-on scrollbar and reveals it only while the
        /// pointer is scrolling over this terminal, hiding again shortly after.
        @MainActor
        func installScrollReveal(for view: NSView) {
            terminalView = view
            let scroller = view.subviews.compactMap { $0 as? NSScroller }.first
            self.scroller = scroller
            scroller?.scrollerStyle = .overlay
            scroller?.isHidden = true

            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleScroll(event)
                return event
            }
        }

        @MainActor
        private func handleScroll(_ event: NSEvent) {
            guard let view = terminalView, let scroller, event.window === view.window else { return }
            let point = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(point) else { return }

            scroller.isHidden = false
            hideWork?.cancel()
            let work = DispatchWorkItem { [weak scroller] in scroller?.isHidden = true }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
        }

        func teardown() {
            hideWork?.cancel()
            if let scrollMonitor {
                NSEvent.removeMonitor(scrollMonitor)
                self.scrollMonitor = nil
            }
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
