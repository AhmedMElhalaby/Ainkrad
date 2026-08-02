import Foundation

/// Maps a file path's extension to an SF Symbol for the `@`-mention overlay
/// rows. Pure and unit-testable — mirrors `ToolPresentation`. Matching is on
/// the lowercased path extension only (no I/O), with `doc.text` as fallback.
enum FileGlyph {
    static func symbol(forPath path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": return "swift"
        case "md", "markdown": return "doc.richtext"
        case "json", "yml", "yaml", "toml", "plist": return "curlybraces"
        case "js", "ts", "jsx", "tsx", "py", "rb", "go", "rs", "c", "h", "cpp", "sh":
            return "chevron.left.forwardslash.chevron.right"
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return "photo"
        case "pdf": return "doc.text.fill"
        default: return "doc.text"
        }
    }
}
