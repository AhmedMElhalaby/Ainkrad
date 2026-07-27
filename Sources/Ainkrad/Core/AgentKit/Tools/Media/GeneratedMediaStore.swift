import Foundation

/// Writes generated media bytes (video) to a stable on-disk location and returns
/// a `file:` URL, so large clips are referenced by path rather than embedded as a
/// base64 `data:` URL in the persisted canvas document. Base directory is
/// injectable for tests.
struct GeneratedMediaStore {
    let baseDirectory: URL

    /// Default: `~/Library/Application Support/<bundle>/GeneratedMedia`.
    init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let bundle = Bundle.main.bundleIdentifier ?? "Ainkrad"
            self.baseDirectory = support.appendingPathComponent(bundle, isDirectory: true)
                .appendingPathComponent("GeneratedMedia", isDirectory: true)
        }
    }

    /// Writes `data` to a new uniquely-named file with the given extension and
    /// returns its `file:` URL.
    func write(_ data: Data, fileExtension: String, id: String = UUID().uuidString) throws -> URL {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let url = baseDirectory.appendingPathComponent("\(id).\(fileExtension)")
        try data.write(to: url)
        return url
    }
}
