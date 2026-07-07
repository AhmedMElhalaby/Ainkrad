import Testing
@testable import Ainkrad

@Suite("IslandLayers")
struct IslandLayersTests {
    @Test("every layer has a non-empty asset name and normalized coords")
    func wellFormed() {
        for l in IslandLayers.all {
            #expect(!l.id.isEmpty)
            #expect((0.0...1.0).contains(l.cx))
            // cy is normalized to the art rect but may exceed 1.0: the
            // wordmark lockup (logo/slogan) intentionally sits just below
            // the art rect. Keep a sane upper bound to still catch typos.
            #expect((0.0...1.5).contains(l.cy))
            #expect(l.width > 0 && l.width <= 1.0)
        }
    }

    @Test("table has the expected element counts")
    func counts() {
        func count(_ k: IslandLayer.Kind) -> Int { IslandLayers.all.filter { $0.kind == k }.count }
        #expect(count(.ring) == 1)
        #expect(count(.citadel) == 1)
        #expect(count(.chevron) == 1)
        #expect(count(.logo) == 1)
        #expect(count(.slogan) == 1)
        #expect(count(.cloud) == 16)
        #expect(count(.islet) == 9)
    }

    @Test("clouds and islets carry contiguous motion seeds; fixed carry none")
    func seeds() {
        let cloudSeeds = IslandLayers.all.filter { $0.kind == .cloud }.compactMap { $0.seed }.sorted()
        let isletSeeds = IslandLayers.all.filter { $0.kind == .islet }.compactMap { $0.seed }.sorted()
        #expect(cloudSeeds == Array(0..<16))
        #expect(isletSeeds == Array(0..<9))
        for l in IslandLayers.all where [.ring,.citadel,.chevron,.logo,.slogan].contains(l.kind) {
            #expect(l.seed == nil)
        }
    }

    @Test("z-order is unique and orders ring < clouds < islets < citadel < wordmark")
    func zOrder() {
        let zs = IslandLayers.all.map { $0.z }
        #expect(Set(zs).count == zs.count)   // all unique
        func maxZ(_ k: IslandLayer.Kind) -> Int { IslandLayers.all.filter { $0.kind == k }.map { $0.z }.max() ?? -1 }
        func minZ(_ k: IslandLayer.Kind) -> Int { IslandLayers.all.filter { $0.kind == k }.map { $0.z }.min() ?? -1 }
        #expect(maxZ(.ring) < minZ(.cloud))
        #expect(maxZ(.cloud) < minZ(.islet))
        #expect(maxZ(.islet) < IslandLayers.all.first { $0.kind == .citadel }!.z)
        #expect(IslandLayers.all.first { $0.kind == .citadel }!.z < minZ(.chevron))
        // Wordmark itself is ordered chevron < logo < slogan.
        let chevronZ = IslandLayers.all.first { $0.kind == .chevron }!.z
        let logoZ = IslandLayers.all.first { $0.kind == .logo }!.z
        let sloganZ = IslandLayers.all.first { $0.kind == .slogan }!.z
        #expect(chevronZ < logoZ)
        #expect(logoZ < sloganZ)
    }
}
