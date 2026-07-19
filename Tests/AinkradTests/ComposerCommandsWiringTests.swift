// Tests/AinkradTests/ComposerCommandsWiringTests.swift
//
// M7 Slice 5c Task 22a: `/compact` and `/export` wiring. The plan's draft test
// referenced `AssistantCommands.makeBuiltins`, which never existed — the real
// factory is `BuiltinCommands.make` (Commands/CommandRegistry.swift). These
// tests exercise it against a live `AgentSession` so a vacuous "command is
// registered" check isn't the only coverage.
import Foundation
import AppKit
import Testing
@testable import Ainkrad

@Suite("Composer commands wiring")
@MainActor
struct ComposerCommandsWiringTests {
    @Test func builtinCommandsRegistered() {
        let reg = CommandRegistry(builtins: BuiltinCommands.make(
            runtime: RuntimeOptionsStore(persistence: InMemoryPersistenceStore()),
            usage: UsageTracker(persistence: InMemoryPersistenceStore(), prices: ModelPriceTable()),
            router: nil, catalog: nil))
        let names = Set(reg.all().map(\.name))
        #expect(names.isSuperset(of: ["new", "model", "think", "verbose", "trace", "usage", "compact", "export"]))
    }

    @Test func compactShrinksALongTranscriptAndReportsWhatHappened() async {
        let reg = CommandRegistry(builtins: BuiltinCommands.make(runtime: nil, usage: nil, router: nil, catalog: nil))
        let session = TestSessionFactory.make(commands: reg)

        // NoopProvider never emits `.done`, so each `send` settles to `.failed`
        // without appending an assistant reply — irrelevant here, since we only
        // need the USER messages accumulating past the compactor's `keepRecent`
        // threshold (6).
        for i in 1...8 {
            session.send("message \(i)")
            await session.currentTask?.value
        }
        #expect(session.messages.count == 8)

        session.send("/compact")

        // `replaceMessages` leaves 7 (1 synthetic summary + 6 kept tail); `send`
        // then appends the command's own note as one more assistant message.
        #expect(session.messages.count == 8)
        #expect(session.messages.first?.text.contains("summarized") == true)
        guard case .assistant = session.messages.last?.role else { Issue.record("expected an assistant note"); return }
        #expect(session.messages.last?.text.contains("Compacted 2") == true)
    }

    @Test func compactDeclinesWhenTranscriptIsAlreadyShort() {
        let reg = CommandRegistry(builtins: BuiltinCommands.make(runtime: nil, usage: nil, router: nil, catalog: nil))
        let session = TestSessionFactory.make(commands: reg)
        session.send("/compact")
        #expect(session.messages.count == 1) // only the "nothing to compact" note
        #expect(session.messages.last?.text.contains("Nothing to compact") == true)
    }

    @Test func exportRendersMarkdownAndCopiesItToThePasteboard() {
        let reg = CommandRegistry(builtins: BuiltinCommands.make(runtime: nil, usage: nil, router: nil, catalog: nil))
        let session = TestSessionFactory.make(commands: reg)
        let result = reg.run("/export", on: TestSessionFactory.make(commands: reg))
        // Fresh empty session: nothing to export yet, not a stub message.
        #expect(result == .handled(note: "Nothing to export yet."))

        session.send("hello there")
        let exportResult = reg.run("/export", on: session)
        guard case .handled(let note) = exportResult, let note else { Issue.record("expected a handled note"); return }
        #expect(note.contains("Copied the transcript"))
        #expect(!note.lowercased().contains("isn't implemented"))

        let clipboard = NSPasteboard.general.string(forType: .string)
        #expect(clipboard?.contains("# Conversation") == true)
        #expect(clipboard?.contains("hello there") == true)
    }
}
