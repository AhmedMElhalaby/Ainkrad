// Tests/AinkradTests/TurnUndoTests.swift
import Foundation
import Testing
@testable import Ainkrad

@Suite("TurnUndo classification")
@MainActor
struct TurnUndoTests {
    @Test func flagsTerminalAndGitAsIrreversible() {
        let turn = [
            AgentMessage(role: .assistant, content: [
                .toolUse(id: "1", name: "edit_file", input: .object(["path": .string("/x")])),
                .toolUse(id: "2", name: "run_terminal", input: .object(["command": .string("rm x")])),
                .toolUse(id: "3", name: "git_op", input: .object(["op": .string("commit")])),
            ]),
        ]
        let notes = TurnUndo.classifyIrreversible(turn)
        #expect(notes.count == 2)                       // run_terminal + git_op, not edit_file
        #expect(notes.contains { $0.contains("run_terminal") })
        #expect(notes.contains { $0.contains("git_op") })
    }

    @Test func pureReadTurnHasNoIrreversibles() {
        let turn = [AgentMessage(role: .assistant, content: [
            .toolUse(id: "1", name: "read_file", input: .object(["path": .string("/x")]))])]
        #expect(TurnUndo.classifyIrreversible(turn).isEmpty)
    }

    @Test func emptyTurnHasNoIrreversibles() {
        #expect(TurnUndo.classifyIrreversible([]).isEmpty)
    }

    @Test func multipleCallsToSameIrreversibleToolEachYieldANote() {
        let turn = [AgentMessage(role: .assistant, content: [
            .toolUse(id: "1", name: "run_terminal", input: .object(["command": .string("ls")])),
            .toolUse(id: "2", name: "run_terminal", input: .object(["command": .string("pwd")])),
        ])]
        #expect(TurnUndo.classifyIrreversible(turn).count == 2)
    }
}
