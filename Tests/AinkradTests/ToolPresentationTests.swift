import Testing
@testable import Ainkrad

@Suite("ToolPresentation")
struct ToolPresentationTests {
    @Test func terminalTool() {
        let p = ToolPresentation.for(toolName: "run_terminal")
        #expect(p.icon == "terminal")
        #expect(p.tint == .secondary)
        #expect(p.label == "Run terminal")
    }

    @Test func gitTool() {
        #expect(ToolPresentation.for(toolName: "git_op").icon == "arrow.triangle.branch")
    }

    @Test func workspaceTool() {
        #expect(ToolPresentation.for(toolName: "workspace_control").icon == "macwindow")
    }

    @Test func editToolsUsePrimaryTint() {
        for name in ["Edit", "Write", "str_replace"] {
            let p = ToolPresentation.for(toolName: name)
            #expect(p.icon == "pencil")
            #expect(p.tint == .primary)
        }
    }

    @Test func readTool() {
        #expect(ToolPresentation.for(toolName: "Read").icon == "doc.text")
    }

    @Test func mcpToolsByPrefix() {
        let p = ToolPresentation.for(toolName: "mcp__linear__create_issue")
        #expect(p.icon == "puzzlepiece.extension")
    }

    @Test func unknownFallsBackToWrench() {
        let p = ToolPresentation.for(toolName: "some_future_tool")
        #expect(p.icon == "wrench.and.screwdriver")
        #expect(p.tint == .secondary)
    }

    @Test func humanizeReplacesUnderscoresAndCapitalizes() {
        #expect(ToolPresentation.humanize("run_terminal") == "Run terminal")
        #expect(ToolPresentation.humanize("Read") == "Read")
    }
}
