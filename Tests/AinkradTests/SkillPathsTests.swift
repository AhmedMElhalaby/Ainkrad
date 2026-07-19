import Foundation
import Testing
@testable import Ainkrad

@Suite("SkillPaths")
struct SkillPathsTests {
    @Test func mapsNamesToLayout() {
        let root = URL(fileURLWithPath: "/tmp/skills-\(UUID().uuidString)")
        let p = SkillPaths(root: root)
        #expect(p.proposedRoot.lastPathComponent == "_proposed")
        #expect(p.skillDir("pdf").lastPathComponent == "pdf")
        #expect(p.skillFile("pdf").lastPathComponent == "SKILL.md")
        #expect(p.skillFile("pdf").deletingLastPathComponent().lastPathComponent == "pdf")
        #expect(p.proposedFile("pdf").lastPathComponent == "SKILL.md")
        // _proposed sits UNDER root, not beside it.
        #expect(p.proposedDir("pdf").deletingLastPathComponent().lastPathComponent == "_proposed")
    }

    @Test func defaultRootEndsInSkills() {
        #expect(SkillPaths.defaultRoot().lastPathComponent == "Skills")
    }
}
