import Foundation

/// Turns committed `@file` mentions into an appended `<mentioned_files>`
/// context block on the outgoing user text. Pure: the file reader is
/// injected, so tests never touch disk. Only `.embed` mentions whose content
/// actually resolves are inlined; `.reference` (and unreadable large/binary)
/// mentions stay as the `@path` token already present in `text`.
enum MentionContentResolver {
    static func augment(text: String, mentions: [ComposerMention], read: (String) -> String?) -> String {
        let sections: [String] = mentions.compactMap { mention in
            guard mention.mode == .embed, let content = read(mention.path) else { return nil }
            return "### \(mention.path)\n\(content)"
        }
        guard !sections.isEmpty else { return text }
        let block = "<mentioned_files>\n" + sections.joined(separator: "\n\n") + "\n</mentioned_files>"
        return text.isEmpty ? block : text + "\n\n" + block
    }
}
