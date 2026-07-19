import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AinkradAppKit

/// The Assistant composer: one seamless neon surface (soft elevated fill) with a
/// bottom control strip holding the connection·model pill, the compact
/// permission-mode select, and send. Owns the draft binding shared with
/// `AssistantRootView`. The text field is `AinkradTextArea`, which carries its
/// own chamfer focus ring.
///
/// M7 Slice 5c Task 22b adds four surfaces on top of the existing bar: the
/// `/`-triggered `CommandPaletteView`, the `@`-triggered `MentionOverlayView`,
/// image drag-and-drop, and an export/redaction flow — see the doc comments
/// on each below.
struct AssistantComposerBar: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.ainkradToastCenter) private var toastCenter
    let session: AgentSession
    let tokens: DesignTokens
    let modelPicker: AssistantModelPickerModel
    @Binding var draft: String
    var autoFocusOnAppear: Bool = false
    @State private var isUsageDashboardPresented = false
    @State private var isRunsPanelPresented = false
    /// M7 Slice 3b (Autonomy: scheduling/triggers) — presents `ScheduleUIView`,
    /// same `.ainkradModal` pattern as the Runs panel below.
    @State private var isSchedulesPresented = false

    /// Images attached via drag-and-drop, carried into the NEXT `session.send`
    /// call and cleared on send (or on manual removal via its chip's ✕).
    @State private var pendingImages: [ImageAttachment] = []

    /// Slash-command palette state. `paletteQuery` is derived from `draft`
    /// (see `ComposerTriggers.paletteQuery`) rather than a separate text
    /// field — the palette has no input of its own, it reads the composer's.
    @State private var isPaletteVisible = false
    @State private var paletteQuery = ""
    @State private var paletteSelectedIndex = 0

    /// `@`-mention overlay state — same shape as the palette's.
    @State private var isMentionVisible = false
    @State private var mentionQuery = ""
    @State private var mentionSelectedIndex = 0

    /// Export/redaction modal state.
    @State private var isExportModalPresented = false
    @State private var redactionsText = ""

    var body: some View {
        let isBusy = AssistantComposerBar.isBusy(session.state)

        return VStack(alignment: .leading, spacing: 8) {
            if !pendingImages.isEmpty {
                attachmentChips
            }

            AinkradTextArea(text: $draft, placeholder: "Message Assistant…",
                            minHeight: 34, maxHeight: 80, autoFocus: autoFocusOnAppear,
                            onSubmit: { send() })
                .disabled(isBusy)
                .onDrop(of: [.image, .fileURL], isTargeted: nil, perform: handleDrop)

            HStack(spacing: 8) {
                AgentSwitcherView(store: environment.agentStore, tokens: tokens)

                AssistantConnectionModelPicker(
                    model: modelPicker,
                    tokens: tokens,
                    onManageConnections: { environment.isSettingsPresented = true }
                )

                permissionModeSelect

                Spacer(minLength: 8)

                exportTrigger

                runsPanelTrigger

                schedulesTrigger

                usageDashboardTrigger

                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(canSend(isBusy: isBusy) ? tokens.accentSecondary : tokens.foreground.opacity(0.25))
                }
                .buttonStyle(.plain)
                .disabled(!canSend(isBusy: isBusy))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(ChamferShape(cut: AinkradRadius.md).fill(tokens.surfaceElevated.opacity(0.45)))
        .ainkradModal(isPresented: $isUsageDashboardPresented) {
            UsageDashboardView(tracker: environment.usageTracker, tokens: tokens)
        }
        .ainkradModal(isPresented: $isExportModalPresented) {
            exportModalContent
        }
        .ainkradModal(isPresented: $isRunsPanelPresented) {
            RunsPanelView(manager: environment.runManager, tokens: tokens)
        }
        .ainkradModal(isPresented: $isSchedulesPresented) {
            ScheduleUIView(store: environment.scheduleStore)
        }
        .background(
            // Tab-cycle affordance (M7 Slice 5a Task 5): swallows a plain Tab
            // keyDown to advance the active agent, but ONLY when the draft is
            // empty — otherwise Tab still moves keyboard focus as normal. A
            // remappable `ShortcutAction` binding is explicitly deferred; this
            // is a local (app-scoped, not global) monitor, same pattern as
            // `KeyboardShortcutMonitor`.
            ComposerTabCycleMonitor(
                isDraftEmpty: { draft.isEmpty },
                onCycle: { environment.agentStore.cycleActive() }
            )
        )
        .background(
            // Up/Down navigates whichever overlay (palette or mention) is
            // currently visible; Return confirms the highlighted row. Esc is
            // NOT handled here — `.ainkradFloatingPanel` already dismisses on
            // Esc via its own monitor. Same local-monitor pattern as
            // `ComposerTabCycleMonitor` (Slice 1 Task 13's established
            // "confirm kit affordances at build time" convention).
            ComposerOverlayKeyMonitor(
                isActive: { isPaletteVisible || isMentionVisible },
                onUp: { moveSelection(by: -1) },
                onDown: { moveSelection(by: 1) },
                onConfirm: { confirmSelection() }
            )
        )
        .ainkradFloatingPanel(isPresented: $isPaletteVisible, maxHeight: 260) {
            CommandPaletteView(
                commands: environment.commandRegistry.all(),
                query: paletteQuery,
                selectedIndex: $paletteSelectedIndex,
                tokens: tokens,
                onSelect: insertCommand
            )
        }
        .ainkradFloatingPanel(isPresented: $isMentionVisible, maxHeight: 260) {
            MentionOverlayView(
                matches: mentionMatches,
                selectedIndex: $mentionSelectedIndex,
                tokens: tokens,
                onSelect: insertMention
            )
        }
        .ainkradToastHost()
        .onChange(of: draft) { _, newValue in updateOverlayTriggers(newValue) }
        .padding(14)
    }

    // MARK: - Command palette / mention overlay

    private var filteredCommands: [SlashCommand] {
        CommandPaletteView.filter(environment.commandRegistry.all(), query: paletteQuery)
    }

    private var mentionMatches: [FileMatch] {
        environment.workspaceFileIndex.search(mentionQuery, limit: 8)
    }

    /// Recomputes trigger state from the live draft. The palette wins when
    /// both could apply (it can't in practice — the palette only fires on a
    /// LEADING `/`, the mention overlay on a trailing `@` token — but the
    /// precedence keeps this deterministic if that ever changes).
    private func updateOverlayTriggers(_ text: String) {
        if let q = ComposerTriggers.paletteQuery(in: text) {
            if !isPaletteVisible { paletteSelectedIndex = 0 }
            paletteQuery = q
            isPaletteVisible = true
            isMentionVisible = false
            return
        }
        isPaletteVisible = false

        if let q = ComposerTriggers.mentionQuery(in: text) {
            if !isMentionVisible { mentionSelectedIndex = 0 }
            mentionQuery = q
            isMentionVisible = true
        } else {
            isMentionVisible = false
        }
    }

    private func moveSelection(by delta: Int) {
        if isPaletteVisible {
            let count = filteredCommands.count
            guard count > 0 else { return }
            paletteSelectedIndex = (paletteSelectedIndex + delta + count) % count
        } else if isMentionVisible {
            let count = mentionMatches.count
            guard count > 0 else { return }
            mentionSelectedIndex = (mentionSelectedIndex + delta + count) % count
        }
    }

    private func confirmSelection() {
        if isPaletteVisible {
            let rows = filteredCommands
            guard rows.indices.contains(paletteSelectedIndex) else { return }
            insertCommand(rows[paletteSelectedIndex])
        } else if isMentionVisible {
            let rows = mentionMatches
            guard rows.indices.contains(mentionSelectedIndex) else { return }
            insertMention(rows[mentionSelectedIndex])
        }
    }

    /// Replaces the leading `/command` token being typed with `/name ` —
    /// the user keeps typing args (or presses Return/send to run it as-is,
    /// same as typing the whole command by hand).
    private func insertCommand(_ command: SlashCommand) {
        draft = "/\(command.name) "
        isPaletteVisible = false
    }

    /// Replaces the trailing `@query` token being typed with `@path ` —
    /// see `ComposerTriggers.trailingToken` for why "trailing" is the token
    /// this overlay always acts on (no cursor position is available).
    private func insertMention(_ match: FileMatch) {
        if let idx = draft.lastIndex(where: { $0.isWhitespace }) {
            let tokenStart = draft.index(after: idx)
            draft.replaceSubrange(tokenStart..., with: "@\(match.path) ")
        } else {
            draft = "@\(match.path) "
        }
        isMentionVisible = false
    }

    // MARK: - Image drop

    /// Attaches a dropped/pasted image or file URL. Accepts both `.image`
    /// (e.g. a Finder image drag, which vends `NSImage`-backed data) and
    /// `.fileURL` (a plain file path drag) — `ImageAttachment.from(fileURL:)`
    /// sniffs the actual bytes either way, so a non-image file URL is
    /// rejected rather than silently misattached.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in attach(fileURL: url) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    Task { @MainActor in attach(imageData: data) }
                }
            }
        }
        return handled
    }

    private func attach(fileURL: URL) {
        do {
            let attachment = try ImageAttachment.from(fileURL: fileURL)
            attachAndWarn(attachment)
        } catch {
            toastCenter.show("Couldn't attach \(fileURL.lastPathComponent) as an image.", status: .danger)
        }
    }

    private func attach(imageData: Data) {
        guard let mediaType = ImageAttachment.sniffMediaType(imageData), imageData.count <= ImageAttachment.maxBytes else {
            toastCenter.show("That image couldn't be attached (unsupported format or too large).", status: .danger)
            return
        }
        attachAndWarn(ImageAttachment(mediaType: mediaType, base64: imageData.base64EncodedString()))
    }

    /// Appends the attachment, then surfaces (never blocks on) a vision-gate
    /// warning if the current model can't accept images — Task 22's spec
    /// explicitly calls for a warning, not a hard block.
    private func attachAndWarn(_ attachment: ImageAttachment) {
        pendingImages.append(attachment)
        let modelID = session.activeModelIDForCommands()
        if let warning = visionGate(model: modelID, catalog: environment.modelCatalog, hasImage: true) {
            toastCenter.show(warning, status: .warning)
        }
    }

    private var attachmentChips: some View {
        HStack(spacing: 6) {
            ForEach(Array(pendingImages.enumerated()), id: \.offset) { index, attachment in
                AinkradChip(label: attachment.mediaType, systemName: "photo") {
                    pendingImages.remove(at: index)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Export

    private var exportTrigger: some View {
        Button { isExportModalPresented = true } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14))
                .foregroundStyle(tokens.foreground.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help("Export conversation")
    }

    /// Redaction/confirm modal content. Rendering + writing happens on
    /// confirm (`performExport`): `ConversationExporter.export` runs with the
    /// user's comma-separated redaction strings, the result is copied to the
    /// clipboard AND written to a user-chosen file via `NSSavePanel`.
    private var exportModalContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export conversation")
                .font(AinkradFont.display(14, weight: .semibold))
                .foregroundStyle(tokens.foreground)
            Text("Strings to redact, comma-separated (optional)")
                .font(AinkradFont.display(11))
                .foregroundStyle(tokens.foreground.opacity(0.6))
            AinkradTextField(text: $redactionsText, placeholder: "e.g. sk-live-…, jane@example.com")

            HStack {
                AinkradButton(title: "Cancel", style: .ghost) { isExportModalPresented = false }
                Spacer(minLength: 8)
                AinkradButton(title: "Export…", style: .primary) { performExport() }
            }
        }
    }

    private func performExport() {
        let redactions = redactionsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let rendered = ConversationExporter.export(session.messages, format: .markdown, redactions: redactions)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(rendered, forType: .string)

        isExportModalPresented = false

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "conversation.md"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try rendered.write(to: url, atomically: true, encoding: .utf8)
                toastCenter.show("Exported the conversation to \(url.lastPathComponent).", status: .success)
            } catch {
                toastCenter.show("Copied to clipboard, but couldn't write the file.", status: .warning)
            }
        }
        toastCenter.show("Copied the transcript to your clipboard.", status: .success)
    }

    private var permissionModeSelect: some View {
        let store = environment.agentPermissionStore
        // `AinkradSelect` is a single `Binding<T>` with no on-change hook, so the
        // `store.setMode` write-back rides in the binding's setter.
        return AinkradSelect(
            items: AgentPermissionMode.allCases,
            selection: Binding(get: { store.mode }, set: { store.setMode($0) }),
            label: { AssistantComposerBar.title($0) }
        )
        .fixedSize()
    }

    /// Opens the `/usage` dashboard (session + cumulative tokens/cost/savings)
    /// in a scoped `.ainkradModal` — the same "gauge" glyph `/usage`'s text
    /// note already reports on, just visualized. A themed icon button, not a
    /// native control.
    /// Opens the live Runs monitor (M7 Slice 3 Task 11) — queue/active/history across
    /// every origin, pause/stop, in the same `.ainkradModal` pattern as Usage. A run
    /// started via `spawn_subagent` or a background schedule shows up here live, since
    /// this reads the SAME `RunManager` the run itself updates.
    private var runsPanelTrigger: some View {
        Button { isRunsPanelPresented = true } label: {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 14))
                .foregroundStyle(tokens.foreground.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help("Runs")
    }

    /// Opens the Scheduler (M7 Slice 3b) — create/edit `AgentSchedule`s (time,
    /// file-change, git-change, webhook triggers) in the same `.ainkradModal`
    /// pattern as Runs/Usage above. Uses `AinkradIconButton` (rather than the
    /// bare-`Button` idiom the sibling triggers above use) so this new trigger
    /// is a proper Cardinal HUD component, not a native control.
    private var schedulesTrigger: some View {
        AinkradIconButton(systemName: "clock.badge", size: 22, tooltip: "Schedules") {
            isSchedulesPresented = true
        }
    }

    private var usageDashboardTrigger: some View {
        Button { isUsageDashboardPresented = true } label: {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 14))
                .foregroundStyle(tokens.foreground.opacity(0.55))
        }
        .buttonStyle(.plain)
        .help("Usage & cost")
    }

    private func canSend(isBusy: Bool) -> Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !isBusy && (hasText || !pendingImages.isEmpty)
    }

    private func send() {
        guard canSend(isBusy: AssistantComposerBar.isBusy(session.state)) else { return }
        let text = draft
        let images = pendingImages
        draft = ""
        pendingImages = []
        isPaletteVisible = false
        isMentionVisible = false
        session.send(text, images: images)
    }

    static func isBusy(_ state: AgentSession.State) -> Bool {
        switch state {
        case .thinking, .streaming, .callingTool, .awaitingApproval: return true
        case .idle, .failed: return false
        }
    }

    static func title(_ mode: AgentPermissionMode) -> String {
        switch mode {
        case .ask: return "Ask"
        case .autoApprove: return "Auto"
        case .fullAuto: return "Full-auto"
        }
    }
}

/// Installs a local `keyDown` monitor (app-scoped, not global — mirrors
/// `KeyboardShortcutMonitor`'s established pattern) that swallows a plain Tab
/// keystroke to cycle the active agent, ONLY while the composer's draft is
/// empty — otherwise Tab is returned untouched so it keeps moving keyboard
/// focus everywhere else (M7 Slice 5a Task 5). Zero-size, invisible; attached
/// via `.background(...)` so it rides the composer's lifetime.
private struct ComposerTabCycleMonitor: NSViewRepresentable {
    let isDraftEmpty: () -> Bool
    let onCycle: () -> Void

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.isDraftEmpty = isDraftEmpty
        view.onCycle = onCycle
        return view
    }

    func updateNSView(_ nsView: MonitoringView, context: Context) {
        nsView.isDraftEmpty = isDraftEmpty
        nsView.onCycle = onCycle
    }

    final class MonitoringView: NSView {
        var isDraftEmpty: (() -> Bool)?
        var onCycle: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    // Tab, no modifiers (keyCode 48) — Shift-Tab and any
                    // Tab+modifier combo pass through untouched.
                    let isPlainTab = event.keyCode == 48
                        && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
                    if isPlainTab, self.isDraftEmpty?() == true {
                        self.onCycle?()
                        return nil
                    }
                    return event
                }
            } else if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

/// Pure trigger-detection over the live draft string — `AinkradTextArea`
/// exposes no cursor position or per-keystroke hook, so both triggers are
/// derived from `draft`'s current value alone (M7 Slice 5c Task 22b).
enum ComposerTriggers {
    /// The palette query when `text` is a LEADING `/` command still being
    /// typed — no space/newline yet — mirroring `CommandRegistry.parse`'s own
    /// "leading `/`" recognition exactly, so the palette only ever offers to
    /// complete something that would actually dispatch as a command. `nil`
    /// once a space follows (the user is now typing the command's args).
    static func paletteQuery(in text: String) -> String? {
        guard text.hasPrefix("/"), !text.contains(" "), !text.contains("\n") else { return nil }
        return String(text.dropFirst())
    }

    /// The mention query when the TRAILING whitespace-delimited token of
    /// `text` starts with `@`. Best-effort: since there's no cursor position,
    /// this assumes composing happens at the end of the draft — true for the
    /// overwhelming majority of chat-composer typing.
    static func mentionQuery(in text: String) -> String? {
        let token = trailingToken(of: text)
        guard token.hasPrefix("@") else { return nil }
        return String(token.dropFirst())
    }

    static func trailingToken(of text: String) -> String {
        guard let idx = text.lastIndex(where: { $0.isWhitespace }) else { return text }
        return String(text[text.index(after: idx)...])
    }
}

/// Local `keyDown` monitor (same app-scoped pattern as `ComposerTabCycleMonitor`)
/// that swallows Up/Down/Return while the palette or mention overlay is visible,
/// driving list navigation/confirmation — the overlays themselves have no text
/// field of their own to receive these keys, since their query comes from the
/// composer's own draft. Esc is deliberately NOT handled here:
/// `.ainkradFloatingPanel` already dismisses on Esc via its own monitor.
private struct ComposerOverlayKeyMonitor: NSViewRepresentable {
    let isActive: () -> Bool
    let onUp: () -> Void
    let onDown: () -> Void
    let onConfirm: () -> Void

    func makeNSView(context: Context) -> MonitoringView {
        let view = MonitoringView()
        view.isActive = isActive; view.onUp = onUp; view.onDown = onDown; view.onConfirm = onConfirm
        return view
    }

    func updateNSView(_ nsView: MonitoringView, context: Context) {
        nsView.isActive = isActive; nsView.onUp = onUp; nsView.onDown = onDown; nsView.onConfirm = onConfirm
    }

    final class MonitoringView: NSView {
        var isActive: (() -> Bool)?
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?
        var onConfirm: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, self.isActive?() == true else { return event }
                    switch event.keyCode {
                    case 126: self.onUp?(); return nil // Up arrow
                    case 125: self.onDown?(); return nil // Down arrow
                    case 36, 76: self.onConfirm?(); return nil // Return / keypad Enter
                    default: return event
                    }
                }
            } else if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
