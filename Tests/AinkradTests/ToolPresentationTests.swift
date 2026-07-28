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
        #expect(ToolPresentation.for(toolName: "run_terminal").icon == "terminal")
    }

    @Test func workspaceTool() {
        #expect(ToolPresentation.for(toolName: "workspace_control").icon == "macwindow")
    }

    @Test func editFileUsesPrimaryTint() {
        let p = ToolPresentation.for(toolName: "edit_file")
        #expect(p.icon == "pencil")
        #expect(p.tint == .primary)
        #expect(p.label == "Edit file")
    }

    @Test func readFileTool() {
        let p = ToolPresentation.for(toolName: "read_file")
        #expect(p.icon == "doc.text")
        #expect(p.label == "Read file")
    }

    @Test func memoryWriteUsesPrimaryTint() {
        let p = ToolPresentation.for(toolName: "memory_write")
        #expect(p.icon == "brain")
        #expect(p.tint == .primary)
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
        #expect(ToolPresentation.humanize("read_file") == "Read file")
        #expect(ToolPresentation.humanize("run_terminal") == "Run terminal")
        #expect(ToolPresentation.humanize("canvas") == "canvas")
    }

    @Test func humanizeStripsMcpPrefixAndCollapsesSeparators() {
        #expect(ToolPresentation.humanize("mcp__linear__create_issue") == "Linear create issue")
    }
}
