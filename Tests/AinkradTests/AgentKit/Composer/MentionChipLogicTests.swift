import Testing
@testable import Ainkrad

@Suite @MainActor struct MentionChipLogicTests {
    @Test func toggleFlipsEmbedToReference() {
        let before = [ComposerMention(path: "/a", mode: .embed)]
        #expect(AssistantComposerBar.toggledMode(before, at: 0)[0].mode == .reference)
    }
    @Test func toggleFlipsReferenceToEmbed() {
        let before = [ComposerMention(path: "/a", mode: .reference)]
        #expect(AssistantComposerBar.toggledMode(before, at: 0)[0].mode == .embed)
    }
    @Test func toggleOutOfBoundsIsNoOp() {
        let before = [ComposerMention(path: "/a", mode: .embed)]
        #expect(AssistantComposerBar.toggledMode(before, at: 5) == before)
    }
}
