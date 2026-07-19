import Foundation

/// A named link surfaced on the app detail page (homepage, changelog,
/// support, …) — see AIN-147.
struct ManifestLink: Codable, Equatable {
    let title: String
    let url: URL
}

/// The kind of item a `CatalogEntry` represents. Defaults to `.plugin` on
/// decode so pre-existing (kind-less) catalog entries keep decoding
/// unchanged (see `CatalogEntry.init(from:)`).
enum CatalogItemKind: String, Codable, Equatable {
    case plugin
    case skill
}

/// Points at a raw `SKILL.md` asset for a `.skill` catalog entry — a
/// markdown file, not a zip/`dlopen`-loaded plugin bundle. For `.skill`
/// entries, `CatalogEntry.downloadURL`/`sha256` are unused.
struct SkillCatalogDescriptor: Codable, Equatable {
    let contentURL: URL
}

/// One installable app in the catalog, assembled from a repo's latest release.
///
/// `author`/`longDescription`/`screenshots`/`links` (AIN-147) are additive
/// detail-page metadata. `screenshots`/`links` default to `[]` — both in the
/// memberwise initializer and when decoding a pre-AIN-147 cached catalog
/// JSON that has no such keys — so existing callers/persisted caches are
/// unaffected.
///
/// `kind`/`skill` are additive too: `kind` defaults to `.plugin` and `skill`
/// to `nil` when decoding a pre-existing (kind-less) catalog entry, so
/// existing plugin-only catalogs keep decoding unchanged.
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
    let author: String?
    let longDescription: String?
    let screenshots: [URL]
    let links: [ManifestLink]
    let kind: CatalogItemKind
    let skill: SkillCatalogDescriptor?

    init(appID: String, displayName: String, icon: String, description: String, version: String,
         apiVersion: Int, downloadURL: URL, sha256: String, sourceRepo: String,
         author: String? = nil, longDescription: String? = nil,
         screenshots: [URL] = [], links: [ManifestLink] = [],
         kind: CatalogItemKind = .plugin, skill: SkillCatalogDescriptor? = nil) {
        self.appID = appID
        self.displayName = displayName
        self.icon = icon
        self.description = description
        self.version = version
        self.apiVersion = apiVersion
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.sourceRepo = sourceRepo
        self.author = author
        self.longDescription = longDescription
        self.screenshots = screenshots
        self.links = links
        self.kind = kind
        self.skill = skill
    }

    enum CodingKeys: String, CodingKey {
        case appID, displayName, icon, description, version, apiVersion, downloadURL, sha256, sourceRepo
        case author, longDescription, screenshots, links, kind, skill
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appID = try c.decode(String.self, forKey: .appID)
        displayName = try c.decode(String.self, forKey: .displayName)
        icon = try c.decode(String.self, forKey: .icon)
        description = try c.decode(String.self, forKey: .description)
        version = try c.decode(String.self, forKey: .version)
        apiVersion = try c.decode(Int.self, forKey: .apiVersion)
        downloadURL = try c.decode(URL.self, forKey: .downloadURL)
        sha256 = try c.decode(String.self, forKey: .sha256)
        sourceRepo = try c.decode(String.self, forKey: .sourceRepo)
        author = try c.decodeIfPresent(String.self, forKey: .author)
        longDescription = try c.decodeIfPresent(String.self, forKey: .longDescription)
        screenshots = try c.decodeIfPresent([URL].self, forKey: .screenshots) ?? []
        links = try c.decodeIfPresent([ManifestLink].self, forKey: .links) ?? []
        kind = try c.decodeIfPresent(CatalogItemKind.self, forKey: .kind) ?? .plugin
        skill = try c.decodeIfPresent(SkillCatalogDescriptor.self, forKey: .skill)
    }
}

extension CatalogEntry {
    /// True iff this entry is a well-formed `.skill` entry (has a descriptor).
    /// A `.skill`-kind entry missing its descriptor is malformed and should
    /// be treated as skippable rather than fatal, mirroring existing catalog
    /// skip behavior for other malformed entries.
    var isValidSkillEntry: Bool {
        kind == .skill && skill != nil
    }
}

/// The `ainkrad-plugin.json` asset attached to each release.
///
/// `author`/`longDescription`/`screenshots`/`links` (AIN-147) are optional so
/// manifests published before AIN-147 keep decoding unchanged (they simply
/// decode to `nil`).
struct PluginManifest: Codable, Equatable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let apiVersion: Int
    let sha256: String
    let author: String?
    let longDescription: String?
    let screenshots: [URL]?
    let links: [ManifestLink]?
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
