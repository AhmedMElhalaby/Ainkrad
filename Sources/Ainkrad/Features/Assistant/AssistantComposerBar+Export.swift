import AppKit
import SwiftUI
import AinkradAppKit

/// Export/redaction flow for `AssistantComposerBar` (M7 finalize Wave D, D2 —
/// extracted verbatim, no behavior change).
extension AssistantComposerBar {
    var exportTrigger: some View {
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
    var exportModalContent: some View {
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

    func performExport() {
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
}
