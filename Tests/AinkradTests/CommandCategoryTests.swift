import Testing
@testable import Ainkrad

@Suite("CommandCategory")
@MainActor
struct CommandCategoryTests {
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

    @Test func builtinsAreCategorized() {
        let cmds = BuiltinCommands.make(runtime: nil, usage: nil, router: nil, catalog: nil)
        func category(_ name: String) -> CommandCategory? { cmds.first { $0.name == name }?.category }
        #expect(category("new") == .session)
        #expect(category("reset") == .session)
        #expect(category("compact") == .session)
        #expect(category("undo") == .session)
        #expect(category("retry") == .session)
        #expect(category("model") == .model)
        #expect(category("think") == .model)
        #expect(category("usage") == .info)
        #expect(category("export") == .info)
        #expect(category("verbose") == .info)
        #expect(category("trace") == .info)
        #expect(category("remember") == .memory)
    }
}
