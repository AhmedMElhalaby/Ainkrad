import Foundation

/// Replaces a LEADING `~` with `home`. A tilde anywhere else is a legal
/// filename character and is left alone.
func expandTilde(_ path: String, home: URL) -> String {
    guard path == "~" || path.hasPrefix("~/") else { return path }
    if path == "~" { return home.path }
    return home.appendingPathComponent(String(path.dropFirst(2))).path
}

/// Tab-completion for the path bar. Returns the completed absolute path, or
/// `nil` when nothing matches or the parent directory can't be read.
///
/// With several matches it returns their longest common prefix — the shell
/// behaviour, which lets repeated Tab narrow the path instead of cycling
/// through candidates the user can't see.
func completePath(_ input: String, using fs: any FileSystemServing, home: URL) -> String? {
    let expanded = expandTilde(input, home: home)
    guard expanded.hasPrefix("/") else { return nil }

    let url = URL(fileURLWithPath: expanded)
    let parent = url.deletingLastPathComponent()
    let fragment = url.lastPathComponent

    guard let children = try? fs.contents(of: parent) else { return nil }
    let matches = children.filter {
        $0.name.lowercased().hasPrefix(fragment.lowercased())
    }
    guard !matches.isEmpty else { return nil }

    if matches.count == 1 {
        return parent.appendingPathComponent(matches[0].name).path
    }
    let common = longestCommonPrefix(matches.map(\.name))
    return parent.appendingPathComponent(common).path
}

/// Longest common prefix, compared case-insensitively but returning the casing
/// of the first candidate.
private func longestCommonPrefix(_ names: [String]) -> String {
    guard var prefix = names.first else { return "" }
    for name in names.dropFirst() {
        while !name.lowercased().hasPrefix(prefix.lowercased()) {
            prefix = String(prefix.dropLast())
            if prefix.isEmpty { return "" }
        }
    }
    return prefix
}
