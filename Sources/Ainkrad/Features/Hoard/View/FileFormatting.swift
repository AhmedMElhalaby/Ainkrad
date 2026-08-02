import Foundation

/// Byte count for display. Directories show an em-dash rather than "0 bytes":
/// their size is unknown, not zero, and claiming zero is a lie.
func formattedSize(_ bytes: Int64, isDirectory: Bool) -> String {
    guard !isDirectory else { return "—" }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

/// Time for today's files, date for anything older — the Finder convention,
/// which puts the most useful precision where it is actually informative.
/// `now` is a parameter so this is testable without freezing the clock.
func formattedDate(_ date: Date, now: Date) -> String {
    let formatter = DateFormatter()
    if Calendar.current.isDate(date, inSameDayAs: now) {
        formatter.dateStyle = .none
        formatter.timeStyle = .short
    } else {
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
    }
    return formatter.string(from: date)
}

/// Cumulative path segments for the breadcrumb — each carrying the URL to
/// navigate to when clicked. Pure.
func breadcrumbComponents(for url: URL) -> [(name: String, url: URL)] {
    var result: [(name: String, url: URL)] = [("/", URL(fileURLWithPath: "/"))]
    var accumulated = URL(fileURLWithPath: "/")
    for component in url.pathComponents.dropFirst() {
        accumulated = accumulated.appendingPathComponent(component)
        result.append((component, accumulated))
    }
    return result
}

/// The footer's one-line summary of the current folder or selection.
func selectionSummary(entries: [FileEntry], selection: Set<URL>) -> String {
    guard !entries.isEmpty else { return "Empty" }
    if selection.isEmpty {
        return entries.count == 1 ? "1 item" : "\(entries.count) items"
    }
    let selected = entries.filter { selection.contains($0.url) }
    let bytes = selected.reduce(Int64(0)) { $0 + $1.size }
    let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    return "\(selected.count) of \(entries.count) selected — \(size)"
}

/// SF Symbol for an entry, by extension. Deliberately a small hand-picked map
/// rather than `NSWorkspace.icon(forFile:)`: the HUD design language wants
/// monochrome symbols tinted from the theme, not macOS's colored file icons.
func iconName(for entry: FileEntry) -> String {
    if entry.isDirectory { return "folder" }
    switch entry.fileExtension {
    case "swift": return "swift"
    case "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff": return "photo"
    case "mp4", "mov", "avi", "mkv": return "film"
    case "mp3", "wav", "aac", "flac", "m4a": return "waveform"
    case "zip", "tar", "gz", "bz2", "xz", "7z": return "archivebox"
    case "pdf": return "doc.richtext"
    case "md", "txt", "rtf": return "doc.text"
    case "json", "yml", "yaml", "toml", "plist", "xml": return "curlybraces"
    case "sh", "bash", "zsh", "fish": return "terminal"
    case "js", "ts", "py", "rb", "go", "rs", "c", "h", "cpp", "java":
        return "chevron.left.forwardslash.chevron.right"
    default: return "doc"
    }
}
