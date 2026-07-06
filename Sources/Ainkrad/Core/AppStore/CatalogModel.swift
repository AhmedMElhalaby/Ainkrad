import Foundation

/// One installable app in the catalog, assembled from a repo's latest release.
struct CatalogEntry: Equatable, Identifiable, Codable {
    var id: String { appID }
    let appID: String
    let displayName: String
    let icon: String
    let description: String
    let version: String        // release tag_name
    let apiVersion: Int
    let downloadURL: URL       // the .bundle.zip asset
    let sha256: String
    let sourceRepo: String     // "owner/repo"
}

/// The `ainkrad-plugin.json` asset attached to each release.
struct PluginManifest: Codable, Equatable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let apiVersion: Int
    let sha256: String
}

/// Minimal subset of the GitHub "releases/latest" response.
struct GHRelease: Decodable, Equatable {
    let tagName: String
    let assets: [GHAsset]
    enum CodingKeys: String, CodingKey { case tagName = "tag_name"; case assets }
}
struct GHAsset: Decodable, Equatable {
    let name: String
    let browserDownloadURL: URL
    enum CodingKeys: String, CodingKey { case name; case browserDownloadURL = "browser_download_url" }
}
