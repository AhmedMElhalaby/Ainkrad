import Testing
@testable import Ainkrad

@Suite("CommandCategory")
@MainActor
struct CommandCategoryTests {
    private func cmd(_ name: String, _ cat: CommandCategory) -> SlashCommand {
        SlashCommand(name: name, summary: "", usage: "/\(name)", category: cat) { _, _ in .handled(note: nil) }
    }

    @Test func defaultCategoryIsOther() {
        let c = SlashCommand(name: "x", summary: "", usage: "/x") { _, _ in .handled(note: nil) }
        #expect(c.category == .other)
    }

    @Test func titlesAndOrder() {
        #expect(CommandCategory.session.title == "Session")
        #expect(CommandCategory.skill.title == "Skills")
        #expect(CommandCategory.session.order < CommandCategory.model.order)
        #expect(CommandCategory.model.order < CommandCategory.info.order)
        #expect(CommandCategory.info.order < CommandCategory.memory.order)
        #expect(CommandCategory.memory.order < CommandCategory.skill.order)
        #expect(CommandCategory.skill.order < CommandCategory.other.order)
    }
}
