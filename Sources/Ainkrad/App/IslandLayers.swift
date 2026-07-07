import Foundation

/// One element of the layered Living Island artwork. Positions are normalized
/// to the fitted 1.5-aspect art rect (origin top-left). Seeded from the
/// extraction in `~/Herd/island-layers-ai/` (alpha bounding boxes +
/// islet-positions.json). This table is the single place to fine-tune the
/// composition — edit values and rebuild.
struct IslandLayer: Identifiable, Equatable {
    enum Kind { case cloud, islet, ring, citadel, chevron, logo, slogan }
    let id: String            // asset name, e.g. "Island-Blue-Cloud-0"
    let kind: Kind
    let cx: Double            // center X, 0…1 of art rect
    let cy: Double            // center Y, 0…1 of art rect
    let width: Double         // width, fraction of art rect width; height follows sprite aspect
    let z: Int                // draw order; lower is farther back
    let seed: Int?            // motion seed for clouds/islets; nil for fixed elements
}

enum IslandLayers {
    static let all: [IslandLayer] = [
        IslandLayer(id: "Island-Blue-Ring",     kind: .ring,    cx: 0.5000, cy: 0.4995, width: 0.4350, z: 20, seed: nil),

        // Clouds sit in the visible sky AROUND the citadel silhouette (sides,
        // corners, and beside the narrow hanging spire) — not behind its
        // opaque body, where they'd be hidden.
        IslandLayer(id: "Island-Blue-Cloud-0",  kind: .cloud,   cx: 0.3900, cy: 0.4200, width: 0.1500, z: 10, seed: 0),
        IslandLayer(id: "Island-Blue-Cloud-1",  kind: .cloud,   cx: 0.3800, cy: 0.6200, width: 0.1200, z: 11, seed: 1),
        IslandLayer(id: "Island-Blue-Cloud-2",  kind: .cloud,   cx: 0.3200, cy: 0.4800, width: 0.1100, z: 12, seed: 2),
        IslandLayer(id: "Island-Blue-Cloud-3",  kind: .cloud,   cx: 0.3600, cy: 0.7200, width: 0.1100, z: 13, seed: 3),
        IslandLayer(id: "Island-Blue-Cloud-4",  kind: .cloud,   cx: 0.7000, cy: 0.5000, width: 0.2500, z: 14, seed: 4),
        IslandLayer(id: "Island-Blue-Cloud-5",  kind: .cloud,   cx: 0.6400, cy: 0.6200, width: 0.1200, z: 15, seed: 5),
        IslandLayer(id: "Island-Blue-Cloud-6",  kind: .cloud,   cx: 0.6800, cy: 0.4800, width: 0.1100, z: 16, seed: 6),
        IslandLayer(id: "Island-Blue-Cloud-7",  kind: .cloud,   cx: 0.7200, cy: 0.7200, width: 0.1100, z: 17, seed: 7),
        IslandLayer(id: "Island-Blue-Cloud-8-0",  kind: .cloud,   cx: 0.3300, cy: 0.7500, width: 0.1300, z: 18, seed: 8),
        IslandLayer(id: "Island-Blue-Cloud-9-1",  kind: .cloud,   cx: 0.3900, cy: 0.4800, width: 0.1100, z: 19, seed: 9),
        IslandLayer(id: "Island-Blue-Cloud-10-2",  kind: .cloud,   cx: 0.6700, cy: 0.7500, width: 0.1300, z: 20, seed: 10),
        IslandLayer(id: "Island-Blue-Cloud-11-3",  kind: .cloud,   cx: 0.6000, cy: 0.4800, width: 0.1100, z: 21, seed: 11),
        IslandLayer(id: "Island-Blue-Cloud-12-4",  kind: .cloud,   cx: 0.3500, cy: 0.4300, width: 0.1000, z: 22, seed: 12),
        IslandLayer(id: "Island-Blue-Cloud-13-5",  kind: .cloud,   cx: 0.6500, cy: 0.4300, width: 0.1000, z: 23, seed: 13),
        IslandLayer(id: "Island-Blue-Cloud-14-6",  kind: .cloud,   cx: 0.3600, cy: 0.5000, width: 0.0900, z: 24, seed: 14),
        IslandLayer(id: "Island-Blue-Cloud-15-7",  kind: .cloud,   cx: 0.7400, cy: 0.4000, width: 0.0900, z: 25, seed: 15),
        IslandLayer(id: "Island-Blue-Cloud-16-8",  kind: .cloud,   cx: 0.2300, cy: 0.5200, width: 0.1000, z: 26, seed: 16),
        IslandLayer(id: "Island-Blue-Cloud-17-9",  kind: .cloud,   cx: 0.7700, cy: 0.5200, width: 0.1000, z: 27, seed: 17),
        IslandLayer(id: "Island-Blue-Cloud-18-10",  kind: .cloud,   cx: 0.6000, cy: 0.4800, width: 0.1100, z: 28, seed: 18),

        IslandLayer(id: "Island-Blue-Islet-0",  kind: .islet,   cx: 0.1989, cy: 0.4966, width: 0.0462, z: 30, seed: 0),
        IslandLayer(id: "Island-Blue-Islet-1",  kind: .islet,   cx: 0.2598, cy: 0.4536, width: 0.0612, z: 31, seed: 1),
        IslandLayer(id: "Island-Blue-Islet-2",  kind: .islet,   cx: 0.5703, cy: 0.2710, width: 0.0378, z: 32, seed: 2),
        IslandLayer(id: "Island-Blue-Islet-3",  kind: .islet,   cx: 0.5999, cy: 0.3203, width: 0.0449, z: 33, seed: 3),
        IslandLayer(id: "Island-Blue-Islet-4",  kind: .islet,   cx: 0.6911, cy: 0.5259, width: 0.0410, z: 34, seed: 4),
        IslandLayer(id: "Island-Blue-Islet-5",  kind: .islet,   cx: 0.7402, cy: 0.4600, width: 0.0729, z: 35, seed: 5),
        IslandLayer(id: "Island-Blue-Islet-6",  kind: .islet,   cx: 0.7689, cy: 0.3530, width: 0.0443, z: 36, seed: 6),
        IslandLayer(id: "Island-Blue-Islet-7",  kind: .islet,   cx: 0.7858, cy: 0.4946, width: 0.0378, z: 37, seed: 7),
        IslandLayer(id: "Island-Blue-Islet-8",  kind: .islet,   cx: 0.8203, cy: 0.4165, width: 0.0312, z: 38, seed: 8),

        IslandLayer(id: "Island-Blue-Citadel",  kind: .citadel, cx: 0.5016, cy: 0.4819, width: 0.4551, z: 40, seed: nil),

        IslandLayer(id: "Island-Blue-Chevron",  kind: .chevron, cx: 0.5003, cy: 0.8550, width: 0.1126, z: 50, seed: nil),
        IslandLayer(id: "Island-Blue-Logo",     kind: .logo,    cx: 0.4997, cy: 1.0040, width: 0.5488, z: 51, seed: nil),
        IslandLayer(id: "Island-Blue-Slogan",   kind: .slogan,  cx: 0.5026, cy: 1.1007, width: 0.4193, z: 52, seed: nil),
    ]

    /// `all` pre-sorted by draw order; avoids re-sorting every frame.
    static let sortedByZ: [IslandLayer] = all.sorted { $0.z < $1.z }
}
