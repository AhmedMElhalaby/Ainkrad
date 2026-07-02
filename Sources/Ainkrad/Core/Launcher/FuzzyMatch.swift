/// Case-insensitive subsequence match: every character of `query`, in order,
/// appears somewhere in `target`. An empty query matches anything.
func fuzzyMatches(query: String, target: String) -> Bool {
    guard !query.isEmpty else { return true }

    var remaining = query.lowercased()[...]
    for char in target.lowercased() {
        guard let next = remaining.first else { break }
        if char == next {
            remaining.removeFirst()
        }
    }
    return remaining.isEmpty
}
