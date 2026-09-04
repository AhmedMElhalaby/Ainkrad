import Foundation
import AinkradSignal

/// How the user last left the feed.
///
/// Persisted because the alternative is rebuilding the same filter every time:
/// the two views anyone actually wants — "just the failures" and "just this
/// app" — take three clicks each, and having to redo them is what teaches
/// people to stop filtering at all.
struct SignalViewState: Codable, Equatable {
    enum Grouping: String, Codable { case byTime, bySource }

    var grouping: Grouping
    /// Nil is "All".
    var selectedSource: SignalSource?
    var severities: Set<SignalSeverity>
    var unreadOnly: Bool
    var collapsedSources: Set<String>

    init(grouping: Grouping = .byTime,
         selectedSource: SignalSource? = nil,
         severities: Set<SignalSeverity> = [],
         unreadOnly: Bool = false,
         collapsedSources: Set<String> = []) {
        self.grouping = grouping
        self.selectedSource = selectedSource
        self.severities = severities
        self.unreadOnly = unreadOnly
        self.collapsedSources = collapsedSources
    }

    /// Tolerant, like every other stored shape here: an unknown or missing
    /// field must leave the rest intact rather than reset the whole view.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grouping = try c.decodeIfPresent(Grouping.self, forKey: .grouping) ?? .byTime
        selectedSource = try c.decodeIfPresent(SignalSource.self, forKey: .selectedSource)
        severities = try c.decodeIfPresent(Set<SignalSeverity>.self, forKey: .severities) ?? []
        unreadOnly = try c.decodeIfPresent(Bool.self, forKey: .unreadOnly) ?? false
        collapsedSources = try c.decodeIfPresent(
            Set<String>.self, forKey: .collapsedSources) ?? []
    }

    /// The two views the user would otherwise rebuild by hand every time. Two,
    /// deliberately — a saved-view editor is a feature nobody has asked for.
    static let failures = SignalViewState(severities: [.failure], unreadOnly: true)

    var isShowingEverything: Bool {
        selectedSource == nil && severities.isEmpty && !unreadOnly
    }

    /// The store filter this view describes. Grouping and collapse are
    /// presentation only and deliberately absent.
    var filter: SignalFilter {
        SignalFilter(sources: selectedSource.map { [$0] },
                     severities: severities.isEmpty ? nil : severities,
                     unreadOnly: unreadOnly)
    }
}

/// JSON beside the preferences. Separate from `SignalPreferences` because this
/// is where the user was looking, not what they decided — losing it is a minor
/// annoyance, and it must never be able to corrupt a routing rule.
struct SignalViewStateStore {
    let url: URL

    func load() -> SignalViewState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SignalViewState.self, from: data)
        else { return SignalViewState() }
        return state
    }

    func save(_ state: SignalViewState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
